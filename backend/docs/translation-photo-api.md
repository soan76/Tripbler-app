# 사진 번역 API

앱이 찍은 사진(기준 사진 하나, JPEG)과 기기(ML Kit)에서 읽은 문단을 **한 번에** 보낸다. 서버는 AI(Claude)에게 사진과 문단을 함께 보내 사진과 대조한 원문 보정·번역·한글 발음·가격을 받고, AI가 실패했거나 돌려주지 않은 문단은 그 문단의 OCR 글자만 Google로 번역해 대신한다.

설계: 저장소 루트의 `docs/superpowers/specs/2026-11-26-photo-translation-design.md`.

## `POST /api/v1/translation/photo`

- **로그인 필요**(Bearer 액세스 토큰, `SecurityConfig`에서 `/lines`와 같은 규칙). 유료 Claude 호출이라 기존 `POST /api/v1/translation`(로그인 없이 열림)과 달리 막는다.
- `Content-Type: multipart/form-data`. 파트 두 개:

| 파트 | 형식 | 규칙 |
| --- | --- | --- |
| `image` | 파일(JPEG) | 5MB 이하(`spring.servlet.multipart.max-file-size`, 요청 전체 6MB). JPEG 시작 바이트(`FF D8 FF`)와 머리 정보로 확인한다(`PhotoImageInspector`). 클라이언트가 보낸 파트 `Content-Type`은 믿지 않고 AI에는 `image/jpeg`로 보낸다. |
| `request` | `application/json` | 아래 JSON. 파트의 `Content-Type`이 `application/json`이어야 한다. |

### 요청 JSON(`request` 파트)

```json
{
  "sourceLanguageCode": "auto",
  "targetLanguageCode": "ko",
  "imageWidth": 1536,
  "imageHeight": 2048,
  "paragraphs": [
    { "id": "p1", "text": "ラーメン定食 ¥980", "box": { "left": 120, "top": 340, "width": 610, "height": 72 } }
  ]
}
```

| 필드 | 규칙 |
| --- | --- |
| `sourceLanguageCode` | `auto` 또는 영문 2~3자 |
| `targetLanguageCode` | 영문 2~3자 |
| `imageWidth`, `imageHeight` | 1~8192. **사진 머리 정보의 실제 크기와 같아야 한다**(좌표계를 하나로 맞추기 위해) |
| `paragraphs` | 1~50개(임시값), 빈 항목 없음 |
| `paragraphs[].id` | `^p[0-9]{1,3}$`, 요청 안에서 중복 없음 |
| `paragraphs[].text` | 공백만 있으면 안 되고 300자 이하(임시값). 모든 문단 합쳐 4000자 이하(임시값, `PhotoRequestValidator.MAX_TOTAL_CHARACTERS`) |
| `paragraphs[].box` | 사진 픽셀 좌표. `left`·`top` ≥ 0, `width`·`height` > 0. 오른쪽·아래 끝이 사진 크기의 102% 안이어야 한다(2% 여유) |

임시값(문단 수·글자 수, 호출 제한, 모델, 시간 제한, `max_tokens`, multipart 한도)은 실제 Claude 측정(계획 Task 14) 뒤 확정한다.

### 응답 `200`

```json
{
  "sourceLanguageCode": "ja",
  "targetLanguageCode": "ko",
  "paragraphs": [
    {
      "id": "p1",
      "original": "ラーメン定食 ¥980",
      "translated": "라멘 정식 980엔",
      "uncertain": false,
      "translationSource": "AI",
      "pronunciation": "라멘 테이쇼쿠",
      "prices": [
        {
          "text": "¥980", "amount": 980, "currency": "JPY", "confirmed": true,
          "krwAmount": 9104, "krwRate": 9.29, "rateFetchedAt": "2026-11-26T09:00:00", "rateStale": false
        }
      ]
    }
  ]
}
```

- 문단 순서·개수·ID는 요청과 같다. `sourceLanguageCode`는 요청이 `auto`면 감지한 언어(AI 감지 → 대체 번역 감지 순, 모르면 `auto`).
- `original`: AI가 사진과 대조해 보정한 원문(사진에서 분명히 다를 때만 고침, 읽지 못한 부분은 표식). AI 원문이 비었거나 길이 상한(max(200, OCR 글자 수×4))을 넘으면 OCR 원문을 쓴다. 대체 번역 문단은 OCR 원문 그대로.
- `uncertain`: 읽지 못한 부분이 있으면 `true`. 그 부분은 `original`·`translated` 안에 정확히 `[읽을 수 없음]`(`PhotoTranslationResponse.UNREADABLE_MARKER`, 앱 `unreadableMarker`와 같은 값)으로 남는다.
- `translationSource`: 문단마다 `AI`(사진 대조 번역) 또는 `OCR_TEXT`(OCR 글자만으로 한 대체 번역).
- `pronunciation`: 원문을 소리 나는 대로 적은 한글(참고용). 규칙은 `/lines`와 같고, `OCR_TEXT` 문단은 `null`.
- `prices`: 문단 안의 가격 목록(0개 이상, 원문 순서).

### 대체 번역 규칙

