import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_data_calculator.dart';

/// 포인터 수명과 선택/3초 유지 상태를 관리한다. 데이터 변경은 포인터를 초기화하지 않는다.
class ExchangeChartTouchController extends ChangeNotifier {
  ExchangeChartTouchController({
    required List<ExchangeRateHistoryModel> history,
    required ChartPeriod period,
  }) : _history = List.of(history),
       _period = period;
  List<ExchangeRateHistoryModel> _history;
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

  void updateData(List<ExchangeRateHistoryModel> history, ChartPeriod period) {
    if (_disposed || (_period == period && listEquals(_history, history))) {
      return;
    }
    _history = List.of(history);
    _period = period;
    clearSelection();
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
