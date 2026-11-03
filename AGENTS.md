# Tripbler 프로젝트 지침

## 목적과 범위
- Tripbler는 환율·지도·번역 등 여행 도구를 연결하는 Flutter 앱이다. 상태 관리는 기존 Provider 구조를 따른다.
- 이 지침은 현재 프론트엔드 저장소에 적용한다. 연동 백엔드는 `../tripbler-backend`의 Spring Boot 프로젝트이며, 수정 시 해당 저장소의 지침과 API 계약을 확인한다.
- 현재 구현 여부는 코드로 확인한다. AI 채팅 화면 제거와 개인 여행 에이전트 확장은 향후 방향이며, 별도 구현 요청 없이 실행하지 않는다.

## 작업 원칙
- 요청 범위에 필요한 최소 변경을 수행하고, 기존 사용자 변경과 무관한 기능은 보존한다.
- 화면은 표시와 사용자 입력을 담당하고, 상태·업무 처리·API 호출은 기존 Provider, Repository, Service의 책임에 맞춰 배치한다.
- 국가 통화와 암호화폐의 데이터/API 로직은 분리한다. 화면에서는 공통 표시 모델, CurrencyRow, CurrencyIcon, 공통 차트를 재사용한다.
- 로딩·빈 결과·실패 상태를 구분한다. 갱신 실패 시 유효한 마지막 성공값과 원래 갱신 시각을 유지하고, 오래된 값임을 알린다.
- 비동기 응답은 화면 제거·요청 변경 후 반영되지 않게 한다. Timer와 소유한 리소스는 정리한다.
- API 키·토큰·개인정보는 코드, 로그, 문서에 노출하지 않는다. API 계약이나 의존성 변경은 필요한 범위로 제한한다.
- 설명과 작업 결과는 한국어로 간결하게 작성하고, 구현 완료·계획·미검증을 구분한다.

## 자기 검증 규칙
- 수정 전 호출부, 관련 모델/API, 기존 테스트를 확인하고 요구사항별 완료 조건을 정한다.
- Dart 변경 파일에 `dart format <변경 파일>`을 실행하고, `flutter analyze --no-pub <변경 파일 또는 디렉터리>`로 정적 분석한다.
- 동작 변경은 관련 `flutter test --no-pub <테스트 경로>`로 검증한다. 버그 수정은 재현 조건과 회귀 방지를 확인하며, 영향이 넓으면 검증 범위를 넓힌다.
- 비동기·캐시 변경은 지연/실패, 재요청, 기간·통화 변경, 화면 제거를 확인한다. 차트 변경은 축·단위·툴팁과 터치 종료 후 3초 유지 동작을 확인한다.
- UI 변경은 가능한 경우 작은 화면, 긴 텍스트, 선택 상태를 확인한다. 문서만 변경하면 내용·경로·변경 내역을 검토하고 앱 테스트는 생략할 수 있다.
- 완료 전 `git diff --check`와 변경 파일 목록을 확인한다. 새 파일도 직접 읽어 누락·오타·요청 외 변경을 점검한다.
- 최종 보고에는 변경 내용, 실제 실행한 검증과 결과, 남은 제한을 적는다. 실행하지 않은 테스트나 실제 외부 API 호출을 성공했다고 표현하지 않는다.

## 명령어
```bash
flutter pub get
flutter run --dart-define=TRIPBLER_API_BASE_URL=http://<host>:8080 --dart-define=GOOGLE_OAUTH_SERVER_CLIENT_ID=<id>
flutter test --no-pub test/providers/exchange_swr_test.dart   # 테스트 파일 하나
flutter test --no-pub --plain-name "<테스트 이름>" <파일>       # 테스트 케이스 하나
```
- `TRIPBLER_API_BASE_URL`이 없으면 `ApiConfig.baseUrl`은 Android 에뮬레이터에서 `http://10.0.2.2:8080`, 그 외에는 `http://localhost:8080`을 쓴다.
- Google Maps 키: Android는 `android/local.properties`의 `GOOGLE_MAPS_ANDROID_API_KEY`, iOS는 `ios/Flutter/Secrets.xcconfig`에서 읽는다.
- `google_maps_flutter*` 패키지는 `dependency_overrides`로 `packages/`에 내려받아 수정해 쓴다(정적 분석 제외). pub 캐시가 아니라 이 폴더에서 고친다.

## 아키텍처

### 서버 연동
외부 서비스(환율, 암호화폐 시세, 장소, 번역)는 모두 백엔드 뒤에 있다. 앱은 외부 API 키를 갖지 않고 Tripbler 서버의 `/api/v1/...`만 호출한다. 엔드포인트 경로는 `lib/core/config/api_config.dart`에 모여 있다. OCR은 기기에서 실행하고(`lib/services/ocr_service.dart`, `google_mlkit_text_recognition`), 인식된 텍스트만 번역 API로 보낸다.

### 앱 구조
- `main.dart`에서 모든 `ChangeNotifierProvider`를 `MultiProvider`로 연결한다. `ExchangeDisplayProvider`는 `ExchangeProvider`(국가 통화)와 `CryptoProvider`를 합쳐 하나의 통화 목록을 만든다. `AuthGate`가 인증 화면과 `MainScreen` 중 무엇을 보여줄지 정한다.
- 화면 이동: `TabProvider`가 하단 탭 3개(환율 / 지도 / 번역)를 관리한다. 인덱스 `-1`은 홈(AI) 화면이고, 선택된 탭을 다시 누르면 홈으로 돌아간다.
- 계층: 화면 → Provider(상태) → Repository(인증) / Service(HTTP, 저장소, OCR). 환율 계산은 `lib/domain/exchange/`, 차트 데이터 변환은 `lib/presentation/charts/`에 있다.
- `lib/crypto/`는 독립된 기능 모듈(models/providers/services/widgets)이다. 서버 계약과 저장 키(`crypto.selected.v1`, `crypto.catalog.v1`, `exchange.displayOrder.v1`)는 `docs/crypto-ui.md`에 있다. 지원 코인 목록은 서버에서 받으므로 코드에 하드코딩하지 않는다.
- 시세 데이터는 저장값을 먼저 보여주고 다시 조회하는 방식(stale-while-revalidate)이다(`test/providers/exchange_swr_test.dart`, `test/crypto/market_swr_test.dart` 참고). `exchange_rate_cache_service.dart` / `market_snapshot_store.dart` / `chart_snapshot_store.dart`로 캐시하며, 서버의 `stale`/`fetchedAt`을 화면까지 유지해야 한다.
- 인증: `auth_http_client.dart`가 `Authorization` 헤더를 붙여 요청한다. 액세스 토큰 인증이 실패하면 `AuthProvider`가 `AuthRepository.refreshAccessToken()`으로 재발급을 시도한다. 토큰은 `token_storage_service.dart`를 통해 `flutter_secure_storage`에 저장한다.
