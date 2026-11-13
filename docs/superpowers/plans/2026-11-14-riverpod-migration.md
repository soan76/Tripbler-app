# provider → Riverpod 전환 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱 상태 10개를 `provider`의 `ChangeNotifier`에서 `flutter_riverpod` 3의 동기 `Notifier`로 옮기고, `provider` 의존성을 제거한다. 화면 동작은 바꾸지 않는다.

**Architecture:** 단계마다 옮긴 상태는 `ProviderScope`가 관리하고, 아직 옮기지 않은 상태는 그 안쪽 `MultiProvider`에 둔다. 상태는 불변 `XState` 클래스와 `XNotifier`로 나눈다. Service는 provider로 만들어 테스트에서 override한다. 서로 의존하는 상태(Exchange·Crypto·ExchangeDisplay, Auth·Map)는 같은 태스크에서 옮긴다.

**Tech Stack:** Flutter, Dart SDK ^3.9.2, `flutter_riverpod` 3.5.x(pub.dev 최신, 2026-11-06 배포), 코드 생성 없음.

**Spec:** `docs/superpowers/specs/2026-11-14-riverpod-migration-design.md`(커밋 `c1f6920`). 0a단계(설계 문서 커밋)는 끝났다.

## Global Constraints
- 패키지: `flutter_riverpod: ^3.5.0`. `riverpod_generator`, `freezed`, `build_runner`는 추가하지 않는다.
- legacy API(`package:flutter_riverpod/legacy.dart`의 `ChangeNotifierProvider`, `StateNotifierProvider`, `StateProvider`)는 쓰지 않는다.
- 형태: `NotifierProvider<XNotifier, XState>(XNotifier.new)`. `build()`는 동기이고, `autoDispose`는 쓰지 않는다. `AsyncNotifier`는 쓰지 않는다.
- `Notifier.build()`에서는 service provider만 `ref.watch`/`ref.read`한다. 다른 상태 provider는 `ref.listen`으로만 받는다. `ref.watch`를 쓰면 `build()`가 다시 돌면서 상태가 초기화된다.
- 이름: 클래스는 `XNotifier`/`XState`, 전역 변수는 `xProvider`. 파일 경로는 바꾸지 않는다.
- 상태 클래스
  - 필드는 모두 `final`이고, 리스트·맵·셋은 `List.unmodifiable` 등으로 감싼다.
  - `==`는 재정의하지 않는다.
  - nullable 필드를 비우려면 `copyWith`에 `bool clearX = false` 인자를 둔다. 여러 필드를 함께 비우는 전이는 이름 있는 메서드로 둔다.
