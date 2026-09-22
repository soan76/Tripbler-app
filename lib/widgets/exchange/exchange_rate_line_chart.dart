import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/exchange_rate_history_model.dart';

// 환율 라인 차트 위젯
class ExchangeRateLineChart extends StatelessWidget { 
  final List<ExchangeRateHistoryModel> history;
  final ChartPeriod period;

  const ExchangeRateLineChart({
    super.key, 
    required this.history,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
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

    // 차트에 표시할 데이터 포인트를 생성
    final spots = <FlSpot>[];

    for (int i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), history[i].rate));
    }

    // 차트의 Y축 최소값과 최대값을 계산
    final minRate = history.map((e) => e.rate).reduce((a, b) => a < b ? a : b);

    final maxRate = history.map((e) => e.rate).reduce((a, b) => a > b ? a : b);

    final yInterval = _getYInterval(minRate, maxRate);

    final minY = (minRate / yInterval).floor() * yInterval - yInterval;

    final maxY = (maxRate / yInterval).ceil() * yInterval + yInterval;

    final xLabelIndexes = _buildXLabelIndexes(history.length);

    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (history.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,

          // 라이트: 흰색 / 다크: #444440
          backgroundColor: chartBackgroundColor,

          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                strokeWidth: 1,
              );
            },
          ),

          borderData: FlBorderData(show: false),

          // 차트의 축과 레이블을 설정
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),

            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),

            // Y축 레이블
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,

                // Y축 숫자 영역을 줄여 실제 그래프가 사용할 수 있는 폭을 확보한다.
                reservedSize: 56,

                interval: yInterval,

                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 2, right: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatYAxisRate(value, yInterval),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // X축 레이블
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.round();

                  // 정수 데이터 포인트가 아니거나
                  // 실제 데이터 범위를 벗어나면 표시하지 않는다.
                  if ((value - index).abs() > 0.001 ||
                      index < 0 ||
                      index >= history.length) {
                    return const SizedBox.shrink();
                  }

                  // 현재 기간에서 표시 대상으로 선택되지 않은 날짜는 숨긴다.
                  if (!xLabelIndexes.contains(index)) {
                    return const SizedBox.shrink();
                  }

                  final date = history[index].date;
                  final text = _formatBottomDate(date);

                  final isFirst = index == 0;
                  final isLast = index == history.length - 1;

                  double horizontalOffset = 0;

                  if (isFirst) {
                    horizontalOffset = 8;
                  } else if (isLast) {
                    horizontalOffset = -8;
                  }

                  return Transform.translate(
                    offset: Offset(horizontalOffset, 0),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        text,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 차트 터치 이벤트와 툴팁
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,

            touchTooltipData: LineTouchTooltipData(
              tooltipBorderRadius: BorderRadius.circular(12),

              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),

              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final index = spot.x.toInt();

                  final item = history[index];

                  final dateText = DateFormat('yyyy.MM.dd').format(item.date);

                  final rateText = _formatRate(item.rate);

                  return LineTooltipItem(
                    '$dateText\n'
                    '${item.baseCurrencyCode}/'
                    '${item.targetCurrencyCode}: '
                    '$rateText',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),

            getTouchedSpotIndicator: (barData, spotIndexes) {
              return spotIndexes.map((index) {
                return TouchedSpotIndicatorData(
                  FlLine(
                    color: colorScheme.primary.withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),

                  FlDotData(
                    show: true,

                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: chartBackgroundColor,
                        strokeWidth: 2,
                        strokeColor: colorScheme.primary,
                      );
                    },
                  ),
                );
              }).toList();
            },
          ),

          // 차트 데이터 라인
          lineBarsData: [
            LineChartBarData(
              spots: spots,
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

  // 데이터 범위에 맞는 Y축 간격을 계산한다.
  // 사람이 읽기 쉬운 1 / 2 / 5 / 10 단위의 눈금을 사용한다.
  double _getYInterval(double minY, double maxY) {
    final diff = (maxY - minY).abs();

    if (diff == 0) {
      final fallback = minY.abs() * 0.01;

      if (fallback == 0) {
        return 1;
      }

      return _getNiceInterval(fallback);
    }

    // 차트에 약 4개의 주요 Y축 구간이 나타나도록 한다.
    return _getNiceInterval(diff / 4);
  }

  double _getNiceInterval(double rawInterval) {
    if (!rawInterval.isFinite || rawInterval <= 0) {
      return 1;
    }

    final exponent = (math.log(rawInterval) / math.ln10).floor();

    final magnitude = math.pow(10, exponent).toDouble();

    final normalized = rawInterval / magnitude;

    final double niceFactor;

    if (normalized <= 1) {
      niceFactor = 1;
    } else if (normalized <= 2) {
      niceFactor = 2;
    } else if (normalized <= 5) {
      niceFactor = 5;
    } else {
      niceFactor = 10;
    }

    return niceFactor * magnitude;
  }

  // 현재 선택된 기간에 따라 X축에 표시할 날짜 인덱스를 계산한다.
  // 첫 번째와 마지막 데이터는 항상 표시한다.
  Set<int> _buildXLabelIndexes(int length) {
    if (length <= 0) {
      return const <int>{};
    }

    final lastIndex = length - 1;
    final interval = period.xAxisLabelInterval;

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

  // X축 레이블을 포맷하는 메서드
  // 현재 선택된 차트 기간에 맞게 X축 날짜를 포맷한다.
  String _formatBottomDate(DateTime date) {
    switch (period) {
      case ChartPeriod.sevenDays:
      case ChartPeriod.oneMonth:
      case ChartPeriod.threeMonths:
        return DateFormat('M/d').format(date);

      case ChartPeriod.sixMonths:
      case ChartPeriod.oneYear:
        return DateFormat('M월').format(date);

      case ChartPeriod.twoYears:
        return DateFormat('yy/MM').format(date);

      case ChartPeriod.fiveYears:
        return DateFormat('yyyy').format(date);
    }
  }

  // Y축 눈금 간격에 맞춰 필요한 소수 자릿수를 자동으로 결정한다.
  // 서로 다른 눈금값이 반올림되어 같은 문자열로 표시되는 것을 방지한다.
  String _formatYAxisRate(double value, double interval) {
    final absoluteInterval = interval.abs();

    if (absoluteInterval == 0) {
      return _formatRate(value);
    }

    int decimalPlaces = 0;
    double scaledInterval = absoluteInterval;

    while (scaledInterval < 1 && decimalPlaces < 10) {
      scaledInterval *= 10;
      decimalPlaces++;
    }

    return value
        .toStringAsFixed(decimalPlaces)
        .replaceAll(RegExp(r'\.?0+$'), '');
  }

  // Y축 레이블을 포맷하는 메서드
  String _formatRate(double value) {
    if (value == 0) {
      return '0';
    }

    if (value.abs() >= 100) {
      return value.toStringAsFixed(2);
    }

    if (value.abs() >= 1) {
      return value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    return value.toStringAsFixed(6).replaceAll(RegExp(r'\.?0+$'), '');
  }
}