- AI 호출이 실패하면(시간 초과, 거절, 출력 한도 도달, 응답 해석 실패, 키·크레딧 없음 등 `TranslationProviderException`) 모든 문단을 대체한다.
- AI 응답의 문단은 ID로 맞춘다. 요청에 없는 ID는 버리고, 같은 ID가 여러 번 오면 처음 것만 쓴다. **AI가 돌려주지 않은 문단만** 대체한다(문단별 대체). 번역이 비었거나 길이 상한을 넘은 AI 문단도 돌려주지 않은 것으로 보고 대체한다.
- 대체는 대체할 문단의 OCR 글자를 Google 번역(`GoogleLineTranslationClient`)으로 한 번에 번역한다. Google도 실패하거나 개수가 맞지 않으면 요청 전체가 503이다.
- 대체 문단의 가격은 OCR 글자에서 `PriceExtractor`로 찾고, 번역문의 통화 단어를 원문 통화에 맞춘다(`TranslatedCurrencyFixer`, `/lines`와 같음).

### 가격 규칙

- **`confirmed`는 가격이 확실한지만 뜻한다.** AI가 확실하다고 했고(`uncertain` 아님), 금액이 있고, 통화가 ISO 4217에 있는 코드일 때만 `true`다. 형식만 맞는 모르는 코드(예: `XYZ`)는 확정하지 않는다.
- 확정한 가격만 원화로 바꾼다(환율 조회는 `KrwPriceConverter`, `/lines`와 같은 경로·5초 대기 예산).
  - KRW 가격: `krwAmount`는 금액을 원 단위로 반올림한 값, `krwRate`·`rateFetchedAt`은 `null`.
  - **환율을 받지 못하면(환율 장애·시간 초과·모르는 통화) `confirmed=true`이고 `krwAmount`·`krwRate`·`rateFetchedAt`은 `null`이다.** 확실성과 원화 환산 여부는 따로 판단한다.
  - `rateStale`: 환율 제공자 일시 장애로 마지막 성공 환율을 썼으면 `true`.
- 확정하지 않은 가격(AI가 불확실하다고 함, 금액·통화 모름)과 **대체 번역 문단의 가격은 모두 `confirmed=false`** 이고 원화 필드는 `null`이다.

### 오류

`ErrorResponse` 형식(`timestamp`, `status`, `code`, `message`, `path`).

| 상태 | `code` | 경우 |
| --- | --- | --- |
| 400 | `INVALID_REQUEST` | 위 요청 규칙 위반(ID 형식·중복, 크기 불일치, 상자 범위, 한도 초과, JPEG 아님), `image`·`request` 파트 없음, `request` JSON이 깨졌거나 형식이 틀림, `request` 파트의 `Content-Type`이 JSON이 아님, multipart 해석 실패 |
| 401 | - | 로그인하지 않음 |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | multipart 본문을 허용 목록 밖으로 보냄(예: `GET`·`PUT`으로 사진 경로, 끝에 `/`를 붙인 경로). 서버 전체 규칙이며 본문을 읽지 않는다("업로드 단계 메모리") |
| 413 | `PAYLOAD_TOO_LARGE` | multipart 한도 초과(파일 5MB, 요청 6MB). 사용자·IP 한도를 쓴다(아래 "호출 제한"). 프로필 이미지 업로드는 기존대로 400 `INVALID_PROFILE_IMAGE` |
| 429 | `TOO_MANY_REQUESTS` | 호출 제한, 또는 동시 처리 상한(사용자별·전체) 도달(기다리지 않고 거절). `Retry-After`(초) 포함 |
| 503 | `TRANSLATION_PROVIDER_UNAVAILABLE` | AI와 Google 대체 번역이 모두 실패 |

- 오류 메시지에는 요청 글자를 넣지 않는다(JSON 해석 실패는 고정 문구, 검증 실패는 규칙 문구만). `request` 파트가 JSON이 아니거나 multipart 해석이 실패하면(`HttpMediaTypeNotSupportedException`, `MultipartException`) 고정 문구 400이며 이 경로에만 적용한다(다른 엔드포인트의 기존 응답은 그대로).

### 호출 제한

`/lines`와 같은 값의 별도 버킷(`RateLimitBucket.TRANSLATION_PHOTO_*`, 임시값): 사용자별 1분 10회·하루 100회, IP별 1분 20회·하루 300회, 서버 전체 1시간 300회·하루 2000회. 한 번에 판정하는 묶음(사용자·IP 묶음, 전체 묶음) 안에서 하나라도 넘으면 429이며 그때는 그 묶음의 어느 한도도 쓰지 않는다. IP는 접속 주소(`getRemoteAddr`)만 쓴다(`/lines`와 같은 이유).

요청이 지나가는 순서와 한도를 쓰는 위치:

multipart는 지연 해석한다(`spring.servlet.multipart.resolve-lazily=true`). `DispatcherServlet`은 요청을 감싸기만 하고, 파트는 컨트롤러 인자 해석(`@RequestPart`)이 처음 읽을 때 해석한다. 아래 1·2는 Spring Security 필터 체인 안이며 `DispatcherServlet`보다 먼저다.

