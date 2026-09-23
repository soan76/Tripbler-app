import 'package:fl_chart/fl_chart.dart';

import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_axis_helper.dart';

/// 렌더링에 필요한 수치 계산 결과. 빈 데이터는 화면에서 별도로 처리한다.
class ExchangeChartData {
  const ExchangeChartData({
    required this.spots,
    required this.minRate,
    required this.maxRate,
    required this.yInterval,
    required this.minY,
    required this.maxY,
    required this.xLabelIndexes,
  });
  final List<FlSpot> spots;
  final double minRate;
  final double maxRate;
  final double yInterval;
  final double minY;
  final double maxY;
  final Set<int> xLabelIndexes;
}

class ExchangeChartDataCalculator {
  static ExchangeChartData calculate(
    List<ExchangeRateHistoryModel> history,
    ChartPeriod period,
  ) {
    assert(history.isNotEmpty);
    final spots = <FlSpot>[
      for (var i = 0; i < history.length; i++)
        FlSpot(i.toDouble(), history[i].rate),
    ];
    final minRate = history.map((e) => e.rate).reduce((a, b) => a < b ? a : b);
    final maxRate = history.map((e) => e.rate).reduce((a, b) => a > b ? a : b);
    final interval = ExchangeChartAxisHelper.yInterval(minRate, maxRate);
    return ExchangeChartData(
      spots: spots,
      minRate: minRate,
      maxRate: maxRate,
      yInterval: interval,
      minY: (minRate / interval).floor() * interval - interval,
      maxY: (maxRate / interval).ceil() * interval + interval,
      xLabelIndexes: buildXLabelIndexes(history.length, period),
    );
  }

  // 현재 선택된 기간에 따라 X축에 표시할 날짜 인덱스를 계산한다.
  // 첫 번째와 마지막 데이터는 항상 표시한다.
  static Set<int> buildXLabelIndexes(int length, ChartPeriod period) {
    if (length <= 0) {
      return const <int>{};
    }

    final lastIndex = length - 1;
    final interval = ExchangeChartAxisHelper.xLabelInterval(period);

    final indexes = <int>{0, lastIndex};

    if (interval <= 0) {
      return indexes;
    }

    // 마지막 날짜 바로 옆에 중간 라벨이 생겨
    // 서로 겹치는 것을 방지한다.
    final minimumLastGap = interval > 2 ? (interval / 2).ceil() : 1;

    for (int index = interval; index < lastIndex; index += interval) {
      if (lastIndex - index < minimumLastGap) {
        continue;
      }

      indexes.add(index);
    }

    return indexes;
  }

  static bool isValidSpot(
    LineBarSpot spot,
    List<ExchangeRateHistoryModel> history,
  ) {
    final index = spot.spotIndex;
    return spot.barIndex == 0 &&
        index >= 0 &&
        index < history.length &&
        spot.x == index.toDouble() &&
        spot.y == history[index].rate;
  }
}
