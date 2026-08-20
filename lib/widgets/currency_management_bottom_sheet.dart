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

class _CurrencyManagementBottomSheetState
    extends State<CurrencyManagementBottomSheet> {
  late List<CurrencyModel> editableCurrencies;
  String query = '';

  @override
  void initState() {
    super.initState();
    editableCurrencies = List.from(widget.visibleCurrencies);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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

    return Container(
      color: colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              // 상단 드래그 핸들
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),

              const SizedBox(height: 16),

              // 상단 바
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '통화 관리',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
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
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: '통화 코드, 국가명, 통화 이름 검색',

                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),

                  prefixIcon: Icon(
                    Icons.search,
                    color: colorScheme.onSurfaceVariant,
                  ),

                  filled: true,

                  fillColor: colorScheme.surfaceContainerHighest,

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

              // 기준 통화
              _buildBaseCurrencyBox(),

              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  children: [
                    _buildSectionTitle('현재 화면에 표시된 통화'),

                    if (displayedCurrencies.isEmpty)
                      _buildEmptyDisplayedBox()
                    else
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

                    Divider(color: colorScheme.outlineVariant, thickness: 1),

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
      ),
    );
  }

  Widget _buildBaseCurrencyBox() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.outlineVariant),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  '${widget.baseCurrency.countryName} · '
                  '${widget.baseCurrency.currencyName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),

          Icon(Icons.lock_outline, color: colorScheme.onPrimaryContainer),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildDisplayedCurrencyTile({
    required Key key,
    required CurrencyModel currency,
    required int index,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Text(currency.flagEmoji, style: const TextStyle(fontSize: 28)),

        title: Text(
          '${currency.code} · ${currency.countryName}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),

        subtitle: Text(
          currency.currencyName,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),

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
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.remove, color: colorScheme.onError, size: 18),
              ),
            ),

            const SizedBox(width: 12),

            Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildHiddenCurrencyTile(CurrencyModel currency) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Text(currency.flagEmoji, style: const TextStyle(fontSize: 28)),

        title: Text(
          '${currency.code} · ${currency.countryName}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),

        subtitle: Text(
          currency.currencyName,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),

        trailing: IconButton(
          onPressed: () {
            setState(() {
              editableCurrencies.add(currency);
              query = '';
            });
          },
          icon: Icon(Icons.add_circle, color: colorScheme.primary),
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

  Widget _buildEmptyDisplayedBox() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        '아직 추가된 환산 통화가 없습니다.',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildEmptyHiddenBox() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        '추가할 수 있는 통화가 없습니다.',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
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
  final colorScheme = Theme.of(context).colorScheme;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,

    // 라이트 / 다크 테마에 맞춰 바텀시트 자체 배경 변경
    backgroundColor: colorScheme.surface,

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