1. **multipart 허용 목록**(`MultipartAllowlistFilter`, 체인 맨 앞의 방화벽 뒤, 토큰 인증 앞). Content-Type이 `multipart/`로 시작하는데 (메서드, 경로)가 `POST /api/v1/translation/photo` 또는 `PUT /api/v1/users/me/profile-image`가 아니면 본문을 읽지 않고 **415 `UNSUPPORTED_MEDIA_TYPE`**(`ErrorResponse` 형식)으로 끝낸다. 로그인 여부와 무관하며 한도를 쓰지 않는다. 정규화되지 않은 경로(`//`, `;`, 인코딩한 `/` 등)는 그 전에 Tomcat이나 Security 방화벽(`StrictHttpFirewall`)이 400으로 거절한다.
2. **로그인 확인**. 로그인하지 않으면 401이며 multipart를 해석하지 않고 한도를 쓰지 않는다. 1·2에서 읽지 않은 본문은 Tomcat이 `max-swallow-size`(2MB)까지 버리며 읽는다(메모리에 쌓지 않음).
3. 핸들러 매핑(`DispatcherServlet`). multipart는 아직 해석하지 않는다.
4. **사용자별·IP별 한도 차감**(`PhotoTranslationRateLimitInterceptor.preHandle`, 컨트롤러 인자 해석 전). 사용자 키는 JWT `sub`다. 그래서 그 뒤에 실패하는 요청 — multipart 해석 실패(크기 초과 413, 깨진 본문 400), `@Valid` 실패(문단 0개·51개 이상, 언어 코드 형식, 크기 범위 등), `request` JSON 해석 실패, `image`·`request` 파트 없음, `request` 파트가 JSON이 아님, 사진 검사·문단 검증 실패, 자리 부족 429 — 도 **모두 이 한도를 쓴다.** 큰 사진에 잘못된 `request`를 붙이거나 크기를 넘겨 한도 없이 반복할 수 없고, 한도를 넘은 요청은 multipart를 해석하지 않는다.
5. **컨트롤러 인자 해석**: 여기서 multipart를 해석한다. 크기 초과는 413 `PAYLOAD_TOO_LARGE`, 깨진 multipart는 400 `INVALID_REQUEST`다. 이어서 `request` JSON 해석·`@Valid`.
6. 서비스의 사진 검사·문단 검증. 5·6에서 실패하면 자리와 전체 한도는 쓰지 않는다.
7. 동시 처리 자리(아래). 없으면 429이며 **전체 한도는 쓰지 않는다**(4의 사용자·IP 한도는 이미 썼고 되돌리지 않는다).
8. **전체(GLOBAL) 한도 차감**(`PhotoTranslationService`, 검증을 통과하고 자리를 잡은 뒤). 잘못된 요청이나 거절된 요청으로 전체 한도를 소진할 수 없다. 여기서 429가 나도 4의 차감은 되돌리지 않는다.
9. 번역 제공자 호출. 실패해도 한도는 되돌리지 않는다.

413·400 응답은 `GlobalExceptionHandler`가 요청 URI로 사진 경로를 가려 만든다. 지연 해석에서도 예외가 같은 요청에서 나므로 응답 형식은 전과 같다(`PhotoTranslationLimitsIT`, `PhotoTranslationNoStorageIT`에서 확인).

검증: `PhotoTranslationLimitsIT`가 실제 내장 Tomcat에 multipart 요청을 보내 4 뒤에서 실패하는 요청(`@Valid` 실패, JSON 해석 실패, 파트 없음, JSON이 아닌 `request` 파트, JPEG가 아닌 사진, 크기 초과 413, 경계가 닫히지 않은 multipart 400)이 모두 사용자·IP 한도를 한 번씩 쓰고 전체 한도는 쓰지 않음을 확인한다. `MultipartPublicPathIT`는 로그인하지 않은 사진 요청이 해석 없이 401로 끝나고, 허용 목록 밖의 multipart가 해석 없이 415로 끝남을 확인한다(아래 "업로드 단계 메모리").

### 동시 처리 상한

요청마다 사진 사본(최대 약 5MB와 base64 사본)이 AI 호출 시간 제한(최대 90초)과 대체 번역 동안 메모리에 머문다. 이 구간을 `PhotoTranslationSlots`가 두 가지 자리로 제한한다. 자리가 없으면 기다리지 않고 바로 **429 `TOO_MANY_REQUESTS` + `Retry-After: 3`**(임시값)으로 거절한다.

| 속성 | 임시값 | 뜻 |
| --- | --- | --- |
| `translation.photo.max-concurrent` | 4 | 서버 전체 동시 처리 수 |
| `translation.photo.max-concurrent-per-user` | 1 | 사용자(JWT `sub`) 한 명의 동시 처리 수. 계정 하나가 글자 많은 요청을 동시에 보내 전체 자리를 모두 차지하지 못하게 한다 |

- 사용자 자리를 먼저 잡고 전체 자리를 잡는다. 전체 자리가 없으면 잡았던 사용자 자리를 돌려준다. 두 값 모두 1보다 작으면 1로 본다.
- 자리는 AI 실패·대체 번역 실패·전체 한도 429·예외 모두 try-with-resources로 돌려준다. 사용자 항목은 처리 중인 요청이 0이 되면 지운다(사용자 수만큼 쌓이지 않음).
- 검증: `PhotoTranslationSlotsTest`(속성 바인딩, 0 이하 보정, 사용자별 거절·항목 삭제), `PhotoTranslationLimitsTest`(순서: 검증 → 자리 → 전체 한도 → AI, 자리 2개 동시 처리), `PhotoTranslationLimitsIT`(HTTP에서 같은 사용자 두 번째 동시 요청 429·다른 사용자 수용·전체 자리 부족 429와 `Retry-After: 3`).

