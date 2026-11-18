import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map_provider.dart';
import 'package:tripbler/widgets/map/current_location_button.dart';
import 'package:tripbler/widgets/map/map_overlay_layout.dart';
import 'package:tripbler/widgets/map/place_detail_card.dart';
import 'package:tripbler/widgets/map/place_search_bar.dart';
import 'package:tripbler/widgets/map/place_search_results_panel.dart';

PlaceModel _place(String id) {
  return PlaceModel(
    id: id,
    name: '장소 $id',
    latitude: 37.5,
    longitude: 126.9,
    address: '서울특별시 종로구 $id',
    rating: null,
    category: 'museum',
    openNow: null,
  );
}

const Key _controlsKey = Key('controls');
const Key _cardKey = Key('card');

class _Harness {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  int mapTapCount = 0;

  Widget build({
    required double screenHeight,
    double textScale = 1,
    bool withCard = true,
    Widget? card,
    MapSearchStatus panelStatus = MapSearchStatus.success,
    Widget? mapControls,
  }) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            // 지도 대역: 빈 영역의 터치가 여기로 와야 한다.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mapTapCount++,
              ),
            ),
            Positioned.fill(
              child: MapOverlayLayout(
                searchBar: PlaceSearchBar(
                  controller: controller,
                  focusNode: focusNode,
                  availability: PlaceSearchAvailability.ready,
                  isSearching: false,
                  onSubmitted: (_) {},
                  onCleared: () {},
                  onUnavailable: () {},
                ),
                mapControlsHeight: 80,
                mapControls:
                    mapControls ??
                    const SizedBox(key: _controlsKey, height: 80),
                resultsPanel: PlaceSearchResultsPanel(
                  status: panelStatus,
                  results: [for (var i = 0; i < 20; i++) _place('$i')],
                  error: panelStatus == MapSearchStatus.failure
                      ? const MapSearchError(
                          type: MapSearchErrorType.network,
                          message: '네트워크 연결을 확인해 주세요.',
                        )
                      : null,
                  canRetry: panelStatus == MapSearchStatus.failure,
                  expanded: true,
                  expandedHeight: screenHeight * 0.45,
                  selectedPlaceId: null,
                  onToggleExpanded: () {},
                  onSelect: (_) {},
                  onRetry: () {},
                ),
                detailCard:
                    card ??
                    (withCard
                        ? const SizedBox(key: _cardKey, height: 160)
                        : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  Future<void> pumpAt(
    WidgetTester tester, {
    required double height,
    double textScale = 1,
    bool withCard = true,
    double keyboardHeight = 0,
    Widget? card,
    MapSearchStatus panelStatus = MapSearchStatus.success,
    Widget? mapControls,
  }) async {
    tester.view.physicalSize = Size(320, height);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.reset);

    // 100자 초과 안내 문구(최대 두 줄)로 검색창이 높아진 상태
    harness.controller.text = List.filled(101, 'a').join();

    await tester.pumpWidget(
      harness.build(
        screenHeight: height,
        textScale: textScale,
        withCard: withCard,
        card: card,
        panelStatus: panelStatus,
        mapControls: mapControls,
      ),
    );
  }

  void expectNothingCoversSearchBar(WidgetTester tester) {
    final searchBarBottom = tester.getRect(find.byType(PlaceSearchBar)).bottom;
    final errorRect = tester.getRect(find.text(PlaceSearchBar.tooLongMessage));
    final panelTop = tester.getRect(find.byType(PlaceSearchResultsPanel)).top;
    final controlsTop = tester.getRect(find.byKey(_controlsKey)).top;

    expect(errorRect.bottom, lessThanOrEqualTo(searchBarBottom));
    expect(controlsTop, greaterThanOrEqualTo(searchBarBottom));
    expect(panelTop, greaterThanOrEqualTo(searchBarBottom));
  }

  testWidgets('작은 화면, 큰 글자, 안내 문구에서도 목록과 카드가 검색창을 가리지 않는다', (tester) async {
    await pumpAt(tester, height: 640, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text(PlaceSearchBar.tooLongMessage), findsOneWidget);
    expectNothingCoversSearchBar(tester);

    // 카드는 화면 안에 다 보이고, 남은 높이가 모자란 만큼 목록이 줄어든다.
    final cardRect = tester.getRect(find.byKey(_cardKey));
    expect(cardRect.bottom, lessThanOrEqualTo(640));
    final panelRect = tester.getRect(find.byType(PlaceSearchResultsPanel));
    expect(panelRect.bottom, lessThanOrEqualTo(cardRect.top));
  });

  testWidgets('키보드가 열리면 카드와 지도 위 버튼을 숨기고 목록은 검색창 아래 남은 높이에 맞춘다', (
    tester,
  ) async {
    const keyboardHeight = 300.0;
    await pumpAt(
      tester,
      height: 640,
      textScale: 2,
      keyboardHeight: keyboardHeight,
    );

    expect(tester.takeException(), isNull);
    expect(find.text(PlaceSearchBar.tooLongMessage), findsOneWidget);
    expect(find.byKey(_cardKey), findsNothing);
    expect(find.byKey(_controlsKey), findsNothing);

    final searchBarBottom = tester.getRect(find.byType(PlaceSearchBar)).bottom;
    final errorRect = tester.getRect(find.text(PlaceSearchBar.tooLongMessage));
    final panelRect = tester.getRect(find.byType(PlaceSearchResultsPanel));

    expect(errorRect.bottom, lessThanOrEqualTo(searchBarBottom));
    expect(panelRect.top, greaterThanOrEqualTo(searchBarBottom));
    expect(panelRect.bottom, lessThanOrEqualTo(640 - keyboardHeight));

    // 키보드를 닫으면 카드와 버튼이 다시 보인다.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(_cardKey), findsOneWidget);
    expectNothingCoversSearchBar(tester);
  });

  testWidgets('키보드로 남은 높이가 손잡이보다 작으면 목록도 숨겨 넘치지 않는다', (tester) async {
    await pumpAt(tester, height: 640, textScale: 2, keyboardHeight: 420);

    expect(tester.takeException(), isNull);
    expect(find.text(PlaceSearchBar.tooLongMessage), findsOneWidget);
    expect(find.byType(PlaceSearchResultsPanel), findsNothing);
    expect(find.byKey(_cardKey), findsNothing);
  });

  testWidgets('공간이 충분하면 펼친 목록은 지정한 높이를 그대로 쓴다', (tester) async {
    await pumpAt(tester, height: 900, withCard: false);

    expect(tester.takeException(), isNull);
    expectNothingCoversSearchBar(tester);

    final panelHeight = tester
        .getSize(find.byType(PlaceSearchResultsPanel))
        .height;
    expect(
      panelHeight,
      greaterThanOrEqualTo(900 * 0.45 + PlaceSearchResultsPanel.handleHeight),
    );
  });

  testWidgets('검색창과 하단 영역 사이 빈 곳을 누르면 지도로 간다', (tester) async {
    await pumpAt(tester, height: 900, withCard: false);

    final searchBarBottom = tester.getRect(find.byType(PlaceSearchBar)).bottom;
    final controlsTop = tester.getRect(find.byKey(_controlsKey)).top;
    expect(controlsTop - searchBarBottom, greaterThan(20));

    await tester.tapAt(Offset(160, (searchBarBottom + controlsTop) / 2));
    expect(harness.mapTapCount, 1);
  });

  testWidgets('실제 현재 위치 버튼은 목록·카드와 함께 있어도 터치를 받는다', (tester) async {
    var pressedCount = 0;

    // MapScreen과 같은 구성: 높이 80 영역 안 Stack의 오른쪽 아래에 버튼을 둔다.
    await pumpAt(
      tester,
      height: 900,
      mapControls: SizedBox(
        key: _controlsKey,
        height: 80,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CurrentLocationButton(
              isLoading: false,
              bottom: 24,
              onPressed: () => pressedCount++,
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final buttonRect = tester.getRect(find.byType(FloatingActionButton));
    final controlsRect = tester.getRect(find.byKey(_controlsKey));
    final panelTop = tester.getRect(find.byType(PlaceSearchResultsPanel)).top;

    // 버튼이 지도 위 버튼 영역 안에 있고 목록과 겹치지 않는다.
    expect(controlsRect.contains(buttonRect.topLeft), isTrue);
    expect(
      controlsRect.contains(buttonRect.bottomRight - const Offset(1, 1)),
      isTrue,
    );
    expect(buttonRect.bottom, lessThanOrEqualTo(panelTop));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(pressedCount, 1);
    expect(harness.mapTapCount, 0, reason: '버튼 터치가 지도로 새지 않는다');
  });

  group('실제 상세 카드와 함께', () {
    var retryCount = 0;

    setUp(() => retryCount = 0);

    PlaceDetailCard failureCard() => PlaceDetailCard(
      place: _place('card'),
      detailsStatus: PlaceDetailsStatus.failure,
      detailsLoaded: false,
      detailsErrorMessage: '장소 상세 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
      onClose: () {},
      onDetailPressed: () => retryCount++,
    );

    Finder cardRetry() => find.descendant(
      of: find.byType(PlaceDetailCard),
      matching: find.text(PlaceDetailCard.retryLabel),
    );

    for (final height in [640.0, 480.0]) {
      testWidgets(
        '폭 320·높이 $height·큰 글자·목록 펼침·실패에서 넘치지 않고 카드의 다시 시도를 누를 수 있다',
        (tester) async {
          await pumpAt(
            tester,
            height: height,
            textScale: 2,
            card: failureCard(),
            panelStatus: MapSearchStatus.failure,
          );

          expect(tester.takeException(), isNull);

          final searchBarBottom = tester
              .getRect(find.byType(PlaceSearchBar))
              .bottom;
          final cardRect = tester.getRect(find.byType(PlaceDetailCard));
          final panelRect = tester.getRect(
            find.byType(PlaceSearchResultsPanel),
          );

          expect(panelRect.top, greaterThanOrEqualTo(searchBarBottom));
          expect(panelRect.bottom, lessThanOrEqualTo(cardRect.top));
          expect(cardRect.bottom, lessThanOrEqualTo(height));

          // 목록이 먼저 줄어든다: 펼친 높이를 다 쓰지 못한다.
          expect(
            panelRect.height,
            lessThan(height * 0.45 + PlaceSearchResultsPanel.handleHeight),
          );

          // 카드 안을 스크롤해 다시 시도 버튼을 화면에 보이게 한 뒤 실제로 누른다.
          await tester.ensureVisible(cardRetry());
          await tester.pumpAndSettle();

          final retryRect = tester.getRect(cardRetry());
          final visibleCard = tester.getRect(find.byType(PlaceDetailCard));
          expect(retryRect.top, greaterThanOrEqualTo(visibleCard.top));
          expect(retryRect.bottom, lessThanOrEqualTo(visibleCard.bottom));

          await tester.tap(cardRetry());
          expect(retryCount, 1);
        },
      );
    }

    testWidgets('카드 높이는 남은 높이의 상한을 넘지 않는다', (tester) async {
      await pumpAt(tester, height: 640, textScale: 2, card: failureCard());

      expect(tester.takeException(), isNull);

      final searchBarBottom = tester
          .getRect(find.byType(PlaceSearchBar))
          .bottom;
      final available = 640 - searchBarBottom;
      final cardHeight = tester.getSize(find.byType(PlaceDetailCard)).height;

      expect(
        cardHeight,
        lessThanOrEqualTo(
          available * MapOverlayLayout.detailCardMaxHeightFactor + 0.01,
        ),
      );
    });

    testWidgets('카드 자리가 모자라면 지도 위 버튼을 숨긴다', (tester) async {
      await pumpAt(tester, height: 420, textScale: 2, card: failureCard());

      expect(tester.takeException(), isNull);
      expect(find.byKey(_controlsKey), findsNothing);
      expect(find.byType(PlaceDetailCard), findsOneWidget);
    });
  });
}
