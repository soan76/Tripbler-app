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
| 400 | `INVALID_REQUEST` | 위 요청 규칙 위반(ID 형식·중복, 크기 불일치, 상자 범위, 한도 초과, JPEG 아님), `image`·`request` 파트 없음, `request` JSON이 깨졌거나 형식이 틀림 |
| 401 | - | 로그인하지 않음 |
| 413 | `PAYLOAD_TOO_LARGE` | multipart 한도 초과(파일 5MB, 요청 6MB). 프로필 이미지 업로드는 기존대로 400 `INVALID_PROFILE_IMAGE` |
| 429 | `TOO_MANY_REQUESTS` | 호출 제한. `Retry-After`(초) 포함 |
| 503 | `TRANSLATION_PROVIDER_UNAVAILABLE` | AI와 Google 대체 번역이 모두 실패 |

- 오류 메시지에는 요청 글자를 넣지 않는다(JSON 해석 실패는 고정 문구, 검증 실패는 규칙 문구만).

### 호출 제한

`/lines`와 같은 값의 별도 버킷(`RateLimitBucket.TRANSLATION_PHOTO_*`, 임시값): 사용자별 1분 10회·하루 100회, IP별 1분 20회·하루 300회, 서버 전체 1시간 300회·하루 2000회. 모두 함께 판정하고 하나라도 넘으면 429이며 그때는 어느 한도도 쓰지 않는다. IP는 접속 주소(`getRemoteAddr`)만 쓴다(`/lines`와 같은 이유). 검증에 실패한 요청은 한도를 쓰지 않고, 검증을 통과한 뒤 번역 제공자 호출이 실패해도 한도는 쓴다.

## 구현

- `TranslationController.translatePhoto` → `PhotoTranslationService`(검증 → 호출 제한 → AI → 문단별 대체 → 가격) → `ClaudePhotoTranslationClient` / `GoogleLineTranslationClient`.
- `ClaudePhotoTranslationClient`: 모델은 속성 `translation.photo.model`(기본 `claude-sonnet-5-5`, 이름만 정해 둔 값). 구조화 출력, 시간 제한 30초 + 글자당 12ms(최대 90초), `max_tokens` = min(16000, 4096 + 문단 수×32 + 글자 수×4). 사진 속 글자는 지시가 아니라고 시스템 프롬프트에서 정한다. 키는 `/lines`와 같은 `ANTHROPIC_API_KEY`이며, 없으면 모든 문단을 Google로 대체한다.

## Tripbler 쪽 비저장 범위

Tripbler 서버가 통제하는 범위다. 사진과 글자는 요청을 처리하는 동안 메모리에만 두고, 디스크에 저장하지 않으며 로그에 남기지 않는다.

- **multipart 임시 파일**: Spring(내장 Tomcat)은 `file-size-threshold`보다 큰 파트를 `spring.servlet.multipart.location`(기본은 Tomcat 임시 폴더)에 임시 파일로 쓴다. `application.properties`에서 `spring.servlet.multipart.file-size-threshold=6MB`(요청 한도 이상)로 두어 파트를 메모리에만 둔다. 이 설정은 전역이라 프로필 이미지 업로드 파트도 메모리에 둔다(5MB 이하).
  - 검증: `PhotoTranslationNoStorageIT`가 실제 내장 Tomcat에 4MB 사진을 multipart로 보내, **처리 도중**(파트가 살아 있는 동안)과 요청 뒤에 임시 폴더가 비어 있음을 확인한다. 대조 테스트는 threshold를 0으로 둔 별도 서버에서 같은 측정으로 임시 파일이 잡힘을 확인한다. 임시 파일은 요청이 끝나면 지워지므로 요청 뒤만 보는 측정은 파일 생성을 놓친다.
- **로그**: 사진 바이트, base64, 인식 글자, 번역문을 어떤 로그에도 남기지 않는다. 개수, 토큰 수, 걸린 시간, 오류 종류만 남긴다.
  - `GlobalExceptionHandler`: JSON 해석 실패(`HttpMessageNotReadableException`)와 `@Valid` 검증 실패는 로그를 남기지 않고, 업무 검증 실패(`BusinessException`)는 규칙 문구만 WARN으로 남긴다. `PhotoTranslationControllerTest`가 표식 글자로 이를 확인한다(`brokenJsonPart_errorLogHasNoRequestText`, `invalidRequest_warnLogHasNoParagraphText`).
  - 서비스·클라이언트 로그는 개수·시간·토큰 수·예외 클래스 이름만 남긴다. SDK 예외는 메시지에 응답 원문이 담길 수 있어 cause로 넘기지 않는다.
  - **운영에서는 `ANTHROPIC_LOG` 환경 변수를 설정하지 않는다.** SDK가 요청·응답 본문(사진 base64·글자)을 로그로 남길 수 있다.
- **프록시**: 지금은 프록시 없는 단일 서버다. 앞으로 nginx 같은 프록시를 앞에 두면 요청 본문 버퍼링(예: `client_body_temp`, `client_body_buffer_size`)과 접근 로그 설정을 같은 기준으로 다시 검증한다.

## AI 제공업체 쪽 보관(별개)

위 항목은 Tripbler가 통제하는 범위만 다룬다. Anthropic 등 AI 제공업체가 사진과 글자를 얼마나 보관하는지, 학습에 쓰는지는 제공업체 정책과 계약(조직 설정 포함)으로 정해진다. 이는 **아직 확인하지 않았고** 계획 Task 13에서 따로 확인해 이 문서에 따로 적는다. 앱 안내 문구에 보관 정책을 넣을지는 둘 다 확인한 뒤 정한다.

## 미검증·남은 일

- **실제 Claude 호출은 아직 하지 않았다.** 모든 테스트는 가짜 클라이언트(대역)를 쓴다. 번역·보정 품질, 구조화 출력 동작, 토큰 사용량, 시간 제한의 적정성은 키와 크레딧을 넣고 확인한다(계획 Task 14). 실제 Google 대체 경로 호출도 확인하지 않았다.
- 제공업체 보관·학습 정책(Task 13).
- 실기기에서 앱과 연결한 업로드, 좌표, 비저장(Task 15).
- 요청 하나의 최악 처리 시간은 `/lines`와 같은 구성(Claude 최대 90초 + Google 대체 + 환율 대기 5초)이다. 앱 시간 제한(120초)과의 차이는 실측 뒤 다시 본다.
- multipart 해석 자체가 실패하는 요청(경계 문자열이 깨진 본문 등)과 `request` 파트의 `Content-Type`이 JSON이 아닌 요청은 지금 전역 처리(500 또는 Spring 기본 응답)를 따른다. 로그에는 예외 종류와 경로만 남는다.