**자리 부족 거절 때 한도를 되돌리지 않는다.** 되돌리면 자리 부족 429를 이용해 한도 없이 업로드를 반복할 수 있기 때문이다(4단계의 목적). 그 대신 다음 문제가 남는다.

- 다른 사용자들이 전체 자리 4개를 차지하고 있는 동안(요청 하나 최대 약 90초) 재시도하는 사용자는 재시도마다 자기 사용자·IP 한도를 쓴다. 3초마다 다시 보내면 1분 안에 사용자 한도 10회를 다 써서, 자리가 난 뒤에도 최대 1분 동안 호출 제한 429를 받는다. 같은 IP(공용 와이파이 등)의 다른 사람도 IP 한도를 함께 쓴다.
- 계정 여러 개로 전체 자리를 계속 차지하는 것은 사용자별 상한만으로는 막지 못한다(가입 인증이 없음, `/lines`와 같은 남은 과제).

**앱 재시도 권고**(앱 코드는 아직 바꾸지 않았다): 429를 받으면 `Retry-After`만큼 기다린 뒤 **자동 재시도는 한 번까지만** 하고, 그래도 429면 "잠시 뒤 다시 시도" 안내와 수동 재시도 버튼으로 넘긴다. 같은 사진을 연속으로 자동 재시도하지 않는다(재시도마다 사용자 한도를 쓴다). 사용자가 다른 사진을 찍었으면 진행 중인 요청을 기다리거나 취소한 뒤 보낸다(사용자별 동시 처리 1).

### 업로드 단계 메모리

동시 처리 자리는 서비스 안에서 잡으므로 그 앞의 업로드 단계(multipart 해석, `image.getBytes()` 사본)는 덮지 못한다. 지금 설정(2026-11-26 확인):

| 설정 | 값 | 출처 |
| --- | --- | --- |
| `spring.servlet.multipart.max-file-size` / `max-request-size` | 5MB / 6MB | `application.properties` |
| `spring.servlet.multipart.file-size-threshold` | 6MB(파트를 메모리에만 둠, 사진 비저장) | `application.properties` |
| `spring.servlet.multipart.resolve-lazily` | true — 핸들러 인자 해석 때 해석(핸들러 매핑 전에는 해석하지 않음) | `application.properties` |
| multipart 허용 목록 | `POST /api/v1/translation/photo`, `PUT /api/v1/users/me/profile-image`만. 나머지 multipart는 415 | `MultipartAllowlistFilter`(`SecurityConfig`에서 등록) |
| `spring.mvc.formcontent.filter.enabled` | false — Spring Boot 기본 `FormContentFilter`를 끈다(아래 "form 본문", 보안 점검 H1) | `application.properties` |
| `server.tomcat.threads.max` | 200(기본) | 설정 없음 |
| `server.tomcat.max-connections` / `accept-count` | 8192 / 100(기본) | 설정 없음 |
| `server.tomcat.max-swallow-size` | 2MB(기본). 본문을 읽지 않고 거절한 요청(예: 415, 401)에서 Tomcat이 버리며 읽는 상한. 메모리에 쌓지 않는다 | 설정 없음 |

요청 하나가 쓰는 메모리(추정, 실측 아님):

- 업로드 단계: multipart 파트 버퍼 최대 약 6MB. 컨트롤러까지 가면 `getBytes()` 사본 5MB가 더해져 약 11MB. 허용 목록 밖이거나(415) 로그인하지 않았거나(401) 사용자·IP 한도에서 거절된(429) 요청은 해석하지 않으므로 파트 버퍼를 쓰지 않는다.
- 처리 단계(자리를 잡은 뒤): 사진 5MB + base64 약 6.7MB + SDK 요청 본문 직렬화 약 7MB + 위 파트 버퍼 → 약 25MB.

**multipart를 해석해 메모리에 올릴 수 있는 요청은 허용 목록의 두 경로(`POST /api/v1/translation/photo`, `PUT /api/v1/users/me/profile-image`)에 로그인해서 보낸 요청뿐이다.** `file-size-threshold=6MB`는 전역 설정이므로, 다른 경로로 보낸 multipart가 해석되지 않게 하는 것은 아래 두 장치다.

