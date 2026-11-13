# 장소 API

Google Places API (New)를 서버에서 호출해 장소 정보를 돌려준다. Google API 키는 서버에만 있고 앱으로 내려보내지 않는다.

| 엔드포인트 | 인증 | 용도 |
| --- | --- | --- |
| `GET /api/v1/places/search` | **로그인 필요** | 검색어로 장소 검색 |
| `GET /api/v1/places/{placeId}` | **로그인 필요** | 장소 상세 |
| `GET /api/v1/places/nearby` | **차단** (모든 요청 거절) | 좌표 주변 장소 목록. 앱이 쓰지 않아 외부 접근을 막고 코드만 남겨 둠 |
| ~~`GET /api/v1/places/nearest`~~ | **차단** | 최근접 장소. 코드를 삭제함(2026-11-13) |

인증 규칙은 `SecurityConfig`에 있다. `nearby`·`nearest`의 `denyAll()`이 `/api/v1/places/**` 인증 규칙보다 앞에 있어야 한다. 늦게 오면 로그인 사용자의 `/nearby`는 주변 핸들러에, `/nearest`는 상세 핸들러(`placeId = "nearest"`)에 닿아 Google을 호출할 수 있다. 차단 경로는 토큰이 없으면 401, 있으면 403이다(GET·HEAD 모두).

## 호출 제한

검색과 상세는 로그인 사용자별(JWT `sub`)로 호출 수를 제한한다. 서버 결과 캐시는 두지 않는다.

| 대상 | 사용자 1분 | 사용자 1시간 | 사용자 하루(24시간) | 전역 1시간 | 전역 하루(24시간) |
| --- | --- | --- | --- | --- | --- |
| 검색 | 10회 | 100회 | 50회 | 125회 | 1,000회 |
| 상세 | 20회 | 200회 | 100회 | 250회 | 2,000회 |

- 숫자는 모두 **개발 초기 설정값**이며 운영 보장값이 아니다(`RateLimitBucket`: `PLACE_*_USER_MINUTE`·`_USER_HOUR`·`_USER_DAY`, `PLACE_*_GLOBAL_HOUR`·`_GLOBAL_DAY`). 사용자 하루 한도가 사용자 1시간 한도보다 작아, 지금 값에서는 사용자 1시간 한도가 실제로 요청을 거절하는 일이 없다(하루 한도에 먼저 걸림). 1시간 한도를 낮출지 지울지는 남은 과제다.
- 한도를 넘으면 `429 TOO_MANY_REQUESTS` + `Retry-After`(남은 초)로 응답하고, 그 요청으로 Google을 호출하지 않는다.
- 다섯 창(사용자 1분·1시간·하루, 전역 1시간·하루)을 한 번에 판정하고(`AuthRateLimiter.acquireKeys`), 모두 허용될 때만 모두 센다. 사용자 한도로 거절된 요청은 전역 사용량을, 전역 한도로 거절된 요청은 사용자 사용량을 쓰지 않는다. 여러 창이 함께 걸리면 `Retry-After`는 가장 긴 쪽이다.
- 검색과 상세는 따로 센다. 입력 검증에 실패한 검색(400)은 한도를 쓰지 않는다.
- 전역 한도는 모든 사용자 합산이며 고정 키 하나(`"*"`)로 센다. 그래서 제한기의 키 개수 상한(묶음당 1만)과 무관하다.
  - 넘으면 **모든 사용자**가 `429` + `Retry-After`를 받는다. 전역 1시간 한도의 `Retry-After`는 최대 3,600초, 전역 하루 한도는 최대 약 86,400초다.
  - **계정 하나로는 전역 한도(1시간·하루)를 채울 수 없다.** 사용자 하루 한도(검색 50·상세 100)가 전역 1시간 한도(125·250)보다 작기 때문이다.
  - **전역 한도는 모든 사용자가 함께 쓰므로, 계정 여러 개로 모두를 막을 수 있다.** 가입에 이메일 인증이나 CAPTCHA가 없고 장소 경로에 IP별 한도도 없어 계정을 만드는 비용이 거의 없다.
    - 계정 3개(검색·상세 각각)면 전역 1시간 한도를 채워, 그 창이 빌 때까지 최대 1시간 동안 모든 사용자를 막을 수 있다.
    - 계정 20개로 8시간에 나눠 보내면 전역 하루 한도를 다 쓴다. 그 뒤 가장 오래된 기록이 24시간 창을 벗어날 때까지 모두 막히고, 빈자리가 나면 같은 계정으로 다시 채울 수 있어 **매일 반복하면 계속 막을 수 있다.** 전역 거절의 `Retry-After`가 빈자리 시각을 알려 주는 점도 이를 돕는다.
    - 따라서 전역 1시간 한도는 몰아치기 공격만 1시간 단위로 끊어 줄 뿐, 장애를 최대 1시간으로 보장하지 않는다. 비용 상한(하루 검색 1,000·상세 2,000)은 그대로 지켜진다.
    - 근본 대책은 아래 "남은 과제"(가입 인증, IP별 한도)다.
  - 공격이 없어도 사용자가 늘면 정상 사용량만으로 전역 1시간 한도에 닿아 모든 사용자가 최대 1시간 동안 429를 받을 수 있다. 배포 전에 예상 피크와 콘솔 쿼터에 맞춰 값을 다시 정한다.
  - 전역 한도(1시간 또는 하루)에 걸려 거절 상태로 바뀌면 `AuthRateLimiter`가 `WARN`을 남긴다(`서버 전체 요청 한도 도달: bucket=..., retryAfter=...s`). 같은 묶음이 계속 거절되는 동안에는 다시 남기지 않고, 그 묶음이 한 번이라도 허용으로 판정된 뒤 다시 걸리면 또 남긴다. 그래서 한도가 찬 상태가 이어지는 중에 빈자리가 날 때마다 다시 남을 수 있다(1시간 창 기준 최대 한도 수만큼, 검색 125·상세 250줄). 사용자 ID 등 식별 정보는 넣지 않는다. 요청마다 남는 429 로그는 지금처럼 `DEBUG`다(`GlobalExceptionHandler`).
