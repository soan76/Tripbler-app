# 상태 관리 전환 설계: provider → Riverpod

- 작성일: 2026-11-14
- 상태: 승인됨(2026-11-14)

## 1. 의도
`provider` 패키지는 마지막 업데이트 뒤 15개월이 지났다. 같은 개발자가 만들고 지금도 업데이트되는 Riverpod로 상태 관리를 옮겨, 앞으로도 관리되는 표준 방식 위에서 앱을 유지한다.

## 2. 목표 / 비목표 / 실패 조건
**목표**
- 앱의 상태 객체 10개를 모두 `flutter_riverpod` 3.x의 `Notifier`로 옮기고, `provider` 의존성을 제거한다.
- 화면 동작과 사용자가 보는 결과는 바꾸지 않는다.

**비목표**
- 기능 추가, 화면 디자인 변경, API 계약 변경.
- 코드 생성(`riverpod_generator`, `freezed`) 도입. 필요하면 전환을 마친 뒤 따로 검토한다.
- Repository·Service 계층 재설계. 생성 방식만 Riverpod provider로 바꾼다.

**실패로 보는 경우**(겉으로는 동작해도)
- 저장값 먼저 보여주기(SWR), `stale`/`fetchedAt` 표시, 갱신 실패 시 마지막 성공값 유지 동작이 달라진다.
- 화면이 사라진 뒤나 요청이 바뀐 뒤 늦게 온 비동기 응답이 상태에 반영된다.
- 두 방식이 섞인 상태로 작업이 멈춘다. 모든 단계는 앱과 테스트가 통과하는 상태로 끝나야 한다.
- Riverpod의 legacy API(`flutter_riverpod/legacy.dart`의 `ChangeNotifierProvider`, `StateNotifierProvider`)를 쓴다.

## 3. 현재 구조 (2026-11-14 기준)
`lib/main.dart`의 `MultiProvider`에 `ChangeNotifier` 10개를 연결한다(약 3,300줄).

| 클래스 | 위치 | 줄 수 | 다른 상태에 대한 의존 |
|---|---|---|---|
| AuthProvider | lib/providers | 561 | 없음 |
| AccountRecoveryProvider | lib/providers | 204 | 없음 |
| TabProvider | lib/providers | 53 | 없음 |
| SettingsProvider | lib/providers | 55 | 없음 |
| TranslationProvider | lib/providers | 236 | 없음 |
| ExchangeProvider | lib/providers | 669 | 없음 |
| CryptoProvider | lib/crypto/providers | 181 | 없음 |
| ExchangeDisplayProvider | lib/presentation/exchange | 212 | Exchange, Crypto에 `addListener` |
| ChartSelectionProvider | lib/presentation/charts | 229 | 없음 |
| MapProvider | lib/providers | 912 | Auth의 `runAuthorizedRequest`, 로그인 상태 `addListener` |

- 앱 코드에서 약 20개 파일이 `context.watch/read/select`나 `Consumer`를 쓴다. 지도·번역·환율 화면에 많이 몰려 있다.
- 테스트 약 13개 파일이 상태 클래스를 직접 생성하거나 `MultiProvider`로 위젯 트리를 만든다.
- 비동기 응답은 `_disposed` 플래그와 요청 번호(`_fetchRequestId` 등)로 막는다. Service는 생성자로 주입받고, 직접 만든 것만 `dispose`에서 정리한다(`_ownsApi`).

## 4. 검토한 방식
| 방식 | 내용 | 판단 |
|---|---|---|
| A. 감싸기 | 기존 클래스를 Riverpod `ChangeNotifierProvider`로 감싼다 | 제외. Riverpod 3에서 legacy로 분류된 API라 전환 목적과 맞지 않는다 |
| **B. Notifier로 다시 쓰기(코드 생성 없음)** | 불변 상태 클래스와 `Notifier`로 옮기고, 기능 단위로 단계적으로 전환한다 | **선택**(사용자 결정, 2026-11-14) |
| C. B와 같되 코드 생성 사용 | `@riverpod`, `build_runner` | 제외. 빌드 단계와 생성 파일이 늘어난다. B를 마친 뒤 얹을 수 있다 |

