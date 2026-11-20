import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map/map_provider.dart';
import 'package:tripbler/widgets/map/place_search_results_panel.dart';

PlaceModel _place(
  String id, {
  String? name,
  String category = 'museum',
  double? latitude = 37.5,
  double? longitude = 126.9,
  String? address,
}) {
  return PlaceModel(
    id: id,
    name: name ?? '장소 $id',
    latitude: latitude,
    longitude: longitude,
    address: address ?? '서울특별시 종로구 $id',
    rating: null,
    category: category,
    openNow: null,
  );
}

class _Harness {
  final List<PlaceModel> selected = <PlaceModel>[];
  int toggleCount = 0;
  int retryCount = 0;

  Widget build({
    required MapSearchStatus status,
    List<PlaceModel> results = const [],
    MapSearchError? error,
    bool canRetry = false,
    bool expanded = true,
    double width = 400,
    LatLng? distanceOrigin,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            child: PlaceSearchResultsPanel(
              status: status,
              results: results,
              distanceOrigin: distanceOrigin,
              error: error,
              canRetry: canRetry,
              expanded: expanded,
              expandedHeight: 300,
              selectedPlaceId: null,
              onToggleExpanded: () => toggleCount++,
              onSelect: selected.add,
              onRetry: () => retryCount++,
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());

  testWidgets('검색 중이면 진행 표시를 보여준다', (tester) async {
    await tester.pumpWidget(harness.build(status: MapSearchStatus.loading));

    expect(find.text('검색 중'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('결과가 없으면 없음 안내를 보여준다', (tester) async {
    await tester.pumpWidget(harness.build(status: MapSearchStatus.success));

    expect(find.text('검색 결과가 없습니다'), findsWidgets);
  });

  testWidgets('결과 항목에 이름·주소·한글 분류를 보여주고 누르면 선택한다', (tester) async {
    final places = [_place('a'), _place('b', category: 'unknown_type')];
    await tester.pumpWidget(
      harness.build(status: MapSearchStatus.success, results: places),
    );

    expect(find.text('검색 결과 2개'), findsOneWidget);
    expect(find.text('장소 a'), findsOneWidget);
    expect(find.text('서울특별시 종로구 a'), findsOneWidget);
    expect(find.text('박물관'), findsOneWidget);
    // 알 수 없는 유형은 표시하지 않는다.
    expect(find.text('unknown_type'), findsNothing);

    await tester.tap(find.text('장소 b'));
    expect(harness.selected.map((p) => p.id), ['b']);
  });

  testWidgets('검색어 오류(400)는 다시 시도를 숨기고 검색어 수정을 안내한다', (tester) async {
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.failure,
        canRetry: true,
        error: const MapSearchError(
          type: MapSearchErrorType.invalidQuery,
          message: '검색어는 공백을 제외하고 1~100자여야 합니다.',
        ),
      ),
    );

    expect(find.text('검색어는 공백을 제외하고 1~100자여야 합니다.'), findsOneWidget);
    expect(find.text('검색어를 고친 뒤 다시 검색해 주세요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('서버 장애·네트워크 오류는 다시 시도를 보여준다', (tester) async {
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.failure,
        canRetry: true,
        error: const MapSearchError(
          type: MapSearchErrorType.network,
          message: '장소 서버에 연결할 수 없습니다.',
        ),
      ),
    );

    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    expect(harness.retryCount, 1);
  });

  testWidgets('같은 조건 재검색이 실패하면 오류·다시 시도 아래에 이전 결과를 보여주고 고를 수 있다', (
    tester,
  ) async {
    final places = [_place('a'), _place('b')];
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.failure,
        canRetry: true,
        results: places,
        error: const MapSearchError(
          type: MapSearchErrorType.providerUnavailable,
          message: '장소 정보를 불러오지 못했습니다.',
        ),
      ),
    );

    expect(find.text('검색하지 못했습니다 · 이전 결과 2개'), findsOneWidget);
    expect(find.text('장소 정보를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.text('이전 검색 결과'), findsOneWidget);

    // 오류 → 다시 시도 → 소제목 → 결과 순서
    final retryRect = tester.getRect(find.text('다시 시도'));
    final headerRect = tester.getRect(find.text('이전 검색 결과'));
    final firstRect = tester.getRect(find.text('장소 a'));
    expect(retryRect.bottom, lessThanOrEqualTo(headerRect.top));
    expect(headerRect.bottom, lessThanOrEqualTo(firstRect.top));

    await tester.tap(find.text('다시 시도'));
    expect(harness.retryCount, 1);

    await tester.tap(find.text('장소 b'));
    expect(harness.selected.map((p) => p.id), ['b']);
  });

  testWidgets('실패 화면의 이전 결과는 펼친 높이 안에서 오류와 함께 스크롤된다', (tester) async {
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.failure,
        canRetry: true,
        results: [for (var i = 0; i < 20; i++) _place('$i')],
        error: const MapSearchError(
          type: MapSearchErrorType.network,
          message: '장소 서버에 연결할 수 없습니다.',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('장소 19'), findsNothing);

    await tester.scrollUntilVisible(find.text('장소 19'), 200);
    expect(find.text('장소 19'), findsOneWidget);
    // 오류 안내도 같은 목록에 있어 함께 밀려 올라간다.
    expect(find.text('장소 서버에 연결할 수 없습니다.'), findsNothing);
  });

  testWidgets('실패했고 이전 결과가 없으면 오류만 보여준다', (tester) async {
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.failure,
        canRetry: true,
        error: const MapSearchError(
          type: MapSearchErrorType.providerUnavailable,
          message: '장소 정보를 불러오지 못했습니다.',
        ),
      ),
    );

    expect(find.text('검색하지 못했습니다'), findsOneWidget);
    expect(find.text('이전 검색 결과'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('폭 320, 큰 글자에서 실패와 이전 결과가 넘치지 않는다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.failure,
        canRetry: true,
        width: 320,
        results: [
          _place('a', name: '아주 긴 장소 이름 ' * 10),
          _place('b'),
        ],
        error: const MapSearchError(
          type: MapSearchErrorType.network,
          message: '장소 서버에 연결할 수 없습니다.',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('이전 검색 결과'), findsOneWidget);
  });

  testWidgets('접힌 상태는 손잡이만 보여주고 누르면 펼침을 요청한다', (tester) async {
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.success,
        results: [_place('a')],
        expanded: false,
      ),
    );

    expect(find.text('검색 결과 1개'), findsOneWidget);
    expect(find.text('장소 a'), findsNothing);

    await tester.tap(find.text('검색 결과 1개'));
    expect(harness.toggleCount, 1);
  });

  testWidgets('폭 320에서 긴 이름과 주소가 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      harness.build(
        status: MapSearchStatus.success,
        width: 320,
        results: [_place('a', name: '아주 긴 장소 이름 ' * 10)],
      ),
    );

    expect(tester.takeException(), isNull);
  });
  group('거리 표시', () {
    const origin = LatLng(37.5, 126.9);
    final distancePattern = RegExp(r'^\d+(\.\d)?(m|km)$');

    testWidgets('기준 위치가 있으면 항목 오른쪽 아래에 거리를 보여준다', (tester) async {
      final semantics = tester.ensureSemantics();
      final places = [
        _place('near', latitude: 37.5027, longitude: 126.9),
        _place('far', latitude: 37.5, longitude: 127.0),
      ];
      await tester.pumpWidget(
        harness.build(
          status: MapSearchStatus.success,
          results: places,
          distanceOrigin: origin,
        ),
      );

      expect(find.text('300m'), findsOneWidget);
      expect(find.text('8.8km'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('현재 위치에서 300m')), findsOneWidget);
      semantics.dispose();

      // 주소 오른쪽, 이름 아래에 놓인다.
      final address = tester.getRect(find.text('서울특별시 종로구 near'));
      final distance = tester.getRect(find.text('300m'));
      final name = tester.getRect(find.text('장소 near'));
      expect(distance.left, greaterThanOrEqualTo(address.right));
      expect(distance.top, greaterThanOrEqualTo(name.bottom));
    });

    testWidgets('기준 위치가 없거나 장소 좌표가 없으면 거리를 숨긴다', (tester) async {
      await tester.pumpWidget(
        harness.build(status: MapSearchStatus.success, results: [_place('a')]),
      );
      expect(find.textContaining(distancePattern), findsNothing);

      await tester.pumpWidget(
        harness.build(
          status: MapSearchStatus.success,
          results: [_place('b', latitude: null, longitude: null)],
          distanceOrigin: origin,
        ),
      );
      expect(find.textContaining(distancePattern), findsNothing);
    });

    testWidgets('주소가 없어도 거리는 보여준다', (tester) async {
      await tester.pumpWidget(
        harness.build(
          status: MapSearchStatus.success,
          results: [_place('a', address: '', latitude: 37.5027)],
          distanceOrigin: origin,
        ),
      );

      expect(find.text('300m'), findsOneWidget);
    });

    testWidgets('좁은 화면에서 긴 주소와 큰 글자에도 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: harness.build(
            status: MapSearchStatus.success,
            width: 320,
            results: [
              _place(
                'a',
                address: '서울특별시 종로구 사직로 161 경복궁 ' * 4,
                latitude: 37.6,
              ),
            ],
            distanceOrigin: origin,
          ),
        ),
      );

      expect(find.text('11km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
