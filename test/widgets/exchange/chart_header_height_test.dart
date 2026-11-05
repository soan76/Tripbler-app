import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/widgets/charts/chart_amount_converter.dart';
import 'package:tripbler/widgets/charts/market_chart_card.dart';
import 'package:tripbler/widgets/charts/market_chart_header.dart';

import '../../helpers/memory_chart_snapshots.dart';

const _staleLoading = '저장된 데이터 · 갱신 중';
const _staleFailed = '마지막 성공 데이터 · 갱신 지연';

class _Source implements ChartDataSource {
  final List<Completer<ChartData>> requests = [];

  @override
  Future<ChartData> load(ChartPeriod period) {
    final request = Completer<ChartData>();
    requests.add(request);
    return request.future;
  }

  @override
  void dispose() {}
}

ChartData _data() => ChartData(
  history: [
    ChartSample(
      date: DateTime.now().subtract(const Duration(days: 1)),
      rate: 100,
      baseCurrencyCode: 'USD',
      targetCurrencyCode: 'KRW',
    ),
    ChartSample(
      date: DateTime.now(),
      rate: 101,
      baseCurrencyCode: 'USD',
      targetCurrencyCode: 'KRW',
    ),
  ],
  currentRate: 101,
  fetchedAt: DateTime.now(),
);

Widget _card(_Source source, {String? unavailableText}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 430,
      child: MarketChartCard(
        baseCurrency: DisplayCurrency.fromFiat(supportedCurrencies.first),
        targetCurrency: DisplayCurrency.fromFiat(supportedCurrencies.last),
        title: '차트',
        errorText: '실패',
        requestKey: 'fiat:A/B',
        createDataSource: () => source,
        period: ChartPeriod.oneMonth,
        shouldLoad: true,
        unavailableText: unavailableText,
        snapshotStore: MemorySnapshots(),
      ),
    ),
  ),
);

Widget _header({
  required double scale,
  required double width,
  bool boldText = false,
  bool isLoading = false,
  bool showsOldData = false,
  DateTime? fetchedAt,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      boldText: boldText,
    ),
    child: Scaffold(
      // 카드처럼 세로 제약 없이 재야 헤더가 내용 높이로 줄어든다.
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: MarketChartHeader(
              title: '차트',
              pair: const Text('USD KRW'),
              isLoading: isLoading,
              showsOldData: showsOldData,
              fetchedAt: fetchedAt,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    ),
  ),
);

double _headerHeight(WidgetTester tester) =>
    tester.getSize(find.byType(MarketChartHeader)).height;

double _rateTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(ChartAmountConverter)).dy;

/// 통화쌍 아래에서 헤더 끝까지, 상태 줄 두 개가 차지하는 높이.
double _statusAreaHeight(WidgetTester tester) =>
    tester.getRect(find.byType(MarketChartHeader)).bottom -
    tester.getRect(find.text('USD KRW')).bottom;

/// 문구를 잘리지 않게 그리는 데 필요한 높이. 부모가 높이를 제한해도 줄어들지 않는다.
double _neededHeight(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return paragraph.getMinIntrinsicHeight(paragraph.constraints.maxWidth);
}

TextStyle? _styleOf(WidgetTester tester, Finder richText) =>
    tester.widget<RichText>(richText).text.style;

