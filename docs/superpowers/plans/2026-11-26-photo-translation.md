# 사진 번역 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 찍은 사진을 기기에서 정리·OCR한 뒤, 사진과 문단을 새 API `/api/v1/translation/photo`로 한 번에 보낸다. AI가 보정·번역한 결과를 사진 위 흰 상자로 보여 준다.

**Architecture:**
- 앱: 기준 사진 하나(EXIF 회전 반영, 축소, JPEG)로 OCR·전송·표시를 모두 처리해 좌표계를 하나로 맞춘다. 새 Notifier가 촬영 → 정리 → OCR → 동의 → 전송 → 결과를 작업 번호로 관리한다.
- 백엔드: `controller → service → client` 구조에 사진 번역 경로를 추가한다. AI 결과는 문단 ID로 검증하고, 빠지거나 실패한 문단은 Google로 문단별 대체 번역한다. 원화 환산은 기존 줄 번역과 같은 환율 경로를 공유한다.
- 진행 순서: 가짜 클라이언트로 구현을 끝낸다 → 제공업체 정책과 안내 문구를 확인한다 → 실제 Claude 측정 → 실기기 확인 → 번역 탭 교체.

**Tech Stack:**
- Flutter, Riverpod 3, `camera`, `google_mlkit_text_recognition`, `http`, `shared_preferences`, `flutter_secure_storage`
- 새 의존성: `image`(순수 Dart)
- Spring Boot 4.1 / Java 17, `anthropic-java` 3.3.0, Spring multipart, JUnit/MockMvc

**Spec:** `docs/superpowers/specs/2026-11-26-photo-translation-design.md`

## Global Constraints

