import '../../models/chart_point.dart';
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_data_calculator.dart';

/// 포인터 수명과 선택/3초 유지 상태를 관리한다. 데이터 변경은 포인터를 초기화하지 않는다.
class ExchangeChartTouchController extends ChangeNotifier {
  ExchangeChartTouchController({
    required List<ChartPoint> history,
    required ChartPeriod period,
  }) : _history = List.of(history),
       _period = period;
  List<ChartPoint> _history;
  ChartPeriod _period;
  LineBarSpot? _selectedSpot;
  Timer? _tooltipTimer;
  final Set<int> _activePointers = {};
  int _timerGeneration = 0;
  bool _disposed = false;
  LineBarSpot? get selectedSpot =>
      _selectedSpot != null && _isValidSpot(_selectedSpot!)
      ? _selectedSpot
      : null;
  bool _isValidSpot(LineBarSpot spot) =>
      ExchangeChartDataCalculator.isValidSpot(spot, _history);

  /// 지금 선택된 기록의 날짜.
  DateTime? get selectedDate {
    final spot = selectedSpot;
    return spot == null ? null : _history[spot.spotIndex].date;
  }

  /// [keepSelectedDate]이면 같은 날짜(없으면 가장 가까운 기록)의 선택을 유지한다.
  /// 같은 차트의 방향만 바뀐 경우에 쓴다. 다른 데이터로 바뀌면 선택을 지운다.
  void updateData(
    List<ChartPoint> history,
    ChartPeriod period, {
    bool keepSelectedDate = false,
  }) {
    if (_disposed || (_period == period && listEquals(_history, history))) {
      return;
    }
    final date = keepSelectedDate ? selectedDate : null;
    final previous = _selectedSpot;
    _history = List.of(history);
    _period = period;
    final index = date == null
        ? null
        : ExchangeChartDataCalculator.nearestIndex(_history, date);
    if (index == null || previous == null) {
      clearSelection();
      return;
    }
    // LineBarSpot은 위치를 선 데이터에서 찾으므로 새 기록으로 만든 선을 넘긴다.
    final bar = previous.bar.copyWith(
      spots: [
        for (var i = 0; i < _history.length; i++)
          FlSpot(i.toDouble(), _history[i].rate),
      ],
    );
    _selectedSpot = LineBarSpot(bar, previous.barIndex, bar.spots[index]);
    notifyListeners();
  }

  void clearSelection() {
    if (_disposed) return;
    _cancelTooltipTimer();
    if (_selectedSpot == null) return;
    _selectedSpot = null;
    notifyListeners();
  }

  void onPointerDown(PointerDownEvent event) {
    if (_disposed) return;
    _activePointers.add(event.pointer);
    _cancelTooltipTimer();
  }

  void _cancelTooltipTimer() {
    _tooltipTimer?.cancel();
    _tooltipTimer = null;
    _timerGeneration++;
  }

  void _scheduleTooltipHide() {
    // 중복 종료 이벤트는 최초 손을 뗀 시점의 만료 시간을 연장하지 않는다.
    if (_activePointers.isNotEmpty ||
        _selectedSpot == null ||
        _tooltipTimer != null) {
      return;
    }
    final generation = _timerGeneration;
    _tooltipTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed || generation != _timerGeneration) return;
      _tooltipTimer = null;
      clearSelection();
    });
  }

  void onPointerEnd(PointerEvent event) {
    if (_disposed) return;
    _activePointers.remove(event.pointer);
    _scheduleTooltipHide();
  }

  void handleTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (_disposed) return;
    final ended =
        event is FlTapUpEvent ||
        event is FlPanEndEvent ||
        event is FlPanCancelEvent ||
        event is FlTapCancelEvent ||
        event is FlLongPressEnd ||
        event is FlPointerExitEvent;

    if (ended) {
      // 종료 이벤트에 포인트 정보가 없어도 마지막 선택을 유지한다.
      _scheduleTooltipHide();
      return;
    }

    final hovering =
        event is FlPointerHoverEvent || event is FlPointerEnterEvent;
    if (hovering && _tooltipTimer != null) return;
    final selecting =
        event is FlTapDownEvent ||
        event is FlPanDownEvent ||
        event is FlPanStartEvent ||
        event is FlPanUpdateEvent ||
        event is FlLongPressStart ||
        event is FlLongPressMoveUpdate ||
        hovering;
    if (!selecting) return;

    // 다시 터치하거나 이동하는 동안 이전 타이머가 선택을 지우지 않도록 한다.
    _cancelTooltipTimer();
    final touchedSpots = response?.lineBarSpots;
    if (touchedSpots == null || touchedSpots.isEmpty) return;
    if (!_isValidSpot(touchedSpots.first)) return;
    _selectedSpot = touchedSpots.first;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTooltipTimer();
    super.dispose();
  }
}
