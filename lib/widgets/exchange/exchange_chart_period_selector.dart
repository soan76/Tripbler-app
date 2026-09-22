import 'package:flutter/material.dart';

import '../../models/exchange_rate_history_model.dart';

/// 환율 차트의 조회 기간을 선택하는 위젯.
///
/// 지원 기간:
/// 7D / 1M / 3M / 6M / 1Y / 2Y / 5Y
class ExchangeChartPeriodSelector extends StatelessWidget {
  final ChartPeriod selectedPeriod;
  final ValueChanged<ChartPeriod> onPeriodChanged;

  const ExchangeChartPeriodSelector({
    super.key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: ChartPeriod.values.map((period) {
        final isSelected = selectedPeriod == period;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (selectedPeriod == period) {
                  return;
                }

                onPeriodChanged(period);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  period.shortLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
