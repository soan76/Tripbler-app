import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_rate_comparison.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_data_calculator.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

import '../../helpers/memory_chart_snapshots.dart';

const usd = ChartPair.fiat('USD', 'KRW');

final amount = find.byKey(const ValueKey('market-chart-amount'));
final swap = find.byKey(const ValueKey('market-chart-swap'));
final selectedDate = find.byKey(const ValueKey('market-chart-selected-date'));
final selectedRate = find.byKey(const ValueKey('market-chart-selected-rate'));
final compareSelected = find.byKey(
  const ValueKey('market-chart-compare-selected'),
);
final compareLatest = find.byKey(const ValueKey('market-chart-compare-latest'));
final compareDifference = find.byKey(
  const ValueKey('market-chart-compare-difference'),
);

class Source implements ChartDataSource {
  Source(this.rates, {double? current, this.historical = false})
    : current = current ?? rates.last;

  List<double> rates;
  final double? current;
  final bool historical;

  @override
  Future<ChartData> load(ChartPeriod period) async => ChartData(
    history: [
      for (var i = 0; i < rates.length; i++)
        ChartSample(
          date: DateTime(2026, 1, 1 + i),
          rate: rates[i],
          baseCurrencyCode: 'USD',
          targetCurrencyCode: 'KRW',
        ),
    ],
    currentRate: current,
    historicalRate: historical,
    fetchedAt: DateTime(2026, 1, 9),
  );

  @override
  void dispose() {}
}

Widget charts(Source source, {double? width}) {
  final carousel = SingleChildScrollView(
    child: ChartPairCarousel(
      pairs: const [usd],
      currencies: const [],
      snapshotStore: MemorySnapshots(),
      createDataSource: (_) => source,
    ),
  );
  return MaterialApp(
    home: Scaffold(
      body: width == null
          ? carousel
          : Center(
              child: SizedBox(width: width, child: carousel),
            ),
    ),
  );
}

LineChartData chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

Future<void> select(WidgetTester tester, int index) async {
  final chart = chartData(tester);
  final bar = chart.lineBarsData.first;
  chart.lineTouchData.touchCallback!(
    FlTapDownEvent(TapDownDetails()),
    LineTouchResponse(
      touchLocation: Offset.zero,
      touchChartCoordinate: Offset.zero,
      lineBarSpots: [TouchLineBarSpot(bar, 0, bar.spots[index], 0)],
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> release(WidgetTester tester) async {
  chartData(tester).lineTouchData.touchCallback!(
    FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch)),
    null,
  );
  await tester.pump();
}

/// 그래프의 선택 마커가 놓인 기록 위치.
List<int> markers(WidgetTester tester) =>
    chartData(tester).lineBarsData.first.showingIndicators;

/// 마커가 놓인 기록의 환율.
double markedRate(WidgetTester tester) {
  final bar = chartData(tester).lineBarsData.first;
  return bar.spots[bar.showingIndicators.single].y;
}

/// 그래프를 실제로 칠하는 렌더 객체. 축 글자는 위젯이라 여기 칠해지는 글자는 툴팁뿐이다.
RenderObject chartPainter(WidgetTester tester) => tester.renderObject(
  find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'LineChartLeaf',
  ),
);

/// 새로고침해 [rates]를 받고, 그래프의 마커가 사라진 바로 그 프레임에서 멈춘다.
Future<void> refreshTo(
  WidgetTester tester,
  Source source,
  List<double> rates,
) async {
  source.rates = rates;
  await tester.tap(find.byIcon(Icons.refresh));
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    if (markers(tester).isEmpty) return;
  }
  fail('마커가 사라지지 않았다');
}