- **지연 해석**(`resolve-lazily=true`): 핸들러를 찾기 전에는 해석하지 않는다. 다만 지연 해석만으로는 부족했다. Spring의 multipart 판단(`StandardServletMultipartResolver.isMultipart`)은 HTTP 메서드를 보지 않고 Content-Type만 보므로, `GET` 요청이라도 핸들러가 `@RequestParam`을 받으면 인자 해석(`MultipartRequest.getFiles`)이 본문 전체를 해석했다. 로그인 없이 열린 환율·암호화폐 조회(`/api/v1/exchange/rates`·`/history`, `/api/v1/crypto/price`·`/history`)와 `/api/v1/users/check-login-id`가 여기에 해당했다(보안 점검 M1).
- **허용 목록 필터**(`MultipartAllowlistFilter`): 위 처리 순서 1. Content-Type이 `multipart/`로 시작하면(대소문자 무시, 메서드 무관) (메서드, 경로)가 허용 목록과 정확히 같을 때만 통과시키고, 나머지는 본문을 읽지 않고 415로 끝낸다. 경로마다 `consumes`를 다는 방식은 새 엔드포인트에서 빠지기 쉬워 한곳에서 막는다.
  - 위치: Spring Security 필터 체인 안, 토큰 인증(`BearerTokenAuthenticationFilter`) 앞. 정규화되지 않은 경로(`//`, `;`, 인코딩한 `/`·`.`)는 Tomcat(인코딩한 `/`)이나 체인 맨 앞의 방화벽이 먼저 400으로 거절하고, 허용 경로 비교는 보안 규칙과 같은 `PathPatternRequestMatcher`(MVC 핸들러 매핑과 같은 경로 해석)로 한다. 그래서 끝 `/`, 대소문자가 다른 경로는 허용하지 않고, 글자를 인코딩한 경로(`%70hoto`)는 MVC와 같은 경로로 본다. 빈으로 등록하지 않는다(빈이면 서블릿 필터로 한 번 더 등록된다).
  - 인증보다 앞이라 로그인이 필요한 경로라도 허용 목록 밖의 multipart는 401이 아니라 415다. 허용 경로로 로그인 없이 보낸 multipart는 그대로 401이다.
  - 오류 응답은 `GlobalExceptionHandler`를 거치지 않으므로 필터가 같은 `ErrorResponse` 형식을 직접 쓴다(`CustomAuthenticationEntryPoint`와 같은 방식). 로그는 DEBUG로 사유 종류만 남긴다(경로·본문 없음).
  - 부수 효과: 로그인처럼 JSON 본문을 받는 공개 경로에 multipart를 보내면 전에는 `HttpMediaTypeNotSupportedException`으로 500과 ERROR 로그(스택 포함)가 났는데, 이제 415다. 다른 엉뚱한 Content-Type(예: `text/plain`)의 500은 그대로다(아래 "미검증·남은 일").
- 검증: `MultipartPublicPathIT`가 실제 내장 Tomcat에서 요청 래퍼로 파트·파라미터 접근(`getParts`, `getPart`, `getParameter*`)을 기록해, 실제 `ExchangeController`·`CryptoController`·`UserController`(서비스는 대역)로 보낸 `GET`+multipart, 공개 `POST`(로그인, 텍스트 번역), 없는 경로가 정상·깨진 본문 모두 해석 없이 415로 끝남을 확인한다. 필터를 빼면 `GET /api/v1/exchange/rates`에서 `getParts` 기록이 남아 실패한다. 메서드·끝 `/`·대소문자 변형은 로그인해도 415, `//`·`;`·`%2F`는 400, 모두 해석 없음도 확인한다. 로그인하지 않은 `PUT /api/v1/users/me/profile-image`와 글자를 인코딩한 `POST /api/v1/translation/%70hoto`도 해석 없이(읽은 바이트 0) 401이다(인코딩 경로가 `/translation/**` 공개 규칙으로 새지 않음). 판정 규칙(대소문자 무시, 앞 공백, `multipart/mixed`, JSON 요청 통과)은 `MultipartAllowlistFilterTest`가 본다.
- **form 본문(보안 점검 H1)**: Spring Boot가 기본으로 등록하는 `FormContentFilter`(순서 -9900, Spring Security와 허용 목록 필터보다 앞)는 메서드가 `PUT`·`PATCH`·`DELETE`이고 Content-Type이 `application/x-www-form-urlencoded`이면 경로·로그인과 상관없이 본문 전체를 크기 제한 없이 문자열로 읽는다(`FormHttpMessageConverter.read`). Tomcat `maxPostSize`(2MB)는 Tomcat이 파라미터를 직접 해석할 때(`POST`)만 적용되므로 여기에는 걸리지 않는다. 이 앱에는 그 파라미터를 쓰는 핸들러가 없어(PATCH는 JSON, PUT은 multipart, DELETE는 본문 없음, 앱도 같음) `spring.mvc.formcontent.filter.enabled=false`로 껐다.
  - 재현(2026-11-26, `FormBodyPublicPathIT`, 실제 내장 Tomcat): 로그인 없이 256KB urlencoded 본문을 `PUT`·`PATCH`·`DELETE`로 `/api/v1/auth/login`(공개, 405), `/api/v1/no-such-path`(404), `/api/v1/users/me/nickname`(로그인 필요, 401)에 보냈다. 끄기 전에는 9개 요청 모두 응답 전에 본문 262,144바이트를 모두 읽었고(로그인 필요 경로도 401 전에 읽음), 끈 뒤에는 응답 코드는 같고 읽은 바이트는 0이다. 설정을 다시 켜면 이 테스트가 실패한다. 대조로 로그인한 JSON `PATCH`(닉네임 200, 비밀번호 204)는 본문을 읽는 것이 기록되고, 본문 없는 `DELETE`(프로필 이미지, 회원 탈퇴)는 204다.
  - 위험(추정, 재현하지 않음): 끄기 전에는 로그인하지 않은 사람이 아무 경로로 큰 urlencoded 본문(chunked 포함)을 보내면 요청마다 본문 전체가 힙에 문자열로 쌓였다(문자열·파라미터 맵 사본으로 본문 크기의 몇 배). 동시 요청 수 × 본문 크기만큼 힙이 차 메모리 부족이 날 수 있었다. 큰 본문과 메모리 부족은 시험하지 않았다(256KB만 보냄).
  - form 파라미터가 필요한 엔드포인트를 새로 만들면 `POST`로 받는다(Tomcat이 2MB 한도로 해석). `PUT`·`PATCH`·`DELETE` form을 받아야 하면 이 필터를 다시 켜지 말고 크기 상한을 먼저 정한다.