## 5. 설계

### 5.1 공통 규칙
- **패키지**: `flutter_riverpod: ^3.x`. 추가할 때 pub.dev의 최신 안정 버전을 확인한다. 마지막 단계에서 `provider`를 제거한다.
- **형태**: 기본은 `NotifierProvider<XNotifier, XState>`이고 `build()`는 동기로 쓴다.
  - `AsyncNotifier`는 쓰지 않는다. 지금 상태는 "로딩/빈 결과/실패 + 마지막 성공값 + stale/fetchedAt"을 함께 들고, 정해진 순서로 바뀐다(저장값 표시 → 갱신 중 → 성공 또는 실패 + 마지막 성공값 유지). 상태 클래스에 지금과 같은 필드를 그대로 두는 편이 이 상태와 전이 순서를 직접 보존하기 쉽다.
- **수명**: 지금처럼 앱 전체 수명으로 유지한다. `autoDispose`는 쓰지 않는다.
- **이름**
  - 클래스: `ExchangeProvider` → `ExchangeNotifier`. 상태 클래스는 `ExchangeState`.
  - 전역 provider 변수: `exchangeProvider`.
  - 파일 경로는 그대로 둔다. git 이력이 이어지게 하기 위해서다.
- **상태 클래스**
  - 필드는 모두 `final`이고, 직접 쓴 `copyWith`를 둔다. 리스트는 `List.unmodifiable`로 감싼다.
  - Riverpod 3은 상태가 `==`로 같으면 알리지 않는다. `==`를 재정의하지 않으면 새 객체마다 알림이 가므로 지금 `notifyListeners()`와 같은 동작이 된다. 기본은 재정의하지 않는다.
  - **nullable 필드 비우기 규칙**: `copyWith`를 `새 값 ?? 기존 값`으로만 만들면 `null`로 비울 수 없다. 기준 통화 변경 시 `activeCrypto`·`krwRate`를 비우는 것, 환산 재시도 시 `conversionError`를 지우는 것 같은 동작이 깨진다.
    - 규칙: nullable 필드는 비우기 전용 bool 인자를 함께 둔다(예: `copyWith({String? activeCrypto, bool clearActiveCrypto = false})`).
    - 여러 필드를 함께 비우는 전이는 이름 있는 상태 메서드로 둔다(예: `ExchangeDisplayState.resetForBase()`).
    - 이 규칙은 1단계에서 확정한다. 1단계의 Settings·Tab에는 nullable 필드가 없으므로, 규칙과 단위 테스트만 그 단계에서 만들어 둔다. 실제 검증은 3단계의 기준 통화 변경 테스트로 한다.
- **getter·계산 메서드**(`decimalPlacesFor`, `visible`, `isSelected` 등)는 상태 클래스로 옮긴다. 화면에서는 `ref.watch(p).decimalPlacesFor(...)`처럼 쓴다.
- **동작 메서드**는 Notifier에 둔다. 화면에서는 `ref.read(p.notifier).method()`로 호출한다.
- **Service 주입**
  - Service마다 `Provider`를 만들고 `ref.onDispose(service.dispose)`로 정리한다.
  - Notifier는 `ref.read(xServiceProvider)`로 받는다. 테스트에서는 `overrides`로 가짜를 넣는다.
  - 기존 생성자 주입과 `_ownsApi`는 없앤다.
  - 위치: 각 Notifier 파일 옆, 또는 `lib/providers/service_providers.dart` 한 곳. 빌더가 정한다.
