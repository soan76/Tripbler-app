import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_inversion.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_axis_helper.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

List<ChartPoint> history(List<double> rates) => [
  for (var i = 0; i < rates.length; i++)
    ChartSample(
      date: DateTime(2026, 1, 1 + i),
      rate: rates[i],
      baseCurrencyCode: 'USD',
      targetCurrencyCode: 'KRW',
    ),
];

Widget chart(
  List<ChartPoint> points, {
  double width = 320,
  ChartPeriod period = ChartPeriod.oneMonth,
  double textScale = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 300,
          child: ExchangeRateLineChart(history: points, period: period),
        ),
      ),
    ),
  ),
);

double reserved(WidgetTester tester) => tester
    .widget<LineChart>(find.byType(LineChart))
    .data
    .titlesData
    .leftTitles
    .sideTitles
    .reservedSize;

Iterable<RenderBox> yLabels(WidgetTester tester) => find
    .descendant(of: find.byType(FittedBox), matching: find.byType(Text))
    .evaluate()
    .map((element) => element.renderObject! as RenderBox);

double right(RenderBox label) =>
    label.localToGlobal(label.size.topRight(Offset.zero)).dx;

/// 줄이기 전의 폭에 대해 화면에 그려진 폭의 비율.
double shownRatio(RenderBox label) =>
    (right(label) - label.localToGlobal(Offset.zero).dx) / label.size.width;

const usdKrw = [1300.0, 1350.0, 1400.0];

void main() {
  test('Y axis labels group only the integer part by thousands', () {
    String label(double value, double interval) =>
        ExchangeChartAxisHelper.formatYAxisRate(value, interval);

    expect(label(1300, 50), '1,300');
    expect(label(145000000, 1000000), '145,000,000');
    expect(label(-1300, 50), '-1,300');
    expect(label(999, 1), '999');
    expect(label(1320.5, 0.5), '1,320.5');
    expect(label(1234.5678, 0.0001), '1,234.5678');
    expect(label(1234.5, 0), '1,234.50');
    expect(label(7.5e-9, 1e-10), '7.5e-9');
    expect(label(1234e-9, 1e-10), '1.2340e-6');
  });

  // 테스트 글꼴은 글자마다 글자 크기만큼 넓다(11). 바깥 여백은 양쪽 합쳐 8이다.
  group('yAxisReservedWidth', () {
    double width(
      double minY,
      double maxY,
      double interval, {
      double chartWidth = 1000,
      double scale = 1,
      TextStyle baseStyle = const TextStyle(),
    }) => ExchangeChartAxisHelper.yAxisReservedWidth(
      minY: minY,
      maxY: maxY,
      yInterval: interval,
      chartWidth: chartWidth,
      textScaler: TextScaler.linear(scale),
      baseStyle: baseStyle,
    );

    test('fits only the labels that will be drawn', () {
      // 천 단위 쉼표도 한 글자로 잰다: '1,300'.
      expect(width(1300, 1400, 50), 5 * 11 + 8);
      expect(width(0.00071, 0.00077, 0.00002), 7 * 11 + 8);
    });

    test('counts decimals the interval adds', () {
      expect(width(1320.5, 1321.5, 0.5), 7 * 11 + 8);
    });

    test('counts a tick with more digits than the ends', () {
      expect(width(99000000, 99999999, 100000000), 10 * 11 + 8);
      expect(width(99000000, 100500000, 500000), 11 * 11 + 8);
    });

    test('counts the longest end, not just the first', () {
      expect(width(900, 1100, 100), 5 * 11 + 8);
      expect(width(1000, 900, 100), 5 * 11 + 8);
    });

    test('measures with the inherited letter spacing', () {
      expect(
        width(1300, 1400, 50, baseStyle: const TextStyle(letterSpacing: 1)),
        5 * 12 + 8,
      );
    });

    test('grows with the text scale', () {
      expect(width(1300, 1400, 50, scale: 1.5), greaterThan(52));
    });

    test('is capped by a quarter of the chart on a small screen', () {
      expect(width(145000000, 150000000, 1000000, chartWidth: 200), 50);
    });

    test('survives an unusual range or interval', () {
      expect(width(1300, 1400, 0).isFinite, isTrue);
      expect(width(1300, 1400, double.nan).isFinite, isTrue);
      expect(width(0, 1000000, 1).isFinite, isTrue);
    });
  });

  group('chart', () {
    testWidgets('labels of any length keep 4 to the graph', (tester) async {
      await tester.pumpWidget(chart(history(usdKrw), width: 1000));
      await tester.pumpAndSettle();
      final labels = yLabels(tester);
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(right(label), reserved(tester) - 4);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('no label shrinks when there is room', (tester) async {
      for (final points in [
        history(usdKrw),
        ChartInversion.history(history(usdKrw)),
        history(const [1320.5, 1321.0, 1321.5]),
        history(const [99000000.0, 100500000.0]),
      ]) {
        await tester.pumpWidget(chart(points, width: 1000));
        await tester.pumpAndSettle();
        for (final label in yLabels(tester)) {
          expect(shownRatio(label), closeTo(1, 0.001));
        }
      }
    });

    testWidgets('swapping keeps the gap and fits the shown direction', (
      tester,
    ) async {
      await tester.pumpWidget(chart(history(usdKrw), width: 1000));
      await tester.pumpAndSettle();
      final forward = reserved(tester);

      await tester.pumpWidget(
        chart(ChartInversion.history(history(usdKrw)), width: 1000),
      );
      await tester.pumpAndSettle();
      // 역방향 라벨(0.0007…)은 정방향(1300)보다 길어 그만큼만 칸을 더 쓴다.
      expect(reserved(tester), greaterThan(forward));
      for (final label in yLabels(tester)) {
        expect(right(label), reserved(tester) - 4);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('changing the period keeps the gap', (tester) async {
      await tester.pumpWidget(
        chart(
          history(const [1320.5, 1321.0, 1321.5]),
          width: 1000,
          period: ChartPeriod.sevenDays,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in yLabels(tester)) {
        expect(right(label), reserved(tester) - 4);
      }
    });

    for (final (width, scale) in const [(160.0, 1.0), (240.0, 2.0)]) {
      testWidgets('long labels shrink to fit at $width wide, scale $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          chart(
            history(const [145000000.0, 150000000.0]),
            width: width,
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(reserved(tester), width * 0.25);
        final labels = yLabels(tester);
        expect(labels, isNotEmpty);
        for (final label in labels) {
          // 칸을 넘는 라벨은 글자를 줄여 그래프 쪽 경계를 넘지 않는다.
          expect(shownRatio(label), lessThan(1));
          expect(right(label), closeTo(reserved(tester) - 4, 0.001));
          expect(label.localToGlobal(Offset.zero).dx, greaterThanOrEqualTo(4));
        }
      });
    }
  });
}
