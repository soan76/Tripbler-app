import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/exchange_rate_history_model.dart';
import 'exchange_chart_axis_helper.dart';
import 'exchange_chart_data_calculator.dart';

/// 툴팁과 선택 점/세로 가이드선의 표시 스타일.
class ExchangeChartTooltip {
  static LineTouchData buildTouchData({
    required List<ExchangeRateHistoryModel> history,
    required ColorScheme colorScheme,
    required void Function(FlTouchEvent, LineTouchResponse?) onTouch,
  }) {
    return LineTouchData(
      handleBuiltInTouches: false,
      touchCallback: onTouch,

      touchTooltipData: LineTouchTooltipData(
        tooltipBorderRadius: BorderRadius.circular(12),

        tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            if (!ExchangeChartDataCalculator.isValidSpot(spot, history)) {
              return null;
            }
            final index = spot.x.toInt();

            final item = history[index];

            final dateText = ExchangeChartAxisHelper.formatTooltipDate(
              item.date,
            );

            final rateText = ExchangeChartAxisHelper.formatRate(item.rate);

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
                  color: colorScheme.surface,
                  strokeWidth: 2,
                  strokeColor: colorScheme.primary,
                );
              },
            ),
          );
        }).toList();
      },
    );
  }

  static List<ShowingTooltipIndicators> showingTooltips(LineBarSpot? spot) => [
    if (spot != null) ShowingTooltipIndicators([spot]),
  ];
  static List<int> showingPoints(LineBarSpot? spot) => [
    if (spot != null) spot.spotIndex,
  ];
}