- **배포 전 필수 조건**: 서버 상한은 서버 한 대의 메모리 기준이고 재시작하면 초기화되므로 비용 상한을 보장하지 않는다. 배포 전에 Google Cloud 콘솔에서 Places API(New)의 **일일 쿼터**(Text Search, Place Details)와 **예산 알림**을 반드시 설정한다.
- 기록은 서버 메모리에 있다(서버 한 대 기준, 재시작하면 초기화). 제한기 규칙은 `docs/auth-rate-limit-api.md`와 같다.
- 남은 과제: 가입 시 이메일 인증이나 CAPTCHA(계정 대량 생성 억제), 장소 경로의 IP별 한도. 둘 다 계정 여러 개로 전역 한도를 소진하는 문제의 근본 대책이다. 그 밖에 사용자 1시간 한도 정리(하루 한도 이하로 낮추거나 삭제), 전역 WARN 최소 간격.

## 공통 응답 형식 (`PlaceResponse`)

```json
{
  "id": "ChIJ...",
  "name": "경복궁",
  "latitude": 37.5796,
  "longitude": 126.977,
  "address": "서울특별시 종로구 사직로 161",
  "rating": 4.6,
  "category": "tourist_attraction",
  "openNow": true
}
```

- `rating`, `openNow`는 값이 없으면 필드를 빼지 않고 `null`로 내려간다. 검색 API는 항상 `null`이다(아래 비용 참고).
- `name`이 없으면 `"이름 없는 장소"`, `address`가 없으면 `"주소 정보 없음"`이다.
- Google 응답에 위치가 없거나, 빈 `location {}`이거나, 위도·경도 중 하나만 있으면 `latitude`, `longitude`는 필드를 빼지 않고 둘 다 `null`로 내려간다. 앱은 이 장소를 목록에는 표시하고 지도 마커와 카메라 범위 계산에서는 뺀다.
- `category`는 Google `primaryType` 값이다.

## 장소 검색

`GET /api/v1/places/search?query=경복궁&lat=37.5665&lng=126.978`

| 파라미터 | 필수 | 규칙 |
| --- | --- | --- |
| `query` | 예 | 앞뒤 공백류를 지운 뒤 1~100자(코드 포인트 기준) |
| `lat` | 아니오 | -90~90. `lng`와 함께 보내거나 둘 다 생략 |
| `lng` | 아니오 | -180~180. `lat`와 함께 보내거나 둘 다 생략 |

