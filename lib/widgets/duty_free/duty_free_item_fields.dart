import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/duty_free/duty_free_item.dart';
import '../schedule/schedule_sheet_parts.dart';

/// 물건 카드의 수량 칸과, 주류·향수면 용량 칸. 값과 오류는 카드가 가진다.
class DutyFreeQuantityFields extends StatelessWidget {
  const DutyFreeQuantityFields({
    super.key,
    required this.category,
    required this.quantity,
    required this.volume,
    required this.quantityError,
    required this.volumeError,
    required this.onQuantityChanged,
    required this.onVolumeChanged,
  });

  final DutyFreeCategory category;
  final TextEditingController quantity;
  final TextEditingController volume;
  final bool quantityError;
  final bool volumeError;
  final VoidCallback onQuantityChanged;
  final VoidCallback onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final liquor = category == DutyFreeCategory.liquor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ScheduleFieldLabel(
            label: category.quantityLabel,
            child: TextField(
              key: const ValueKey('duty-free-quantity'),
              controller: quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                suffixText: switch (category) {
                  DutyFreeCategory.liquor => '병',
                  DutyFreeCategory.tobacco => '갑',
                  _ => '개',
                },
                errorText: quantityError ? '수량을 1 이상의 정수로 입력해 주세요' : null,
                errorMaxLines: 2,
              ),
              onChanged: (_) => onQuantityChanged(),
            ),
          ),
        ),
        if (category.hasVolume) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ScheduleFieldLabel(
              label: liquor ? '병당 용량(L)' : '개당 용량(mL)',
              child: TextField(
                key: const ValueKey('duty-free-volume'),
                controller: volume,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  suffixText: liquor ? 'L / 병' : 'mL / 개',
                  errorText: volumeError ? '용량을 0보다 큰 숫자로 입력해 주세요' : null,
                  errorMaxLines: 2,
                ),
                onChanged: (_) => onVolumeChanged(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 물건 카드의 금액 칸, 통화 고르기, 달러 환산 안내.
class DutyFreeAmountField extends StatelessWidget {
  const DutyFreeAmountField({
    super.key,
    required this.amount,
    required this.amountError,
    required this.currency,
    required this.usdHint,
    required this.onAmountChanged,
    required this.onCurrencyChanged,
  });

  final TextEditingController amount;
  final bool amountError;
  final String currency;

  /// 금액 아래 보일 달러 환산 글자.
  final String usdHint;
  final VoidCallback onAmountChanged;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ScheduleFieldLabel(
                label: '금액(합계)',
                child: TextField(
                  key: const ValueKey('duty-free-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    errorText: amountError ? '금액을 0보다 큰 숫자로 입력해 주세요' : null,
                    errorMaxLines: 2,
                  ),
                  onChanged: (_) => onAmountChanged(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              key: const ValueKey('duty-free-currency'),
              value: currency,
              items: [
                for (final c in DutyFreeItem.currencies)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) {
                if (c != null) onCurrencyChanged(c);
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          usdHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
