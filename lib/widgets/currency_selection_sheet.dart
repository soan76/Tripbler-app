import 'package:flutter/material.dart';

import '../models/currency_model.dart';

// 통화 선택 시트 위젯
class CurrencySelectionSheet extends StatefulWidget {
  final CurrencyModel? selectedCurrency;
  final ValueChanged<CurrencyModel> onSelected;

  const CurrencySelectionSheet({
    super.key,
    required this.selectedCurrency,
    required this.onSelected,
  });

  @override
  State<CurrencySelectionSheet> createState() => _CurrencySelectionSheetState();
}
// CurrencySelectionSheet의 상태를 관리하는 State 클래스
class _CurrencySelectionSheetState extends State<CurrencySelectionSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final filteredCurrencies = supportedCurrencies.where((currency) {
      final lowerQuery = query.toLowerCase();

      return currency.code.toLowerCase().contains(lowerQuery) ||
          currency.countryName.toLowerCase().contains(lowerQuery) ||
          currency.currencyName.toLowerCase().contains(lowerQuery);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            // 검색 입력 필드
            TextField(
              decoration: InputDecoration(
                hintText: '통화 코드, 국가명, 통화 이름 검색',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  query = value;
                });
              },
            ),
            const SizedBox(height: 16),
            // 통화 목록을 표시하는 ListView
            Expanded(
              child: ListView.separated(
                itemCount: filteredCurrencies.length,
                separatorBuilder: (_, __) =>
                    Divider(color: Colors.grey.shade200, height: 1),
                itemBuilder: (context, index) {
                  final currency = filteredCurrencies[index];
                  final isSelected =
                      widget.selectedCurrency?.code == currency.code;

                  return ListTile(
                    leading: Text(
                      currency.flagEmoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                    title: Text(
                      '${currency.code} · ${currency.countryName}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(currency.currencyName),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () {
                      widget.onSelected(currency);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// CurrencySelectionSheet를 보여주는 함수
Future<void> showCurrencySelectionSheet({
  required BuildContext context,
  required CurrencyModel? selectedCurrency,
  required ValueChanged<CurrencyModel> onSelected,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: CurrencySelectionSheet(
          selectedCurrency: selectedCurrency,
          onSelected: onSelected,
        ),
      );
    },
  );
}