- 파일 하나는 450줄을 넘지 않는다(앱 `AGENTS.md`, `backend/AGENTS.md`). 줄 수만 맞추려고 쪼개지 않는다.
- 사진 바이트, base64, 인식 글자, 번역문은 앱과 서버의 어떤 로그에도 남기지 않는다. 크기, 개수, 시간, 오류 종류만 남긴다.
- 읽지 못한 부분 표시는 정확히 `[읽을 수 없음]`이다. 앱 상수 `unreadableMarker`와 서버 상수 `PhotoTranslationResponse.UNREADABLE_MARKER`는 같은 값이어야 한다.
- 동의 안내 문구: "번역을 위해 촬영한 사진과 인식된 글자를 Tripbler 서버 및 AI 제공업체에 전송합니다." 버튼은 `동의하고 번역`과 `취소`다.
- 촬영 화면 고정 안내: "촬영한 사진은 AI 번역을 위해 전송됩니다". 보관·삭제·학습 관련 문구는 Task 13 전에는 넣지 않는다.
- 새 엔드포인트는 로그인이 필요하다(`SecurityConfig`).
- 임시값은 코드 한곳에 모으고, 주석으로 `// 임시값: <확정 근거> 뒤 확정`을 단다(아래 표).
- 커밋은 사용자가 요청할 때만 한다. 각 Task의 "커밋" 단계는 사용자 승인 뒤 진행한다. 메시지 끝에는 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` 줄을 넣는다.
- 화면이 바뀌는 Task는 `design-improver`를 거친 뒤 `code-inspector`(Sonnet)로 점검한다. 업로드·`SecurityConfig`를 바꾸는 Task는 `security-reviewer`도 거친다.
- 가짜 클라이언트 테스트만으로는 실제 번역 연동을 완료로 보지 않는다. 실제 연동 완료는 Task 14의 기록이 있어야 한다.

### 설정값: 개발용 임시값과 확정 시점

| 항목 | 위치 | 개발용 임시값 | 확정 Task |
|---|---|---|---|
| 기준 사진 긴 변 | `PhotoNormalizer.maxLongSide` | 2048 | 14 |
| JPEG 품질 | `PhotoNormalizer.jpegQuality` | 85 | 14 |
| 모델 | `translation.photo.model` | `claude-sonnet-5-5`(이름만 정해 둔 값, 품질 미확인) | 14 |
| 서버 시간 제한 | `ClaudePhotoTranslationClient` | 30초 + 글자당 12ms, 최대 90초 | 14 |
| `max_tokens` | `ClaudePhotoTranslationClient` | min(16000, 4096 + 문단 수×32 + 글자 수×4) | 14 |
| 앱 HTTP 시간 제한 | `PhotoTranslationApiService.defaultTimeout` | 120초 | 14 |
| 문단 한도 | 앱 `PhotoParagraphLimits` / 서버 DTO·`PhotoRequestValidator` | 50개, 문단당 300자, 전체 4000자 | 14 |
| 호출 제한 | `RateLimitBucket.TRANSLATION_PHOTO_*` | `/lines`와 같음(사용자 1분 10회·하루 100회, IP 1분 20회·하루 300회, 전체 1시간 300회·하루 2000회) | 14 |
| multipart | `application.properties` | 파일 5MB, 요청 6MB(기존), `file-size-threshold=6MB` | 14 |
| 동의 안내 버전 | `PhotoConsentStore.currentVersion` | 1 | 13(바꿀 내용이 있으면 올림) |

## Review Focus

1. 동의 안내에서 `동의하고 번역`을 빠르게 두 번 누름 → 업로드는 한 번만 일어난다. 테스트는 Task 10에 둔다.
2. 갤러리에서 고른 디코딩할 수 없는 형식(HEIC 등)이나 손상된 파일 → 앱이 멈추지 않는다. "이 사진은 읽을 수 없어요"와 재촬영을 보여 주고, 아무것도 보내지 않는다. 테스트는 Task 7, 10에 둔다.
3. 가로로 찍은 사진, EXIF 방향 6·8 → 기준 사진이 바로 서고, 상자가 원문 위에 놓인다. 테스트는 Task 7, 11에 둔다.
4. 업로드 중 재촬영, 탭 이탈, 화면 제거 → 늦은 응답은 반영하지 않고, 임시 파일은 지워진다. 테스트는 Task 10에 둔다.
5. 서버가 보낸 JSON 파트가 깨졌거나 아주 길 때 → 400으로 끝난다. 오류 로그에 요청 글자가 들어가지 않는다. 테스트는 Task 5에 둔다.

---

## 1부. 백엔드(가짜 클라이언트로 완결)

### Task 1: 원화 환산을 공용 컴포넌트로 분리

**Files:**
- Create: `backend/src/main/java/com/tripbler/backend/translation/service/KrwPriceConverter.java`
- Modify: `backend/src/main/java/com/tripbler/backend/translation/service/LineTranslationService.java`(`RATE_LOOKUP_*`, 실행기, `krwRatesFor`, `krwRates`, `toPrice`의 환산 부분을 옮김)
- Test: `backend/src/test/java/com/tripbler/backend/translation/service/KrwPriceConverterTest.java`. 기존 `LineTranslationServiceTest.java`는 바꾸지 않고 통과해야 한다.

**Interfaces:**
- Produces:
  - `@Component class KrwPriceConverter implements DisposableBean`
  - `Map<String, Optional<ExchangeRateResponse>> ratesFor(Set<String> currencies)`: 전체 대기 5초, 동작은 지금 `krwRatesFor`와 같다.
  - `Optional<KrwConversion> convert(BigDecimal amount, String currency, Map<String, Optional<ExchangeRateResponse>> rates)`: KRW이거나 환율이 없으면 empty.
  - `record KrwConversion(BigDecimal krwAmount, BigDecimal krwRate, LocalDateTime fetchedAt, boolean stale)`
  - 테스트용 생성자 `KrwPriceConverter(ExchangeService, Duration budget)`

- [ ] **Step 1: 실패하는 테스트 작성** — `convert`가 KRW이면 empty를 돌려준다. JPY 980에 환율 9.29이면 `krwAmount` 9104(HALF_UP, 소수 0자리)를 돌려준다. 환율이 없으면 empty다. `ratesFor`는 예산을 넘긴 통화를 empty로 돌려준다(가짜 `ExchangeService`가 지연).
- [ ] **Step 2: 실행해 실패 확인** — `./gradlew test --tests "*KrwPriceConverterTest"` → 컴파일 실패
- [ ] **Step 3: 구현하고 `LineTranslationService`가 이 컴포넌트를 쓰게 바꾸기** — 생성자에 `KrwPriceConverter`를 추가한다. 테스트용 생성자의 `Duration`은 converter로 넘긴다.
- [ ] **Step 4: 실행해 통과 확인** — `./gradlew test --tests "*KrwPriceConverterTest" --tests "*LineTranslationServiceTest" --tests "*LineTranslationControllerTest"` → PASS. 기존 테스트는 바꾸지 않는다.
- [ ] **Step 5: 커밋(사용자 요청 시)** — `refactor: 줄 번역의 원화 환산을 KrwPriceConverter로 분리`

### Task 2: 사진 번역 DTO와 요청 검증

**Files:**
- Create: `backend/src/main/java/com/tripbler/backend/translation/dto/PhotoTranslationRequest.java`, `PhotoTranslationResponse.java`
- Create: `backend/src/main/java/com/tripbler/backend/translation/service/PhotoImageInspector.java`, `PhotoRequestValidator.java`
- Test: `backend/src/test/java/com/tripbler/backend/translation/service/PhotoImageInspectorTest.java`, `PhotoRequestValidatorTest.java`

**Interfaces:**
- Produces:
  - `record PhotoTranslationRequest(String sourceLanguageCode, String targetLanguageCode, int imageWidth, int imageHeight, List<Paragraph> paragraphs)`
    - 언어 코드 검증은 `LineTranslationRequest`와 같은 `@Pattern`을 쓴다.
    - `imageWidth`, `imageHeight`는 `@Positive`이고 최대 8192다.
    - `paragraphs`는 `@NotNull @Size(min=1,max=50) @Valid`다.
  - 중첩 `record Paragraph(@Pattern(regexp="^p[0-9]{1,3}$") String id, @NotBlank @Size(max=300) String text, @NotNull @Valid Box box)`
  - 중첩 `record Box(@PositiveOrZero double left, @PositiveOrZero double top, @Positive double width, @Positive double height)`
  - `record PhotoTranslationResponse(String sourceLanguageCode, String targetLanguageCode, List<TranslatedParagraph> paragraphs)`
    - 상수 `UNREADABLE_MARKER = "[읽을 수 없음]"`
  - 중첩 `record TranslatedParagraph(String id, String original, String translated, boolean uncertain, TranslationSource translationSource, String pronunciation, List<Price> prices)`
  - `enum TranslationSource { AI, OCR_TEXT }`
  - `record Price(String text, BigDecimal amount, String currency, boolean confirmed, BigDecimal krwAmount, BigDecimal krwRate, LocalDateTime rateFetchedAt, boolean rateStale)`
  - `@Component PhotoImageInspector`
    - `Dimensions inspect(byte[] image)`: JPEG 시작 바이트(`FF D8 FF`)를 확인하고, `ImageIO` 리더로 머리 정보만 읽어 크기를 구한다. JPEG이 아니거나 읽지 못하면 `BusinessException(INVALID_REQUEST, "JPEG 사진만 보낼 수 있습니다.")`를 던진다.
    - `record Dimensions(int width, int height)`
  - `@Component PhotoRequestValidator`
    - `void validate(PhotoTranslationRequest request, PhotoImageInspector.Dimensions actual)`
    - 아래 경우에 `INVALID_REQUEST`를 던진다: 크기 불일치, ID 중복, 상자가 사진 밖(2% 여유), 전체 글자가 4000자 초과
    - 상수 `MAX_TOTAL_CHARACTERS = 4000`(임시값)

- [ ] **Step 1: 실패하는 테스트 작성**
  - `PhotoImageInspectorTest`
    - `inspect_readsSizeFromJpegHeader`: 테스트에서 `ImageIO`로 만든 1536×2048 JPEG → (1536, 2048)
    - `inspect_rejectsPng`: PNG → `INVALID_REQUEST`
    - `inspect_rejectsTruncatedBytes`: 잘린 바이트 → `INVALID_REQUEST`
  - `PhotoRequestValidatorTest`
    - `rejectsSizeMismatch`: 요청 1536×2048, 실제 2048×1536
    - `rejectsDuplicateIds`: `p1` 두 개
    - `rejectsBoxOutside`: right가 width×1.03
    - `acceptsBoxWithinTolerance`: right가 width×1.019
    - `rejectsTotalOver4000`
- [ ] **Step 2: 실행해 실패 확인** — `./gradlew test --tests "*PhotoImageInspectorTest" --tests "*PhotoRequestValidatorTest"` → 컴파일 실패
- [ ] **Step 3: DTO, 검사기, 검증기 구현**
- [ ] **Step 4: 실행해 통과 확인** — 같은 명령 → PASS
- [ ] **Step 5: 커밋(사용자 요청 시)** — `feat: 사진 번역 요청·응답 DTO와 사진·문단 검증 추가`

### Task 3: Claude 사진 번역 클라이언트

**Files:**
- Create: `backend/src/main/java/com/tripbler/backend/translation/client/PhotoTranslationClient.java`, `ClaudePhotoTranslationClient.java`
- Test: `backend/src/test/java/com/tripbler/backend/translation/client/ClaudePhotoTranslationClientTest.java`

**Interfaces:**
- Consumes: `PhotoTranslationRequest.Paragraph`(Task 2)
- Produces:
  - `interface PhotoTranslationClient`
    - `Result translate(byte[] jpeg, String mediaType, List<PhotoTranslationRequest.Paragraph> paragraphs, String source, String target)`
    - 실패하면 `TranslationProviderException`을 던진다.
  - `record Result(String detectedLanguageCode, List<Paragraph> paragraphs)`
  - `record Paragraph(String id, String original, String translated, boolean uncertain, String pronunciation, List<AiPrice> prices)`
  - `record AiPrice(String text, BigDecimal amount, String currency, boolean uncertain)`
  - `@Component("claudePhotoTranslationClient") ClaudePhotoTranslationClient`
    - 모델 속성 `translation.photo.model`, 기본값 `claude-sonnet-5-5`(임시값)
    - `ClaudeLineTranslationClient`와 같은 `MessageSender` 대역 패턴을 쓴다. 테스트용 생성자는 `(MessageSender, String model)`이다.
- 구현 방식:
  - 사용자 메시지에 base64 이미지 블록 하나와 문단 JSON(`id`, `text`, `box`)을 넣는다.
  - 출력은 구조화 출력(레코드 스키마)으로 받는다.
  - SDK 재시도는 `maxRetries(0)`으로 끈다.
  - 시간 제한과 `max_tokens`는 위 표의 임시값을 쓴다.
  - 출력 검사(제어·양방향 문자 정리, 길이 상한, 발음 문자 검사)는 `ClaudeLineTranslationClient`의 규칙을 그대로 쓴다. 공통 메서드로 뽑을 수 있으면 같은 패키지의 package-private 유틸로 옮긴다.
  - 응답 ID는 걸러 내지 않는다. 그대로 돌려주고, 검증은 서비스가 맡는다.
- 시스템 프롬프트에 꼭 들어갈 지시(사양 7.3):
  - OCR 글자는 참고용이고, 사진에서 분명히 보일 때만 고친다.
  - 흐리거나 잘리거나 가려진 글자는 추측하지 않는다. 그 부분을 정확히 `[읽을 수 없음]`으로 남기고 `uncertain=true`로 둔다. 읽을 수 있는 부분은 번역한다.
  - 문단 ID를 그대로 쓰고, 문단을 합치거나 쪼개거나 새로 만들지 않는다.
  - 가격은 사진과 대조해 금액과 통화를 적는다. 확실하지 않으면 `uncertain=true`로 둔다.
  - 발음은 원문을 소리 나는 대로 적은 한글이다. 원문이 이미 번역 언어이거나 숫자·기호뿐이면 null로 둔다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `sendsImageBlockAndParagraphJson`: 가짜 sender가 받은 요청에 이미지 블록(`image/jpeg`, base64)이 하나 있고, 문단 JSON에 `p1`, `p2`의 `id`, `text`, `box`가 들어 있다.
  - `usesConfiguredModelAndNoRetry`: 요청의 모델이 생성자에 넘긴 값이다.
  - `promptForbidsGuessing`: 시스템 프롬프트에 `[읽을 수 없음]`과 "추측하지" 문구가 들어 있다.
  - `mapsStructuredOutput`: 가짜 응답의 uncertain, 가격 uncertain, 발음을 그대로 옮긴다.
  - `throwsProviderExceptionOnMaxTokens`, `throwsProviderExceptionOnRefusal`, `throwsProviderExceptionOnTimeout`
  - `stripsBidiControlsFromTranslated`
- [ ] **Step 2: 실행해 실패 확인** — `./gradlew test --tests "*ClaudePhotoTranslationClientTest"` → 컴파일 실패
- [ ] **Step 3: 구현**
- [ ] **Step 4: 실행해 통과 확인** — 같은 명령 → PASS. 실제 API는 부르지 않는다.
- [ ] **Step 5: 커밋(사용자 요청 시)** — `feat: Claude 사진 번역 클라이언트 추가(가짜 sender 테스트)`

### Task 4: 사진 번역 서비스(ID 검증, 문단별 대체, 가격 확정 규칙, 호출 제한)

**Files:**
- Create: `backend/src/main/java/com/tripbler/backend/translation/service/PhotoTranslationService.java`
- Modify: `backend/src/main/java/com/tripbler/backend/common/ratelimit/RateLimitBucket.java`(`TRANSLATION_PHOTO_USER_MINUTE/USER_DAY/IP_MINUTE/IP_DAY/GLOBAL_HOUR/GLOBAL_DAY`를 `/lines`와 같은 값으로 추가, 임시값 주석)
- Test: `backend/src/test/java/com/tripbler/backend/translation/service/PhotoTranslationServiceTest.java`

**Interfaces:**
- Consumes: Task 1 `KrwPriceConverter`, Task 2 DTO·검사기·검증기, Task 3 `PhotoTranslationClient`, 기존 `@Qualifier("googleLineTranslationClient") LineTranslationClient`, `PriceExtractor`, `AuthRateLimiter`
- Produces: `PhotoTranslationResponse translate(String userId, String clientIp, byte[] image, String mediaType, PhotoTranslationRequest request)`
- 처리 순서:
  1. 검사기·검증기로 검증한다. 실패하면 한도를 쓰지 않는다.
  2. 호출 한도를 쓴다(`/lines`와 같은 방식).
  3. AI를 호출한다.
  4. 응답 ID를 요청 ID 집합과 대조한다. 모르는 ID는 버리고, 중복 ID는 처음 것만 쓴다. 빠진 ID는 대체 목록에 넣는다.
  5. AI 호출이 실패하면 모든 문단을 대체 목록에 넣는다.
  6. 대체 목록은 Google로 한 번에 번역한다. 실패하면 `TRANSLATION_PROVIDER_UNAVAILABLE`(503)이다.
  7. 가격 규칙
     - AI 가격: `uncertain=false`이고 통화를 알면 `confirmed=true`와 원화 환산값을 채운다. 그렇지 않으면 `confirmed=false`, `krwAmount=null`이다.
     - 대체 문단: `PriceExtractor`로 뽑은 가격을 `confirmed=false`, `krwAmount=null`로 채우고, `pronunciation=null`로 둔다.
  8. 응답 문단은 요청 순서를 따른다.
- 로그: 문단 수, 대체 문단 수, 처리 시간만 남긴다.

- [ ] **Step 1: 실패하는 테스트 작성**(가짜 AI, 가짜 Google, 가짜 환율)
  - `allParagraphsFromAi_markedAi`
  - `unknownAndDuplicateIdsFromAi_ignored`
  - `missingIdFromAi_fallsBackForThatParagraphOnly`: p2만 `OCR_TEXT`, 발음 null, Google은 p2 원문 하나만 받는다.
  - `aiFailure_allParagraphsFallBack`
  - `aiAndFallbackFailure_throws503`
  - `uncertainParagraph_keepsMarkerText`: `translated`에 `[읽을 수 없음]`이 그대로 남고 `uncertain=true`다.
  - `confirmedPrice_hasKrw`: JPY 980, 환율 9.29 → 9104, `confirmed=true`
  - `uncertainPrice_notConfirmedNoKrw`
  - `unknownCurrencyPrice_notConfirmed`
  - `fallbackParagraphPrice_extractedButNotConfirmed`
  - `validationFailure_doesNotConsumeRateLimit`
  - `rateLimitExceeded_throws429BeforeCallingAi`
  - `responseOrderFollowsRequest`
- [ ] **Step 2: 실행해 실패 확인** — `./gradlew test --tests "*PhotoTranslationServiceTest"` → 실패
- [ ] **Step 3: 구현**
- [ ] **Step 4: 실행해 통과 확인** — 같은 명령 → PASS
- [ ] **Step 5: 커밋(사용자 요청 시)** — `feat: 사진 번역 서비스(문단 ID 검증·문단별 대체·가격 확정 규칙)`

### Task 5: 컨트롤러, 보안, multipart 비저장, 로그 검증, API 문서

**Files:**
- Modify: `backend/src/main/java/com/tripbler/backend/translation/controller/TranslationController.java`(`/photo` 추가)
- Modify: `backend/src/main/java/com/tripbler/backend/common/config/SecurityConfig.java`(`"/api/v1/translation/photo"`를 `/lines`와 같은 authenticated 줄에 추가)
- Modify: `backend/src/main/resources/application.properties`(`spring.servlet.multipart.file-size-threshold=6MB`)
- Modify(필요할 때만): `backend/src/main/java/com/tripbler/backend/common/exception/GlobalExceptionHandler.java`. JSON 파트 해석 실패나 검증 실패 로그에 입력 글자가 실리면, 메시지 대신 예외 종류만 남기게 바꾼다.
- Create: `backend/docs/translation-photo-api.md`(계약, 한도, 오류, 대체 규칙, 가격 규칙, 비저장 범위, 제공업체 보관과의 구분, 미검증 항목)
- Modify: `backend/AGENTS.md`의 아키텍처 표와 추가 문서 목록(한 줄씩)
- Test: `backend/src/test/java/com/tripbler/backend/translation/controller/PhotoTranslationControllerTest.java`(MockMvc), `backend/src/test/java/com/tripbler/backend/translation/PhotoTranslationNoStorageIT.java`(`@SpringBootTest(webEnvironment = RANDOM_PORT)`, 서비스는 대역)

**Interfaces:**
- Consumes: Task 4 `PhotoTranslationService.translate(...)`
- Produces:
  - `POST /api/v1/translation/photo`
  - `consumes = multipart/form-data`, 파트 `image`(`MultipartFile`)와 `request`(`application/json`, `@Valid PhotoTranslationRequest`)
  - 응답은 `PhotoTranslationResponse`

- [ ] **Step 1: 실패하는 테스트 작성**
  - 컨트롤러 테스트
    - `returns200WithParagraphs`
    - `returns401WithoutToken`
    - `returns400OnInvalidId`
    - `returns400OnMissingImagePart`
    - `returns400OnBrokenJsonPart`
    - `returns413OverFileLimit`
    - `returns429WithRetryAfter`
    - `returns503WhenProvidersFail`
  - 로그 검사: `brokenJsonPart_errorLogHasNoRequestText`. `OutputCaptureExtension`으로 로그를 잡아, 요청 JSON 안의 표식 글자(`ZZ_SECRET_TEXT_ZZ`)가 로그에 없음을 확인한다. `invalidRequest_warnLogHasNoParagraphText`도 같은 방식이다.
  - 비저장 IT: `photoUpload_writesNoTempFile`. 테스트 속성 `spring.servlet.multipart.location`을 `@TempDir`로 두고, 4MB JPEG 요청 뒤 그 폴더가 비어 있음을 확인한다. 대조 테스트 `thresholdZero_wouldWriteTempFile`은 threshold를 0으로 둔 별도 컨텍스트에서 파일이 생기는 것을 확인한다. 측정 방법이 실제로 파일 생성을 잡는다는 증명이다.
- [ ] **Step 2: 실행해 실패 확인** — `./gradlew test --tests "*PhotoTranslationControllerTest" --tests "*PhotoTranslationNoStorageIT"` → 실패
- [ ] **Step 3: 컨트롤러, 보안, 속성, 필요한 로그 수정 구현 + API 문서 작성**
- [ ] **Step 4: 실행해 통과 확인** — 같은 명령 → PASS. 이어서 `./gradlew test` 전체 → PASS
- [ ] **Step 5: 점검** — `code-inspector`(Sonnet), `security-reviewer`(업로드·`SecurityConfig` 변경)
- [ ] **Step 6: 커밋(사용자 요청 시)** — `feat: 사진 번역 API(/translation/photo)와 비저장·로그 검증`

---

## 2부. 앱(가짜 서버로 완결, 번역 탭에는 아직 연결하지 않음)

### Task 6: 문단 ID 부여와 한도

**Files:**
- Create: `lib/domain/translation/photo_paragraphs.dart`
- Test: `test/domain/translation/photo_paragraphs_test.dart`

**Interfaces:**
- Consumes: `buildTextParagraphs`, `RecognizedTextLine`, `TextParagraph`(`text_paragraphs.dart`)
- Produces:
  - `const String unreadableMarker = '[읽을 수 없음]'`
  - `@immutable class OcrParagraph { final String id; final String text; final Rect box; }`(== / hashCode 포함)
  - `abstract final class PhotoParagraphLimits { static const int maxParagraphs = 50; static const int maxParagraphLength = 300; static const int maxTotalCharacters = 4000; }`(임시값 주석)
  - `({List<OcrParagraph> paragraphs, int omitted}) toOcrParagraphs(List<RecognizedTextLine> lines)`
    - `buildTextParagraphs` 결과(위→아래, 왼→오른쪽)에 `p1`부터 번호를 붙인다.
    - 300자를 넘는 문단은 300자로 자른다.
    - 문단 수나 전체 글자가 한도를 넘으면 앞에서부터 한도까지만 담고, 나머지 개수를 `omitted`로 돌려준다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `assignsIdsInReadingOrder`: 두 덩어리(위·아래) → `p1`=위, `p2`=아래
  - `emptyLines_returnsEmpty`
  - `over50Paragraphs_keeps50AndCountsOmitted`
  - `totalOver4000_stopsBeforeLimit`
  - `longParagraph_truncatedTo300`
  - `unreadableMarkerMatchesServer`: `unreadableMarker`가 `'[읽을 수 없음]'`과 같다.
- [ ] **Step 2: 실행해 실패 확인** — `flutter test --no-pub test/domain/translation/photo_paragraphs_test.dart` → FAIL
- [ ] **Step 3: 구현**
- [ ] **Step 4: 실행해 통과 확인, 포맷·분석** — 같은 명령 → PASS. `dart format`, `flutter analyze --no-pub` 해당 파일
- [ ] **Step 5: 커밋(사용자 요청 시)**

### Task 7: 기준 사진 만들기(EXIF 회전, 축소, JPEG)와 줄 상자 OCR

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`(`image` 추가. 이유: 순수 Dart라서 EXIF 회전 반영과 JPEG 인코딩을 단위 테스트에서 실제 바이트로 검증할 수 있다)
- Create: `lib/services/photo_normalizer.dart`
- Modify: `lib/services/ocr_service.dart`(`recognizeTextLines` 추가. 기존 메서드는 그대로 둔다)
- Test: `test/services/photo_normalizer_test.dart`

