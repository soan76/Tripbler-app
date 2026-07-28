import 'package:flutter/material.dart';

import '../models/currency_model.dart';

// 하단 통화 관리 바텀 시트 위젯
class CurrencyManagementBottomSheet extends StatefulWidget {
  final CurrencyModel baseCurrency;
  final List<CurrencyModel> visibleCurrencies;
  final ValueChanged<List<CurrencyModel>> onApply;

  const CurrencyManagementBottomSheet({
    super.key,
    required this.baseCurrency,
    required this.visibleCurrencies,
    required this.onApply,
  });

  @override
  State<CurrencyManagementBottomSheet> createState() =>
      _CurrencyManagementBottomSheetState();
}

// CurrencyManagementBottomSheet의 상태를 관리하는 State 클래스
class _CurrencyManagementBottomSheetState
    extends State<CurrencyManagementBottomSheet> {
  late List<CurrencyModel> editableCurrencies;
  String query = '';

  @override
  void initState() {
    super.initState();
    editableCurrencies = List.from(widget.visibleCurrencies);
  }

  // 위젯을 빌드하는 메서드
  @override
  Widget build(BuildContext context) {
    final displayedCurrencies = editableCurrencies;

    final hiddenCurrencies = supportedCurrencies.where((currency) {
      final isBaseCurrency = currency.code == widget.baseCurrency.code;
      final isAlreadyDisplayed = editableCurrencies.any(
        (item) => item.code == currency.code,
      );

      final lowerQuery = query.toLowerCase();

      final matchesQuery =
          currency.code.toLowerCase().contains(lowerQuery) ||
          currency.countryName.toLowerCase().contains(lowerQuery) ||
          currency.currencyName.toLowerCase().contains(lowerQuery);

      return !isBaseCurrency && !isAlreadyDisplayed && matchesQuery;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 16),
            // 상단 바
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '통화 관리',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.onApply(editableCurrencies);
                    Navigator.pop(context);
                  },
                  child: const Text('완료'),
                ),
              ],
            ),

            const SizedBox(height: 12),
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
            // 기준 통화 박스
            _buildBaseCurrencyBox(),

            const SizedBox(height: 16),

            Expanded(
              // 표시된 통화와 숨겨진 통화를 보여주는 리스트
              child: ListView(
                children: [
                  _buildSectionTitle('현재 화면에 표시된 통화'),

                  if (displayedCurrencies.isEmpty)
                    _buildEmptyDisplayedBox()
                  else
                    // 표시된 통화 목록을 드래그 앤 드롭으로 재정렬할 수 있는 ReorderableListView
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayedCurrencies.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) {
                            newIndex -= 1;
                          }

                          final item = editableCurrencies.removeAt(oldIndex);
                          editableCurrencies.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final currency = displayedCurrencies[index];

                        return _buildDisplayedCurrencyTile(
                          key: ValueKey(currency.code),
                          currency: currency,
                          index: index,
                        );
                      },
                    ),

                  const SizedBox(height: 20),

                  Divider(color: Colors.grey.shade300, thickness: 1),

                  const SizedBox(height: 12),

                  _buildSectionTitle('표시되지 않은 통화'),

                  if (hiddenCurrencies.isEmpty)
                    _buildEmptyHiddenBox()
                  else
                    ...hiddenCurrencies.map((currency) {
                      return _buildHiddenCurrencyTile(currency);
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // 기준 통화 박스를 빌드하는 메서드
  Widget _buildBaseCurrencyBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Text(
            widget.baseCurrency.flagEmoji,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.baseCurrency.code} · 기준 통화',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.baseCurrency.countryName} · ${widget.baseCurrency.currencyName}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, color: Colors.grey),
        ],
      ),
    );
  }
  // 섹션 제목을 빌드하는 메서드
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }
  // 표시된 통화 타일을 빌드하는 메서드
  Widget _buildDisplayedCurrencyTile({
    required Key key,
    required CurrencyModel currency,
    required int index,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Text(currency.flagEmoji, style: const TextStyle(fontSize: 28)),
        title: Text(
          '${currency.code} · ${currency.countryName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(currency.currencyName),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  editableCurrencies.removeAt(index);
                });
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.remove, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.drag_handle, color: Colors.grey),
          ],
        ),
      ),
    );
  }
  // 숨겨진 통화 타일을 빌드하는 메서드
  Widget _buildHiddenCurrencyTile(CurrencyModel currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Text(currency.flagEmoji, style: const TextStyle(fontSize: 28)),
        title: Text(
          '${currency.code} · ${currency.countryName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(currency.currencyName),
        trailing: IconButton(
          onPressed: () {
            setState(() {
              editableCurrencies.add(currency);
              query = '';
            });
          },
          icon: const Icon(Icons.add_circle, color: Colors.blue),
        ),
        onTap: () {
          setState(() {
            editableCurrencies.add(currency);
            query = '';
          });
        },
      ),
    );
  }
  // 표시된 통화가 없을 때 보여주는 박스를 빌드하는 메서드
  Widget _buildEmptyDisplayedBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Text(
        '아직 추가된 환산 통화가 없습니다.',
        style: TextStyle(color: Colors.black54),
      ),
    );
  }
  // 숨겨진 통화가 없을 때 보여주는 박스를 빌드하는 메서드
  Widget _buildEmptyHiddenBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Text(
        '추가할 수 있는 통화가 없습니다.',
        style: TextStyle(color: Colors.black54),
      ),
    );
  }
}
// CurrencyManagementBottomSheet를 보여주는 함수
Future<void> showCurrencyManagementBottomSheet({
  required BuildContext context,
  required CurrencyModel baseCurrency,
  required List<CurrencyModel> visibleCurrencies,
  required ValueChanged<List<CurrencyModel>> onApply,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: CurrencyManagementBottomSheet(
          baseCurrency: baseCurrency,
          visibleCurrencies: visibleCurrencies,
          onApply: onApply,
        ),
      );
    },
  );
}
