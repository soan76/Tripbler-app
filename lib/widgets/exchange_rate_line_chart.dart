import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/exchange_rate_history_model.dart';

class ExchangeRateLineChart extends StatelessWidget {
  final List<ExchangeRateHistoryModel> history;

  const ExchangeRateLineChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Container(
        height: 280,
        alignment: Alignment.center,
        child: const Text(
          '표시할 환율 데이터가 없습니다.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), history[i].rate));
    }

    final minY = history.map((e) => e.rate).reduce((a, b) => a < b ? a : b);
    final maxY = history.map((e) => e.rate).reduce((a, b) => a > b ? a : b);

    final yPadding = (maxY - minY) * 0.15 == 0 ? 1.0 : (maxY - minY) * 0.15;

    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (history.length - 1).toDouble(),
          minY: minY - yPadding,
          maxY: maxY + yPadding,

          backgroundColor: Colors.white,

          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _getYInterval(minY, maxY),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withOpacity(0.18),
                strokeWidth: 1,
              );
            },
          ),

          borderData: FlBorderData(show: false),

          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),

            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: _getYInterval(minY, maxY),
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatRate(value),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  );
                },
              ),
            ),

            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _getXInterval(history.length),
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();

                  if (index < 0 || index >= history.length) {
                    return const SizedBox.shrink();
                  }

                  final date = history[index].date;
                  final text = _formatBottomDate(date, history.length);

                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

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
                    '$dateText\n${item.baseCurrencyCode}/${item.targetCurrencyCode}: $rateText',
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
                    color: Colors.blue.withOpacity(0.4),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: Colors.blue,
                      );
                    },
                  ),
                );
              }).toList();
            },
          ),

          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: Colors.blue,
              barWidth: 2,
              isStrokeCapRound: true,

              dotData: const FlDotData(show: false),

              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.blue.withOpacity(0.25),
                    Colors.blue.withOpacity(0.10),
                    Colors.blue.withOpacity(0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getYInterval(double minY, double maxY) {
    final diff = maxY - minY;

    if (diff <= 1) return 0.2;
    if (diff <= 5) return 1;
    if (diff <= 20) return 5;
    if (diff <= 100) return 20;
    return diff / 4;
  }

  double _getXInterval(int length) {
    if (length <= 7) return 1;
    if (length <= 31) return 5;
    if (length <= 90) return 15;
    if (length <= 180) return 30;
    if (length <= 365) return 60;
    return 120;
  }

  String _formatBottomDate(DateTime date, int length) {
    if (length <= 31) {
      return DateFormat('M/d').format(date);
    } else if (length <= 365) {
      return DateFormat('M월').format(date);
    } else {
      return DateFormat('yy/MM').format(date);
    }
  }

  String _formatRate(double value) {
    if (value == 0) return '0';

    if (value.abs() >= 100) {
      return value.toStringAsFixed(2);
    }

    if (value.abs() >= 1) {
      return value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    return value.toStringAsFixed(4).replaceAll(RegExp(r'\.?0+$'), '');
  }
}
