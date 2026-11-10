import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map_provider.dart';
import 'package:tripbler/widgets/map/map_overlay_layout.dart';
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
                mapControls: const SizedBox(key: _controlsKey, height: 80),
                resultsPanel: PlaceSearchResultsPanel(
                  status: MapSearchStatus.success,
                  results: [for (var i = 0; i < 20; i++) _place('$i')],
                  error: null,
                  canRetry: false,
                  expanded: true,
                  expandedHeight: screenHeight * 0.45,
                  selectedPlaceId: null,
                  onToggleExpanded: () {},
                  onSelect: (_) {},
                  onRetry: () {},
                ),
                detailCard: withCard
                    ? const SizedBox(key: _cardKey, height: 160)
                    : null,
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
}