**Interfaces:**
- Produces:
  - `@immutable class NormalizedPhoto { final String path; final int width; final int height; }`
  - `class UnsupportedPhotoException implements Exception {}`
  - `class PhotoNormalizer`
    - `static const int maxLongSide = 2048;`, `static const int jpegQuality = 85;`(둘 다 임시값)
    - `Future<NormalizedPhoto> normalize({required String sourcePath, required String outputDirectory})`
    - `Isolate.run` 안에서 `decodeImage` → `bakeOrientation` → 긴 변이 한도보다 크면 `copyResize` → `encodeJpg(quality: jpegQuality)` 순서로 처리한다. 결과는 `outputDirectory/photo_<타임스탬프>.jpg`에 저장한다.
    - 디코딩하지 못하면 `UnsupportedPhotoException`을 던진다.
    - `Future<void> delete(NormalizedPhoto photo)`: 파일이 없어도 오류 없이 넘어간다.
  - `final photoNormalizerProvider = Provider<PhotoNormalizer>((ref) => PhotoNormalizer());`(`lib/providers/translation/photo_translation_provider.dart`에 둔다. Task 10)
  - `OcrService.recognizeTextLines({required String imagePath, required String sourceLanguageCode}) → Future<List<RecognizedTextLine>>`
    - 덩어리 번호는 `recognizedText.blocks`의 인덱스이고, 상자는 `line.boundingBox`다.
    - `auto`이면 문자 체계 4가지 중 글자가 가장 많은 결과를 쓴다.
    - 글자 내용은 로그에 남기지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**(테스트에서 `image`로 JPEG을 만들고 EXIF 방향을 넣는다)
  - `orientation6_isBakedUpright`: 400×300 원본, 방향 6 → 결과 300×400. 원본 왼쪽 위 빨간 점이 결과 오른쪽 위에 있다.
  - `orientation8_isBakedUpright`
  - `largePhoto_longSideScaledTo2048`: 4032×3024 → 2048×1536
  - `smallPhoto_notUpscaled`
  - `outputHasNoExifOrientation`
  - `nonImageFile_throwsUnsupportedPhotoException`
  - `delete_missingFileIsNoop`
