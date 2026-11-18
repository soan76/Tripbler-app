import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/providers/map_provider.dart';
import 'package:tripbler/providers/tab_provider.dart';
import 'package:tripbler/screens/map_screen.dart';
import 'package:tripbler/widgets/map/place_search_bar.dart';
import 'package:tripbler/widgets/map/place_search_results_panel.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_place_api.dart';

const _mapTab = 1;

void main() {
  late FakeAuthNotifier auth;
  late HeldPlaceApi places;
  late ProviderContainer container;

  Future<void> pumpMapScreen(WidgetTester tester) async {
    // 지도 위젯(TripblerGoogleMap)은 기기 플랫폼으로 지도 ID를 고르므로 테스트 실행
    // 환경에서는 UnsupportedError를 낸다. 이 오류만 걸러 내고 나머지 화면은 그대로 쓴다.
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

    auth = FakeAuthNotifier();
    places = HeldPlaceApi();
    addTearDown(places.dispose);
    container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        authProvider.overrideWith(() => auth),
        placeApiServiceProvider.overrideWithValue(places),
        authorizedRequestRunnerProvider.overrideWithValue(passThroughRunner),
      ],
    );
    container.read(tabProvider.notifier).selectTab(_mapTab);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MapScreen())),
      ),
    );
    await tester.pump();

    // 방향 보간 타이머가 남지 않게 화면을 먼저 내린다.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  bool canPop(WidgetTester tester) {
    final popScope = find.descendant(
      of: find.byType(MapScreen),
      matching: find.byWidgetPredicate((widget) => widget is PopScope),
    );
    return (tester.widget(popScope) as PopScope).canPop;
  }

  PlaceSearchResultsPanel panel(WidgetTester tester) {
    return tester.widget<PlaceSearchResultsPanel>(
      find.byType(PlaceSearchResultsPanel),
    );
  }

  testWidgets('검색어를 입력하거나 지우면 뒤로가기 판정이 바로 바뀐다', (tester) async {
    await pumpMapScreen(tester);
    expect(canPop(tester), isTrue);

    await tester.enterText(find.byType(TextField), '경복궁');
    await tester.pump();
    expect(canPop(tester), isFalse, reason: '검색어가 있으면 뒤로가기로 먼저 지운다');

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(canPop(tester), isTrue);
  });

  testWidgets('다시 시도하면 처음 검색처럼 결과 목록을 펼친다', (tester) async {
    await pumpMapScreen(tester);

    await tester.enterText(find.byType(TextField), '경복궁');
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
    await tester.pump();
    expect(panel(tester).expanded, isTrue);

    places.searches.single.completeError(
      const ApiException(message: '네트워크 연결을 확인해 주세요.'),
    );
    await tester.pump();
    expect(panel(tester).status, MapSearchStatus.failure);

    // 사용자가 목록을 접은 상태에서 다시 시도가 불린다.
    await tester.tap(find.text('검색하지 못했습니다'));
    await tester.pump();
    expect(panel(tester).expanded, isFalse);

    panel(tester).onRetry();
    await tester.pump();
    expect(panel(tester).expanded, isTrue);
    expect(places.searchQueries, ['경복궁', '경복궁']);

    places.searches.last.complete([testPlace('a')]);
    await tester.pump();
    expect(panel(tester).status, MapSearchStatus.success);
    expect(panel(tester).expanded, isTrue);
  });

  testWidgets('검색창이 다시 그려지기 전에 로그인이 풀린 채 제출되면 목록 펼침이 남지 않는다', (tester) async {
    await pumpMapScreen(tester);

    // 로그인이 풀렸지만 아직 다시 그리기 전: 검색창은 이전(검색 가능) 상태다.
    auth.isAuthenticated = false;
    final searchBar = tester.widget<PlaceSearchBar>(
      find.byType(PlaceSearchBar),
    );
    expect(searchBar.availability, PlaceSearchAvailability.ready);

    searchBar.onSubmitted('경복궁');
    await tester.pump();

    expect(places.searchQueries, isEmpty);
    expect(find.byType(PlaceSearchResultsPanel), findsNothing);
    expect(canPop(tester), isTrue, reason: '숨은 펼침 상태가 뒤로가기를 가로채지 않는다');
    expect(find.text('로그인하면 장소를 검색할 수 있습니다.'), findsOneWidget);
  });
}
