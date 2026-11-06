import '../../models/chart_point.dart';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/exchange_rate_history_model.dart';

/// 축 간격, 라벨 배치와 날짜/숫자 표시 규칙.
class ExchangeChartAxisHelper {
  static const _yLabelFontSize = 11.0;

  // Y축 라벨 바깥 여백. 그래프 쪽 여백이 라벨과 그래프 사이의 간격이다.
  // 카드가 화면 폭을 꽉 채우므로 왼쪽 여백은 곧 화면 가장자리까지의 거리다.
  static const _yLabelStartGap = 4.0;
  static const _yLabelEndGap = 4.0;

  // 작은 화면에서 Y축 칸이 그래프 자리를 지나치게 차지하지 않게 하는 상한.
  // 이보다 긴 라벨은 잘리지 않게 글자를 줄인다.
  static const _yAxisMaxWidthRatio = 0.25;

  // 눈금이 이보다 많을 만큼 간격이 비정상이면 양 끝 라벨만 잰다.
  static const _yTickMeasureLimit = 64;

  /// Y축 칸의 폭. 지금 화면에 그려질 눈금 라벨 중 가장 긴 것에 맞춰 그래프 폭을 최대로 쓴다.
  /// 방향이나 기간이 바뀌면 칸 폭도 달라질 수 있지만, 라벨과 그래프의 간격은 그대로다.
  static double yAxisReservedWidth({
    required double minY,
    required double maxY,
    required double yInterval,
    required double chartWidth,
    required TextScaler textScaler,
    TextStyle baseStyle = const TextStyle(),
  }) {
    // 라벨은 화면의 기본 글자 스타일(글꼴, 자간)을 물려받으므로 같은 스타일로 잰다.
    final labelStyle = baseStyle.merge(
      const TextStyle(fontSize: _yLabelFontSize),
    );
    final labels = {
      for (final value in _yTickValues(minY, maxY, yInterval))
        formatYAxisRate(value, yInterval),
    };

    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }

    final width = widest.ceilToDouble() + _yLabelStartGap + _yLabelEndGap;
    return math.min(width, chartWidth * _yAxisMaxWidthRatio);
  }

  // fl_chart가 라벨을 그리는 값: 양 끝과 그 사이의 눈금 간격 배수.
  static List<double> _yTickValues(double minY, double maxY, double interval) {
    final values = [minY, maxY];
    if (!minY.isFinite ||
        !maxY.isFinite ||
        !interval.isFinite ||
        interval <= 0) {
      return values;
    }
    final first = (minY / interval).ceil();
    final last = (maxY / interval).floor();
    if (last - first >= _yTickMeasureLimit) return values;
    for (var step = first; step <= last; step++) {
      values.add(step * interval);
    }
    return values;
  }

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
    // NaN·무한대는 지수 계산(log().floor())에서 예외가 나므로 그대로 표시한다.
    if (!value.isFinite) return value.toString();

    final absoluteInterval = interval.abs();

    if (absoluteInterval == 0) {
      return _groupThousands(formatRate(value));
    }

    // 반전된 코인 환율처럼 눈금이 아주 작으면 축 폭을 넘지 않게 지수로 표시한다.
    if (absoluteInterval < 1e-6) {
      if (value == 0) return '0';
      final digits = (_exponent(value.abs()) - _exponent(absoluteInterval))
          .clamp(0, 6);
      return value.toStringAsExponential(digits);
    }

    int decimalPlaces = 0;
    double scaledInterval = absoluteInterval;

    while (scaledInterval < 1 && decimalPlaces < 10) {
      scaledInterval *= 10;
      decimalPlaces++;
    }

    final formatted = value.toStringAsFixed(decimalPlaces);
    // 정수의 끝자리 0은 보존하고 소수부의 불필요한 0만 제거한다.
    return _groupThousands(
      formatted.contains('.')
          ? formatted.replaceAll(RegExp(r'\.?0+$'), '')
          : formatted,
    );
  }

  // 금액과 같은 천 단위 쉼표를 정수부에만 넣는다. 소수부와 지수 표기에는 넣지 않는다.
  static String _groupThousands(String number) => number.replaceFirstMapped(
    RegExp(r'^-?\d+'),
    (match) => match[0]!.replaceAll(RegExp(r'(?<=\d)(?=(\d{3})+$)'), ','),
  );

  // Y축 레이블을 포맷하는 메서드
  static String formatRate(double value) {
    if (!value.isFinite) return value.toString();

    if (value == 0) {
      return '0';
    }

    if (value.abs() >= 100) {
      return value.toStringAsFixed(2);
    }

    if (value.abs() >= 1) {
      return value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    // 1 미만은 소수 6자리 이상, 유효숫자 4자리 이상으로 표시한다(최대 20자리).
    // 반전된 코인 환율(예: 4.1e-6)이 6자리 고정으로 뭉개지지 않게 한다.
    final decimals = math.max(6, 3 - _exponent(value.abs()));
    return value
        .toStringAsFixed(math.min(decimals, 20))
        .replaceAll(RegExp(r'\.?0+$'), '');
  }

  static int _exponent(double value) => (math.log(value) / math.ln10).floor();

  static String formatTooltipDate(DateTime date, {bool includesTime = false}) =>
      DateFormat(includesTime ? 'yyyy.MM.dd HH:mm' : 'yyyy.MM.dd').format(date);

  static int xLabelInterval(ChartPeriod period) => period.xAxisLabelInterval;

  static FlTitlesData buildTitles({
    required List<ChartPoint> history,
    required ChartPeriod period,
    required Set<int> xLabelIndexes,
    required double yInterval,
    required double yAxisWidth,
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
          reservedSize: yAxisWidth,

          interval: yInterval,

          getTitlesWidget: (value, meta) {
            // 그래프 쪽에 붙여 라벨 길이와 상관없이 그래프와의 간격을 같게 한다.
            return Padding(
              padding: const EdgeInsets.only(
                left: _yLabelStartGap,
                right: _yLabelEndGap,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatYAxisRate(value, yInterval),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: _yLabelFontSize,
                      color: colorScheme.onSurfaceVariant,
                    ),
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