- [ ] **Step 2: 실행해 실패 확인** — `flutter test --no-pub test/services/photo_normalizer_test.dart` → FAIL
- [ ] **Step 3: `flutter pub add image`, 정리기 구현, `recognizeTextLines` 추가** — ML Kit는 단위 테스트를 할 수 없으므로 Task 15의 실기기 확인 항목에 넣는다.
- [ ] **Step 4: 실행해 통과 확인, 포맷·분석** — 같은 테스트 → PASS. `flutter analyze --no-pub lib/services` → 새 문제 없음
- [ ] **Step 5: 커밋(사용자 요청 시)** — 의존성 추가를 메시지에 적는다.

### Task 8: 사진 전송 동의 저장(안내 버전, 설치 표식, 백업 복원 대응)

**Files:**
- Create: `lib/services/photo_consent_store.dart`
- Test: `test/services/photo_consent_store_test.dart`

**Interfaces:**
- Produces:
  - `class PhotoConsentStore`
    - 생성자 `PhotoConsentStore({FlutterSecureStorage? secureStorage, Future<SharedPreferences> Function()? prefs, DateTime Function()? now, String Function()? newMarker})`
    - `static const int currentVersion = 1;`
    - 보안 저장소 옵션: iOS `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`(새 기기로 옮겨지지 않음), Android 기본 옵션(복원되면 복호화되지 않음)
    - `Future<bool> hasValidConsent()`: 아래를 모두 만족할 때만 true다.
      - prefs의 `photo.consent.v1`(JSON `{version, acceptedAt, marker}`)이 있다.
      - `version >= currentVersion`이다.
      - 보안 저장소 `photo.consent.marker`를 읽을 수 있고, 저장된 `marker`와 같다.
      - 하나라도 읽다가 예외가 나면 false다.
    - `Future<void> accept()`: 표식이 없거나 읽지 못하면 새로 만들어 쓴다. 그다음 `{currentVersion, now, marker}`를 저장한다.
  - `final photoConsentStoreProvider = Provider<PhotoConsentStore>((ref) => PhotoConsentStore());`(Task 10 파일에 둔다)

