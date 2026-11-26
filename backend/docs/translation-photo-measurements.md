# 사진 번역 실제 측정 기록

계획 Task 14의 기록 양식이다. 가짜 클라이언트 테스트로는 번역 품질, 토큰 사용량, 지연을 알 수 없으므로 실제 Claude 호출 결과를 여기에 적고, 이 결과로 임시값을 확정한다.

**상태: 아직 측정하지 않았다.** 2026-11-26 사용자 결정에 따라 실제 사진 전송과 유료 API 호출은 보류 중이다. AI 제공업체도 아직 최종 선택하지 않았다. 아래 표는 빈 양식이다.

## 실행 전 확인

- [ ] 사용자가 실제 사진 전송과 유료 호출을 승인했다(날짜: ).
- [ ] 측정할 AI 제공업체와 모델 후보를 정했다. 제공업체 보관 정책 안내는 AI를 정한 뒤 확정한다(`translation-photo-api.md` "AI 제공업체 쪽 보관" 절).
- [ ] 시료에 개인정보(얼굴, 이름, 전화번호, 카드·영수증 번호, 위치)가 없다.
- [ ] 시료 폴더는 저장소 밖에 있다. 결과 폴더(`build/photo-live`)도 커밋하지 않는다. 테스트가 확인한다: 시료·결과 경로가 저장소 안이면 `backend/build/` 아래가 아닐 때 실패한다.
- [ ] 운영 설정과 같게 `ANTHROPIC_LOG`를 설정하지 않았다. 설정돼 있으면 테스트가 실행을 거부한다(SDK가 본문을 테스트 출력에 남기고 Gradle이 `build/test-results`에 저장하므로).

## 시료 준비

시료마다 같은 이름의 두 파일을 둔다.

- `이름.jpg`: 앱의 `PhotoNormalizer`와 같은 방식으로 정리한 사진. 회전을 바로잡고 EXIF를 지운 JPEG이며, 긴 변은 측정할 크기(1536/2048/2560)로 맞춘다.
- `이름.json`: 앱이 보내는 `request` 파트와 같은 형식(`translation-photo-api.md`의 요청 JSON). OCR 문단은 실기기 앱의 디버그 출력이나 수동 입력으로 만든다.

| 분류 | 언어 | 시료 수 | 모은 위치(목록만) |
| --- | --- | --- | --- |
| 메뉴판 | ja / zh / en | | |
| 표지판·안내문 | ja / zh / en | | |
| 작은 글씨 | | | |
| 흐리거나 기운 사진 | | | |
| 가격이 있는 사진 | | | |

## 실행

```bash
ANTHROPIC_LIVE_TEST=true ANTHROPIC_API_KEY=... PHOTO_LIVE_SAMPLES=/저장소/밖/시료폴더 PHOTO_LIVE_MODEL=claude-sonnet-5-5 PHOTO_LIVE_RUN=2048px-q85 ./gradlew liveTest
```

- 테스트: `src/test/java/com/tripbler/backend/translation/client/ClaudePhotoTranslationLiveIT.java`(`@Tag("live")`). **일반 `./gradlew test`에서는 빠진다.** `./gradlew liveTest`로만 돌고, 그때도 `ANTHROPIC_LIVE_TEST=true`가 없으면 건너뛴다.
- 결과 폴더 규칙(`PhotoLiveRunFiles`, 일반 test의 `PhotoLiveRunFilesTest`가 확인):
  - `<결과 폴더>/<모델>/<실행 이름>/`. 결과 폴더는 `PHOTO_LIVE_OUT`(없으면 `build/photo-live`), 실행 이름은 `PHOTO_LIVE_RUN`(없으면 UTC 시각 `yyyyMMdd-HHmmss`).
  - **이미 있는 실행 폴더에는 쓰지 않고 실패한다**(같은 모델로 크기를 바꿔 다시 돌려도 덮어쓰지 않음). 크기·품질마다 실행 이름을 다르게 준다.
  - 모델·실행 이름은 영문·숫자·`. _ -`만 쓸 수 있다(`/`, `\`, `..` 불가).
  - 시료·결과 경로가 저장소 안이면 `backend/build/` 아래만 허용한다.
- 결과 파일:
  - `이름.result.json`: OCR 문단과 AI 결과를 나란히.
  - `samples.csv`: 시료마다 바로 덧붙인다(중간에 멈춰도 앞 시료 기록이 남음). 열: `sample, paragraphs, elapsedMs, inputTokens, outputTokens, returned, uncertain, unknownIds, error`. 시료 파일 읽기 실패는 `error=sample:<예외>`, 호출 실패는 예외 종류. 요청에 없는 문단 ID는 `unknownIds`에 `;`로 잇는다. 쉼표·따옴표가 든 값은 따옴표로 감싼다.
  - `summary.csv`: `key,value` 형식(모델, 실행 이름, 시료 수, 측정 수, 실패 수, unknownIds 시료 수, p50Ms, p90Ms). 도중 예외가 나도 항상 쓴다.
- 테스트는 모든 기록을 쓴 뒤 요청에 없는 문단 ID를 돌려준 시료가 있으면 실패한다. 품질 판정은 사람이 한다.
- 모델 후보마다, 사진 크기마다 실행 이름을 바꿔 한 번씩 실행한다.

## 결과 기록

### 실행 목록

| 날짜 | 모델 | 긴 변(px) | JPEG 품질 | 시료 수 | p50(ms) | p90(ms) | 평균 입력 토큰 | 평균 출력 토큰 | 요청당 비용(추정) | 실패·대체 비율 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | | | |

비용은 측정 날짜의 공식 가격표로 계산하고 가격표 링크를 함께 적는다.

### 시료별 판정

| 시료 | 모델 | 번역 정확 | 읽지 못한 글자를 `[읽을 수 없음]`으로 남김 | 지어낸 글자 없음 | 가격·통화 정확 | uncertain 적절 | 메모 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |

판정 기준:
- **번역 정확**: 뜻이 맞으면 O, 일부 틀리면 △, 틀리면 X.
- **지어낸 글자 없음**: 사진에 없는 글자나 가격이 결과에 있으면 X. 한 건이라도 있으면 메모에 자세히 적는다.
- **uncertain 적절**: 흐리거나 잘린 문단에만 uncertain이 붙었으면 O.

## 확정할 값

측정 뒤 사용자 결정을 받아 바꾸고, 코드의 "임시값" 주석을 지운다. 위치는 설계 문서 8.1절 표를 따른다.

| 값 | 지금 임시값 | 확정값 | 근거(실행 날짜·표 행) |
| --- | --- | --- | --- |
| 모델(`translation.photo.model`) | `claude-sonnet-5-5` | | |
| 사진 긴 변 | 2048px | | |
| JPEG 품질(앱 `PhotoNormalizer.jpegQuality`) | 85 | | |
| 시간 제한 | 30초 + 글자당 12ms, 최대 90초 | | |
| `max_tokens` | min(16000, 4096 + 문단 수×32 + 글자 수×4) | | |
| 문단 수 / 문단 길이 | 50개 / 300자 | | |
| 동시 처리 상한 | 4 | | |
| 호출 제한 | `RateLimitBucket`의 `TRANSLATION_PHOTO_*` | | |

## 아직 확인하지 못한 것

측정 뒤에도 남는 항목을 적는다. 예: 실기기 앱과 연결한 처음부터 끝까지 확인(Task 14 Step 6), 실제 Google 대체 경로 호출.
