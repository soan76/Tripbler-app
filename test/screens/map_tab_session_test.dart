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
import 'package:tripbler/screens/map_screen.dart';
import 'package:tripbler/services/local_storage_service.dart';

import '../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../helpers/exchange_handles.dart';
import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_place_api.dart';

const _exchangeTab = 0;
const _mapTab = 1;

void main() {
  testWidgets('실제 탭 전환 뒤 지도로 돌아오면 이전 사용자 데이터가 없다', (tester) async {
    // 지도 위젯(TripblerGoogleMap)은 기기 플랫폼(dart:io)으로 지도 ID를 고르므로
    // Android·iOS가 아닌 테스트 실행 환경에서는 그리다가 UnsupportedError를 낸다.
    // 이 오류만 걸러 내고, 그 밖의 화면·탭 전환·상태 구독은 실제 MainScreen 그대로 쓴다.
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (_) async => 0,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        null,
      ),
    );

    final cryptoApi = makeApi();
    final fiatApi = FiatApi();
    addTearDown(() {
      cryptoApi.dispose();
      fiatApi.dispose();
    });

    final auth = FakeAuthNotifier();
    final places = HeldPlaceApi();
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
    MapNotifier map() => container.read(mapProvider.notifier);
    MapState mapState() => container.read(mapProvider);

    container.read(tabProvider.notifier).selectTab(_mapTab);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TripblerApp(home: MainScreen()),
      ),
    );
    // 환율 갱신·방향 센서 보간처럼 계속 움직이는 화면이 있어 정해진 시간만큼만 그린다.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MapScreen), findsOneWidget);

    // 이전 사용자: 장소를 골라 상세 결과까지 받아 둔다.
    final first = map().search('남산');
    places.searches.last.complete([testPlace('a')]);
    await first;
    map().selectSearchResult(mapState().searchResults.single);
    final details = map().loadSelectedPlaceDetails();
    places.details.last.complete(testPlace('a'));
    await details;
    await tester.pump();
    expect(mapState().selectedPlaceDetailsLoaded, isTrue);

    // 지도에서 검색을 시작하고 응답을 기다린다.
    final pending = map().search('경복궁');
    await tester.pump();

    // 다른 탭으로 옮긴 뒤 로그아웃→재로그인한다.
    container.read(tabProvider.notifier).selectTab(_exchangeTab);
    await tester.pump(const Duration(milliseconds: 500));

    auth.signOut();
    await tester.pump();
    auth.signIn();
    await tester.pump();

    // 이전 검색의 응답이 도착한다.
    places.searches.last.complete([testPlace('b')]);
    await pending;
    await tester.pump();

    // 지도 탭으로 돌아온다.
    container.read(tabProvider.notifier).selectTab(_mapTab);
    await tester.pump(const Duration(milliseconds: 500));

    final state = mapState();
    expect(state.searchResults, isEmpty);
    expect(state.selectedPlace, isNull);
    expect(state.selectedPlaceDetailsLoaded, isFalse);
    expect(state.hasSessionExpiryNotice, isFalse);

    // 상세 캐시도 비었다: 새 세션에서 같은 장소를 열면 다시 조회한다.
    final again = map().search('남산');
    places.searches.last.complete([testPlace('a')]);
    await again;
    map().selectSearchResult(mapState().searchResults.single);
    final reload = map().loadSelectedPlaceDetails();
    expect(places.detailCalls, ['a', 'a']);
    places.details.last.complete(testPlace('a'));
    await reload;

    // 화면과 상태를 정리해 남는 타이머가 없게 한다.
    map().clearSelectedPlace();
    await tester.pumpWidget(const SizedBox());
  });
}