- [ ] **Step 1: 실패하는 테스트 작성**(`SharedPreferences.setMockInitialValues`, 메모리 대역 보안 저장소)
  - `noRecord_false`
  - `afterAccept_true`
  - `olderVersion_false`: 저장 version 0
  - `restoredPrefsWithoutMarker_false`: prefs만 있고 보안 저장소는 빔. 새 기기 복원 상황이다.
  - `markerMismatch_false`
  - `secureStorageThrows_false`: 복원된 암호문이 복호화되지 않는 상황이다.
  - `brokenJson_false`
  - `acceptTwice_keepsSameMarker`
- [ ] **Step 2: 실행해 실패 확인** — `flutter test --no-pub test/services/photo_consent_store_test.dart` → FAIL
- [ ] **Step 3: 구현**
- [ ] **Step 4: 실행해 통과 확인, 포맷·분석** — 같은 명령 → PASS. 실기기 백업·복원 확인은 Task 15에서 한다.
- [ ] **Step 5: 커밋(사용자 요청 시)**

### Task 9: 사진 번역 API 클라이언트와 결과 모델

**Files:**
- Create: `lib/models/translation/photo_translation_result.dart`, `lib/services/photo_translation_api_service.dart`
- Modify: `lib/core/config/api_config.dart`(`translationPhotoPath = '/api/v1/translation/photo'`, `translationPhotoUri`)
- Test: `test/services/photo_translation_api_service_test.dart`(`package:http/testing.dart`의 `MockClient`)

