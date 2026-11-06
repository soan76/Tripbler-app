import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/exchange/display_currency.dart';
import '../../providers/settings_provider.dart';
import 'amount_input_field.dart';
import 'currency_icon.dart';

// 통화 행 위젯
class CurrencyRow extends StatelessWidget {
  final DisplayCurrency currency;
  final bool isBase;
  final double? amount;
  final double? rate;
  final VoidCallback onCurrencyTap;
  final VoidCallback? onGraphTap;
  final String? status;
  final ValueChanged<double>? onAmountChanged;
  final VoidCallback? onAmountTap;

  const CurrencyRow({
    super.key,
    required this.currency,
    required this.isBase,
    required this.amount,
    required this.rate,
    required this.onCurrencyTap,
    this.onGraphTap,
    this.status,
    this.onAmountChanged,
    this.onAmountTap,
  });

  // 통화 행 위젯을 빌드하는 메서드
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 설정 화면에서 선택한 자릿수 설정을 가져옴
    final decimalPlaces = context.watch<SettingsProvider>().decimalPlaces;

    return Container(
      // 평소 높이는 72dp다. 코인 행의 상태 문구는 글자를 크게 키우면 72dp를 넘으므로 잘리지 않게 늘린다.
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        // 현재 선택된 통화는 강조 배경,
        // 일반 통화는 기본 화면 배경 사용
        color: isBase ? colorScheme.primaryContainer : colorScheme.surface,

        // 현재 라이트/다크 테마에 맞는 구분선
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onCurrencyTap,
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                CurrencyIcon(currency: currency),

                const SizedBox(width: 8),

                // 통화 코드
                Text(
                  currency.code,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isBase
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),

                const SizedBox(width: 4),

                // 통화 선택 화살표
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 22,
                  color: isBase
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 환율 금액 영역
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountInputField(
                  amount: amount ?? 0,
                  unavailable: amount == null,

                  // 현재 선택된 통화 여부
                  isBase: isBase,

                  // SettingsProvider에서 가져온 자릿수 설정을 전달
                  decimalPlaces: decimalPlaces,

                  // 입력 영역을 터치하면 해당 통화를 선택
                  onTap: onAmountTap,

                  // 금액 변경 시 환율 재계산
                  onChanged: onAmountChanged ?? (_) {},
                ),
                if (status != null)
                  Tooltip(
                    message: status!,
                    child: Text(
                      status!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 행마다 반복되는 보조 동작이라 강조색을 쓰지 않는다.
          if (onGraphTap != null)
            IconButton(
              onPressed: onGraphTap,
              icon: Icon(Icons.show_chart, color: colorScheme.onSurfaceVariant),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