- 앞뒤에서 지우는 공백류: Java 공백(`Character.isWhitespace`), 유니코드 구분자(NBSP U+00A0, U+3000 등), 서식 문자(U+200B, U+FEFF 등). 단, 태그 문자(U+E0020~U+E007F)는 지역 깃발 이모지(예: 스코틀랜드 깃발)의 일부라 지우지 않는다. 가운데 문자는 그대로 둔다.
- 좌표가 있으면 그 지점 반경 **5000m** 안의 결과를 우선한다(`locationBias`). 결과를 이 범위로 제한하지는 않는다.
- 좌표를 생략하면 Google이 요청 IP를 기준으로 결과를 우선한다(IP biasing, `locationBias`·`locationRestriction`이 모두 없을 때의 기본 동작). Tripbler에서는 백엔드가 Google을 호출하므로 사용자 기기가 아니라 **서버의 외부 IP**가 검색 순위에 영향을 줄 수 있다. 근거: [Text Search (New)](https://developers.google.com/maps/documentation/places/web-service/text-search)
- 결과는 최대 20개이고, 없으면 `200 []`이다.

응답: `200 List<PlaceResponse>`

### Google 요청

`POST https://places.googleapis.com/v1/places:searchText`

```json
{
  "textQuery": "경복궁",
  "languageCode": "ko",
  "pageSize": 20,
  "locationBias": {
    "circle": {
      "center": { "latitude": 37.5665, "longitude": 126.978 },
      "radius": 5000.0
    }
  }
}
```

- 좌표가 없으면 `locationBias` 필드 자체를 보내지 않는다(`null`도 보내지 않는다).
- 키는 `X-Goog-Api-Key` 헤더로 보낸다.

### 비용 (필드 마스크)

Google은 요청한 필드 중 가장 높은 등급으로 과금한다. `rating`, `currentOpeningHours`는 Enterprise 등급이다.

| 엔드포인트 | 필드 마스크 | 등급 |
| --- | --- | --- |
| 검색 | `places.id,places.displayName,places.location,places.formattedAddress,places.primaryType` | Pro |
| 주변(차단 중) | 위 필드 + `places.rating,places.currentOpeningHours.openNow` | Enterprise |
| 상세 | `id,displayName,location,formattedAddress,rating,primaryType,currentOpeningHours.openNow` | Enterprise |

검색은 평점과 영업 여부를 요청하지 않는다. 필요하면 선택한 장소만 상세 API로 조회한다.

검색과 상세의 반복 호출은 위 "호출 제한"으로 막는다. 캐시는 없으므로 한도 안의 호출은 그대로 유료 호출이 된다.

## 주변 장소 (차단 중)

> 외부 접근은 `SecurityConfig`의 `denyAll()`로 막혀 있다. 아래는 코드가 남아 있는 동작이다. 다시 열 때는 로그인과 사용자별 호출 제한을 함께 둔다.

`GET /api/v1/places/nearby?lat=37.5665&lng=126.978&type=restaurant&radius=1500`

| 파라미터 | 필수 | 기본값 | 규칙 |
| --- | --- | --- | --- |
| `lat` | 예 | | -90~90 |
| `lng` | 예 | | -180~180 |
| `type` | 아니오 | `tourist_attraction` | `tourist_attraction` 또는 `restaurant`. 빈 값이면 기본값 |
| `radius` | 아니오 | `1500` | 1~50000(m) |

- Google `places:searchNearby`를 `locationRestriction`(반경 안으로 제한), 최대 20개, `languageCode: "ko"`로 호출한다.
- 응답: `200 List<PlaceResponse>`. 결과가 없으면 `[]`.

## 장소 상세

`GET /api/v1/places/{placeId}`

- 로그인 필요. 사용자별 호출 제한이 있다(위 "호출 제한").
- Google Place Details를 `languageCode=ko`로 호출한다. 평점과 영업 여부를 포함한다(Enterprise 등급). 검색·주변·상세 모두 한국어로 받아 이름·주소 언어가 섞이지 않는다.
- 응답: `200 PlaceResponse`.

## 입력 검증

- 좌표는 `BigDecimal`로 받아 `NaN`, `Infinity`, 숫자가 아닌 값을 형식 오류로 막는다.
- 범위 경계값(±90, ±180, 반경 1과 50000)은 허용한다.
- 검증은 Google 호출 전에 끝난다. 실패하면 Google을 호출하지 않는다.

## 오류

모든 오류는 공통 `ErrorResponse`(`timestamp`, `status`, `code`, `message`, `path`) 형식이다.

| 상황 | 상태 | code | message 예 |
| --- | --- | --- | --- |
| 필수 파라미터 없음 | 400 | `INVALID_REQUEST` | `필수 요청 파라미터가 없습니다: lat` |
| 숫자 형식 오류 | 400 | `INVALID_REQUEST` | `요청 파라미터 형식이 올바르지 않습니다.` |
| 범위 밖 위도 | 400 | `INVALID_REQUEST` | `위도는 -90~90 사이여야 합니다.` |
| 범위 밖 경도 | 400 | `INVALID_REQUEST` | `경도는 -180~180 사이여야 합니다.` |
| 범위 밖 반경 | 400 | `INVALID_REQUEST` | `반경은 1~50000m 사이여야 합니다.` |
| 허용하지 않는 `type` | 400 | `INVALID_REQUEST` | `장소 유형은 tourist_attraction 또는 restaurant만 사용할 수 있습니다.` |
| 검색어가 비었거나 100자 초과 | 400 | `INVALID_REQUEST` | `검색어는 공백을 제외하고 1~100자여야 합니다.` |
| 검색 좌표가 하나만 옴 | 400 | `INVALID_REQUEST` | `위도와 경도는 함께 보내야 합니다.` |
| 검색·상세를 토큰 없이 호출 | 401 | `UNAUTHORIZED` | `인증이 필요합니다.` |
| 주변·최근접(차단) 토큰 없음 / 토큰 있음 | 401 / 403 | `UNAUTHORIZED` / `FORBIDDEN` | `인증이 필요합니다.` / `접근 권한이 없습니다.` |
| 검색·상세 사용자별 한도 초과 | 429 | `TOO_MANY_REQUESTS` | `요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.` (`Retry-After` 헤더) |
| 검색·상세 전역 한도(1시간·하루) 초과 | 429 | `TOO_MANY_REQUESTS` | 사용자별 한도 초과와 같은 응답(`Retry-After` 헤더) |
| 상세: Google 404 | 404 | `RESOURCE_NOT_FOUND` | `요청한 장소를 찾을 수 없습니다.` |
| 상세: Google 400(키 문제 아님) | 400 | `INVALID_REQUEST` | `장소 ID가 올바르지 않습니다.` |
| Google 장애, 시간 초과, 키 오류, Google 응답 본문 누락 | 503 | `PLACES_PROVIDER_UNAVAILABLE` | `현재 장소 정보 제공 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해 주세요.` |

- 검색·주변은 입력을 서버에서 먼저 검증하므로 Google 쪽 오류(400 포함)를 모두 503으로 본다.
- 검색·주변에서 Google 200 응답의 본문 자체가 없으면 결과 0건이 아니라 503이다. 본문이 정상 JSON 객체이고 `places`가 없거나 빈 배열이면 결과 0건(`200 []`)이다.
- 상세는 `placeId`가 사용자 입력이라 Google 404·400을 그대로 구분한다. 단, 400이어도 오류 본문의 `reason`이 `API_KEY_INVALID`, `API_KEY_SERVICE_BLOCKED`, `SERVICE_DISABLED`이면 서버 설정 문제이므로 503이다.
- 파라미터 제약(위도, 경도, 반경, `type`) 위반이 여러 개면 메시지를 `, `로 이어서 함께 돌려준다(순서는 보장하지 않음).

## 타임아웃

Google 호출은 연결 2초, 읽기 5초 제한이 있다. 앱의 장소 요청 제한 시간(8초)보다 먼저 503으로 끝나도록 정한 값이다.

- 읽기 제한은 응답 전체 시간이 아니라 데이터를 기다리는 구간마다 걸린다. Google 응답은 작아 보통 한 번에 오므로 대개 7초 안에 끝나지만, 응답이 조금씩 끊겨 오면 합계가 7초(드물게 앱의 8초)를 넘을 수 있다. 전체 시간을 강제하지 않기로 했다(2026-11-12).

## 앱 연동 시 확인할 것

- 검색과 상세 요청에는 `Authorization: Bearer <액세스 토큰>`을 붙인다. 없거나 만료되면 401이다(앱은 재발급 후 다시 시도).
- 429를 받으면 서버 `message`를 보여 주고 로그인 상태는 유지한다.
- 좌표는 둘 다 보내거나 둘 다 생략한다.
- 검색 결과의 `rating`, `openNow`는 `null`이다. 필요하면 장소를 고른 뒤 상세 API로 다시 조회한다.

## 검증

```powershell
.\gradlew.bat test --tests "com.tripbler.backend.place.*" --tests "*SecurityConfigTest"
```

Google 호출은 `MockRestServiceServer`와 로컬 HTTP 서버로 대체하므로 실제 API 키와 외부 네트워크 없이 검증한다.
- `GooglePlacesClientTest`: Google 요청 본문·헤더(필드 마스크), 응답 변환, 오류별 예외, 타임아웃 연결
- `PlaceControllerTest`: 입력 검증, 상태 코드, 오류 응답
- `PlaceControllerSecurityTest`: 실제 `SecurityConfig`로 검색 401과 나머지 공개 API 확인
