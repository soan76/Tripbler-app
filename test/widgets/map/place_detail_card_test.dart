import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/providers/map/map_provider.dart';
import 'package:tripbler/widgets/map/place_detail_card.dart';

PlaceModel _place({
  double? rating,
  bool? openNow,
  String category = 'museum',
  String name = '국립중앙박물관',
}) {
  return PlaceModel(
    id: 'a',
    name: name,
    latitude: 37.5,
    longitude: 126.9,
    address: '서울특별시 용산구 서빙고로 137',
    rating: rating,
    category: category,
    openNow: openNow,
  );
}

void main() {
  var detailPressed = 0;
  var closed = 0;

  setUp(() {
    detailPressed = 0;
    closed = 0;
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    PlaceModel? place,
    PlaceDetailsStatus status = PlaceDetailsStatus.idle,
    bool loaded = false,
    bool stale = false,
    DateTime? fetchedAt,
    DateTime? now,
    String? errorMessage,
    double width = 400,
    double textScale = 1,
    VoidCallback? onRoutePressed,
    String? distanceLabel,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlaceDetailCard(
              place: place ?? _place(),
              detailsStatus: status,
              detailsLoaded: loaded,
              detailsStale: stale,
              detailsFetchedAt: fetchedAt,
              now: () => now ?? DateTime(2026, 11, 11, 15),
              detailsErrorMessage: errorMessage,
              onClose: () => closed++,
              onDetailPressed: () => detailPressed++,
              onRoutePressed: onRoutePressed,
              distanceLabel: distanceLabel,
            ),
          ),
        ),
      ),
    );
  }

  Finder buttonWithLabel(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  bool isEnabled(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(buttonWithLabel(label)).enabled;

  group('조회 전', () {
    testWidgets('평점·영업 정보 버튼만 보이고 값이나 정보 없음을 표시하지 않는다', (tester) async {
      // 검색 결과에 값이 있어도 조회 전에는 표시하지 않는다.
      await pumpCard(tester, place: _place(rating: 4.6, openNow: true));

      expect(find.text(PlaceDetailCard.detailButtonLabel), findsOneWidget);
      expect(isEnabled(tester, PlaceDetailCard.detailButtonLabel), isTrue);
      expect(find.textContaining('평점'), findsOneWidget); // 버튼 문구뿐
      expect(find.text('영업 중'), findsNothing);
      expect(find.text(PlaceDetailCard.noRatingLabel), findsNothing);
      expect(find.text(PlaceDetailCard.noOpenNowLabel), findsNothing);
    });

    testWidgets('버튼을 한 번 누르면 조회를 한 번 요청한다', (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text(PlaceDetailCard.detailButtonLabel));

      expect(detailPressed, 1);
    });

    testWidgets('분류는 한글로, 모르는 분류는 표시하지 않는다', (tester) async {
      await pumpCard(tester);
      expect(find.text('박물관'), findsOneWidget);
      expect(find.text('museum'), findsNothing);

      await pumpCard(tester, place: _place(category: 'unknown_type'));
      expect(find.text('unknown_type'), findsNothing);
    });

    testWidgets('닫기 버튼으로 카드를 닫는다', (tester) async {
      await pumpCard(tester);

      await tester.tap(find.byTooltip('닫기'));

      expect(closed, 1);
    });
  });

  group('조회 중', () {
    testWidgets('진행 표시와 함께 버튼이 꺼져 추가 요청을 보내지 않는다', (tester) async {
      await pumpCard(tester, status: PlaceDetailsStatus.loading);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(PlaceDetailCard.loadingLabel), findsOneWidget);
      expect(isEnabled(tester, PlaceDetailCard.loadingLabel), isFalse);

      await tester.tap(find.text(PlaceDetailCard.loadingLabel));
      expect(detailPressed, 0);
    });

    testWidgets('처음 조회하는 중에는 검색 결과의 값을 보이지 않는다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: true),
        status: PlaceDetailsStatus.loading,
      );

      expect(find.text('평점 4.6'), findsNothing);
      expect(find.text('영업 중'), findsNothing);
    });
  });

  group('실패', () {
    testWidgets('오류 문구와 다시 시도를 보이고, 한 번 누르면 한 번 요청한다', (tester) async {
      await pumpCard(
        tester,
        status: PlaceDetailsStatus.failure,
        errorMessage: '장소 정보를 잠시 불러올 수 없습니다.',
      );

      expect(find.text('장소 정보를 잠시 불러올 수 없습니다.'), findsOneWidget);
      expect(isEnabled(tester, PlaceDetailCard.retryLabel), isTrue);

      await tester.tap(find.text(PlaceDetailCard.retryLabel));
      expect(detailPressed, 1);
    });

    testWidgets('오류 문구가 없으면 기본 문구를 보인다', (tester) async {
      await pumpCard(tester, status: PlaceDetailsStatus.failure);

      expect(find.text(PlaceDetailCard.defaultErrorMessage), findsOneWidget);
    });
  });

  group('조회 완료', () {
    testWidgets('평점과 영업 여부를 보이고 조회 버튼을 숨긴다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.56, openNow: true),
        loaded: true,
      );

      expect(find.text('평점 4.6'), findsOneWidget);
      expect(find.text('영업 중'), findsOneWidget);
      expect(find.text(PlaceDetailCard.detailButtonLabel), findsNothing);
    });

    testWidgets('영업 종료를 표시한다', (tester) async {
      await pumpCard(tester, place: _place(openNow: false), loaded: true);

      expect(find.text('영업 종료'), findsOneWidget);
    });

    testWidgets('값이 없으면 항목마다 정보 없음을 표시한다', (tester) async {
      await pumpCard(tester, place: _place(rating: 4.2), loaded: true);
      expect(find.text('평점 4.2'), findsOneWidget);
      expect(find.text(PlaceDetailCard.noOpenNowLabel), findsOneWidget);

      await pumpCard(tester, place: _place(openNow: true), loaded: true);
      expect(find.text(PlaceDetailCard.noRatingLabel), findsOneWidget);
      expect(find.text('영업 중'), findsOneWidget);

      await pumpCard(tester, place: _place(), loaded: true);
      expect(find.text(PlaceDetailCard.noRatingLabel), findsOneWidget);
      expect(find.text(PlaceDetailCard.noOpenNowLabel), findsOneWidget);
    });
  });

  testWidgets('길찾기 콜백이 없으면 버튼만 꺼지고 준비 중 문구는 없다', (tester) async {
    for (final loaded in [false, true]) {
      await pumpCard(tester, loaded: loaded);

      expect(find.text(PlaceDetailCard.routeLabel), findsOneWidget);
      expect(isEnabled(tester, PlaceDetailCard.routeLabel), isFalse);
      expect(find.text('길찾기는 준비 중입니다'), findsNothing);
    }
  });

  testWidgets('길찾기 버튼은 상세 조회 상태와 상관없이 켜지고 한 번 누르면 콜백이 한 번 불린다', (tester) async {
    for (final status in PlaceDetailsStatus.values) {
      for (final loaded in [false, true]) {
        var routePressed = 0;

        await pumpCard(
          tester,
          status: status,
          loaded: loaded,
          onRoutePressed: () => routePressed++,
        );

        expect(isEnabled(tester, PlaceDetailCard.routeLabel), isTrue);

        await tester.tap(find.text(PlaceDetailCard.routeLabel));
        await tester.pump();

        expect(routePressed, 1, reason: '$status, loaded: $loaded');
        expect(detailPressed, 0);
      }
    }
  });

  testWidgets('좌표가 없는 장소도 길찾기 버튼이 켜진다', (tester) async {
    await pumpCard(
      tester,
      place: const PlaceModel(
        id: 'no-coordinates',
        name: '좌표 없는 장소',
        latitude: null,
        longitude: null,
        address: '주소',
        rating: null,
        category: 'cafe',
        openNow: null,
      ),
      onRoutePressed: () {},
    );

    expect(isEnabled(tester, PlaceDetailCard.routeLabel), isTrue);
  });

  testWidgets('길찾기 버튼은 Google 지도로 넘어간다는 것을 낭독 문구로 알린다', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpCard(tester, onRoutePressed: () {});

    expect(
      find.bySemanticsLabel(PlaceDetailCard.routeSemanticsLabel),
      findsOneWidget,
    );
    // 화면 글자는 짧은 "길찾기" 그대로다.
    expect(find.text(PlaceDetailCard.routeLabel), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('버튼은 터치 영역 48 이상이고, 넓으면 나란히 좁거나 글자가 크면 세로로 놓인다', (tester) async {
    Rect rectOf(String label) => tester.getRect(buttonWithLabel(label));

    await pumpCard(tester, width: 400);
    var detail = rectOf(PlaceDetailCard.detailButtonLabel);
    var route = rectOf(PlaceDetailCard.routeLabel);
    expect(detail.height, greaterThanOrEqualTo(48));
    expect(route.height, greaterThanOrEqualTo(48));
    expect(detail.top, route.top);
    expect(detail.right, lessThan(route.left));

    await pumpCard(tester, width: 320, textScale: 2);
    detail = rectOf(PlaceDetailCard.detailButtonLabel);
    route = rectOf(PlaceDetailCard.routeLabel);
    expect(detail.height, greaterThanOrEqualTo(48));
    expect(detail.bottom, lessThan(route.top));
    expect(detail.width, route.width);
  });

  testWidgets('폭 320·큰 글자·긴 이름에서도 넘치지 않는다', (tester) async {
    for (final status in PlaceDetailsStatus.values) {
      await pumpCard(
        tester,
        place: _place(name: '아주 긴 이름의 장소 ' * 6),
        status: status,
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    }

    await pumpCard(tester, loaded: true, width: 320, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  group('오래된 정보', () {
    final fetchedAt = DateTime(2026, 11, 11, 14, 5);

    testWidgets('이전 값과 받은 시각, 새로 고침 버튼을 보인다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: fetchedAt,
      );

      expect(find.text('평점 4.6'), findsOneWidget);
      expect(find.text('영업 중'), findsOneWidget);
      expect(
        find.text('${PlaceDetailCard.staleLabel} · 14:05 기준'),
        findsOneWidget,
      );
      expect(isEnabled(tester, PlaceDetailCard.refreshLabel), isTrue);
      expect(find.text(PlaceDetailCard.detailButtonLabel), findsNothing);

      await tester.tap(find.text(PlaceDetailCard.refreshLabel));
      expect(detailPressed, 1);
    });

    testWidgets('새로 고침 중에는 이전 값을 유지하고 버튼을 끈다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: fetchedAt,
        status: PlaceDetailsStatus.loading,
      );

      expect(find.text('영업 중'), findsOneWidget);
      expect(
        find.text('${PlaceDetailCard.staleLabel} · 14:05 기준'),
        findsOneWidget,
      );
      expect(isEnabled(tester, PlaceDetailCard.loadingLabel), isFalse);

      await tester.tap(find.text(PlaceDetailCard.loadingLabel));
      expect(detailPressed, 0);
    });

    testWidgets('새로 고침이 실패하면 이전 값, 받은 시각, 오류, 다시 시도를 함께 보인다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: fetchedAt,
        status: PlaceDetailsStatus.failure,
        errorMessage: '장소 정보를 잠시 불러올 수 없습니다.',
      );

      expect(find.text('평점 4.6'), findsOneWidget);
      expect(find.text('영업 중'), findsOneWidget);
      expect(
        find.text('${PlaceDetailCard.staleLabel} · 14:05 기준'),
        findsOneWidget,
      );
      expect(find.text('장소 정보를 잠시 불러올 수 없습니다.'), findsOneWidget);

      await tester.tap(find.text(PlaceDetailCard.retryLabel));
      expect(detailPressed, 1);
    });

    testWidgets('낭독기는 값과 오래된 정보 안내를 한 묶음으로 읽는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: fetchedAt,
      );

      final node = tester.getSemantics(find.text('영업 중'));
      expect(node.label, contains('평점 4.6'));
      expect(node.label, contains('영업 중'));
      expect(node.label, contains('${PlaceDetailCard.staleLabel}, 14:05 기준'));
      handle.dispose();
    });

    testWidgets('유효한 값에는 오래된 정보 안내가 없다', (tester) async {
      await pumpCard(
        tester,
        place: _place(openNow: true),
        loaded: true,
        fetchedAt: fetchedAt,
      );

      expect(find.textContaining(PlaceDetailCard.staleLabel), findsNothing);
      expect(find.text(PlaceDetailCard.refreshLabel), findsNothing);
    });

    testWidgets('날짜가 바뀌었으면 받은 날짜를 함께 보인다', (tester) async {
      await pumpCard(
        tester,
        place: _place(openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: DateTime(2026, 11, 10, 23, 55),
        now: DateTime(2026, 11, 11, 0, 30),
      );

      expect(
        find.text('${PlaceDetailCard.staleLabel} · 11월 10일 23:55 기준'),
        findsOneWidget,
      );
    });

    testWidgets('폭 320·큰 글자에서 실패 상태도 넘치지 않는다', (tester) async {
      await pumpCard(
        tester,
        place: _place(name: '아주 긴 이름의 장소 ' * 6, rating: 4.6, openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: DateTime(2026, 11, 10, 23, 55),
        status: PlaceDetailsStatus.failure,
        width: 320,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('조회 시각 문구', () {
    test('같은 날이면 시각만, 한 자리 시·분은 0을 채운다', () {
      expect(
        PlaceDetailCard.fetchedAtLabel(
          DateTime(2026, 11, 11, 9, 5),
          now: DateTime(2026, 11, 11, 23, 59),
        ),
        '09:05 기준',
      );
    });

    test('자정을 넘기면 날짜를 포함한다', () {
      expect(
        PlaceDetailCard.fetchedAtLabel(
          DateTime(2026, 11, 10, 23, 55),
          now: DateTime(2026, 11, 11, 0, 1),
        ),
        '11월 10일 23:55 기준',
      );
    });

    test('같은 일·다른 달도 날짜를 포함한다', () {
      expect(
        PlaceDetailCard.fetchedAtLabel(
          DateTime(2026, 10, 11, 14, 5),
          now: DateTime(2026, 11, 11, 14, 5),
        ),
        '10월 11일 14:05 기준',
      );
    });
  });

  group('거리', () {
    testWidgets('분류 옆에 거리를 바로 보여주고 평점·영업 정보는 버튼으로 둔다', (tester) async {
      await pumpCard(tester, distanceLabel: '350m');

      expect(find.text('박물관 · 350m'), findsOneWidget);
      expect(
        buttonWithLabel(PlaceDetailCard.detailButtonLabel),
        findsOneWidget,
      );
      expect(find.text(PlaceDetailCard.noRatingLabel), findsNothing);
    });

    testWidgets('분류가 없으면 거리만, 거리가 없으면 분류만 보여준다', (tester) async {
      await pumpCard(
        tester,
        place: _place(category: 'unknown_type'),
        distanceLabel: '1.2km',
      );
      expect(find.text('1.2km'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);

      await pumpCard(tester);
      expect(find.text('박물관'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
    });

    testWidgets('조회한 평점·영업 줄과 오래된 정보 안내에는 거리가 섞이지 않는다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: true),
        loaded: true,
        stale: true,
        fetchedAt: DateTime(2026, 11, 11, 14, 5),
        distanceLabel: '350m',
      );

      final summary = tester.getRect(find.text('박물관 · 350m'));
      final rating = tester.getRect(find.text('평점 4.6'));
      final stale = tester.getRect(
        find.text('${PlaceDetailCard.staleLabel} · 14:05 기준'),
      );
      // 거리는 평점·영업 줄보다 위(분류 줄)에 있고, 오래된 안내는 평점·영업 줄 아래다.
      expect(summary.bottom, lessThanOrEqualTo(rating.top));
      expect(rating.bottom, lessThanOrEqualTo(stale.top));
    });

    testWidgets('낭독기는 분류와 거리를 쉼표로 끊고 거리를 현재 위치 기준으로 읽는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester, distanceLabel: '350m');

      expect(find.bySemanticsLabel('박물관, 현재 위치에서 350m'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('좁은 화면·큰 글자에서도 넘치지 않는다', (tester) async {
      await pumpCard(
        tester,
        place: _place(rating: 4.6, openNow: false),
        loaded: true,
        stale: true,
        fetchedAt: DateTime(2026, 11, 10, 23, 55),
        distanceLabel: '12km',
        width: 320,
        textScale: 2,
      );

      expect(find.text('박물관 · 12km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