- **비동기 가드**: 상태는 앱 전체 수명이라, 화면을 닫아도 `ref.mounted`는 `true`로 남는다. 그래서 막아야 할 경우를 셋으로 나누고, 각각 다른 장치로 막는다.
  1. **상태 객체가 폐기된 뒤 도착한 응답**: `ref.mounted`로 막는다. 기존 `_disposed`/`_isDisposed`와 같은 범위다. 앱 종료나 테스트의 컨테이너 폐기, override 교체 때 해당한다.
  2. **통화·기간·검색어·세션이 바뀌기 전에 보낸 요청의 응답**: 요청 번호(`_fetchRequestId`, `_searchRequestId` 등)와 세션 번호로 무효화한다. 지금 코드의 번호를 Notifier 필드로 그대로 옮긴다.
  3. **화면을 닫은 뒤의 다이얼로그·내비게이션·SnackBar**: 위젯의 `mounted`(`ConsumerState.mounted`, `context.mounted`)로 막는다. 이 책임은 지금처럼 화면에 있다.
  - `await` 뒤에는 1과 2를 모두 확인한 다음 `state`를 바꾼다.
  - 화면을 떠난 동안 진행 중이던 유효한 시세 갱신은 지금처럼 끝까지 반영한다. 지금도 상태가 앱 수명이라 화면을 떠나도 갱신이 이어지기 때문이다.
- **Timer·리스너 정리**: `build()` 안에서 `ref.onDispose`로 등록한다(예: MapNotifier의 상세 표시 타이머).
- **초기화**
  - 지금처럼 화면이 `initialize()`를 명시적으로 호출하는 구조를 유지한다. `build()`에서 자동으로 요청을 시작하지 않는다. 호출 시점이 바뀌면 SWR 순서가 바뀔 수 있기 때문이다.
  - `initialize()`의 중복 호출 방지(`_initialization ??=`)도 그대로 둔다.
- **Riverpod 3 기본 동작**
  - **자동 재시도**: `ProviderScope(retry: (_, _) => null)`로 끈다. 자동 재시도는 provider 값을 계산하다(`build()`) 예외가 난 경우에만 적용된다. 화면이 호출한 `refresh()` 등에서 오류를 잡아 실패 상태를 저장하는 흐름은 지금처럼 각 Notifier가 맡는다. 끄는 이유는, `build()`가 예상치 못하게 실패했을 때 몰래 다시 실행되는 일을 막기 위해서다.
  - **화면 밖 구독 일시 중지**: Riverpod 3은 `TickerMode`가 꺼진 위젯의 구독을 멈춘다. 탭 화면은 `IndexedStack`(`main_screen.dart:81`)이지만, 이것만으로 선택되지 않은 탭의 `TickerMode`가 꺼진다고 단정하지 않는다. 구독이 멈추면 그 화면만 구독하는 provider도 멈출 수 있고, 멈춘 동안의 중간 변화가 마지막 값 하나로 합쳐질 수 있다. 어느 쪽이든 맞게 동작하도록 설계한다.
    - 그래서 "중간 변화가 있었는지"로 동작이 달라지는 곳은 값(`isAuthenticated`)이 아니라 계속 늘어나는 번호(세션 번호)를 비교한다(5.2 Map).
    - 동작 차이가 없는지는 5.5의 지도 시나리오로 검증한다.

### 5.2 의존 관계 바꾸기
**ExchangeDisplay**(`ExchangeDisplayProvider`가 Exchange·Crypto에 `addListener`)
- `ExchangeDisplayNotifier`는 자기 상태만 가진다. 표시 순서 `order`, `activeCrypto`, `krwRate`, `conversionError`다.
- 기준 통화가 바뀌는 것은 `build()`에서 `ref.listen(exchangeProvider.select((s) => s.baseCurrency.code), ...)`로 받는다. 받으면 지금 `_onExchange`처럼 `krwRate`·`activeCrypto`를 비우고 `refreshConversion()`을 호출한다.
  - `ref.watch`는 쓰지 않는다. `build()`가 다시 돌면서 자기 상태가 초기화되기 때문이다.