**Interfaces:**
- Consumes: Task 6 `OcrParagraph`, Task 7 `NormalizedPhoto`, 기존 `ApiException`
- Produces:
  - `enum PhotoTranslationSource { ai, ocrText, original }`(`original`은 앱에서만 쓴다. 원문 언어와 번역 언어가 같아 보내지 않은 경우이고, 서버 값이 아니다. `fromJson`은 `AI`·`OCR_TEXT`만 받는다)
  - `@immutable class PhotoPrice { text, amount(double?), currency(String?), confirmed(bool), krwAmount(double?), krwRate(double?), rateFetchedAt(DateTime?), rateStale(bool) }`
  - `@immutable class TranslatedParagraph { id, original, translated, uncertain, source, pronunciation(String?), prices(List<PhotoPrice>) }`
  - `@immutable class PhotoTranslationResult { sourceLanguageCode, targetLanguageCode, List<TranslatedParagraph> paragraphs; static PhotoTranslationResult fromJson(Map<String, dynamic>, {required Set<String> requestedIds}) }`
    - 요청에 없는 ID는 버리고, 같은 ID가 다시 나오면 처음 것만 쓴다.
    - 알 수 없는 `translationSource` 값은 `FormatException`이다.
  - `class PhotoTranslationApiService`
    - 생성자 `({http.Client? client, Duration timeout = defaultTimeout})`, `static const Duration defaultTimeout = Duration(seconds: 120)`(임시값)
    - `Future<PhotoTranslationResult> translate({required NormalizedPhoto photo, required List<OcrParagraph> paragraphs, required String sourceLanguageCode, required String targetLanguageCode, required String authorizationHeader})`
    - `http.MultipartRequest`로 보낸다. `image`는 `image/jpeg` 파일 파트, `request`는 `application/json` 파트다.
    - 오류 변환(시간 초과, 연결 실패, 비정상 응답)은 `LineTranslationApiService`와 같은 규칙을 쓴다. 공통 `_errorFrom`은 복사하지 않고 같은 파일 밖 유틸로 옮겨 함께 쓴다.
    - `void dispose()`

- [ ] **Step 1: 실패하는 테스트 작성**
  - `sendsMultipartWithImageAndJsonParts`: 요청의 파트 이름, content-type, JSON의 `imageWidth`·`imageHeight`·`paragraphs[0].box`
  - `parsesParagraphsAndPrices`
  - `ignoresUnknownAndDuplicateIds`
  - `missingIds_resultHasFewerParagraphs`
  - `uncertainAndOcrTextSourceParsed`
  - `unconfirmedPriceHasNullKrw`
  - `http429_throwsApiExceptionWithCode`
  - `timeout_throwsNetworkApiException`
  - `brokenJson_throwsApiException`
- [ ] **Step 2: 실행해 실패 확인** — `flutter test --no-pub test/services/photo_translation_api_service_test.dart` → FAIL
- [ ] **Step 3: 구현**
- [ ] **Step 4: 실행해 통과 확인** — 같은 명령, 그리고 `test/services/line_translation_api_service_test.dart` → PASS
- [ ] **Step 5: 커밋(사용자 요청 시)**

### Task 10: 사진 번역 Notifier(흐름, 동의 관문, 늦은 응답 무시, 임시 파일 정리)

**Files:**
- Create: `lib/providers/translation/photo_translation_state.dart`, `lib/providers/translation/photo_translation_provider.dart`
- Test: `test/providers/photo_translation_provider_test.dart`

**Interfaces:**
- Consumes: Task 6~9, 기존 `ocrServiceProvider`, `authorizedRequestRunnerProvider`, `authProvider`
- Produces:
  - `enum PhotoTranslationStatus { idle, preparing, awaitingConsent, uploading, completed, noText, unsupportedPhoto, failed }`
  - `@immutable class PhotoTranslationState { status, NormalizedPhoto? photo, List<OcrParagraph> paragraphs, int omittedCount, PhotoTranslationResult? result, bool showOriginal, String? errorMessage, String sourceLanguageCode, String targetLanguageCode; copyWith(...) }`
  - `final photoTranslationProvider = NotifierProvider<PhotoTranslationNotifier, PhotoTranslationState>(...)`
  - 같은 파일의 provider: `photoNormalizerProvider`, `photoConsentStoreProvider`, `photoTranslationApiServiceProvider`(`ref.onDispose(service.dispose)`)
  - `class PhotoTranslationNotifier`
    - `Future<void> processPhoto(String sourcePath)`: 정리 → OCR → 문단화
      - 글자가 없으면 `noText`, 디코딩하지 못하면 `unsupportedPhoto`다.
      - 동의가 유효하면 바로 업로드하고, 아니면 `awaitingConsent`다.
    - `Future<void> acceptConsentAndTranslate()`
      - `awaitingConsent`일 때만 동작한다. 두 번째 호출은 무시한다.
      - `accept()`한 뒤 업로드한다.
    - `void cancelConsent()`: 임시 사진을 지우고 `idle`로 돌아간다. 아무것도 보내지 않는다.
    - `Future<void> retry()`: `failed`에서 같은 기준 사진과 같은 문단으로 다시 보낸다. 동의는 다시 묻지 않는다.
    - `void retake()`: 작업 번호를 올리고, 임시 사진을 지우고, `idle`로 돌아간다.
    - `void toggleOriginal()`
    - `void changeSourceLanguage(String)`, `void changeTargetLanguage(String)`
  - 작업 번호 `_requestId`는 `processPhoto`, `cancelConsent`, `retake`, `retry`, 화면 이탈(`leave()`), `ref.onDispose`에서 올린다.
  - 각 `await` 뒤에는 번호와 `ref.mounted`를 확인하고, 다르면 결과를 버린다. 정리 단계에서 버려진 사진 파일은 지운다.
  - 원문 언어와 번역 언어가 같고 `auto`가 아니면 서버에 보내지 않고 동의도 묻지 않는다. OCR 원문을 `translated`에 그대로 넣고 `source=original`인 결과를 만든다(대체 안내를 띄우지 않음). 이것은 제 판단이고, 기존 `/lines` 흐름과 같은 규칙이다.

