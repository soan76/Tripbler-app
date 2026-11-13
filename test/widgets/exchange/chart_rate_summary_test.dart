import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/widgets/charts/chart_rate_summary.dart';
import 'package:tripbler/widgets/charts/market_chart_body.dart';
import 'package:tripbler/widgets/charts/market_chart_card.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_period_selector.dart';

import 'chart_delete_mode_test.dart' show Charts, usd, jpy;

final _change = find.byKey(const ValueKey('market-chart-period-change'));
final _rate = find.byKey(const ValueKey('market-chart-current-rate'));

String _changeText(WidgetTester tester) => tester
    .widget<RichText>(
      find.descendant(of: _change, matching: find.byType(RichText)),
    )
    .text
    .toPlainText();

/// 변화량 글자(첫 글자 조각)의 색.
Color? _changeColor(WidgetTester tester) {
  final root = tester
      .widget<RichText>(
        find.descendant(of: _change, matching: find.byType(RichText)),
      )
      .text;
  Color? color;
  root.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      color = span.style?.color;
      return false;
    }
    return true;
  });
  return color;
}

List<ChartPoint> _history(List<double> rates) {
  final now = DateTime(2026, 11, 13);
  return [
    for (var i = 0; i < rates.length; i++)
      ChartSample(
        date: now.subtract(Duration(days: rates.length - 1 - i)),
        rate: rates[i],
        baseCurrencyCode: 'USD',
        targetCurrencyCode: 'KRW',
      ),
  ];
}

Widget _summary({
  double? rate,
  List<ChartPoint> history = const [],
  bool historicalRate = false,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 300,
        child: ChartRateSummary(
          rate: rate,
          history: history,
          period: ChartPeriod.oneMonth,
          baseCode: 'USD',
          targetCode: 'KRW',
          historicalRate: historicalRate,
        ),
      ),
    ),
  ),
);

void main() {
  group('ChartRateSummary', () {
    testWidgets('a rise shows ▲, the amount, the percent and the period', (
      tester,
    ) async {
      await tester.pumpWidget(
        _summary(rate: 1385.2, history: _history([1372, 1380, 1385.2])),
      );
      expect(tester.widget<Text>(_rate).data, '1,385.2');
      expect(find.text('KRW / 1 USD'), findsOneWidget);
      expect(_changeText(tester), '▲ 13.2 (0.96%)  1개월 전보다');
      final colors = Theme.of(tester.element(_change)).colorScheme;
      expect(_changeColor(tester), colors.gain);
    });

    testWidgets('a fall shows ▼ in the loss color', (tester) async {
      await tester.pumpWidget(
        _summary(rate: 95, history: _history([100, 98, 95])),
      );
      expect(_changeText(tester), '▼ 5 (5.00%)  1개월 전보다');
      final colors = Theme.of(tester.element(_change)).colorScheme;
      expect(_changeColor(tester), colors.loss);
    });

    testWidgets('no change says so without a sign or color', (tester) async {
      await tester.pumpWidget(
        _summary(rate: 100, history: _history([100, 101, 100])),
      );
      expect(_changeText(tester), '변동 없음  1개월 전보다');
      final colors = Theme.of(tester.element(_change)).colorScheme;
      expect(_changeColor(tester), colors.onSurfaceVariant);
    });

    testWidgets('a rate from the records says so next to the unit', (
      tester,
    ) async {
      await tester.pumpWidget(
        _summary(
          rate: 1385.2,
          history: _history([1372, 1385.2]),
          historicalRate: true,
        ),
      );
      expect(find.text('KRW / 1 USD · 최근 기록'), findsOneWidget);
      // 변화 줄은 그대로 보여 준다.
      expect(_changeText(tester), '▲ 13.2 (0.96%)  1개월 전보다');
    });

    testWidgets('a tiny but real change shows <0.01%, not 0.00%', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // 4.1e-6에서 4.100001e-6: 변화량은 표시되지만 퍼센트는 0.00으로 반올림된다.
      await tester.pumpWidget(
        _summary(rate: 0.0041001, history: _history([0.0041, 0.0041001])),
      );
      expect(_changeText(tester), contains('(<0.01%)'));
      expect(_changeText(tester), startsWith('▲ '));
      expect(_changeText(tester), isNot(contains('0.00%')));
      expect(
        find.bySemanticsLabel('1개월 전보다 0.0000001 오름, 0.01% 미만'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('without data it keeps the same height and reads nothing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _summary(rate: 104, history: _history([100, 104])),
      );
      final loadedHeight = tester.getSize(find.byType(ChartRateSummary)).height;

      await tester.pumpWidget(_summary());
      expect(_change, findsNothing);
      expect(tester.widget<Text>(_rate).data, '—');
      expect(
        tester.getSize(find.byType(ChartRateSummary)).height,
        loadedHeight,
      );
      expect(find.bySemanticsLabel(RegExp('▲')), findsNothing);
      semantics.dispose();
    });
  });

  group('the chart card', () {
    Future<void> pumpCharts(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Charts(pairs: [usd, jpy])),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the rate and its change above the converter', (
      tester,
    ) async {
      await pumpCharts(tester);
      // 시험 데이터는 100에서 104로 오른다.
      expect(tester.widget<Text>(_rate).data, '104');
      expect(_changeText(tester), '▲ 4 (4.00%)  1개월 전보다');
      // 제목은 화면에 쓰지 않는다.
      expect(find.text('환율 차트'), findsNothing);
    });

    testWidgets('period buttons sit in the card right under the graph', (
      tester,
    ) async {
      await pumpCharts(tester);
      final selector = find.descendant(
        of: find.byType(MarketChartCard),
        matching: find.byType(ExchangeChartPeriodSelector),
      );
      expect(selector, findsOneWidget);
      // 위젯은 눌리는 영역(48dp)까지 그래프에 붙어 있고, 보이는 버튼은 그 아래에 있다.
      final button = find.descendant(
        of: selector,
        matching: find.byType(TextButton),
      );
      final chartBottom = tester.getBottomLeft(find.byType(LineChart)).dy;
      expect(tester.getTopLeft(selector).dy, greaterThanOrEqualTo(chartBottom));
      expect(tester.getSize(button.first).height, greaterThanOrEqualTo(48));
      expect(tester.getTopLeft(find.text('7D')).dy, greaterThan(chartBottom));
      expect(
        tester.getBottomLeft(selector).dy,
        lessThanOrEqualTo(
          tester.getBottomLeft(find.byType(MarketChartCard)).dy,
        ),
      );

      await tester.tap(find.text('7D'));
      await tester.pumpAndSettle();
      expect(_changeText(tester), endsWith('7일 전보다'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the graph marks the period start with a dashed line', (
      tester,
    ) async {
      await pumpCharts(tester);
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final line = data.extraLinesData.horizontalLines.single;
      expect(line.y, data.lineBarsData.single.spots.first.y);
      expect(line.dashArray, isNotEmpty);
    });
  });

  group('the chart card with large text', () {
    for (final (scale, minGraph) in [
      (1.0, 160.0),
      (1.5, 160.0),
      (2.0, 150.0),
    ]) {
      testWidgets('text scale $scale keeps the graph and does not overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(child: Charts(pairs: [usd, jpy])),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(MarketChartBody)).height,
          greaterThanOrEqualTo(minGraph),
        );
        final cardHeight = tester.getSize(find.byType(PageView)).height;
        if (scale == 1.0) {
          // 기본 글자 크기에서는 카드 높이가 그대로다.
          expect(cardHeight, 450);
        } else {
          expect(cardHeight, greaterThan(450));
        }
      });
    }
  });
}
