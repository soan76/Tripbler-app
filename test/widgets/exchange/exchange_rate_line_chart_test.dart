import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

void main() {
  Future<void> showChart(
    WidgetTester tester, {
    ChartPeriod period = ChartPeriod.sevenDays,
    int count = 3,
    double rateOffset = 0,
    double rateStep = 1,
    String target = 'KRW',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExchangeRateLineChart(
            history: List.generate(
              count,
              (index) => ExchangeRateHistoryModel(
                date: DateTime(2026, 9, index + 1),
                rate: 1300 + index * rateStep + rateOffset,
                baseCurrencyCode: 'USD',
                targetCurrencyCode: target,
              ),
            ),
            period: period,
          ),
        ),
      ),
    );
  }

  LineChartData data(WidgetTester tester) =>
      tester.widget<LineChart>(find.byType(LineChart)).data;

  void select(WidgetTester tester, int index) {
    final chart = data(tester);
    final bar = chart.lineBarsData.first;
    chart.lineTouchData.touchCallback!(
      FlTapDownEvent(TapDownDetails()),
      LineTouchResponse(
        touchLocation: Offset.zero,
        touchChartCoordinate: Offset.zero,
        lineBarSpots: [TouchLineBarSpot(bar, 0, bar.spots[index], 0)],
      ),
    );
  }

  for (final event in <FlTouchEvent>[
    FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch)),
    FlPanEndEvent(DragEndDetails()),
    const FlLongPressEnd(LongPressEndDetails()),
  ]) {
    testWidgets('${event.runtimeType} retains selection for three seconds', (
      tester,
    ) async {
      await showChart(tester);
      select(tester, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(data(tester).showingTooltipIndicators, hasLength(1));

      data(tester).lineTouchData.touchCallback!(event, null);
      await tester.pump(const Duration(milliseconds: 2999));
      final chart = data(tester);
      expect(chart.showingTooltipIndicators, hasLength(1));
      expect(chart.lineBarsData.first.showingIndicators, [1]);
      final items = chart.lineTouchData.touchTooltipData.getTooltipItems(
        chart.showingTooltipIndicators.first.showingSpots,
      );
      expect(items.single!.text, contains('2026.09.02'));
      expect(items.single!.text, contains('1301.00'));

      await tester.pump(const Duration(milliseconds: 1));
      expect(data(tester).showingTooltipIndicators, isEmpty);
      expect(data(tester).lineBarsData.first.showingIndicators, isEmpty);
    });
  }

  testWidgets('new touch cancels old timer and release restarts it', (
    tester,
  ) async {
    await showChart(tester);
    select(tester, 0);
    data(tester).lineTouchData.touchCallback!(
      FlPanEndEvent(DragEndDetails()),
      null,
    );
    await tester.pump(const Duration(seconds: 2));
    select(tester, 2);
    await tester.pump(const Duration(seconds: 4));
    expect(data(tester).lineBarsData.first.showingIndicators, [2]);
    data(tester).lineTouchData.touchCallback!(
      FlPanEndEvent(DragEndDetails()),
      null,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(data(tester).showingTooltipIndicators, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(data(tester).showingTooltipIndicators, isEmpty);
  });

  testWidgets('disposing chart cancels pending timer', (tester) async {
    await showChart(tester);
    select(tester, 1);
    data(tester).lineTouchData.touchCallback!(
      FlPanEndEvent(DragEndDetails()),
      null,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  for (final change in ['period', 'shorter', 'empty', 'rates', 'currency']) {
    testWidgets('$change change clears selection and pending timer', (
      tester,
    ) async {
      await showChart(tester);
      select(tester, 2);
      data(tester).lineTouchData.touchCallback!(
        FlPanEndEvent(DragEndDetails()),
        null,
      );
      await tester.pump(const Duration(seconds: 1));
      await showChart(
        tester,
        period: change == 'period'
            ? ChartPeriod.twoYears
            : ChartPeriod.sevenDays,
        count: change == 'empty'
            ? 0
            : change == 'shorter'
            ? 1
            : 3,
        rateOffset: change == 'rates' ? 10 : 0,
        target: change == 'currency' ? 'JPY' : 'KRW',
      );
      if (change == 'empty') {
        expect(find.byType(LineChart), findsNothing);
      } else {
        expect(data(tester).showingTooltipIndicators, isEmpty);
        expect(data(tester).lineBarsData.first.showingIndicators, isEmpty);
        select(tester, 0);
      }
      await tester.pump(const Duration(seconds: 3));
      if (change != 'empty') {
        // 이전 데이터의 타이머가 새 선택을 지우면 안 된다.
        expect(data(tester).showingTooltipIndicators, hasLength(1));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final sample in [
    (offset: -1300.0, step: 20.0, expected: ['0', '10', '20', '30', '40']),
    (offset: 0.0, step: 20.0, expected: ['1300', '1310', '1320']),
    (offset: -1298.8, step: 0.2, expected: ['1.2', '1.4', '1.6']),
  ]) {
    testWidgets('Y axis preserves numeric labels ${sample.expected}', (
      tester,
    ) async {
      await showChart(tester, rateOffset: sample.offset, rateStep: sample.step);
      await tester.pumpAndSettle();
      for (final label in sample.expected) {
        expect(find.text(label), findsWidgets);
      }
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'data change keeps held pointer until ${cancel ? 'cancel' : 'up'}',
      (tester) async {
        await showChart(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(LineChart)),
        );
        select(tester, 1);
        await showChart(tester, rateOffset: 10);
        expect(data(tester).showingTooltipIndicators, isEmpty);
        select(tester, 1);
        data(tester).lineTouchData.touchCallback!(
          const FlTapCancelEvent(),
          null,
        );
        await tester.pump(const Duration(seconds: 4));
        expect(data(tester).showingTooltipIndicators, hasLength(1));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pump(const Duration(milliseconds: 2999));
        expect(data(tester).showingTooltipIndicators, hasLength(1));
        await tester.pump(const Duration(milliseconds: 1));
        expect(data(tester).showingTooltipIndicators, isEmpty);
      },
    );
  }

  testWidgets('pointer released while data is empty does not remain active', (
    tester,
  ) async {
    await showChart(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LineChart)),
    );
    await showChart(tester, count: 0);
    await gesture.up();
    await showChart(tester);
    select(tester, 1);
    data(tester).lineTouchData.touchCallback!(
      FlPanEndEvent(DragEndDetails()),
      null,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(data(tester).showingTooltipIndicators, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equivalent data rebuild preserves selection', (tester) async {
    await showChart(tester);
    select(tester, 1);
    await showChart(tester);
    expect(data(tester).showingTooltipIndicators, hasLength(1));
  });

  testWidgets('invalid touch and stale tooltip indices are ignored', (
    tester,
  ) async {
    await showChart(tester);
    final chart = data(tester);
    final invalidBar = LineChartBarData(spots: const [FlSpot(99, 1)]);
    final invalid = TouchLineBarSpot(invalidBar, 0, const FlSpot(-1, 1), 0);
    chart.lineTouchData.touchCallback!(
      FlTapDownEvent(TapDownDetails()),
      LineTouchResponse(
        touchLocation: Offset.zero,
        touchChartCoordinate: Offset.zero,
        lineBarSpots: [invalid],
      ),
    );
    await tester.pump();
    expect(data(tester).showingTooltipIndicators, isEmpty);
    expect(chart.lineTouchData.touchTooltipData.getTooltipItems([invalid]), [
      null,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate end events do not extend the countdown', (
    tester,
  ) async {
    await showChart(tester);
    select(tester, 1);
    data(tester).lineTouchData.touchCallback!(
      FlPanEndEvent(DragEndDetails()),
      null,
    );
    await tester.pump(const Duration(seconds: 2));
    data(tester).lineTouchData.touchCallback!(const FlTapCancelEvent(), null);
    await tester.pump(const Duration(seconds: 1));
    expect(data(tester).showingTooltipIndicators, isEmpty);
  });

  testWidgets(
    'gesture cancellation while finger is down does not start timer',
    (tester) async {
      await showChart(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LineChart)),
      );
      select(tester, 1);
      data(tester).lineTouchData.touchCallback!(const FlTapCancelEvent(), null);
      await tester.pump(const Duration(seconds: 4));
      expect(data(tester).showingTooltipIndicators, hasLength(1));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 2999));
      expect(data(tester).showingTooltipIndicators, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(data(tester).showingTooltipIndicators, isEmpty);
    },
  );
}