- 비동기 가드: `await` 뒤에는 ① `ref.mounted`(기존 `_disposed`/`_isDisposed` 대체), ② 기존 요청 번호·세션 번호를 확인한 뒤 `state`를 바꾼다. 화면의 다이얼로그·내비게이션·SnackBar는 위젯 `mounted`로 막는다(지금과 같음).
- 초기화는 지금처럼 화면이 `initialize()`/`restoreSession()`을 호출한다. `build()`에서 요청을 시작하지 않는다. `_initialization ??=` 중복 방지도 유지한다.
- `main.dart`: `ProviderScope(retry: (_, _) => null, child: ...)`.
- 기존 테스트의 검증 내용(assertion)은 바꾸지 않는다. 설정 코드만 바꾼다. 검증을 바꿔야 하면 커밋 메시지에 이유를 적는다.
- 태스크마다 실행: 바뀐 Dart 파일에 `dart format`, `flutter analyze --no-pub lib test`(새 문제 0건), 태스크에 적힌 테스트, `git diff --check`.
- 커밋 메시지는 한국어로 쓰고, 끝에 빈 줄과 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`을 넣는다.

## Review Focus
1. **기준 통화를 바꾼 직후 늦게 도착한 이전 기준의 KRW 연결 환율 응답**: 새 기준의 금액에 섞이면 안 된다. → Task 5의 `기준 통화 변경 직후 이전 요청의 KRW 환율은 반영하지 않는다`
2. **환율 화면을 떠난 동안 끝난 시세 갱신**: 돌아왔을 때 갱신된 값과 원래 `fetchedAt`이 보여야 한다. 상태는 앱 수명이라 버리면 안 된다. → Task 5의 `화면을 떠난 동안 끝난 갱신도 상태에 남는다`
3. **로그아웃 직후 `AuthState.sessionId`가 저장소 값과 어긋나는 경우**: 지도가 이전 세션 결과를 남기면 안 된다. → Task 6의 `로그인·로그아웃·만료마다 sessionId가 저장소와 같다`
4. **지도 상세 표시 Timer가 컨테이너 폐기 뒤에 울리는 경우**: 예외 없이 무시돼야 한다. → Task 6의 `폐기 뒤 상세 표시 타이머가 상태를 바꾸지 않는다`
5. **설정 화면의 다크 모드 전환이 `MaterialApp`에 바로 반영되지 않는 경우**: 루트가 `ConsumerWidget`이어야 한다. → Task 2의 `테마 전환이 MaterialApp themeMode에 반영된다`

---

### Task 1: Riverpod 도입 (0b단계)

**Files:**
- Modify: `pubspec.yaml`(dependencies에 `flutter_riverpod: ^3.5.0`)
- Modify: `lib/main.dart`
- Create: `test/app_scope_test.dart`

**Interfaces:**
- Produces: `Widget buildAppScope({List<Override> overrides = const [], required Widget child})`(`lib/main.dart`). `ProviderScope(retry: (_, _) => null, overrides: overrides, child: child)`를 돌려준다. `main()`은 `runApp(buildAppScope(child: MultiProvider(...기존 그대로..., child: const TripblerApp())))`.

- [ ] **Step 1: 실패하는 테스트 작성** `test/app_scope_test.dart`

```dart
final failing = Provider<int>((ref) {
  calls++;
  throw StateError('x');
});
testWidgets('buildAppScope는 자동 재시도를 하지 않는다', (tester) async {
  calls = 0;
  await tester.pumpWidget(buildAppScope(
    child: Consumer(builder: (_, ref, __) {
      ref.watch(failing.select((_) => 0)); // 오류 상태 구독
      return const SizedBox();
    }),
  ));
  await tester.pump(const Duration(seconds: 5));
  expect(calls, 1);
});
```
(`ref.watch`가 오류를 다시 던지면 `tester.takeException()`으로 받아 처리한다.)

- [ ] **Step 2: 실행해 실패 확인**: `flutter pub get` 후 `flutter test --no-pub test/app_scope_test.dart` → `buildAppScope` 미정의로 FAIL.
- [ ] **Step 3: `buildAppScope` 구현, `main()`에 적용.**
- [ ] **Step 4: 실행해 통과 확인**: 같은 명령 PASS. 이어서 `flutter test --no-pub`을 전체 실행해 기존과 같은 수(2026-11-14 기준 836건 이상)가 통과하는지 확인한다.
- [ ] **Step 5: 커밋** `Riverpod 도입: flutter_riverpod 추가, ProviderScope와 자동 재시도 끄기`

---

### Task 2: Settings·Tab 전환과 상태 클래스 규칙 확정 (1단계)

**Files:**
- Modify: `lib/providers/settings_provider.dart`, `lib/providers/tab_provider.dart`
- Modify(사용처): `lib/main.dart`(`TripblerApp` → `ConsumerWidget`), `lib/screens/settings_screen.dart`, `lib/widgets/exchange/currency_row.dart`, `lib/widgets/map/tripbler_google_map.dart`, `lib/screens/main_screen.dart`, `lib/screens/map_screen.dart`(Tab 부분만)
- Modify(테스트): `test/providers/settings_provider_test.dart`. 이 두 클래스를 `MultiProvider`로 넣는 위젯 테스트(`grep -rln "SettingsProvider\|TabProvider" test`)
- Create: `test/providers/tab_provider_test.dart`, `test/app_theme_switch_test.dart`

**Interfaces:**
- Produces
  - `SettingsState { final int decimalPlaces; final ThemeMode themeMode; int decimalPlacesFor({required bool isCrypto}); bool get isDarkMode; String get decimalPlacesLabel; }`
  - `SettingsNotifier.autoFiatDecimalPlaces`, `autoCryptoDecimalPlaces`, `autoDecimalPlacesLabel`(static const)는 `SettingsState`로 옮긴다.
  - `SettingsNotifier { void changeDecimalPlaces(int value); void toggleTheme(); }`
  - `final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);`
  - `TabState { final int selectedIndex; bool get isHomeSelected; bool isSelected(int index); }`. static const `homeIndex`·`firstTabIndex`·`tabCount`는 `TabState`로 옮긴다.
  - `TabNotifier { void selectTab(int index); void selectHome(); }`, `final tabProvider = NotifierProvider<TabNotifier, TabState>(TabNotifier.new);`
- 이후 태스크가 따를 규칙(이 태스크의 코드로 확정): 상태 클래스는 `const` 생성자 + `copyWith`. 바꾼 값이 같으면 `state`에 대입하지 않는다(지금의 "같으면 notify 안 함"과 동일).

- [ ] **Step 1: 테스트 작성/변환**
  - `settings_provider_test.dart`: 생성을 `final c = ProviderContainer.test();`로 바꾸고, 기존 단언을 `c.read(settingsProvider).decimalPlacesFor(...)`로 유지한다.
  - `tab_provider_test.dart` 새로 작성
    - `같은 탭을 다시 누르면 홈으로 돌아간다`: `selectTab(1)` 후 `selectTab(1)` → `selectedIndex == TabState.homeIndex`
    - `범위 밖 인덱스는 무시한다`: `selectTab(3)` → 상태 변화 없음, `c.listen` 호출 0회
  - `app_theme_switch_test.dart`: 앱 루트(`buildAppScope(child: MultiProvider(...남은 것..., child: TripblerApp()))`)를 띄운 뒤 `toggleTheme()` → `tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode == ThemeMode.dark`
- [ ] **Step 2: 실행해 실패 확인**: `flutter test --no-pub test/providers/settings_provider_test.dart test/providers/tab_provider_test.dart test/app_theme_switch_test.dart` → 미정의 FAIL.
- [ ] **Step 3: 구현**
  - 두 Notifier와 상태 클래스를 만들고, `main.dart`의 `MultiProvider`에서 두 항목을 지운다.
  - 사용처를 `ConsumerWidget`/`ConsumerStatefulWidget`으로 바꾼다. `context.select`는 `ref.watch(p.select(...))`로 바꾼다.
- [ ] **Step 4: 실행해 통과 확인**: Step 2 명령 PASS. 그 뒤 `flutter test --no-pub test/widgets test/providers` PASS.
- [ ] **Step 5: 커밋** `Settings·Tab 상태를 Riverpod Notifier로 전환`

---

### Task 3: ChartSelection 전환 (2단계 ①)

**Files:**
- Modify: `lib/presentation/charts/chart_selection_provider.dart`, `lib/screens/exchange_screen.dart`(ChartSelection 부분), 차트 위젯 중 `ChartSelectionProvider`를 쓰는 곳(`grep -rn ChartSelectionProvider lib`)
- Modify(테스트): `test/presentation/charts/chart_selection_provider_test.dart`, `test/widgets/exchange/chart_delete_mode_test.dart`, `chart_focus_test.dart`, `chart_pair_selection_test.dart`, `chart_swap_test.dart`, `crypto_currency_ui_test.dart`의 ChartSelection 설정

**Interfaces:**
- Produces
  - `ChartSelectionState { final List<ChartPair> pairs; final bool loaded; final ({String from, String to, bool swapped, bool exchanged})? lastSideEdit; bool get canAdd; bool get canRemove; }`. `storageKey`, `maxCards`, `defaults`는 `ChartSelectionNotifier`의 static const로 둔다.
  - `ChartSelectionNotifier`: `Future<void> initialize()`, `ChartPairChange replace(int index, ChartPair next)`, `ChartPairChange replaceSide(...)`(시그니처 그대로), `ChartPair? add()`, `void remove(int index)`. 이 밖의 기존 public 메서드도 이름·시그니처를 그대로 둔다.
  - `final chartSelectionProvider = NotifierProvider<ChartSelectionNotifier, ChartSelectionState>(ChartSelectionNotifier.new);`
- `ChartPairChange` enum은 그대로 둔다.

- [ ] **Step 1: 테스트 설정 변환**: 단위 테스트는 `ProviderContainer.test()`로, 위젯 테스트는 `buildAppScope(child: MultiProvider(남은 것, child: ...))`로 바꾼다. 단언은 그대로 둔다.
- [ ] **Step 2: 실행해 실패 확인**: `flutter test --no-pub test/presentation/charts test/widgets/exchange` → 컴파일 FAIL.
- [ ] **Step 3: 구현.** `_disposed`는 `ref.mounted`로 바꾼다. `SharedPreferences` 읽기 뒤에도 `ref.mounted`를 확인한다.
- [ ] **Step 4: 실행해 통과 확인**: Step 2 명령 PASS.
- [ ] **Step 5: 커밋** `차트 선택 상태를 Riverpod Notifier로 전환`

---

### Task 4: Translation·AccountRecovery 전환 (2단계 ②)

**Files:**
- Modify: `lib/providers/translation_provider.dart`, `lib/screens/translation_screen.dart`
- Modify: `lib/providers/account_recovery_provider.dart`, `lib/screens/auth/find_id_screen.dart`, `find_password_screen.dart`, `reset_password_screen.dart`
- Create: `test/providers/translation_provider_test.dart`, `test/providers/account_recovery_provider_test.dart`

**Interfaces:**
- Produces
  - `ocrServiceProvider = Provider<OcrService>`, `translationServiceProvider = Provider<TranslationService>`. 각각 `dispose` 메서드가 있으면 `ref.onDispose`로 정리한다.
  - `TranslationState`: 기존 getter(`status`, `selectedImagePath`, `recognizedText`, `translatedText`, `errorMessage`, `sourceLanguageCode`, `targetLanguageCode`, `hasImage`, `hasRecognizedText`, `hasTranslatedText`, `isProcessing`, `languages`)와 같은 이름. `TranslationNotifier`의 메서드는 기존 이름·시그니처 그대로(`setStatus`, `setError`, `changeSourceLanguage`, `changeTargetLanguage`, `swapLanguages`, `processImage`, `translateRecognizedText`, `resetForRetake`). `translationProvider`.
  - `accountRecoveryRepositoryProvider = Provider<AuthRepository>`. AuthProvider와 **별도 인스턴스**다(지금과 같음). `ref.onDispose(repo.dispose)`.
  - `AccountRecoveryState { bool isLoading; String? errorMessage; }`. 메서드는 기존 그대로. `accountRecoveryProvider`.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `translation_provider_test.dart`
    - `processImage가 끝나기 전에 resetForRetake하면 늦은 OCR 결과를 반영하지 않는다`: 가짜 `OcrService`가 `Completer`로 응답하게 하고, reset 뒤 complete → `recognizedText == ''`
    - `swapLanguages는 auto 원본에서 기존 규칙을 따른다`: 기대값은 지금 코드 결과를 먼저 기록해 둔다.
  - `account_recovery_provider_test.dart`: `실패하면 errorMessage를 남기고 isLoading을 끈다`(가짜 repo가 예외를 던짐)
- [ ] **Step 2: 실행해 실패 확인**: `flutter test --no-pub test/providers/translation_provider_test.dart test/providers/account_recovery_provider_test.dart` → FAIL.
- [ ] **Step 3: 구현.** 첫 번째 테스트가 기존 코드에서도 늦은 결과를 반영한다면, 기존 동작을 유지하고 테스트 기대값을 기존 동작으로 바꾼다. 이 경우 진행 기록에 적는다(동작 변경은 이 계획의 범위가 아님).
- [ ] **Step 4: 실행해 통과 확인**: Step 2 명령, `flutter test --no-pub test/widgets/auth` PASS.
- [ ] **Step 5: 커밋** `번역·계정 복구 상태를 Riverpod Notifier로 전환`

---

### Task 5: Exchange·Crypto·ExchangeDisplay 전환 (3단계)

**Files:**
- Modify: `lib/providers/exchange_provider.dart`, `lib/crypto/providers/crypto_provider.dart`, `lib/presentation/exchange/exchange_display_provider.dart`
- Create: `lib/presentation/exchange/exchange_display_view.dart`
- Modify(사용처): `lib/screens/exchange_screen.dart`, `lib/screens/settings_screen.dart`, `lib/widgets/exchange/chart_currency_picker_sheet.dart`, `lib/widgets/exchange/currency_management_bottom_sheet.dart`, `lib/main.dart`
- Modify(테스트): `test/providers/exchange_swr_test.dart`, `test/crypto/crypto_test.dart`, `test/crypto/market_swr_test.dart`, `test/widgets/exchange/*`(Exchange·Crypto·Display 설정)
- Create: `test/presentation/exchange/exchange_display_view_test.dart`

**Interfaces:**
- Consumes: `settingsProvider`(Task 2)
- Produces
  - Service provider: `exchangeRateApiServiceProvider`, `localStorageServiceProvider`, `cryptoApiServiceProvider`. ExchangeDisplay의 KRW 조회도 `exchangeRateApiServiceProvider`를 함께 쓴다(지금은 인스턴스가 따로지만, 상태가 없는 HTTP 서비스라 동작이 같음. 다르면 별도 provider로 되돌린다).
  - `ExchangeState`: `baseCurrency`, `visibleCurrencies`, `inputAmount`, `activeInputCurrencyCode`, `rates`, `isLoading`, `errorMessage`, `lastUpdated`, `allRows`, `double convertedAmount(String)`, `double? rateFor(String)`. `ExchangeNotifier`의 메서드는 기존 그대로(`initialize`, `fetchRates`, `changeAmountFromCurrency`, `selectInputCurrency`, `changeBaseCurrency`, `replaceVisibleCurrency`, `applyVisibleCurrencies`, `addCurrency`, `removeCurrency`). `exchangeProvider`.
  - `CryptoState`: `coins`, `selectedCoins`, `loading`, `catalogError`, `CryptoPrice? priceFor(String)`, `bool isStale(String)`, `String? errorFor(String)`, `bool isLoading(String)`. `_pending`의 Future 맵은 Notifier 필드로 두고, 상태에는 `Set<String> pendingSymbols`만 둔다. `CryptoNotifier` 메서드는 기존 그대로. `cryptoProvider`.
  - `ExchangeDisplayState { final List<String> order; final String? activeCrypto; final double? krwRate; final String? conversionError; ExchangeDisplayState resetForBase(); }`. `resetForBase()`는 `activeCrypto`·`krwRate`를 `null`로 만든다. `ExchangeDisplayNotifier` 메서드는 기존 그대로(`initialize`, `apply`, `refresh`, `refreshConversion`, `selectInput`, `changeAmount`). `exchangeDisplayProvider`.
  - `ExchangeDisplayView { final DisplayCurrency base; final List<DisplayCurrency> available; final List<DisplayRowView> rows; }`, `DisplayRowView { final DisplayCurrency currency; final double? amount; final bool isActive; }`
  - `final exchangeDisplayViewProvider = Provider<ExchangeDisplayView>((ref) => ...)`: `exchangeProvider`, `cryptoProvider`, `exchangeDisplayProvider`를 `watch`한다. `rows`의 순서·`amount`·`isActive`는 지금의 `visible`·`amountFor`·`isActive`와 같은 계산이다.
  - 기준 통화 변경 감지: `ExchangeDisplayNotifier.build()`에서 `ref.listen(exchangeProvider.select((s) => s.baseCurrency.code), (_, _) { state = state.resetForBase(); refreshConversion(); })`
  - 화면: `exchange_screen.dart`는 `display.visible`/`amountFor`/`isActive` 대신 `ref.watch(exchangeDisplayViewProvider)`를 쓴다. 상태 문구에 쓰는 코인 시세·`isStale`·`isLoading`은 `ref.watch(cryptoProvider)`에서 읽는다.

- [ ] **Step 1: 실패하는 테스트 작성** `exchange_display_view_test.dart`. 가짜 `exchangeRateApiServiceProvider`·`cryptoApiServiceProvider`·`localStorageServiceProvider`를 override하고 `SharedPreferences.setMockInitialValues({})`.
  - `행 목록이 그대로여도 입력 금액이 바뀌면 다른 행 금액이 갱신된다`: `changeAmountFromCurrency(USD, 1)` → `changeAmountFromCurrency(USD, 2)`. rows의 id 목록은 같고, JPY 행 `amount`는 2배.
  - `코인 시세만 바뀌면 해당 코인 행 금액이 갱신된다`: 가짜 시세 BTC 100 → `fetchPrice('BTC')`로 200. BTC 행 `amount`는 2배이고 국가 통화 행은 그대로.
  - `입력 행을 국가 통화에서 코인으로 바꾸면 선택 표시가 옮겨 간다`: `selectInput(BTC 행)` → BTC `isActive == true`, 이전 국가 통화 행 `isActive == false`. 다시 `selectInput(USD 행)` → 반대.
  - `기준 통화를 바꾸면 activeCrypto와 KRW 환율이 비워진다`: `selectInput(BTC)` 뒤 `changeBaseCurrency(USD)` → `activeCrypto == null`, `krwRate == null`(재조회 응답 전).
  - `환산을 다시 시도하면 conversionError가 지워진다`: 첫 KRW 조회 실패 → `conversionError != null`, `refreshConversion()` 시작 직후 → `null`
  - `기준 통화 변경 직후 이전 요청의 KRW 환율은 반영하지 않는다`(Review Focus 1): 첫 KRW 요청을 `Completer`로 붙잡고 기준 통화 변경 → 두 번째 요청 complete(1300) → 첫 요청 complete(9999) → `krwRate == 1300`
  - `화면을 떠난 동안 끝난 갱신도 상태에 남는다`(Review Focus 2): 위젯 테스트. 환율 화면에서 `fetchRates` 요청을 붙잡은 채 다른 탭으로 이동 → complete → 환율 탭으로 복귀 → 새 값과 응답의 `fetchedAt`이 표시됨.
  - `폐기 뒤 응답은 무시된다`: 요청을 붙잡은 채 `container.dispose()` → complete → 예외 없음.
- [ ] **Step 2: 기존 테스트 설정 변환**: `exchange_swr_test.dart`, `crypto_test.dart`, `market_swr_test.dart`, `test/widgets/exchange/*`. `addListener`로 알림 수를 세던 곳은 `container.listen(p, (_, _) => count++)`로 바꾼다. 단언은 그대로 둔다.
- [ ] **Step 3: 실행해 실패 확인**: `flutter test --no-pub test/presentation/exchange test/providers/exchange_swr_test.dart test/crypto test/widgets/exchange` → 컴파일 FAIL.
- [ ] **Step 4: 구현.** 세 Notifier와 view provider를 만들고 사용처를 바꾼다. `main.dart`에서 세 항목을 지운다. 요청 번호(`_fetchRequestId`, ExchangeDisplay의 `_request`)는 Notifier 필드로 그대로 옮긴다.
- [ ] **Step 5: 실행해 통과 확인**: Step 3 명령 PASS. 그 뒤 `flutter test --no-pub` 전체 PASS.
- [ ] **Step 6: 커밋** `환율·암호화폐·표시 목록 상태를 Riverpod Notifier로 전환`
- [ ] **Step 7: 실기기 확인을 사용자에게 요청**(직접 확인하지 않았으면 미검증으로 기록): 저장값 표시 → 갱신, 기준 통화 변경, 오프라인일 때 stale 표시.

---

### Task 6: Auth·Map 전환 (4단계)

**Files:**
- Modify: `lib/providers/auth_provider.dart`, `lib/providers/map_provider.dart`
- Modify(사용처): `lib/main.dart`, `lib/screens/auth/auth_gate.dart`, `login_screen.dart`, `signup_screen.dart`, `lib/screens/main_screen.dart`, `lib/screens/map_screen.dart`, `lib/screens/user/user_page.dart`, `lib/widgets/auth/signup/signup_login_id_field.dart`, `lib/widgets/navigation/app_drawer.dart`
- Modify(테스트): `test/providers/auth_provider_test.dart`, `auth_provider_update_nickname_test.dart`, `test/providers/map_provider_search_test.dart`, `test/widgets/map/place_search_bar_test.dart`, `test/widgets/navigation/app_drawer_test.dart`
- Create: `test/providers/map_session_transition_test.dart`, `test/screens/map_tab_session_test.dart`

**Interfaces:**
- Produces
  - `authRepositoryProvider = Provider<AuthRepository>`(`ref.onDispose(repo.dispose)`)
  - `AuthState`: 기존 getter 전부(`isInitialized`, `isLoading`, `isAuthenticated`, `isCheckingLoginId`, `isLoadingSocialAccounts`, `sessionRestoreFailed`, `googleLinked`, `userId`, `loginId`, `nickname`, `profileImageUrl`, `errorMessage`, `isLoginIdAvailable`, `checkedLoginId`, `loginIdCheckMessage`)에 `final int sessionId`를 더한다. `bool isLoginIdCheckedAndAvailable(String)`도 상태로 옮긴다.
  - `AuthNotifier`: 기존 메서드 이름·시그니처 그대로(`signup`, `checkLoginIdAvailability`, `resetLoginIdAvailability`, `login`, `updateNickname`, `updateProfileImage`, `deleteProfileImage`, `restoreSession`, `retryRestoreSession`, `loadLinkedSocialAccounts`, `linkGoogleAccount`, `unlinkGoogleAccount`, `deleteAccount`, `logout`, `runAuthorizedRequest<T>`, `clearSession`, `clearError`). 상태를 내보낼 때마다 `sessionId: _repo.sessionId`를 함께 넣는다. 지금 `notifyListeners()`를 부르는 모든 자리가 해당한다. 이를 한 곳의 `_emit(AuthState next)` 헬퍼로 모은다. `authProvider`.
  - `typedef AuthorizedRequestRunner`는 그대로 둔다. `final authorizedRequestRunnerProvider = Provider<AuthorizedRequestRunner>((ref) => ref.read(authProvider.notifier).runAuthorizedRequest);`
  - `placeApiServiceProvider = Provider<PlaceApiService>`, `clockProvider = Provider<DateTime Function()>((_) => DateTime.now)`
  - `MapState`: 기존 public getter 전부(`searchStatus`, `searchResults`, `searchResultsOrigin`, `searchError`, `lastSearchQuery`, `isSearching`, `hasSearchResults`, `canRetrySearch`, `hasSessionExpiryNotice`, `detailsStatus`, `detailsErrorMessage`, `selectedPlaceDetailsLoaded`, `selectedPlaceDetailsStale`, `selectedPlaceDetailsFetchedAt`, `searchResultBounds`, `status`, `places`, `selectedPlace`, `errorMessage`, `isLoading`, `hasPlaces`, `markers`). 계산 getter는 상태 클래스의 getter로 둔다.
  - `MapNotifier`: 기존 public 메서드 그대로(`loadNearbyPlaces`, `search`, `retrySearch`, `consumeSessionExpiryNotice`, `selectSearchResult`, `clearSearch`, `loadSelectedPlaceDetails`, `selectPlace`, `clearSelectedPlace`, `clearError`, `DateTime now()`). `maxCachedPlaceDetails`, `placeDetailsCacheTtl`는 static const로 둔다. 상세 캐시, 요청 번호, `_inFlightSearchIds`, `_signedOutSearchIds`, `_noticedExpiredSessionIds`, Timer는 Notifier 필드로 둔다. `mapProvider`.
  - 인증 전이: `build()`에서 `ref.listen(authProvider.select((s) => (s.sessionId, s.isAuthenticated)), _onAuthChanged)`. Timer 정리는 `ref.onDispose`로 한다.
    - `sessionId`가 바뀌면 검색 결과·선택·상세 캐시를 비우고, 진행 중 검색은 `_signedOutSearchIds`에 넣는다.
    - 재로그인(`isAuthenticated == true`)이면 대기 중인 만료 안내를 지운다.
    - 로그인 여부 읽기(`_isSignedIn`, `_raiseSessionExpiryNotice`)는 `ref.read(authProvider).isAuthenticated`로 한다.
  - **만료 예외 처리 순서는 지금 코드(`map_provider.dart:447-460`)를 그대로 옮긴다.** 안내 판단을 먼저 하고, 결과 반영 판단은 그다음에 한다. `catch` 앞에서 세션 비교로 일괄 `return`하지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**
  - `test/providers/auth_provider_test.dart`에 `로그인·로그아웃·만료마다 sessionId가 저장소와 같다`(Review Focus 3): 각 동작 뒤 `c.read(authProvider).sessionId == repo.sessionId`
  - `map_session_transition_test.dart`. 가짜 `authProvider`(테스트가 `signIn()`/`signOut()`으로 `sessionId`·`isAuthenticated`를 직접 바꾸는 `Notifier`)와 `Completer` 기반 가짜 `placeApiServiceProvider`/`authorizedRequestRunnerProvider`를 override한다.
    - `구독이 멈춘 동안 로그아웃→재로그인해도 이전 세션 결과가 남지 않는다`
      - 순서: 지도 Consumer를 `TickerMode(enabled: true)`로 감싸 띄움 → `search('경복궁')` 대기 → `TickerMode`를 false로 → `signOut()` → `signIn()` → 검색 complete → `TickerMode` true로
      - 기대: `searchResults.isEmpty`, `selectedPlace == null`, 상세 캐시 비어 있음(`selectedPlaceDetailsLoaded == false`), `hasSessionExpiryNotice == false`
    - `폐기 뒤 상세 표시 타이머가 상태를 바꾸지 않는다`(Review Focus 4): 상세 표시 타이머가 걸린 상태에서 `container.dispose()` → `tester.pump(타이머 시간)` → 예외 없음
  - `test/screens/map_tab_session_test.dart`: `실제 탭 전환 뒤 지도로 돌아오면 이전 사용자 데이터가 없다`. 실제 `MainScreen`, 위와 같은 순서이며 탭 전환은 `tabProvider.notifier.selectTab(...)`으로 한다. 기대값은 위와 같다.
- [ ] **Step 2: 기존 테스트 설정 변환**: `map_provider_search_test.dart`의 생성자 주입(`authorizedRequest`, `authState`, `isAuthenticated`, `placeApiService`, `now`)을 provider override로 바꾼다. 기존 `authState.signOut()/signIn()`은 가짜 `authProvider`의 같은 이름 메서드로 바꾼다. 단언은 그대로 둔다. 그 밖에 auth·drawer·검색창 테스트도 같은 방식으로 바꾼다.
- [ ] **Step 3: 실행해 실패 확인**: `flutter test --no-pub test/providers test/screens test/widgets/map test/widgets/navigation` → FAIL.
- [ ] **Step 4: 구현.** `main.dart`에서 마지막 두 항목을 지운다. `MultiProvider`가 비면 함께 지운다.
- [ ] **Step 5: 실행해 통과 확인**
  - Step 3 명령 PASS. 특히 기존 두 테스트를 확인한다.
    - `검색 중 만료되면 검색 상태가 먼저 비워져도 안내를 정확히 한 번 남긴다`
    - `새 로그인 뒤 도착한 이전 세션의 만료 예외는 안내하지 않는다`
  - 확인 명령: `flutter test --no-pub --plain-name "세션 만료 안내" test/providers/map_provider_search_test.dart`
  - 그 뒤 `flutter test --no-pub` 전체 PASS.
- [ ] **Step 6: 커밋** `인증·지도 상태를 Riverpod Notifier로 전환`
- [ ] **Step 7: 실기기 확인을 사용자에게 요청**: 로그인·로그아웃, 장소 검색, 로그아웃 시 검색 결과 비우기, 다른 탭에서 로그아웃→재로그인 뒤 지도 복귀.

---

### Task 7: provider 제거와 문서 갱신 (5단계)

**Files:**
- Modify: `pubspec.yaml`(`provider` 제거), `lib/main.dart`
- Modify: `AGENTS.md`(아키텍처 절의 "Provider 구조", `ChangeNotifierProvider`·`MultiProvider` 설명 → Riverpod `Notifier`·`ProviderScope`), `docs/crypto-ui.md`(Provider 클래스 이름이 나오면 새 이름으로)

- [ ] **Step 1: 남은 사용처 확인**: `grep -rn "package:provider\|ChangeNotifier\|MultiProvider\|context.watch\|context.read\|context.select" lib test` → 출력 없음. 남아 있으면 해당 태스크 범위로 처리한다.
- [ ] **Step 2: `provider` 의존성을 제거하고 `flutter pub get`.**
- [ ] **Step 3: 검증**: `flutter analyze --no-pub` 새 문제 0건, `flutter test --no-pub` 전체 PASS, `git diff --check` 통과.
- [ ] **Step 4: 문서 수정**: 바꾼 문장의 경로·이름이 실제 코드와 맞는지 읽어서 확인한다.
- [ ] **Step 5: 커밋** `provider 패키지 제거, 문서를 Riverpod 구조로 갱신`

---

## 태스크 끝날 때마다
- 진행 기록(`D:\personal_project\progress.md`)을 갱신한다. 실기기 확인처럼 실행하지 않은 검증은 "미검증"에 적는다.
- `CLAUDE.md` 규칙에 따라, 기능 구현이 끝나면 `code-inspector`로 점검하고 결과를 사용자에게 보고한다. 수정은 사용자가 고른 항목만 한다.
- 화면 모양은 바꾸지 않는 전환이므로 `design-improver`는 쓰지 않는다.
