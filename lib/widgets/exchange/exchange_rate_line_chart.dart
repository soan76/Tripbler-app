import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_axis_helper.dart';
import 'exchange_chart_data_calculator.dart';
import 'exchange_chart_tooltip.dart';
import 'exchange_chart_touch_controller.dart';

// 환율 라인 차트 위젯
class ExchangeRateLineChart extends StatefulWidget {
  final List<ExchangeRateHistoryModel> history;
  final ChartPeriod period;

  const ExchangeRateLineChart({
    super.key,
    required this.history,
    required this.period,
  });

  @override
  State<ExchangeRateLineChart> createState() => _ExchangeRateLineChartState();
}

class _ExchangeRateLineChartState extends State<ExchangeRateLineChart> {
  late final ExchangeChartTouchController _touchController;
  List<ExchangeRateHistoryModel> get history => widget.history;
  ChartPeriod get period => widget.period;

  @override
  void initState() {
    super.initState();
    _touchController = ExchangeChartTouchController(
      history: history,
      period: period,
    );
    _touchController.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ExchangeRateLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _touchController.updateData(history, period);
  }

  @override
  void dispose() {
    _touchController.removeListener(_onSelectionChanged);
    _touchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 데이터가 비어도 Listener를 유지해 기존 포인터의 up/cancel을 받는다.
    return Listener(
      onPointerDown: _touchController.onPointerDown,
      onPointerUp: _touchController.onPointerEnd,
      onPointerCancel: _touchController.onPointerEnd,
      child: _buildChart(context),
    );
  }

  Widget _buildChart(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chartBackgroundColor = colorScheme.surface;

    if (history.isEmpty) {
      return Container(
        height: 280,
        alignment: Alignment.center,
        color: chartBackgroundColor,
        child: Text(
          '표시할 환율 데이터가 없습니다.',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final data = ExchangeChartDataCalculator.calculate(history, period);
    final selectedSpot = _touchController.selectedSpot;

    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (history.length - 1).toDouble(),
          minY: data.minY,
          maxY: data.maxY,

          // 라이트: 흰색 / 다크: #444440
          backgroundColor: chartBackgroundColor,

          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: data.yInterval,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                strokeWidth: 1,
              );
            },
          ),

          borderData: FlBorderData(show: false),

          // 차트의 축과 레이블을 설정
          titlesData: ExchangeChartAxisHelper.buildTitles(
            history: history,
            period: period,
            xLabelIndexes: data.xLabelIndexes,
            yInterval: data.yInterval,
            colorScheme: colorScheme,
          ),
          lineTouchData: ExchangeChartTooltip.buildTouchData(
            history: history,
            colorScheme: colorScheme,
            onTouch: _touchController.handleTouch,
          ),

          // 차트 데이터 라인
          showingTooltipIndicators: ExchangeChartTooltip.showingTooltips(
            selectedSpot,
          ),
          lineBarsData: [
            LineChartBarData(
              spots: data.spots,
              showingIndicators: ExchangeChartTooltip.showingPoints(
                selectedSpot,
              ),
              isCurved: true,
              curveSmoothness: 0.25,

              color: colorScheme.primary,

              barWidth: 2,
              isStrokeCapRound: true,

              dotData: const FlDotData(show: false),

              belowBarData: BarAreaData(
                show: true,

                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,

                  colors: [
                    colorScheme.primary.withValues(alpha: 0.25),
                    colorScheme.primary.withValues(alpha: 0.10),
                    colorScheme.primary.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