- 화면용 파생 값은 별도의 계산 provider로 뺀다. 이 provider가 `exchangeProvider`, `cryptoProvider`, `exchangeDisplayProvider`를 `watch`해서 조합한다. 지금 `exchange.addListener`·`crypto.addListener(_notify)`로 하던 재알림은 이것으로 대체된다.
  - 행 목록만 다루지 않는다. 화면은 `amountFor(row)`(`exchange_screen.dart:90`)와 `isActive(row)`(`:67`)도 쓴다. 두 값은 행 목록의 구성·순서가 그대로여도 바뀐다.
    - `amountFor(row)`: 입력 금액, 코인 시세, KRW 연결 환율에 따라 바뀐다.
    - `isActive(row)`: `activeCrypto`와 `exchange.activeInputCurrencyCode`를 함께 읽는다.
  - 그래서 계산 provider의 결과에 행별 표시 금액과 선택 여부를 함께 담는다(예: `ExchangeDisplayView { base, available, rows: [ { currency, amount, isActive } ] }`). 행 목록을 비교해서 알림을 거르는 최적화(`==` 재정의)는 하지 않는다.
  - 화면의 상태 문구에 쓰는 코인 시세·`isStale`·`isLoading`은 지금처럼 `cryptoProvider`를 `watch`해 읽는다.
- 메서드 안에서 Exchange·Crypto를 바꿀 때는 `ref.read(exchangeProvider.notifier)`를 쓴다.

**Map**(`MapProvider`가 Auth를 사용)
지도에는 요청 실행기와 현재 인증 상태가 모두 필요하다.
- 지금 코드는 세 가지를 한다.
  - 요청을 실행한다(`runAuthorizedRequest`).
  - 비동기 요청이 끝나는 시점에 로그인 여부를 다시 읽는다(`_isSignedIn`, `map_provider.dart:499,504`).
  - 인증 상태가 바뀔 때마다 처리한다(`_handleAuthStateChanged`, `:590`). 재로그인하면 대기 중인 이전 세션의 만료 안내를 지우고, 로그아웃하면 검색 결과·선택·상세 캐시를 비우고 진행 중인 검색을 로그아웃 뒤 요청으로 표시한다.
- **요청 실행기**: `authorizedRequestRunnerProvider`가 `ref.read(authProvider.notifier).runAuthorizedRequest`를 돌려준다. 지금 생성자의 `authorizedRequest` 주입을 대체한다.
- **현재 인증 상태 읽기**: 요청이 끝나는 시점의 로그인 여부는 `ref.read(authProvider).isAuthenticated`로 읽는다. `ref.read`는 구독이 멈춰 있어도 항상 현재 값을 준다.
- **인증 전이 받기**: `AuthState`에 저장소의 `sessionId`를 노출한다. `sessionId`는 이미 로그인·로그아웃·만료 때마다 바뀐다. MapNotifier는 `build()`에서 `ref.listen(authProvider.select((s) => (s.sessionId, s.isAuthenticated)), ...)`로 받는다.
  - `sessionId`가 바뀌면 이전 세션의 검색 결과·선택·상세 캐시를 비운다. 사용자 요청이 확정한 만료 안내는 재로그인 전까지 기존의 1회 표시 규칙을 따르고, 재로그인하면 이전 세션의 대기 중 안내를 지운다. 진행 중 검색은 로그아웃 뒤 요청으로 표시한다.
  - 지도 구독이 멈춘 동안 로그아웃→재로그인이 일어나서 다시 볼 때 `isAuthenticated`가 `true` 하나로 합쳐져도, `sessionId`가 다르므로 비우기가 빠지지 않는다.
  - **세션이 달라졌을 때 버릴 것과 남길 것**: 이전 세션의 검색 결과와 상세 결과는 반영하지 않고 버린다. 만료 안내는 따로 판단한다.
    - 사용자 요청이 세션 만료를 확정했고 아직 재로그인 전이면, 검색 상태를 이미 비웠더라도 만료 안내를 정확히 한 번 남긴다.
    - 재로그인한 뒤 도착한 이전 세션의 만료 예외는 안내하지 않는다.
    - 그래서 `sessionId` 비교를 모든 `catch` 앞의 일괄 `return`으로 구현하지 않는다. 지금 코드(`map_provider.dart:447-460`)처럼 만료 예외는 먼저 안내 여부를 판단하고, 그다음에 결과 반영 여부를 판단한다.
  - 세션 번호 노출은 `AuthState`에 필드 하나를 더하는 것이며, 앱 동작과 API 계약은 바뀌지 않는다.
