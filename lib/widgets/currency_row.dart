import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/currency_model.dart';
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

  const CurrencyRow({
    super.key,
    required this.currency,
    required this.isBase,
    required this.amount,
    required this.rate,
    required this.onCurrencyTap,
    required this.onGraphTap,
    this.onAmountChanged,
  });
  // 통화 행 위젯을 빌드하는 메서드
  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat('#,##0.##');

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isBase ? const Color(0xFFEAF4FF) : Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
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
                Text(
                  currency.code,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 22,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
          // 환율을 표시하는 위젯
          const SizedBox(width: 12),
          Expanded(
            child: isBase
                ? AmountInputField(
                    amount: amount,
                    onChanged: onAmountChanged ?? (_) {},
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      numberFormat.format(amount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: onGraphTap,
            icon: const Icon(Icons.show_chart, color: Colors.blue),
          ),
        ],
      ),
    );
  }
}