void main() {
  testWidgets('헤더와 현재 환율은 첫 로딩부터 새로고침 완료까지 움직이지 않는다', (tester) async {
    final source = _Source();
    await tester.pumpWidget(_card(source));
    await tester.pump();

    expect(find.textContaining('업데이트:'), findsNothing);
    final height = _headerHeight(tester);
    final rateTop = _rateTop(tester);

    void expectSteady(String state) {
      expect(_headerHeight(tester), height, reason: '$state 헤더 높이');
      expect(_rateTop(tester), rateTop, reason: '$state 현재 환율 위치');
    }

    // 조회 완료
    source.requests.single.complete(_data());
    await tester.pumpAndSettle();
    expect(find.textContaining('업데이트:'), findsOneWidget);
    expectSteady('조회 완료');
    final updateTop = tester.getTopLeft(find.textContaining('업데이트:')).dy;

    // 새로고침 중
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(find.text(_staleLoading), findsOneWidget);
    expectSteady('새로고침 중');
    expect(
      tester.getTopLeft(find.textContaining('업데이트:')).dy,
      updateTop,
      reason: '안내 문구가 나타나도 갱신 시각은 제자리에 있다',
    );

    // 새로고침 실패: 마지막 성공값 안내
    source.requests.last.completeError(StateError('timeout'));
    await tester.pumpAndSettle();
    expect(find.text(_staleFailed), findsOneWidget);
    expectSteady('새로고침 실패');

    // 새로고침 완료
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    source.requests.last.complete(_data());
    await tester.pumpAndSettle();
    expect(find.text(_staleFailed), findsNothing);
    expectSteady('새로고침 완료');
  });

  testWidgets('조회 불가 카드도 같은 높이라 넘겨도 현재 환율 위치가 같다', (tester) async {
    final loaded = _Source();
    await tester.pumpWidget(_card(loaded));
    await tester.pump();
    loaded.requests.single.complete(_data());
    await tester.pumpAndSettle();
    final height = _headerHeight(tester);
    final rateTop = _rateTop(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_card(_Source(), unavailableText: '지원하지 않는 코인'));
    await tester.pump();

    expect(_headerHeight(tester), height);
    expect(_rateTop(tester), rateTop);
  });

  // 좁은 폭은 큰 글자에서 안내 문구가 두 줄로 접히는 경우까지 확인한다.
  for (final (scale, width) in const [
    (1.0, 360.0),
    (1.5, 360.0),
    (2.0, 360.0),
    (2.0, 200.0),
  ]) {
    testWidgets('글자 배율 $scale, 폭 $width: 상태와 관계없이 높이가 같고 문구가 잘리지 않는다', (
      tester,
    ) async {
      final fetchedAt = DateTime(2026, 1, 2, 3, 4);

      Future<double> heightOf({
        bool isLoading = false,
        bool showsOldData = false,
        DateTime? fetchedAt,
      }) async {
        await tester.pumpWidget(
          _header(
            scale: scale,
            width: width,
            isLoading: isLoading,
            showsOldData: showsOldData,
            fetchedAt: fetchedAt,
          ),
        );
        final header = tester.getRect(find.byType(MarketChartHeader));
        for (final text in [
          if (fetchedAt != null) find.textContaining('업데이트:'),
          if (showsOldData) find.textContaining(' · 갱신'),
        ]) {
          expect(text, findsOneWidget);
          expect(tester.getRect(text).bottom, lessThanOrEqualTo(header.bottom));
          expect(
            tester.getSize(text).height,
            greaterThanOrEqualTo(_neededHeight(tester, text)),
            reason: '문구가 잘리지 않는다',
          );
        }
        return header.height;
      }

      final firstLoad = await heightOf(isLoading: true);
      expect(await heightOf(fetchedAt: fetchedAt), firstLoad);
      expect(
        await heightOf(
          isLoading: true,
          showsOldData: true,
          fetchedAt: fetchedAt,
        ),
        firstLoad,
      );
      expect(
        await heightOf(showsOldData: true, fetchedAt: fetchedAt),
        firstLoad,
      );
      expect(await heightOf(), firstLoad);
    });
  }

  testWidgets('글자 배율을 키우면 비워 둔 자리도 문구가 들어갈 만큼 커진다', (tester) async {
    await tester.pumpWidget(_header(scale: 2, width: 360));
    final reserved = _statusAreaHeight(tester);

    await tester.pumpWidget(
      _header(
        scale: 2,
        width: 360,
        showsOldData: true,
        fetchedAt: DateTime(2026, 1, 2, 3, 4),
      ),
    );
    expect(
      reserved,
      greaterThanOrEqualTo(
        _neededHeight(tester, find.textContaining('업데이트:')) +
            _neededHeight(tester, find.text(_staleFailed)),
      ),
    );
  });

  // 테스트 글꼴은 굵기가 달라도 글자 폭이 같아 높이로는 재현되지 않는다. 그래서 줄바꿈을
  // 정하는 스타일이 같은지를 비교한다.
  for (final boldText in const [false, true]) {
    testWidgets('굵은 글씨 $boldText: 자리 글자는 보이는 문구와 같은 스타일로 그린다', (tester) async {
      await tester.pumpWidget(
        _header(
          scale: 1,
          width: 360,
          boldText: boldText,
          showsOldData: true,
          fetchedAt: DateTime(2026, 1, 2, 3, 4),
        ),
      );

      final reserved = find.descendant(
        of: find.byType(Opacity),
        matching: find.byType(RichText),
      );
      final visible = [
        for (final text in [
          find.textContaining('업데이트:'),
          find.text(_staleFailed),
        ])
          find.descendant(of: text, matching: find.byType(RichText)),
      ];
      expect(reserved, findsNWidgets(visible.length));
      for (final (index, line) in visible.indexed) {
        final style = _styleOf(tester, line);
        expect(style?.fontWeight == FontWeight.bold, boldText);
        expect(_styleOf(tester, reserved.at(index)), style);
      }
    });
  }

  testWidgets('비워 둔 자리는 화면 낭독기에 읽히지 않는다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_header(scale: 1, width: 360));

    expect(find.bySemanticsLabel(RegExp('갱신 지연|업데이트:')), findsNothing);

    handle.dispose();
  });
}
