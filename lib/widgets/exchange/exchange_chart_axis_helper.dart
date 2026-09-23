import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/exchange_rate_history_model.dart';

/// 축 간격, 라벨 배치와 날짜/숫자 표시 규칙.
class ExchangeChartAxisHelper {
  // 데이터 범위에 맞는 Y축 간격을 계산한다.
  // 읽기 쉬운 1 / 2 / 5 / 10 단위의 눈금을 사용한다.
  static double yInterval(double minY, double maxY) {
    final diff = (maxY - minY).abs();

    if (diff == 0) {
      final fallback = minY.abs() * 0.01;

      if (fallback == 0) {
        return 1;
      }

      return niceInterval(fallback);
    }

    // 차트에 약 4개의 주요 Y축 구간이 나타나도록 한다.
    return niceInterval(diff / 4);
  }

  static double niceInterval(double rawInterval) {
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

  // X축 레이블을 포맷하는 메서드
  // 현재 선택된 차트 기간에 맞게 X축 날짜를 포맷한다.
  static String formatBottomDate(DateTime date, ChartPeriod period) {
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
  static String formatYAxisRate(double value, double interval) {
    final absoluteInterval = interval.abs();

    if (absoluteInterval == 0) {
      return formatRate(value);
    }

    int decimalPlaces = 0;
    double scaledInterval = absoluteInterval;

    while (scaledInterval < 1 && decimalPlaces < 10) {
      scaledInterval *= 10;
      decimalPlaces++;
    }

    final formatted = value.toStringAsFixed(decimalPlaces);
    // 정수의 끝자리 0은 보존하고 소수부의 불필요한 0만 제거한다.
    return formatted.contains('.')
        ? formatted.replaceAll(RegExp(r'\.?0+$'), '')
        : formatted;
  }

  // Y축 레이블을 포맷하는 메서드
  static String formatRate(double value) {
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

  static String formatTooltipDate(DateTime date) =>
      DateFormat('yyyy.MM.dd').format(date);

  static int xLabelInterval(ChartPeriod period) => period.xAxisLabelInterval;

  static FlTitlesData buildTitles({
    required List<ExchangeRateHistoryModel> history,
    required ChartPeriod period,
    required Set<int> xLabelIndexes,
    required double yInterval,
    required ColorScheme colorScheme,
  }) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),

      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),

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
                  formatYAxisRate(value, yInterval),
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
            final text = formatBottomDate(date, period);

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
    );
  }
}