- **테스트**: 실행기만 가짜로 바꾸는 것으로는 부족하다. 다음 두 가지를 각각 제어할 수 있어야 한다.
  - 인증 상태 전이: 가짜 `authProvider`를 override해서 로그인·로그아웃·재로그인과 `sessionId`를 테스트가 직접 바꾼다.
  - 요청 완료 순서: 가짜 실행기가 `Completer`로 응답 시점을 테스트에 맡긴다.
- 시간 주입(`now`)은 `clockProvider`로 바꾸거나 Notifier 필드로 남긴다. 빌더가 정한다.

### 5.3 화면 쪽
- 상태를 읽는 위젯은 `ConsumerWidget`이나 `ConsumerStatefulWidget`으로 바꾼다.
- 바꾸는 방식은 아래와 같다.

| 지금 | 바꾼 뒤 |
|---|---|
| `context.watch<X>()` | `ref.watch(xProvider)` |
| `context.select<X, T>(f)` | `ref.watch(xProvider.select(f))` |
| `context.read<X>().m()` | `ref.read(xProvider.notifier).m()` |

- 지금 `select`로 범위를 좁힌 곳은 그대로 `select`를 유지한다. 다시 그리는 범위가 넓어지지 않게 하기 위해서다.
- `main.dart`: `runApp(ProviderScope(retry: ..., child: TripblerApp()))`. 전환하는 동안에는 `ProviderScope` 안쪽에 아직 옮기지 않은 것만 담은 `MultiProvider`를 둔다.

### 5.4 단계와 순서
모든 단계는 독립된 커밋이다. 단계마다 앱이 빌드되고 관련 테스트가 통과해야 한다.

| 단계 | 대상 | 이유 |
|---|---|---|
| 0a | 이 설계 문서만 커밋 | 설계와 코드 변경을 분리한다 |
| 0b | `flutter_riverpod` 추가, `ProviderScope`로 감싸기, 재시도 끄기(별도 커밋) | 동작 변경 없이 기반만 놓는다 |
| 1 | Settings, Tab. `copyWith` 비우기 규칙 확정 | 작고 의존 관계가 없다. 규칙을 확정하는 시범 단계 |
| 2 | ChartSelection, Translation, AccountRecovery | 의존 관계가 없다 |
| 3 | Exchange, Crypto, ExchangeDisplay(함께) | 서로 묶여 있어 나눠 옮기면 두 방식을 잇는 코드가 필요해진다 |
| 4 | Auth, Map(함께) | Map이 Auth를 쓰고, AuthGate·로그인 화면이 Auth를 쓴다 |
| 5 | `MultiProvider`와 `provider` 의존성 제거, 문서(`AGENTS.md`의 "Provider 구조" 표현, `docs/crypto-ui.md`) 갱신 | 마무리 |

### 5.5 테스트
- 단위 테스트는 상태 클래스를 직접 생성하던 부분을 `ProviderContainer.test(overrides: [...])`로 바꾼다. 가짜 Service는 service provider override로 넣는다.
- 위젯 테스트는 `MultiProvider`를 `ProviderScope(overrides: [...])`로 바꾼다.
- **검증 내용(assertion)은 바꾸지 않는다.** 바꿔야 한다면 이유를 커밋 메시지에 적는다.
- `addListener`로 알림 횟수를 세던 테스트는 `container.listen`으로 바꾼다.
- 단계마다 실행하는 것
  - 바뀐 파일: `dart format`, `flutter analyze --no-pub`
  - 해당 기능 테스트
  - 3·4단계는 추가로 `test/providers/exchange_swr_test.dart`, `test/crypto/market_swr_test.dart`, `test/providers/map_provider_search_test.dart`