- 고치기 전(`resolve-lazily` 기본값 false)에는 `DispatcherServlet`이 핸들러를 찾기 전에 모든 경로의 multipart를 해석했고, 지연 해석만 넣은 뒤에도 위 `@RequestParam` 경로에서는 해석했다. 그래서 로그인하지 않은 사람이 이런 경로에 6MB multipart를 동시에 보내면 요청마다 약 6MB가 힙에 올라갔고 어떤 호출 한도에도 걸리지 않았다(스레드 200 × 6MB ≈ 1.2GB). 깨진 multipart는 500과 ERROR 로그를 냈다.

동시 요청 수 × 요청당 바이트로 본 상한(추정):

- 처리 단계: 전체 자리 4 × 약 25MB ≈ **100MB**.
- 업로드 단계: 해석 중인 요청은 허용 목록을 지나 로그인하고 사용자·IP 한도를 통과한 사진 요청과 로그인한 프로필 이미지 요청뿐이다. 그래도 동시에 해석 중인 요청 수의 최종 상한은 Tomcat 작업 스레드 수(200)이며, 200 × 약 11MB ≈ **2.2GB**가 최악이다. 이 최악에 이르려면 로그인한 계정이 여러 개 필요하다(사진 경로는 계정당 1분 10회, IP당 20회. 프로필 이미지 경로에는 호출 한도가 없다).

**업로드 단계의 별도 동시 처리 제한(필터·스레드 수)은 적용하지 않았다.** 지연 해석과 허용 목록 필터로 로그인 없는 해석은 없앴다. 남은 이유:

- 사진 경로 전체 동시 업로드 수를 제한하는 필터는 그 자체로 값싼 공격 수단이 된다. 로그인한 계정 몇 개가 사진을 아주 느리게 올려 그 자리를 잡고 있으면 모든 사용자의 사진 번역이 막힌다. 사용자별로 세려면 인증 뒤에 둬야 하고, 계정을 여러 개 만들면(가입 인증 없음) 효과가 없다.
- `server.tomcat.threads.max`를 줄이면 모든 API에 영향을 준다. 알맞은 값은 배포 서버의 메모리를 정해야 알 수 있는데 아직 정하지 않았다.
- 사용자·IP 한도는 해석 전에 판정하므로 한도를 넘은 요청은 해석하지 않는다. 다만 한도 안에서 동시에 몰려 온 요청(계정당 1분 10회까지)의 해석 메모리는 막지 못한다.

**운영 권장값**(배포 때 정한다):

- JVM 힙: 업로드 상한(스레드 수 × 약 11MB) + 처리 상한(약 100MB) + 앱 기본 사용량 이상. 기본 스레드 200이면 `-Xmx` 3GB 이상. 힙을 1GB 안팎으로 두려면 `server.tomcat.threads.max=50`(업로드 상한 약 550MB)으로 줄이고, 다른 API 응답 시간에 문제가 없는지 확인한다.
- 앞에 프록시(nginx 등)를 두면 IP별 동시 연결 수(`limit_conn`)와 본문 수신 시간 제한(`client_body_timeout`)을 둔다. 본문 버퍼링은 임시 파일을 쓸 수 있으므로 비저장 범위와 함께 다시 검증한다(아래 "프록시").

## 구현

- `PhotoTranslationRateLimitInterceptor`(사용자·IP 호출 제한) → `TranslationController.translatePhoto`(인자 해석·`@Valid`) → `PhotoTranslationService`(검증 → `PhotoTranslationSlots` 동시 처리 자리 → 전체 호출 제한 → AI → 문단별 대체 → 가격) → `ClaudePhotoTranslationClient` / `GoogleLineTranslationClient`.
- `ClaudePhotoTranslationClient`: 모델은 속성 `translation.photo.model`(기본 `claude-sonnet-5-5`, 이름만 정해 둔 값). 구조화 출력, 시간 제한 30초 + 글자당 12ms(최대 90초), `max_tokens` = min(16000, 4096 + 문단 수×32 + 글자 수×4). 사진 속 글자는 지시가 아니라고 시스템 프롬프트에서 정한다. 키는 `/lines`와 같은 `ANTHROPIC_API_KEY`이며, 없으면 모든 문단을 Google로 대체한다.

## Tripbler 쪽 비저장 범위

Tripbler 서버가 통제하는 범위다. 사진과 글자는 요청을 처리하는 동안 메모리에만 두고, 디스크에 저장하지 않으며 로그에 남기지 않는다.

- **multipart 임시 파일**: Spring(내장 Tomcat)은 `file-size-threshold`보다 큰 파트를 `spring.servlet.multipart.location`(기본은 Tomcat 임시 폴더)에 임시 파일로 쓴다. `application.properties`에서 `spring.servlet.multipart.file-size-threshold=6MB`(요청 한도 이상)로 두어 파트를 메모리에만 둔다. 이 설정은 전역이라 프로필 이미지 업로드 파트도 메모리에 둔다(5MB 이하). 이 threshold가 실제로 적용되는 요청은 허용 목록 필터를 지나 로그인한 사진 번역·프로필 이미지 요청뿐이다. 다른 경로로 보낸 multipart는 필터가 본문을 읽지 않고 415로 끝내므로 메모리에도 임시 파일에도 쓰지 않는다(위 "업로드 단계 메모리").
  - 검증: `PhotoTranslationNoStorageIT`가 실제 내장 Tomcat에 4MB 사진을 multipart로 보내, **처리 도중**(파트가 살아 있는 동안)과 요청 뒤에 임시 폴더가 비어 있음을 확인한다. 대조 테스트는 threshold를 0으로 둔 별도 서버에서 같은 측정으로 임시 파일이 잡힘을 확인한다. 임시 파일은 요청이 끝나면 지워지므로 요청 뒤만 보는 측정은 파일 생성을 놓친다.
