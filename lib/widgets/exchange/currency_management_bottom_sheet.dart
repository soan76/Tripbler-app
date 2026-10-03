import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../../presentation/exchange/display_currency.dart';
import '../../presentation/exchange/exchange_display_provider.dart';
import 'currency_icon.dart';

enum CurrencyCategory { fiat, crypto }

// 하단 통화 관리 바텀 시트 위젯
class CurrencyManagementBottomSheet extends StatefulWidget {
  final DisplayCurrency baseCurrency;
  final List<DisplayCurrency> availableCurrencies;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final List<DisplayCurrency> visibleCurrencies;
  final ValueChanged<List<DisplayCurrency>> onApply;

  const CurrencyManagementBottomSheet({
    super.key,
    required this.baseCurrency,
    required this.availableCurrencies,
    this.loading = false,
    this.error,
    this.onRetry,
    required this.visibleCurrencies,
    required this.onApply,
  });

  @override
  State<CurrencyManagementBottomSheet> createState() =>
      _CurrencyManagementBottomSheetState();
}

class _CurrencyManagementBottomSheetState
    extends State<CurrencyManagementBottomSheet> {
  late List<DisplayCurrency> editableCurrencies;
  String query = '';
  CurrencyCategory _category = CurrencyCategory.fiat;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    editableCurrencies = List.from(widget.visibleCurrencies);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final displayedCurrencies = editableCurrencies;

    final hiddenCurrencies = widget.availableCurrencies.where((currency) {
      final isBaseCurrency = currency.id == widget.baseCurrency.id;

      final isAlreadyDisplayed = editableCurrencies.any(
        (item) => item.id == currency.id,
      );

      final matchesQuery = currency.matches(query);
      final matchesCategory =
          currency.isCrypto == (_category == CurrencyCategory.crypto);

      return !isBaseCurrency &&
          !isAlreadyDisplayed &&
          matchesCategory &&
          matchesQuery;
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
                controller: _searchController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: _category == CurrencyCategory.fiat
                      ? '통화 코드, 국가명, 통화 이름 검색'
                      : '코인 심볼·이름 검색',

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
                            key: ValueKey(currency.id),
                            currency: currency,
                            index: index,
                          );
                        },
                      ),

                    const SizedBox(height: 20),

                    Divider(color: colorScheme.outlineVariant, thickness: 1),

                    const SizedBox(height: 12),

                    _buildSectionTitle('표시되지 않은 통화'),
                    SegmentedButton<CurrencyCategory>(
                      segments: const [
                        ButtonSegment(
                          value: CurrencyCategory.fiat,
                          label: Text('통화'),
                        ),
                        ButtonSegment(
                          value: CurrencyCategory.crypto,
                          label: Text('암호'),
                        ),
                      ],
                      selected: {_category},
                      onSelectionChanged: (selection) {
                        setState(() => _category = selection.single);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_category == CurrencyCategory.crypto && widget.loading)
                      const LinearProgressIndicator(),
                    if (_category == CurrencyCategory.crypto &&
                        widget.error != null)
                      ListTile(
                        title: Text(widget.error!),
                        trailing: TextButton(
                          onPressed: widget.onRetry,
                          child: const Text('다시 시도'),
                        ),
                      ),

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
          CurrencyIcon(currency: widget.baseCurrency),

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
    required DisplayCurrency currency,
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
        leading: CurrencyIcon(currency: currency),

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

  Widget _buildHiddenCurrencyTile(DisplayCurrency currency) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CurrencyIcon(currency: currency),

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
              _searchController.clear();
            });
          },
          icon: Icon(Icons.add_circle, color: colorScheme.primary),
        ),

        onTap: () {
          setState(() {
            editableCurrencies.add(currency);
            query = '';
            _searchController.clear();
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

// 진입점에서만 두 도메인을 조합한다. 편집 중에는 로컬 초안을 유지한다.
Future<void> showCurrencyManagementBottomSheet({
  required BuildContext context,
}) {
  final display = context.read<ExchangeDisplayProvider>();
  final initialization = display.initialize();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) => FutureBuilder<void>(
      future: initialization,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('저장된 통화 목록을 불러오지 못했습니다. 창을 다시 열어 주세요.')),
          );
        }
        return Consumer<ExchangeDisplayProvider>(
          builder: (_, model, _) => SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.85,
            child: CurrencyManagementBottomSheet(
              baseCurrency: model.base,
              visibleCurrencies: model.visible,
              availableCurrencies: model.available,
              loading: model.crypto.loading,
              error: model.crypto.catalogError,
              onRetry: model.crypto.refreshCatalog,
              onApply: (rows) async {
                try {
                  await display.apply(rows);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('통화 목록을 저장하지 못했습니다. 다시 시도해 주세요.'),
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      },
    ),
  );
}
