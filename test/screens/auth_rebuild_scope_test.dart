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
import 'package:tripbler/widgets/auth/session_restore_banner.dart';
import 'package:tripbler/widgets/map/place_search_bar.dart';

import '../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../helpers/exchange_handles.dart';
import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_place_api.dart';

const _mapTab = 1;

/// 화면과 무관한 인증 필드(닉네임)·세션 복구 상태를 바꿀 수 있는 가짜 인증 상태.
class _EditableAuthNotifier extends FakeAuthNotifier {
  void rename(String nickname) {
    state = state.copyWith(nickname: nickname);
  }

  void setLoading(bool value) {
    state = state.copyWith(isLoading: value);
  }

  void failRestore() {
    state = state.copyWith(sessionRestoreFailed: true);
  }
}

void main() {
  late _EditableAuthNotifier auth;

  Future<void> pumpMainScreen(WidgetTester tester) async {
    // 지도 위젯은 테스트 실행 환경에서 지도 ID를 고르지 못해 UnsupportedError를 낸다.
    // 이 오류만 걸러 내고 나머지 화면은 실제 MainScreen 그대로 쓴다.
    final reportError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = reportError);
    FlutterError.onError = (details) {
      final fromMapId =
          details.exception is UnsupportedError &&
          details.stack.toString().contains('MapIdConfig');
      if (!fromMapId) {
        reportError?.call(details);
      }
    };

    SharedPreferences.setMockInitialValues({});

    // 번역 탭이 처음 그려질 때 확인하는 카메라 권한: 거부(0)로 답한다.
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      permissions,
      (_) async => 0,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        permissions,
        null,
      ),
    );

    final cryptoApi = makeApi();
    final fiatApi = FiatApi();
    addTearDown(() {
      cryptoApi.dispose();
      fiatApi.dispose();
    });

    auth = _EditableAuthNotifier();
    final places = HeldPlaceApi();
    addTearDown(places.dispose);
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        ...exchangeOverrides(
          fiatApi: fiatApi,
          cryptoApi: cryptoApi,
          storage: LocalStorageService(),
        ),
        authProvider.overrideWith(() => auth),
        placeApiServiceProvider.overrideWithValue(places),
        authorizedRequestRunnerProvider.overrideWithValue(passThroughRunner),
      ],
    );
    container.read(tabProvider.notifier).selectTab(_mapTab);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TripblerApp(home: MainScreen()),
      ),
    );
    // 환율 갱신·방향 센서 보간처럼 계속 움직이는 화면이 있어 정해진 시간만큼만 그린다.
    await tester.pump(const Duration(milliseconds: 500));

    // 화면을 먼저 내려 남는 타이머가 없게 한다.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  // MainScreen이 build에서 직접 만드는 위젯. 다시 그려지지 않았으면 같은 인스턴스가 남는다.
  IndexedStack tabStack(WidgetTester tester) => tester.widget<IndexedStack>(
    find
        .descendant(
          of: find.byType(MainScreen),
          matching: find.byType(IndexedStack),
        )
        .first,
  );

  // MapScreen이 build에서 직접 만드는 검색창.
  PlaceSearchBar searchBar(WidgetTester tester) =>
      tester.widget<PlaceSearchBar>(find.byType(PlaceSearchBar));

  testWidgets('닉네임만 바뀌면 MainScreen과 MapScreen을 다시 그리지 않는다', (tester) async {
    await pumpMainScreen(tester);
    final stackBefore = tabStack(tester);
    final searchBarBefore = searchBar(tester);

    auth.rename('새 닉네임');
    await tester.pump();

    expect(identical(tabStack(tester), stackBefore), isTrue);
    expect(identical(searchBar(tester), searchBarBefore), isTrue);
  });

  testWidgets('세션 복구 실패가 아닐 때 로딩만 바뀌면 MainScreen을 다시 그리지 않는다', (tester) async {
    await pumpMainScreen(tester);
    final stackBefore = tabStack(tester);

    auth.setLoading(true);
    await tester.pump();

    expect(identical(tabStack(tester), stackBefore), isTrue);
    expect(find.byType(SessionRestoreBanner), findsNothing);
  });

  testWidgets('세션 복구 실패와 재시도 중 표시는 그대로 반영된다', (tester) async {
    await pumpMainScreen(tester);

    auth.failRestore();
    await tester.pump();
    expect(find.byType(SessionRestoreBanner), findsOneWidget);
    expect(
      tester
          .widget<SessionRestoreBanner>(find.byType(SessionRestoreBanner))
          .isRetrying,
      isFalse,
    );

    auth.setLoading(true);
    await tester.pump();
    expect(
      tester
          .widget<SessionRestoreBanner>(find.byType(SessionRestoreBanner))
          .isRetrying,
      isTrue,
    );
  });

  testWidgets('로그인이 풀리면 지도 검색창의 검색 가능 상태는 바로 바뀐다', (tester) async {
    await pumpMainScreen(tester);
    expect(searchBar(tester).availability, PlaceSearchAvailability.ready);

    auth.signOut();
    await tester.pump();

    expect(
      searchBar(tester).availability,
      isNot(PlaceSearchAvailability.ready),
    );
  });
}