- 마지막 단계에서는 `flutter test --no-pub` 전체를 실행한다.
- **단계별 추가 완료 조건**
  - 3단계(환율)
    - 행 목록이 그대로일 때 입력 금액만 바뀌어도 다른 행의 표시 금액이 갱신된다.
    - 코인 시세만 바뀌어도 해당 코인 행의 표시 금액이 갱신된다.
    - 입력 행을 국가 통화 ↔ 코인으로 바꾸면 선택 표시(`isActive`)가 새 행으로 옮겨 가고, 이전 행에서는 사라진다.
    - 기준 통화를 바꾸면 `activeCrypto`·KRW 연결 환율이 비워지고(`null`), 환산을 다시 시도하면 `conversionError`가 지워진다. nullable 비우기 규칙을 검증하는 테스트다.
    - 기준 통화나 기간을 바꾼 뒤 이전 요청의 응답이 도착해도 반영되지 않는다(요청 번호).
  - 4단계(지도)
    - 시나리오: 지도에서 검색 시작(응답 대기) → 다른 탭으로 이동 → 로그아웃 → 재로그인 → 이전 요청 완료 → 지도 탭 복귀. 복귀했을 때 이전 사용자의 검색 결과, 선택한 장소, 상세 캐시, 이전 세션의 만료 안내가 남아 있지 않아야 한다. 이 시나리오를 두 테스트로 따로 검증한다.
      - 실제 탭 전환: 실제 `MainScreen`으로 탭을 옮겼다가 지도로 돌아온다.
      - 구독 일시 중지: 지도 Consumer를 `TickerMode(enabled: false)`로 감싸 구독을 멈춘 뒤, 같은 결과가 나오는지 확인한다. 상태 사이의 `ref.listen`이 중간 전이를 모두 전달하는지에 앱의 정확성을 걸지 않기 위해서다.
    - 기존 세션 만료 안내 테스트를 그대로 완료 조건으로 삼는다.
      - "검색 중 만료되면 검색 상태가 먼저 비워져도 안내를 정확히 한 번 남긴다"(`map_provider_search_test.dart:1264`)
      - "새 로그인 뒤 도착한 이전 세션의 만료 예외는 안내하지 않는다"(`:1352`)
    - 지도 탭에 머문 상태에서 로그아웃→재로그인해도 같은 결과가 나온다.
    - 기존 `map_provider_search_test.dart`의 인증 관련 검증은 모두 그대로 통과한다.
  - 공통: 상태 객체를 폐기한 뒤(테스트 컨테이너 dispose) 응답이 도착해도 예외 없이 무시된다(`ref.mounted`).
- 기기 실행 확인
  - 3단계 뒤: 환율 화면. 저장값 표시 → 갱신, 기준 통화 변경, 오프라인일 때 stale 표시
  - 4단계 뒤: 로그인·로그아웃, 장소 검색, 로그아웃 시 검색 결과 비우기

## 6. 빌더에게 맡기는 것
- 각 상태 클래스의 필드를 어떻게 나눌지. 지금 private 필드를 기준으로 한다.
- service provider 파일 위치, `now` 주입 방식.
- 화면별로 `ConsumerWidget`과 `Consumer` 위젯 중 무엇을 쓸지. 다시 그리는 범위가 지금보다 넓어지지 않으면 된다.

## 7. 결정 기록
**사용자 승인(2026-11-14)**
- 동기 `Notifier`와 불변 상태를 쓴다.
- 초기 조회는 기존 화면에서 시작한다.
- 서로 의존하는 상태는 같은 단계에서 옮긴다.
- 파일 경로는 유지한다.
- 단계 순서는 그대로 둔다. 0단계는 설계 문서 커밋과 의존성 도입 커밋으로 나눈다.

**검토 반영(2026-11-14)**
- 비동기 가드를 세 가지 경우로 나눴다: 상태 폐기는 `ref.mounted`, 요청·세션 변경은 번호, 화면 닫힘은 위젯 `mounted`.
- ExchangeDisplay 계산 provider에 행별 금액과 선택 여부를 넣었다.
- 지도에 요청 실행기와 현재 인증 상태를 모두 주고, 인증 전이와 요청 완료 순서를 테스트에서 각각 제어하게 했다.
- nullable 필드를 비우는 `copyWith` 규칙을 정했다.

**설계자가 정한 것**
- 지도의 인증 전이 판단은 `isAuthenticated` 대신 `sessionId` 비교로 한다. 화면 밖 구독이 멈추면 중간 전이가 합쳐질 수 있어서다. 실제로 멈추는지는 테스트로 따로 확인한다(5.2, 5.5).
- 비우기 규칙은 `clearX` bool 인자와 이름 있는 상태 메서드로 정했다(5.1).
