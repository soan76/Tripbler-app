import '../../models/chart_point.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_axis_helper.dart';
import 'exchange_chart_data_calculator.dart';
import 'exchange_chart_tooltip.dart';
import 'exchange_chart_touch_controller.dart';

// 환율 라인 차트 위젯
class ExchangeRateLineChart extends StatefulWidget {
  final List<ChartPoint> history;
  final ChartPeriod period;
  final int? maxXAxisLabels;

  /// false이면 데이터가 바뀔 때 기본 전환 없이 새 그래프를 바로 그린다.
  final bool animateDataChange;

  /// false이면 터치와 툴팁을 끄고, 떠 있던 선택도 지운다.
  final bool interactive;

  /// false이면 선택해도 툴팁을 그리지 않는다. 마커와 세로 안내선은 그대로다.
  /// 날짜와 값을 다른 자리에 보여 주는 화면에서만 끈다.
  final bool showTooltip;

  /// 선택된 기록의 날짜가 바뀔 때. 선택이 풀리면 null을 알린다.
  final ValueChanged<DateTime?>? onSelectionChanged;

  /// 이 값이 바뀌며 기록이 바뀌면 같은 날짜의 선택을 유지한다(같은 차트의 방향 변경).
  final Object? selectionKey;

  const ExchangeRateLineChart({
    super.key,
    required this.history,
    required this.period,
    this.maxXAxisLabels,
    this.animateDataChange = true,
    this.interactive = true,
    this.showTooltip = true,
    this.onSelectionChanged,
    this.selectionKey,
  });

  @override
  State<ExchangeRateLineChart> createState() => _ExchangeRateLineChartState();
}

class _ExchangeRateLineChartState extends State<ExchangeRateLineChart> {
  late final ExchangeChartTouchController _touchController;
  List<ChartPoint> get history => widget.history;
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

  // 마지막으로 바깥에 알린 선택 날짜.
  DateTime? _reportedDate;

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {});
    _reportSelection();
  }

  void _reportSelection() {
    final date = _touchController.selectedDate;
    if (date == _reportedDate) return;
    _reportedDate = date;
    final report = widget.onSelectionChanged;
    if (report == null) return;
    // 빌드 중(데이터 변경, 삭제 모드)에는 바깥을 다시 그리게 할 수 없어 프레임 뒤에 알린다.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && date == _reportedDate) report(date);
      });
    } else {
      report(date);
    }
  }

  @override
  void didUpdateWidget(covariant ExchangeRateLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _touchController.updateData(
      history,
      period,
      keepSelectedDate: oldWidget.selectionKey != widget.selectionKey,
    );
    if (oldWidget.interactive && !widget.interactive) {
      _touchController.clearSelection();
    }
  }

  @override
  void dispose() {
    // 분기가 바뀌어 그래프가 사라지면 바깥의 선택 표시도 함께 푼다.
    final report = widget.onSelectionChanged;
    if (report != null && _reportedDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => report(null));
    }
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

    final data = ExchangeChartDataCalculator.calculate(
      history,
      period,
      maxXAxisLabels: widget.maxXAxisLabels,
    );
    final selectedSpot = _touchController.selectedSpot;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: 300,
        child: _buildLineChart(
          context,
          data,
          selectedSpot,
          ExchangeChartAxisHelper.yAxisReservedWidth(
            minY: data.minY,
            maxY: data.maxY,
            yInterval: data.yInterval,
            chartWidth: constraints.maxWidth,
            textScaler: MediaQuery.textScalerOf(context),
            baseStyle: DefaultTextStyle.of(context).style,
          ),
        ),
      ),
    );
  }

  Widget _buildLineChart(
    BuildContext context,
    ExchangeChartData data,
    LineBarSpot? selectedSpot,
    double yAxisWidth,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final chartBackgroundColor = colorScheme.surface;
    final bar = _buildBar(colorScheme, data, selectedSpot);

    return LineChart(
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
          yAxisWidth: yAxisWidth,
          colorScheme: colorScheme,
        ),
        lineTouchData: ExchangeChartTooltip.buildTouchData(
          history: history,
          colorScheme: colorScheme,
          onTouch: _touchController.handleTouch,
        ).copyWith(enabled: widget.interactive),

        // 차트 데이터 라인
        // 마커와 툴팁이 지금 그리는 선을 가리키게 한다(방향이 바뀌면 선도 새로 만들어진다).
        showingTooltipIndicators: ExchangeChartTooltip.showingTooltips(
          selectedSpot == null || !widget.showTooltip
              ? null
              : LineBarSpot(bar, 0, bar.spots[selectedSpot.spotIndex]),
        ),
        lineBarsData: [bar],
      ),
      // fl_chart 기본값과 같은 시간이다.
      duration: widget.animateDataChange
          ? const Duration(milliseconds: 150)
          : Duration.zero,
    );
  }

  LineChartBarData _buildBar(
    ColorScheme colorScheme,
    ExchangeChartData data,
    LineBarSpot? selectedSpot,
  ) {
    return LineChartBarData(
      spots: data.spots,
      showingIndicators: ExchangeChartTooltip.showingPoints(selectedSpot),
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
    );
  }
}