- [ ] **Step 1: 실패하는 테스트 작성**(가짜 정리기, OCR, 동의 저장소, API를 override)
  - `firstTime_waitsForConsent_andSendsNothing`: API 호출 0회
  - `cancelConsent_deletesPhoto_returnsIdle_noUpload`
  - `acceptTwice_uploadsOnce`
  - `validConsent_uploadsWithoutAsking`
  - `noText_statusNoText_noUpload`
  - `unsupportedPhoto_statusUnsupported_noUpload`
  - `retakeDuringUpload_lateResponseIgnored_photoDeleted`
  - `leaveDuringOcr_lateOcrIgnored`
  - `disposeDuringUpload_noStateWrite`(`ProviderContainer.dispose` 뒤 응답 완료)
  - `retryAfterFailure_resendsSamePhoto_noConsentPrompt`
  - `sameSourceAndTarget_noUpload_showsOriginal`
  - `omittedParagraphs_countKept`
  - `sessionExpired_failedWithLoginMessage`
- [ ] **Step 2: 실행해 실패 확인** — `flutter test --no-pub test/providers/photo_translation_provider_test.dart` → FAIL
- [ ] **Step 3: 구현**(상태 파일과 Notifier 파일 각각 450줄 이하)
- [ ] **Step 4: 실행해 통과 확인, 포맷·분석**
- [ ] **Step 5: 커밋(사용자 요청 시)**

### Task 11: 화면(전체 화면 카메라, 동의 안내, 결과·상자 터치·상세)과 개발용 진입점

**Files:**
- Create: `lib/screens/photo_translation_screen.dart`(촬영 ↔ 결과 전환, 카메라 생명주기는 `TranslationCamera` 재사용)
- Create: `lib/widgets/translation/photo/photo_capture_view.dart`(전체 화면 미리보기 cover, 셔터·갤러리·플래시·언어 막대, 하단 고정 안내)
- Create: `lib/widgets/translation/photo/photo_consent_dialog.dart`
- Create: `lib/widgets/translation/photo/photo_result_view.dart`(`InteractiveViewer` + contain 크기 `Stack[Image.file, TranslationBoxOverlay]`, 원문 보기, 재촬영, 진행 표시, 실패·다시 시도, 대체 안내 줄)
- Create: `lib/widgets/translation/photo/paragraph_detail_sheet.dart`
- Modify: `lib/widgets/translation/translation_box_overlay.dart`
  - `TranslationBox`에 선택 필드를 추가한다: `String? id`, `bool uncertain = false`, `bool fallback = false`
  - `onBoxTap: ValueChanged<String>?`를 추가한다.
  - `IgnorePointer`를 걷어 내고, 배치된 상자(`_PlacedLine.box`)로 터치를 판정한다.
  - `[읽을 수 없음]` 부분을 다른 색으로 그린다.
  - 불확실·대체 표시 아이콘을 넣는다.
- Modify: `lib/screens/main_screen.dart` 또는 번역 탭 진입부(파일명은 구현자가 확인). `const bool.fromEnvironment('TRIPBLER_PHOTO_TRANSLATION')`이 true일 때만 번역 탭에서 `PhotoTranslationScreen`을 보여 준다. 실제 연동 확인 전 실기기 시험용이고, 사용자에게 보이는 스위치가 아니다. Task 16에서 지운다.
- Test: `test/widgets/translation/photo/photo_consent_dialog_test.dart`, `photo_result_view_test.dart`, `paragraph_detail_sheet_test.dart`, `test/widgets/translation/translation_box_overlay_test.dart`(추가), `test/screens/photo_translation_screen_test.dart`(`FakeCameraPlatform` 재사용)

**Interfaces:**
- Consumes: Task 10 `photoTranslationProvider`와 메서드, `TranslationBoxOverlay`
- 상자 좌표: `fitScale = min(viewW / photo.width, viewH / photo.height)`. 상자는 `OcrParagraph.box`에 `fitScale`을 곱한 사각형이고, overlay 크기는 `photo.size × fitScale`이다. 확대·이동은 `InteractiveViewer`가 사진과 상자를 함께 변환한다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - 동의 대화상자: 정확한 안내 문구와 두 버튼이 보인다. `동의하고 번역` → 콜백 1회. `취소`·뒤로가기 → 취소 콜백.
  - 촬영 화면: 하단 고정 안내 "촬영한 사진은 AI 번역을 위해 전송됩니다"가 보이고, 보관·삭제 관련 문구는 없다.
  - 결과 화면
    - `boxesMoveWithPhotoOnZoom`: `TransformationController`로 2배 확대·이동한 뒤, 상자의 전역 위치가 사진 속 원문 사각형의 전역 위치와 같다(오차 1px).
    - `landscapePhotoBoxesAligned`: 가로 사진도 같다.
    - `tapBox_opensDetailWithPronunciationAndPrices`
    - `toggleOriginal_hidesBoxes`
    - `fallbackParagraph_showsNotice`
    - `uncertainMarker_rendered`
    - `unconfirmedPrice_noKrwShown`
    - `uploading_showsProgressAndRetakeEnabled`
    - `failed_showsRetry`
    - 작은 화면(320폭), 글자 배율 2에서 넘침 없음
  - overlay: `tapInsidePlacedBox_callsOnBoxTapWithId`, `tapOutside_noCallback`, 기존 5건 유지
- [ ] **Step 2: 실행해 실패 확인** — 위 테스트 파일들 → FAIL
- [ ] **Step 3: 기능과 기본 화면 구현**
- [ ] **Step 4: 실행해 통과 확인**
- [ ] **Step 5: `design-improver`로 화면 다듬기 → 같은 테스트 재실행**
- [ ] **Step 6: `code-inspector`(Sonnet) 점검, 보고**
- [ ] **Step 7: 커밋(사용자 요청 시)**

### Task 12: 1~2부 전체 검증

- [ ] **Step 1:** `flutter test --no-pub` 전체 → PASS
- [ ] **Step 2:** `flutter analyze --no-pub` → 기존 deprecated 안내 말고는 문제 없음
- [ ] **Step 3:** `backend`에서 `./gradlew test` → PASS
- [ ] **Step 4:** `git diff --check` → 통과
- [ ] **Step 5:** progress.md를 갱신한다. "가짜 클라이언트 검증 완료, 실제 연동 미검증"으로 적는다.

---

## 3부. 실제 연동(가짜 검증과 따로 완료를 판단)

### Task 13: 실제 사진을 보내기 전에 제공업체 정책과 안내 문구 확인(코드 변경 최소)

**Files:**
- Modify: `backend/docs/translation-photo-api.md`("제공업체 보관 정책" 절)
- Modify(필요할 때만): 앱 안내 문구 상수, `PhotoConsentStore.currentVersion`