- **로그**: 사진 바이트, base64, 인식 글자, 번역문을 어떤 로그에도 남기지 않는다. 개수, 토큰 수, 걸린 시간, 오류 종류만 남긴다.
  - `GlobalExceptionHandler`: JSON 해석 실패(`HttpMessageNotReadableException`)와 `@Valid` 검증 실패는 로그를 남기지 않고, 업무 검증 실패(`BusinessException`)는 규칙 문구만 WARN으로 남긴다. `PhotoTranslationControllerTest`가 표식 글자로 이를 확인한다(`brokenJsonPart_errorLogHasNoRequestText`, `invalidRequest_warnLogHasNoParagraphText`).
  - 서비스·클라이언트 로그는 개수·시간·토큰 수·예외 클래스 이름만 남긴다. SDK 예외는 메시지에 응답 원문이 담길 수 있어 cause로 넘기지 않는다.
  - **운영에서는 `ANTHROPIC_LOG` 환경 변수를 설정하지 않는다.** SDK가 요청·응답 본문(사진 base64·글자)을 로그로 남길 수 있다. 실제 측정 테스트(`ClaudePhotoTranslationLiveIT`)도 이 변수가 설정돼 있으면 실행을 거부한다(테스트 출력이 `build/test-results`에 저장되기 때문).
- **실제 측정 결과**: `./gradlew liveTest`로만 돌고, 결과·시료 경로가 저장소 안이면 빌드 폴더(git 제외) 아래만 허용한다(`translation-photo-measurements.md`).
- **프록시**: 지금은 프록시 없는 단일 서버다. 앞으로 nginx 같은 프록시를 앞에 두면 요청 본문 버퍼링(예: `client_body_temp`, `client_body_buffer_size`)과 접근 로그 설정을 같은 기준으로 다시 검증한다.

## AI 제공업체 쪽 보관(별개)

위 절은 Tripbler가 통제하는 범위만 다룬다. 제공업체가 사진과 글자를 얼마나 보관하고 학습에 쓰는지는 제공업체 정책과 계약(조직 설정 포함)이 정한다. 아래는 2026-11-26에 공개 문서만 읽고 정리한 내용이다. **조직 콘솔 설정과 계약 내용은 아직 확인하지 않았다.** AI 제공업체와 모델을 아직 최종 선택하지 않았으므로(2026-11-26 사용자 결정), 이 절과 앱 안내에 넣을 보관 정책 문구는 AI를 정한 뒤 확정한다. 동의 기본 문구는 그대로 둔다.

### Anthropic(Claude API, 주 번역)

