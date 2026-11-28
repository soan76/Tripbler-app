import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/main.dart' show TripblerApp;
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/map/map_provider.dart';
import 'package:tripbler/providers/tab_provider.dart';
import 'package:tripbler/screens/coming_soon_screen.dart';
import 'package:tripbler/screens/duty_free_screen.dart';
import 'package:tripbler/screens/main_screen.dart';
import 'package:tripbler/screens/schedule_screen.dart';
import 'package:tripbler/services/local_storage_service.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';
import 'package:tripbler/widgets/navigation/app_top_bar.dart';

import '../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../helpers/bottom_menu_background.dart';
import '../helpers/exchange_handles.dart';
import '../helpers/fake_camera_platform.dart';
import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_place_api.dart';

// 확장 메뉴의 면세·일정 버튼이 메인 화면에서 각 탭(면세 화면, 일정 화면)으로 이동한다(bottom-nav.md 10-5·10-8절).

const _exchangeTab = 0, _scheduleTab = 3, _dutyFreeTab = 4;
final _current = find.byKey(const ValueKey('bottom-menu-current'));
Finder _tab(int index) => find.byKey(ValueKey('bottom-menu-tab-$index'));
double _width(WidgetTester tester) =>
    tester.getSize(bottomMenuBackground).width;

/// 메인 화면을 [tab] 탭으로 띄운다(main_screen_capture_test.dart와 같은 하네스).
Future<ProviderContainer> _pumpMain(
  WidgetTester tester, {
  required int tab,
}) async {
  // 지도 위젯은 테스트 환경에서 지도 ID를 고르다 UnsupportedError를 낸다(map_tab_session_test 참고).
  final reportError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = reportError);
  FlutterError.onError = (details) {
    final fromMapId =
        details.exception is UnsupportedError &&
        details.stack.toString().contains('MapIdConfig');
    if (!fromMapId) reportError?.call(details);
  };

  SharedPreferences.setMockInitialValues({});
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger = tester.binding.defaultBinaryMessenger;
  // 카메라 권한은 거부(0)로 둔다. 번역 탭으로 가지 않으므로 카메라를 열지 않는다.
  messenger.setMockMethodCallHandler(permissions, (call) async => 0);
  addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
  final camera = CameraPlatform.instance;
  CameraPlatform.instance = FakeCameraPlatform();
  addTearDown(() => CameraPlatform.instance = camera);

  final cryptoApi = makeApi();
  final fiatApi = FiatApi();
  addTearDown(() {
    cryptoApi.dispose();
    fiatApi.dispose();
  });
  final container = ProviderContainer.test(
    retry: (_, _) => null,
    overrides: [
      ...exchangeOverrides(
        fiatApi: fiatApi,
        cryptoApi: cryptoApi,
        storage: LocalStorageService(),
      ),
      authProvider.overrideWith(FakeAuthNotifier.new),
      placeApiServiceProvider.overrideWithValue(HeldPlaceApi()),
      authorizedRequestRunnerProvider.overrideWithValue(passThroughRunner),
    ],
  );
  container.read(tabProvider.notifier).selectTab(tab);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TripblerApp(home: MainScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  return container;
}

/// 점 → 현재 화면 버튼 → 한 번 끌어 펼친다.
Future<void> _open(WidgetTester tester) async {
  if (_width(tester) < 74) {
    await tester.tap(_current);
    await _settle(tester);
  }
  await tester.drag(_current, const Offset(0, -150));
  await _settle(tester);
}

