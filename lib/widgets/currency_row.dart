import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/currency_model.dart';
import '../providers/settings_provider.dart';
import 'amount_input_field.dart';

// 통화 행 위젯
class CurrencyRow extends StatelessWidget {
  final CurrencyModel currency;
  final bool isBase;
  final double amount;
  final double? rate;
  final VoidCallback onCurrencyTap;
  final VoidCallback onGraphTap;
  final ValueChanged<double>? onAmountChanged;
  final VoidCallback? onAmountTap;

  const CurrencyRow({
    super.key,
    required this.currency,
    required this.isBase,
    required this.amount,
    required this.rate,
    required this.onCurrencyTap,
    required this.onGraphTap,
    this.onAmountChanged,
    this.onAmountTap,
  });

  // 통화 행 위젯을 빌드하는 메서드
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 설정 화면에서 선택한 자릿수 설정을 가져옴
    final decimalPlaces = context.watch<SettingsProvider>().decimalPlaces;

    return Container(
      height: 72,
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
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Text(currency.flagEmoji, style: const TextStyle(fontSize: 28)),

                const SizedBox(width: 10),

                // 통화 코드
                Text(
                  currency.code,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isBase
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),

                const SizedBox(width: 2),

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
            child: AmountInputField(
              amount: amount,

              // 현재 선택된 통화 여부
              isBase: isBase,

              // SettingsProvider에서 가져온 자릿수 설정을 전달
              decimalPlaces: decimalPlaces,

              // 입력 영역을 터치하면 해당 통화를 선택
              onTap: onAmountTap,

              // 금액 변경 시 환율 재계산
              onChanged: onAmountChanged ?? (_) {},
            ),
          ),

          const SizedBox(width: 12),

          // 현재 테마의 대표 강조색 사용
          IconButton(
            onPressed: onGraphTap,
            icon: Icon(Icons.show_chart, color: colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
