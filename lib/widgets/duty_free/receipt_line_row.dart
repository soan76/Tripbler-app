import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/duty_free/receipt_parser.dart';
import '../../utils/duty_free/duty_free_format.dart';

/// 영수증 검토 화면의 물건 한 줄: 고르기 칸, 이름·분류, 고칠 수 있는 금액 칸.
class ReceiptLineRow extends StatelessWidget {
  const ReceiptLineRow({
    super.key,
    required this.index,
    required this.line,
    required this.selected,
    required this.invalid,
    required this.amount,
    required this.currency,
    required this.onSelected,
    required this.onAmountChanged,
  });

  final int index;
  final ReceiptLine line;
  final bool selected;

  /// 골랐는데 금액이 0 이하이거나 읽을 수 없는지. 칸에 오류를 보인다.
  final bool invalid;
  final TextEditingController amount;

  /// 금액 앞에 붙일 통화. 아직 고르지 않았으면 null.
  final String? currency;
  final ValueChanged<bool> onSelected;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 고르지 않은 줄은 글자·금액만 흐리게 하고, 선택 칸은 또렷하게 두어 다시 고르기 쉽게 한다.
    final dim = selected ? 1.0 : 0.6;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.surfaceContainerHighest),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
          child: Row(
            children: [
              Checkbox(
                key: ValueKey('receipt-line-$index'),
                value: selected,
                semanticLabel: '${line.name} 고르기',
                onChanged: (v) => onSelected(v ?? false),
              ),
              Expanded(
                child: Opacity(
                  opacity: dim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.name, style: theme.textTheme.bodyLarge),
                      Text(
                        line.unsure
                            ? '${line.category.label} · 확인 필요 · 금액을 확인하고 고르세요'
                            : line.category.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: line.unsure
                              ? colorScheme.warning
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: dim,
                child: SizedBox(
                  width: 104,
                  child: TextField(
                    key: ValueKey('receipt-amount-$index'),
                    controller: amount,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      // 확인이 필요한 금액 칸은 주의색 2dp 테두리로 먼저 눈에 띄게 한다.
                      enabledBorder: line.unsure
                          ? OutlineInputBorder(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(AppTheme.cornerRadius),
                              ),
                              borderSide: BorderSide(
                                color: colorScheme.warning,
                                width: 2,
                              ),
                            )
                          : null,
                      prefixText: DutyFreeFormat.symbol(currency ?? ''),
                      errorText: invalid ? '금액 확인' : null,
                    ),
                    onChanged: (_) => onAmountChanged(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
