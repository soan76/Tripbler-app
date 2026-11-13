import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/providers/map_provider.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_place_api.dart';

void main() {
  late FakeAuthNotifier auth;
  late HeldPlaceApi places;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthNotifier();
    places = HeldPlaceApi();
    container = ProviderContainer.test(
      overrides: [
        authProvider.overrideWith(() => auth),
        placeApiServiceProvider.overrideWithValue(places),
        authorizedRequestRunnerProvider.overrideWithValue(passThroughRunner),
      ],
    );
  });

  MapNotifier map() => container.read(mapProvider.notifier);
  MapState mapState() => container.read(mapProvider);

  /// 이전 세션에서 검색 결과를 고르고 상세 결과까지 받아 둔다.
  Future<void> openDetailsInSession() async {
    final search = map().search('남산');
    places.searches.last.complete([testPlace('a')]);
    await search;
    map().selectSearchResult(mapState().searchResults.single);
    final details = map().loadSelectedPlaceDetails();
    places.details.last.complete(testPlace('a'));
    await details;
    expect(mapState().selectedPlaceDetailsLoaded, isTrue);
  }

  testWidgets('구독이 멈춘 동안 로그아웃→재로그인해도 이전 세션 결과가 남지 않는다', (tester) async {
    final ticking = ValueNotifier<bool>(true);
    addTearDown(ticking.dispose);

    // 지도 화면 대역: 지도 상태를 구독하는 Consumer 하나. 이 상태를 구독하는 곳은
    // 이것뿐이라, TickerMode를 끄면 지도 상태의 구독도 멈춘다.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: ticking,
            builder: (context, enabled, _) => TickerMode(
              enabled: enabled,
              child: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(mapProvider);
                  return Text('결과 ${state.searchResults.length}');
                },
              ),
            ),
          ),
        ),
      ),
    );

    await openDetailsInSession();
    await tester.pump();

    // 검색을 시작하고 응답을 기다린다.
    final pending = map().search('경복궁');
    await tester.pump();

    ticking.value = false;
    await tester.pump();

    auth.signOut();
    await tester.pump();
    auth.signIn();
    await tester.pump();

    places.searches.last.complete([testPlace('b')]);
    await pending;
    await tester.pump();

    ticking.value = true;
    await tester.pump();

    final state = mapState();
    expect(state.searchResults, isEmpty);
    expect(state.selectedPlace, isNull);
    expect(state.selectedPlaceDetailsLoaded, isFalse);
    expect(state.hasSessionExpiryNotice, isFalse);
    expect(find.text('결과 0'), findsOneWidget);

    // 상세 캐시도 비었다: 새 세션에서 같은 장소를 열면 다시 조회한다.
    final search = map().search('남산');
    places.searches.last.complete([testPlace('a')]);
    await search;
    map().selectSearchResult(mapState().searchResults.single);
    final details = map().loadSelectedPlaceDetails();
    expect(places.detailCalls, ['a', 'a']);
    places.details.last.complete(testPlace('a'));
    await details;

    // 상세 표시 타이머를 남기지 않게 카드를 닫는다.
    map().clearSelectedPlace();
  });

  testWidgets('로그아웃→재로그인이 한 번의 변화로 합쳐져 도착해도 이전 세션 결과를 비운다', (tester) async {
    await openDetailsInSession();
    final pending = map().search('경복궁');

    // 로그인 여부는 true 그대로이고 세션 번호만 바뀐다.
    auth.signOutAndInAtOnce();

    places.searches.last.complete([testPlace('b')]);
    await pending;

    final state = mapState();
    expect(state.searchResults, isEmpty);
    expect(state.selectedPlace, isNull);
    expect(state.selectedPlaceDetailsLoaded, isFalse);
    expect(state.hasSessionExpiryNotice, isFalse);
    expect(state.searchStatus, MapSearchStatus.idle);
  });

  testWidgets('폐기 뒤 상세 표시 타이머가 상태를 바꾸지 않는다', (tester) async {
    await openDetailsInSession();

    container.dispose();

    // 상세 결과가 만료되는 시각을 지나도 예외가 없다.
    await tester.pump(MapNotifier.placeDetailsCacheTtl);
    expect(tester.takeException(), isNull);
  });
}