- [ ] **Step 1:** Anthropic의 API 데이터 보관·학습 사용 정책과 이 조직 계정의 설정(보관 기간, 학습 제외 여부)을 공식 문서와 콘솔에서 확인한다. 확인 날짜와 출처 링크를 문서에 적는다. Google 번역(대체)도 같은 방식으로 확인한다.
- [ ] **Step 2:** Tripbler 쪽 비저장 범위(Task 5 검증 결과)와 제공업체 쪽 정책을 문서에서 **나눠** 적는다.
- [ ] **Step 3:** 확인 결과를 사용자에게 보고한다. 동의 안내 문구와 촬영 화면 안내를 바꿀지 결정받는다. 바꾸면 문구를 고치고 `currentVersion`을 올린 뒤 Task 8, 11의 해당 테스트를 다시 실행한다.
- [ ] **Step 4:** 사용자가 확인을 마치기 전에는 Task 14를 시작하지 않는다.

### Task 14: 실제 Claude 연동 확인과 측정 → 확정값 정하기

**Files:**
- Create: `backend/src/test/java/com/tripbler/backend/translation/client/ClaudePhotoTranslationLiveIT.java`
  - `@EnabledIfEnvironmentVariable(named = "ANTHROPIC_LIVE_TEST", matches = "true")`이다. 기본 빌드에서는 건너뛴다.
  - 시료 폴더 경로는 환경 변수로 받는다.
  - 저장소에 시료 사진을 넣지 않는다.
- Create: `backend/docs/translation-photo-measurements.md`(날짜, 모델, 사진 크기, 시료 수, 정확도·추측 여부·가격 정확도 판정, 지연 p50/p90, 요청당 입력·출력 토큰과 비용, 대체 비율)
- Modify: 위 설정값 표의 위치들(확정값으로 바꾸고 임시값 주석을 지움)

- [ ] **Step 1:** 개인정보가 없는 시료를 준비한다. 메뉴판, 표지판, 안내문, 작은 글씨, 흐리거나 기운 사진을 언어별(ja/zh/en)로 모은다. 모은 위치와 목록만 기록한다.
- [ ] **Step 2:** 앱의 `PhotoNormalizer`와 같은 방식으로 긴 변 1536/2048/2560 시료를 만든다. OCR 문단은 실기기 앱의 디버그 출력이나 시료별 수동 입력으로 준비한다.
- [ ] **Step 3:** 후보 모델(`claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`)마다 live IT를 실행한다(`ANTHROPIC_LIVE_TEST=true ./gradlew test --tests "*ClaudePhotoTranslationLiveIT"`). usage와 지연을 기록한다.
- [ ] **Step 4:** 사람이 결과를 판정한다. 번역이 맞는지, 읽지 못한 글자를 `[읽을 수 없음]`으로 남겼는지, 지어낸 글자가 없는지, 가격·통화가 맞는지, uncertain이 적절한지를 본다.
- [ ] **Step 5:** 측정 결과로 모델, 사진 크기, JPEG 품질, 시간 제한, `max_tokens`, 문단 한도, 호출 제한을 제안하고 사용자 결정을 받는다. 결정대로 값을 바꾸고 관련 테스트를 다시 실행한다.
- [ ] **Step 6:** 서버를 실제 키로 띄우고, 앱(`--dart-define=TRIPBLER_PHOTO_TRANSLATION=true`)에서 시료 사진으로 처음부터 끝까지 확인한다. 이때 Google 대체 경로도 실제로 한 번 확인한다(Claude 키를 일부러 무효로 둔 실행).
- [ ] **Step 7:** progress.md에 실제 확인 결과와 아직 확인하지 못한 것을 나눠 적는다.

### Task 15: 실기기 확인(동의 백업·복원, 좌표, 비저장)

- [ ] **Step 1: 좌표** — Android와 iOS에서 세로·가로·EXIF 회전 사진, 갤러리 사진을 넣어 본다. 상자가 원문 위에 있고, 확대·이동해도 어긋나지 않는지 본다.
- [ ] **Step 2: 동의 백업·복원(Android)**
  - 동의한 뒤 `adb shell bmgr backupnow <패키지>` → 앱 삭제 → 재설치 → `adb shell bmgr restore`(또는 기기 이전)를 차례로 실행한다.
  - 기대: 다음 촬영에서 동의 안내가 다시 나온다.
- [ ] **Step 3: 동의 백업·복원(iOS)** — 가능하면 백업 복원이나 새 기기 이전으로 같은 기대를 확인한다. 확인하지 못하면 미검증으로 적는다.
- [ ] **Step 4: 버전 올림** — `currentVersion`을 2로 올린 빌드에서 다시 묻는지 확인한다.
- [ ] **Step 5: 임시 파일** — 촬영, 취소, 재촬영, 완료 뒤 앱 임시 폴더에 `photo_*.jpg`가 남지 않는지 디버그 빌드에서 확인한다.
- [ ] **Step 6: ML Kit 줄 상자** — 정리된 사진에서 줄 상자가 그 사진 좌표인지 확인한다. 이 내용은 Task 7에서 단위 테스트로 검증하지 못했다.
- [ ] **Step 7:** 결과를 progress.md에 적는다. 실패 항목이 있으면 사용자에게 보고한 뒤 수정한다.

---

## 4부. 기존 흐름 교체

### Task 16: 번역 탭을 사진 번역으로 교체

**교체 시점:** Task 13(정책·문구 확인), Task 14(실제 연동과 확정값), Task 15(실기기)가 끝나고, 사용자가 교체를 승인한 뒤에 한다.

**Files:**
- Modify: 번역 탭 진입부. Task 11의 `TRIPBLER_PHOTO_TRANSLATION` 분기를 지우고 항상 `PhotoTranslationScreen`을 쓴다.
- Modify: `test/screens/translation_screen_test.dart`, `translation_screen_lifecycle_test.dart` 등. 번역 탭을 전제로 하는 테스트를 새 화면 기준으로 옮기거나, 탭 연결 테스트를 새로 둔다.
- 지우지 않음: `TranslationScreen`, `translation_provider.dart`, `/lines`, 줄 목록 위젯, `CaptureFrame`, `live_*`. 이것들의 삭제는 별도 요청으로 한다(사양 11절).

- [ ] **Step 1: 실패하는 테스트 작성** — `translationTab_showsPhotoTranslationScreen`(main 화면에서 번역 탭 선택 → 촬영 화면 고정 안내가 보임)
- [ ] **Step 2: 실행해 실패 확인**
- [ ] **Step 3: 분기 제거와 연결**
- [ ] **Step 4: 실행해 통과 확인** — `flutter test --no-pub` 전체, `flutter analyze --no-pub`, `git diff --check`
- [ ] **Step 5: `code-inspector`(Sonnet) 점검, progress.md 갱신**
- [ ] **Step 6: 커밋(사용자 요청 시)**
