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
import 'package:tripbler/screens/main_screen.dart';
import 'package:tripbler/services/local_storage_service.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';
import 'package:tripbler/widgets/navigation/navigation_capture_controller.dart';

import '../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../helpers/exchange_handles.dart';
import '../helpers/fake_camera_platform.dart';
import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_place_api.dart';

const _exchangeTab = 0;
const _translationTab = 2;
const _granted = 1; // PermissionStatus.granted 번호

void _capture() {}

final _currentButton = find.byKey(const ValueKey('bottom-menu-current-button'));

/// 메인 화면을 [tab] 탭으로 띄운다. 카메라 권한 확인은 [permission](PermissionStatus 번호)을 돌려준다.
Future<ProviderContainer> _pumpMain(
  WidgetTester tester, {
  required int tab,
  int permission = 0,
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
  messenger.setMockMethodCallHandler(permissions, (call) async {
    return call.method == 'checkPermissionStatus' ? permission : 0;
  });
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

BottomTabBar _bar(WidgetTester tester) =>
    tester.widget<BottomTabBar>(find.byType(BottomTabBar));

/// 메뉴를 아이콘 상태로 키우고 안쪽 버튼의 아이콘을 돌려준다.
Future<IconData?> _menuIcon(WidgetTester tester) async {
  if (_currentButton.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('bottom-menu-current')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  return tester
      .widget<Icon>(
        find.descendant(of: _currentButton, matching: find.byType(Icon)),
      )
      .icon;
}

void main() {
  testWidgets('메뉴 촬영과 촬영 중 표시는 번역 탭에서만 연결한다', (tester) async {
    final container = await _pumpMain(tester, tab: _exchangeTab);

    // 번역 화면의 촬영 가능 여부와 상관없이 메인 화면의 탭 조건만 보려고, 화면과 같은 컨트롤러에
    // 촬영 동작과 촬영 중 상태를 직접 등록한다.
    final controller = tester
        .widget<NavigationCaptureBinding>(
          find.byType(NavigationCaptureBinding, skipOffstage: false),
        )
        .controller!;
    controller.register(Object(), _capture, busy: true);
    await tester.pump();

    BottomTabBar bar() => _bar(tester);
    expect(bar().onCurrentScreenTap, isNull);
    expect(bar().isCapturing, isFalse);
    // 바깥 누르기로 접지 않는 것도 번역 탭에서만 켠다.
    expect(bar().alwaysShowIcon, isFalse);

    container.read(tabProvider.notifier).selectTab(_translationTab);
    await tester.pump(const Duration(milliseconds: 500));
    controller.register(Object(), _capture, busy: true);
    await tester.pump();
    expect(bar().onCurrentScreenTap, same(_capture));
    expect(bar().isCapturing, isTrue);
    expect(bar().alwaysShowIcon, isTrue);

    container.read(tabProvider.notifier).selectHome();
    await tester.pump(const Duration(milliseconds: 500));
    controller.register(Object(), _capture, busy: true);
    await tester.pump();
    expect(bar().onCurrentScreenTap, isNull);
    expect(bar().isCapturing, isFalse);
    expect(bar().alwaysShowIcon, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('번역 촬영 화면에서만 카메라 아이콘을 보이고, 번역 탭을 고른 프레임부터 바로 보인다', (
    tester,
  ) async {
    final container = await _pumpMain(
      tester,
      tab: _exchangeTab,
      permission: _granted,
    );
    expect(await _menuIcon(tester), Icons.attach_money);

    // 버그 수정: 번역 화면의 등록이 다음 프레임이라, 탭을 고른 프레임에는 번역 탭 아이콘이 보였다.
    container.read(tabProvider.notifier).selectTab(_translationTab);
    await tester.pump();
    expect(_bar(tester).isCaptureScreen, isTrue);
    expect(await _menuIcon(tester), Icons.photo_camera);

    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(_bar(tester).onCurrentScreenTap, isNotNull);
    expect(await _menuIcon(tester), Icons.photo_camera);
    // 메뉴 꼬리표("눌러서 촬영")는 2026-11-27 사용자 요청으로 없앴다.
    expect(find.text('눌러서 촬영'), findsNothing);

    container.read(tabProvider.notifier).selectTab(_exchangeTab);
    await tester.pump();
    expect(await _menuIcon(tester), Icons.attach_money);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카메라 권한이 없으면 번역 탭에서도 번역 탭 아이콘을 보인다', (tester) async {
    final container = await _pumpMain(tester, tab: _exchangeTab);
    container.read(tabProvider.notifier).selectTab(_translationTab);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(_bar(tester).isCaptureScreen, isFalse);
    expect(await _menuIcon(tester), Icons.translate);
    expect(find.text('눌러서 촬영'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