- 전송 방식: 사진은 Files API를 쓰지 않고 요청 본문에 base64로 담아 보낸다(`ClaudePhotoTranslationClient`). 아래 기본 보관 규정이 적용된다.
- 기본 보관: API 입력과 출력은 받거나 만든 뒤 30일 안에 백엔드에서 자동 삭제된다.
  - 출처: [How long do you store my organization's data](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data) (문서 날짜 2026-07-01)
- 학습: 상업 제품(API 포함)의 입력·출력은 기본적으로 모델 학습에 쓰지 않는다. 상업 약관도 고객 콘텐츠로 학습하지 않는다고 정한다.
  - 출처: [Is my data used for model training](https://privacy.claude.com/en/articles/7996868-is-my-data-used-for-model-training) (2026-08-18), [Commercial Terms](https://www.anthropic.com/legal/commercial-terms)
- 예외:
  - 자동 안전 시스템이 사용 정책 위반으로 표시한 요청은 입력·출력을 최대 2년, 분류 점수를 최대 7년 보관한다. 법적 요구가 있을 때도 더 오래 보관할 수 있다.
  - 피드백을 보내면 관련 데이터를 5년 보관하고 학습에 쓸 수 있다. Tripbler 서버는 피드백을 보내지 않는다.
  - 2026-06-09부터 특정 "covered models"는 ZDR 조직에서도 30일 보관한다([Data retention practices for covered models](https://privacy.claude.com/en/articles/15425996-data-retention-practices-for-covered-models)). 쓰려는 모델이 여기에 해당하는지는 모델을 정할 때(Task 14) 확인한다.
- ZDR(무보관): Anthropic 승인을 받은 조직만 쓸 수 있으며 영업팀에 신청한다. ZDR에서도 법 준수나 오용 방지를 위한 보관과 안전 분류 결과 보관은 남는다. 조직의 현재 보관 기간은 콘솔의 Settings > Privacy Controls > Data retention period에서 확인한다.
  - 출처: [Zero data retention agreement](https://privacy.claude.com/en/articles/8956058-i-have-a-zero-data-retention-agreement-with-anthropic-what-products-does-it-apply-to) (2026-10-15)

### Google Cloud Translation(대체 번역, 글자만 전송)

- 사진은 보내지 않고 문단 글자만 보낸다.
- 보관: 번역하는 동안 메모리에만 잠깐 둔다고만 적혀 있다. 요청 정보를 로그에 남기는지, 남긴다면 얼마나 두는지는 문서에 없다.
- 학습: 보낸 콘텐츠를 Google 번역 기능의 학습·개선에 쓰지 않고, 서비스 제공 외의 목적으로 쓰지 않는다.
- 출처: [Data usage](https://docs.cloud.google.com/translate/data-usage), [FAQ](https://docs.cloud.google.com/translate/faq) (두 문서 모두 날짜 표시 없음, 2026-11-26 확인)

### 안내 문구에 미치는 영향

- 지금 동의 문구는 "Tripbler 서버 및 AI 제공업체에 전송"만 말하고 보관 기간은 약속하지 않는다. 위 내용과 어긋나지 않는다.
- "Tripbler는 사진을 저장하지 않습니다"는 위 비저장 범위로 뒷받침된다. 다만 제공업체가 최대 30일(예외 시 더 길게) 보관하므로, 이 문장만 따로 쓰면 전체가 저장되지 않는 것처럼 읽힐 수 있다.
- 보관 기간을 안내에 넣을지, 넣으면 어떤 문장으로 넣을지는 사용자가 정한다. 문구를 바꾸면 `PhotoConsentStore.currentVersion`을 올린다.

## 미검증·남은 일

- **실제 Claude 호출은 아직 하지 않았다.** 모든 테스트는 가짜 클라이언트(대역)를 쓴다. 번역·보정 품질, 구조화 출력 동작, 토큰 사용량, 시간 제한의 적정성은 키와 크레딧을 넣고 확인한다(계획 Task 14). 실제 Google 대체 경로 호출도 확인하지 않았다.
- 제공업체 정책은 공개 문서만 확인했다. 조직 콘솔의 보관 설정, 계약 내용, 안내 문구 결정은 남았다(Task 13).
- 실기기에서 앱과 연결한 업로드, 좌표, 비저장(Task 15).
- 요청 하나의 최악 처리 시간은 `/lines`와 같은 구성(Claude 최대 90초 + Google 대체 + 환율 대기 5초)이다. 앱 시간 제한(120초)과의 차이는 실측 뒤 다시 본다.
- `request` 파트의 `Content-Type`이 JSON이 아닌 요청은 `PhotoTranslationControllerTest.nonJsonRequestPart_returns400_andLogHasNoBodyText`로 400을 확인했다. multipart 해석 자체가 실패하는 요청(닫는 경계가 없는 본문)은 `PhotoTranslationLimitsIT.brokenMultipart_returns400_afterInterceptor`가 실제 Tomcat에서 400 `INVALID_REQUEST`와 사용자·IP 한도 사용을 확인했다. 다른 종류의 깨진 본문(헤더 형식 오류 등)은 확인하지 않았다.
- 동시 처리 상한(전체 4, 사용자별 1), `Retry-After` 3초는 임시값이다.
- 업로드 단계 메모리 상한(약 2.2GB, 스레드 200 기준, 로그인 사용자 요청만)은 코드 분석에 따른 추정이다. 부하 시험으로 실측하지 않았고, 업로드 단계 제한 설정(필터·Tomcat 스레드 수)은 적용하지 않았다(위 "업로드 단계 메모리").
- 로그인하지 않은 urlencoded `PUT`·`PATCH`·`DELETE` 본문을 읽지 않는다는 것은 `FormBodyPublicPathIT`가 요청 래퍼로 본문 스트림 접근과 읽은 바이트 수(0)를 관찰해 확인했다. 힙 사용량과 큰 본문(수백 MB) 동작은 측정하지 않았다. 전체 앱 기동(`TripblerBackendApplicationTests`)은 PostgreSQL이 없어 확인하지 않았다.
- 허용 목록 밖과 로그인하지 않은 multipart를 해석하지 않는다는 것은 `MultipartPublicPathIT`가 요청 래퍼로 파트·파라미터 접근이 없음을 관찰해 확인했다. 힙 사용량을 직접 측정하지는 않았다. 415·401로 끝난 요청의 본문을 Tomcat이 2MB(`max-swallow-size`)까지 버리며 읽고 그보다 크면 연결을 끊는 동작도 실측하지 않았다(테스트는 1MB 본문만 보낸다).
- 허용 목록은 코드에 고정했다. multipart를 받는 엔드포인트를 새로 만들면 `MultipartAllowlistFilter.ALLOWED`에 넣어야 하며, 빠뜨리면 415로 막힌다(안전한 쪽으로 실패).
- JSON 본문을 받는 공개 경로(로그인 등)에 multipart가 아닌 엉뚱한 Content-Type(예: `text/plain`)을 보내면 `HttpMediaTypeNotSupportedException`이 사진 경로가 아니라는 이유로 `handleUnexpectedException`으로 넘어가 500과 ERROR 로그(스택 포함)가 남는다. 본문을 해석하지는 않는다(남은 과제, 낮음). multipart를 보낸 경우는 허용 목록 필터가 먼저 415로 끝내므로 더는 500이 아니다.
- 자리 부족 429 뒤 재시도로 한도를 소진하는 문제는 문서화만 했다. 앱의 429 재시도 동작은 위 권고대로 바꾸지 않았다.