String textOf(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data!;

Future<void> enter(WidgetTester tester, String text) async {
  await tester.enterText(amount, text);
  await tester.pump();
}

const rates = [1300.0, 1350.0, 1400.0];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ChartRateComparison', () {
    test('difference is latest minus selected', () {
      final comparison = ChartRateComparison.of(
        amount: 2,
        selectedRate: 1300,
        latestRate: 1400,
      )!;
      expect(comparison.selectedAmount, 2600);
      expect(comparison.latestAmount, 2800);
      expect(comparison.difference, 200);
    });

    test('is null without an amount or a usable rate', () {
      expect(
        ChartRateComparison.of(amount: null, selectedRate: 1, latestRate: 1),
        isNull,
      );
      expect(
        ChartRateComparison.of(amount: 1, selectedRate: 0, latestRate: 1),
        isNull,
      );
      expect(
        ChartRateComparison.of(amount: 1, selectedRate: 1, latestRate: null),
        isNull,
      );
    });

    test('rounding noise counts as no difference', () {
      for (final (amount, selected, latest) in const [
        (3.0, 0.1 + 0.2, 0.3),
        (3.0, 0.3, 0.1 + 0.2),
        (1e6, 1.1 + 2.2, 3.3),
        (1e-6, 1.0 / 3 * 3e-9, 1e-9),
      ]) {
        final comparison = ChartRateComparison.of(
          amount: amount,
          selectedRate: selected,
          latestRate: latest,
        )!;
        expect(comparison.difference, 0, reason: '$amount $selected $latest');
      }
    });

    test('keeps real differences however small the amounts are', () {
      for (final (selected, latest) in const [
        (0.001, 0.002),
        (0.002, 0.001),
        (1e-20, 2e-20),
        (0.000004115, 0.000004116),
        // 큰 환율의 작은 움직임도 오차가 아니다.
        (145000000.12, 145000000.13),
      ]) {
        final comparison = ChartRateComparison.of(
          amount: 1,
          selectedRate: selected,
          latestRate: latest,
        )!;
        expect(comparison.difference, latest - selected);
      }
    });
  });

  group('nearestIndex', () {
    final points = [
      for (final day in const [1, 5, 9])
        ChartSample(
          date: DateTime(2026, 1, day),
          rate: 1,
          baseCurrencyCode: 'USD',
          targetCurrencyCode: 'KRW',
        ),
    ];

    test('finds the closest real record', () {
      expect(
        ExchangeChartDataCalculator.nearestIndex(points, DateTime(2026, 1, 5)),
        1,
      );
      expect(
        ExchangeChartDataCalculator.nearestIndex(points, DateTime(2026, 1, 2)),
        0,
      );
      expect(
        ExchangeChartDataCalculator.nearestIndex(points, DateTime(2026, 1, 8)),
        2,
      );
    });

    test('is null with no records', () {
      expect(
        ExchangeChartDataCalculator.nearestIndex(const [], DateTime(2026)),
        isNull,
      );
    });
  });

  group('selecting a point', () {
    testWidgets('shows its date and rate and compares both amounts', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      expect(find.text('2,800 KRW'), findsOneWidget);

      await select(tester, 0);
      expect(textOf(tester, selectedDate), '2026.01.01');
      expect(textOf(tester, selectedRate), '1 USD = 1,300 KRW');
      expect(textOf(tester, compareSelected), '2,600 KRW');
      expect(textOf(tester, compareLatest), '2,800 KRW');
      expect(textOf(tester, compareDifference), '+200 KRW');
    });

    testWidgets('marker and numbers point at the same record', (tester) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 1);

      final chart = chartData(tester);
      expect(chart.lineBarsData.first.showingIndicators, [1]);
      expect(markedRate(tester), 1350);
      expect(chart.showingTooltipIndicators, isEmpty);
      expect(textOf(tester, selectedDate), '2026.01.02');
      expect(textOf(tester, compareSelected), '1,350 KRW');
    });

    testWidgets('colors the difference by its sign', (tester) async {
      await tester.pumpWidget(charts(Source(const [1300, 1500, 1400])));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      final colors = Theme.of(tester.element(amount)).colorScheme;
      Color? color() => tester.widget<Text>(compareDifference).style!.color;

      await select(tester, 0);
      expect(textOf(tester, compareDifference), '+100 KRW');
      expect(color(), colors.gain);

      await select(tester, 1);
      expect(textOf(tester, compareDifference), '-100 KRW');
      expect(color(), colors.loss);

      await select(tester, 2);
      expect(textOf(tester, compareDifference), '0 KRW');
      expect(color(), colors.onSurfaceVariant);
    });

    testWidgets('rounding noise shows zero with no sign or color', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(const [0.1 + 0.2, 0.5, 0.3])));
      await tester.pumpAndSettle();
      await enter(tester, '3');
      await select(tester, 0);
      final colors = Theme.of(tester.element(amount)).colorScheme;
      expect(textOf(tester, compareDifference), '0 KRW');
      expect(
        tester.widget<Text>(compareDifference).style!.color,
        colors.onSurfaceVariant,
      );
    });

    testWidgets('a small real difference keeps its sign and color', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(const [0.001, 0.0015, 0.002])));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 0);
      final colors = Theme.of(tester.element(amount)).colorScheme;
      expect(textOf(tester, compareDifference), '+0.001 KRW');
      expect(tester.widget<Text>(compareDifference).style!.color, colors.gain);
    });

    testWidgets('a difference too small to show has no sign or color', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(const [1e-21, 1.5e-21, 2e-21])));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 0);
      final colors = Theme.of(tester.element(amount)).colorScheme;
      expect(textOf(tester, compareDifference), '0 KRW');
      expect(
        tester.widget<Text>(compareDifference).style!.color,
        colors.onSurfaceVariant,
      );
    });

    testWidgets('recalculates at once when the amount changes', (tester) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 0);

      await enter(tester, '3');
      expect(textOf(tester, compareSelected), '3,900 KRW');
      expect(textOf(tester, compareLatest), '4,200 KRW');
      expect(textOf(tester, compareDifference), '+300 KRW');
    });

    testWidgets('without an amount shows only the date and rate', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await select(tester, 0);

      expect(textOf(tester, selectedDate), '2026.01.01');
      expect(textOf(tester, selectedRate), '1 USD = 1,300 KRW');
      expect(compareDifference, findsNothing);
      expect(find.textContaining('업데이트:'), findsOneWidget);
      final status = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.textContaining('업데이트:'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(status.opacity, 1);

      await enter(tester, '2');
      expect(compareDifference, findsOneWidget);
      await enter(tester, '');
      expect(compareDifference, findsNothing);
    });

    testWidgets('names a rate taken from history', (tester) async {
      await tester.pumpWidget(charts(Source(rates, historical: true)));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 0);
      expect(find.text('최근 기록'), findsOneWidget);
      expect(find.text('최신'), findsNothing);
    });

    testWidgets('says latest for a plain current rate', (tester) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 0);
      expect(find.text('최신'), findsOneWidget);
    });

    testWidgets('without a latest rate compares nothing', (tester) async {
      await tester.pumpWidget(charts(Source(rates, current: 0)));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 0);
      expect(textOf(tester, selectedRate), '1 USD = 1,300 KRW');
      expect(compareDifference, findsNothing);
    });
  });

  group('swapping', () {
    testWidgets('keeps the date and flips both rates', (tester) async {
      await tester.pumpWidget(charts(Source(const [1000, 2000, 500])));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('market-chart-amount')));
      await enter(tester, '1000');
      await select(tester, 0);
      expect(textOf(tester, compareDifference), '-500,000 KRW');

      await tester.tap(swap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(textOf(tester, selectedDate), '2026.01.01');
      expect(textOf(tester, selectedRate), '1 KRW = 0.001 USD');
      expect(textOf(tester, compareSelected), '1 USD');
      expect(textOf(tester, compareLatest), '2 USD');
      expect(textOf(tester, compareDifference), '+1 USD');
      expect(chartData(tester).lineBarsData.first.showingIndicators, [0]);
      expect(markedRate(tester), 0.001);
      expect(chartData(tester).showingTooltipIndicators, isEmpty);
    });

    testWidgets('while returning shows only the new direction', (tester) async {
      await tester.pumpWidget(charts(Source(const [1000, 2000, 500])));
      await tester.pumpAndSettle();
      await enter(tester, '1000');
      await select(tester, 0);
      await release(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(markers(tester), isEmpty);
      expect(textOf(tester, compareDifference), '-500,000 KRW');

      await tester.tap(swap);
      await tester.pump();
      // 복귀는 끊기지 않고 이어지되, 모든 프레임의 값이 새 방향이어야 한다.
      expect(compareDifference, findsOneWidget);
      var frames = 0;
      while (compareDifference.evaluate().isNotEmpty) {
        expect(textOf(tester, selectedDate), '2026.01.01');
        expect(textOf(tester, selectedRate), '1 KRW = 0.001 USD');
        expect(textOf(tester, compareSelected), '1 USD');
        expect(textOf(tester, compareLatest), '2 USD');
        expect(textOf(tester, compareDifference), '+1 USD');
        frames++;
        expect(frames, lessThan(20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(frames, greaterThan(1));
      expect(selectedDate, findsNothing);
      expect(find.text('2 USD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('moves to the nearest record when the date is gone', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(const [1000, 0, 500])));
      await tester.pumpAndSettle();
      await select(tester, 1);
      expect(textOf(tester, selectedDate), '2026.01.02');

      await tester.tap(swap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // 환율 0은 뒤집을 수 없어 빠지고, 마커와 글자가 같은 기록으로 옮겨 간다.
      final index = chartData(
        tester,
      ).lineBarsData.first.showingIndicators.single;
      expect(index, 0);
      expect(textOf(tester, selectedDate), '2026.01.01');
      expect(textOf(tester, selectedRate), '1 KRW = 0.001 USD');
    });
  });

  group('releasing', () {
    testWidgets('holds for three seconds and returns the amount', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 0);
      await release(tester);

      await tester.pump(const Duration(milliseconds: 2999));
      expect(compareDifference, findsOneWidget);
      expect(selectedDate, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(compareDifference, findsNothing);
      expect(selectedDate, findsNothing);
      expect(find.text('2,800 KRW'), findsOneWidget);
    });

    testWidgets('a new touch restarts the hold', (tester) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 0);
      await release(tester);
      await tester.pump(const Duration(seconds: 2));
      await select(tester, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(textOf(tester, selectedDate), '2026.01.02');
      await release(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(selectedDate, findsNothing);
    });

    testWidgets('moves the amount down while selecting', (tester) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      final chart = chartData(tester);
      final bar = chart.lineBarsData.first;
      chart.lineTouchData.touchCallback!(
        FlTapDownEvent(TapDownDetails()),
        LineTouchResponse(
          touchLocation: Offset.zero,
          touchChartCoordinate: Offset.zero,
          lineBarSpots: [TouchLineBarSpot(bar, 0, bar.spots[0], 0)],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final moving = tester.getTopLeft(compareLatest).dy;
      final movingLabel = tester.getTopLeft(find.text('최신'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getTopLeft(compareLatest).dy, greaterThan(moving));
      // 금액만 내려오고 라벨은 제자리에 있어 위쪽 글자와 겹치지 않는다.
      expect(tester.getTopLeft(find.text('최신')), movingLabel);
    });
  });

  group('refreshing with a selection', () {
    testWidgets('changed records keep the numbers the marker pointed at', (
      tester,
    ) async {
      final source = Source(rates);
      await tester.pumpWidget(charts(source));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 0);
      final settled = tester.getTopLeft(compareLatest).dy;

      await refreshTo(tester, source, const [1310, 1350, 1400]);
      expect(textOf(tester, selectedRate), '1 USD = 1,300 KRW');
      expect(textOf(tester, compareSelected), '2,600 KRW');

      // 한 프레임 뒤 그래프가 선택 해제를 알려도 값은 그대로이고 금액이 돌아간다.
      await tester.pump();
      expect(textOf(tester, selectedRate), '1 USD = 1,300 KRW');
      await tester.pump(const Duration(milliseconds: 50));
      expect(textOf(tester, compareSelected), '2,600 KRW');
      expect(tester.getTopLeft(compareLatest).dy, lessThan(settled));
      await tester.pump(const Duration(milliseconds: 200));
      expect(compareDifference, findsNothing);
      expect(selectedDate, findsNothing);
      expect(find.text('2,800 KRW'), findsOneWidget);

      // 새 기록에서 같은 날짜를 다시 고르면 새 값을 보여 준다.
      await select(tester, 0);
      expect(textOf(tester, selectedRate), '1 USD = 1,310 KRW');
      expect(textOf(tester, compareSelected), '2,620 KRW');
      expect(markers(tester), [0]);
    });

    testWidgets('a removed record does not move the numbers to its neighbor', (
      tester,
    ) async {
      final source = Source(rates);
      await tester.pumpWidget(charts(source));
      await tester.pumpAndSettle();
      await enter(tester, '1');
      await select(tester, 2);

      await refreshTo(tester, source, const [1300, 1350]);
      expect(textOf(tester, selectedDate), '2026.01.03');
      expect(textOf(tester, selectedRate), '1 USD = 1,400 KRW');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(selectedDate, findsNothing);
    });

    testWidgets('the same values keep the selection', (tester) async {
      final source = Source(rates);
      await tester.pumpWidget(charts(source));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 1);

      source.rates = List.of(rates);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(markers(tester), [1]);
      expect(textOf(tester, selectedRate), '1 USD = 1,350 KRW');
      expect(textOf(tester, compareSelected), '2,700 KRW');
    });

    testWidgets('changed records while swapped return in the shown direction', (
      tester,
    ) async {
      final source = Source(const [1000, 2000, 500]);
      await tester.pumpWidget(charts(source));
      await tester.pumpAndSettle();
      await enter(tester, '1000');
      await tester.tap(swap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await select(tester, 0);
      expect(textOf(tester, selectedRate), '1 KRW = 0.001 USD');

      await refreshTo(tester, source, const [800, 2000, 500]);
      expect(textOf(tester, selectedRate), '1 KRW = 0.001 USD');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(selectedDate, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with reduced motion returns at once', (tester) async {
      final source = Source(rates);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: charts(source),
        ),
      );
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 0);
      expect(compareDifference, findsOneWidget);

      await refreshTo(tester, source, const [1310, 1350, 1400]);
      expect(compareDifference, findsNothing);
      expect(find.text('2,800 KRW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the card has no tooltip', () {
    testWidgets('keeps the marker and guide line for three seconds', (
      tester,
    ) async {
      await tester.pumpWidget(charts(Source(rates)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      await select(tester, 1);

      expect(chartData(tester).showingTooltipIndicators, isEmpty);
      expect(markers(tester), [1]);
      expect(markedRate(tester), 1350);
      // 마커 점과 세로 안내선은 칠하고 툴팁 글자는 칠하지 않는다.
      expect(chartPainter(tester), paints..circle());
      expect(chartPainter(tester), isNot(paints..paragraph()));
      final chart = chartData(tester);
      final indicator = chart.lineTouchData.getTouchedSpotIndicator(
        chart.lineBarsData.first,
        [1],
      ).single!;
      expect(indicator.indicatorBelowLine.dashArray, [4, 4]);
      expect(indicator.touchedSpotDotData.show, isTrue);

      await release(tester);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(markers(tester), [1]);
      expect(chartData(tester).showingTooltipIndicators, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(markers(tester), isEmpty);
      // fl_chart가 데이터 전환(150ms)을 마치면 점도 더 칠하지 않는다.
      await tester.pump(const Duration(milliseconds: 200));
      expect(chartPainter(tester), isNot(paints..circle()));
    });
  });

  testWidgets('selection keeps the chart where it is', (tester) async {
    await tester.pumpWidget(charts(Source(rates)));
    await tester.pumpAndSettle();
    await enter(tester, '2');
    final before = tester.getRect(find.byType(ExchangeRateLineChart));
    await select(tester, 0);
    expect(tester.getRect(find.byType(ExchangeRateLineChart)), before);
  });

  testWidgets('the comparison spans the whole row at full size', (
    tester,
  ) async {
    await tester.pumpWidget(charts(Source(rates)));
    await tester.pumpAndSettle();
    await enter(tester, '2');
    await select(tester, 0);
    expect(
      tester.getRect(compareDifference).right,
      closeTo(tester.getRect(selectedRate).right, 0.5),
    );
    expect(
      tester.getRect(compareSelected).size,
      tester.getSize(compareSelected),
    );
  });

  testWidgets('a long amount shrinks without shrinking its label', (
    tester,
  ) async {
    await tester.pumpWidget(
      charts(Source(const [145000000, 150000000, 148000000]), width: 280),
    );
    await tester.pumpAndSettle();
    await enter(tester, '123456789.5');
    await select(tester, 0);
    final value = tester.getRect(compareSelected);
    expect(value.width, lessThan(tester.getSize(compareSelected).width));
    final label = find.text('선택일');
    expect(tester.getRect(label).size, tester.getSize(label));
  });

  for (final (width, scale) in const [
    (320.0, 1.0),
    (320.0, 1.5),
    (280.0, 1.0),
  ]) {
    testWidgets('long amounts fit at $width wide, scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: charts(
            Source(const [145000000, 150000000, 148000000]),
            width: width,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await enter(tester, '123456789.5');
      await select(tester, 0);
      expect(tester.takeException(), isNull);
      for (final finder in [
        compareSelected,
        compareLatest,
        compareDifference,
      ]) {
        expect(finder, findsOneWidget);
      }
    });
  }

  testWidgets('touches between records still pick one', (tester) async {
    await tester.pumpWidget(charts(Source(rates)));
    await tester.pumpAndSettle();
    expect(chartData(tester).lineTouchData.touchSpotThreshold, double.infinity);
  });
}