/// 정해진 시간만 그린다(환율 화면 로딩 표시 등으로 pumpAndSettle이 끝나지 않을 수 있다).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final (index, title) in [(4, '면세'), (3, '일정')]) {
    testWidgets('$title 버튼을 고르면 탭 $index의 화면으로 가고 메뉴는 점으로 접힌다', (tester) async {
      final container = await _pumpMain(tester, tab: _exchangeTab);
      expect(find.byType(ComingSoonScreen), findsNothing);

      await tester.tap(_current);
      await _settle(tester);
      await tester.drag(_current, const Offset(0, -150));
      await _settle(tester);
      expectBottomMenuBackgroundCoversArea(tester);

      await tester.tap(find.byKey(ValueKey('bottom-menu-tab-$index')));
      await _settle(tester);

      expect(container.read(tabProvider).selectedIndex, index);
      if (index == _scheduleTab) {
        // 일정 탭은 실제 일정 화면이다(schedule.md). 저장된 일정이 없으면 빈 상태.
        expect(find.byType(ComingSoonScreen), findsNothing);
        expect(find.byType(ScheduleScreen), findsOneWidget);
        expect(find.text(ScheduleScreen.emptyMessage), findsOneWidget);
      } else {
        // 면세 탭은 실제 면세 화면이다(duty-free.md). 산 물건이 없으면 한도가 그대로 남는다.
        expect(find.byType(ComingSoonScreen), findsNothing);
        expect(find.byType(DutyFreeScreen), findsOneWidget);
        expect(find.text('남은 한도 \$800'), findsOneWidget);
      }
      expect(tester.widget<AppTopBar>(find.byType(AppTopBar)).title, title);
      expect(tester.getSize(bottomMenuBackground).width, 10);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (from, title) in [(_dutyFreeTab, '면세'), (_scheduleTab, '일정')]) {
    testWidgets('$title 화면에서 환율·AI로 나갈 수 있다', (tester) async {
      final container = await _pumpMain(tester, tab: from);
      for (final (to, home, barTitle) in [
        (_exchangeTab, false, '환율'),
        (-1, true, 'AI 채팅'),
      ]) {
        container.read(tabProvider.notifier).selectTab(from);
        await _settle(tester);
        await _open(tester);
        expectBottomMenuBackgroundCoversArea(tester);
        await tester.tap(_tab(to));
        await _settle(tester);
        final state = container.read(tabProvider);
        expect(state.isHomeSelected, home, reason: barTitle);
        if (!home) expect(state.selectedIndex, to);
        expect(
          tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
          barTitle,
        );
        expect(_width(tester), 10, reason: barTitle);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('키보드가 본문을 줄여 메뉴 높이가 212보다 작으면 펼치지 않고, 펼친 채 키보드가 뜨면 접는다', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    // 기본 테스트 화면은 800×600(배율 3). 키보드 400이 올라오면 본문은 200이 된다.
    const keyboard = FakeViewPadding(bottom: 400 * 3);
    final container = await _pumpMain(tester, tab: _scheduleTab);
    // 펼친 동안(p > 0)에만 부채꼴 버튼이 있다.
    bool expanded() => _tab(_scheduleTab).evaluate().isNotEmpty;

    tester.view.viewInsets = keyboard;
    await _settle(tester);
    expect(tester.getSize(find.byType(BottomTabBar)).height, 200);
    await tester.tap(_current);
    await _settle(tester);
    expect(_width(tester), 74);
    await tester.drag(_current, const Offset(0, -150));
    await _settle(tester);
    expect(expanded(), isFalse, reason: '키보드가 떠 있으면 펼치지 않는다');
    expect(_width(tester), 74);

    tester.view.viewInsets = FakeViewPadding.zero;
    await _settle(tester);
    await _open(tester);
    expectBottomMenuBackgroundCoversArea(tester);

    // 펼친 채 키보드가 뜨면 점으로 접는다.
    tester.view.viewInsets = keyboard;
    await _settle(tester);
    expect(expanded(), isFalse);
    expect(_width(tester), 10);

    // 키보드가 내려가면 다시 펼칠 수 있다.
    tester.view.viewInsets = FakeViewPadding.zero;
    await _settle(tester);
    await _open(tester);
    expectBottomMenuBackgroundCoversArea(tester);
    expect(container.read(tabProvider).selectedIndex, _scheduleTab);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('펼친 배경은 SafeArea 안쪽 본문 전체를 덮고, 상태 표시줄·제스처 바 영역은 덮지 않는다', (
    tester,
  ) async {
    // 의도된 동작이다(bottom-nav.md 10-3절): 메뉴는 SafeArea 안에 있어 그 바깥은 받지 않는다.
    addTearDown(tester.view.reset);
    tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
    await _pumpMain(tester, tab: _scheduleTab);
    await _open(tester);
    expect(
      tester.getRect(find.byType(BottomTabBar)),
      const Rect.fromLTRB(0, 24, 800, 600 - 16),
    );
    expectBottomMenuBackgroundCoversArea(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
