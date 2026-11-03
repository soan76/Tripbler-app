import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/exchange/display_currency.dart';
import '../../presentation/exchange/exchange_display_provider.dart';
import 'currency_search_parts.dart';

/// 차트 한쪽 통화를 고르는 검색 목록. 통화 관리의 '통화 추가'와 같은 검색 입력,
/// 통화/암호 전환, 목록 줄을 쓴다. 고르면 그 통화를 돌려주며 창을 닫는다.
class ChartCurrencyPicker extends StatefulWidget {
  const ChartCurrencyPicker({
    super.key,
    required this.title,
    required this.current,
    required this.options,
    this.note,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final String title;
  final DisplayCurrency current;
  final List<DisplayCurrency> options;

  /// 목록 위에 보여 줄 안내(예: 코인 차트는 KRW만 고를 수 있음).
  final String? note;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<ChartCurrencyPicker> createState() => _ChartCurrencyPickerState();
}

class _ChartCurrencyPickerState extends State<ChartCurrencyPicker> {
  final _searchController = TextEditingController();
  String _query = '';
  late CurrencyCategory _category = widget.current.category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categories = {for (final c in widget.options) c.category};
    // 한 종류만 고를 수 있으면 전환을 숨기고 그 종류만 보여 준다.
    final showFilter = categories.length > 1;
    final category = showFilter || categories.isEmpty
        ? _category
        : categories.single;
    final catalogPending =
        category == CurrencyCategory.crypto &&
        (widget.loading || widget.error != null);
    final shown = [
      for (final currency in widget.options)
        if (currency.category == category && currency.matches(_query)) currency,
    ];

    return Container(
      color: colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CurrencySearchField(
                controller: _searchController,
                category: category,
                onChanged: (value) => setState(() => _query = value),
              ),
              if (widget.note != null) ...[
                const SizedBox(height: 12),
                // 고를 수 있는 통화가 제한된 이유를 아이콘과 함께 알려 준다.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.note!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                // 목록을 끌면 키보드를 내리고, 키보드가 가린 만큼 끝에 여백을 둬
                // 마지막 줄까지 올려 볼 수 있게 한다.
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    if (showFilter) ...[
                      CurrencyCategoryFilter(
                        selected: category,
                        onChanged: (next) => setState(() => _category = next),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (category == CurrencyCategory.crypto)
                      CurrencyCatalogStatus(
                        loading: widget.loading,
                        error: widget.error,
                        onRetry: widget.onRetry,
                      ),
                    // 코인 목록을 불러오는 중이거나 실패했을 때는 위의 상태 안내만
                    // 보여 주고, 결과 없음 문구를 겹쳐 띄우지 않는다.
                    if (shown.isEmpty)
                      if (!catalogPending)
                        _EmptyResult(
                          message: _query.trim().isEmpty
                              ? '고를 수 있는 통화가 없습니다.'
                              : "'${_query.trim()}'에 맞는 통화가 없습니다.",
                        )
                      else
                        const SizedBox.shrink()
                    else
                      for (final currency in shown)
                        CurrencyOptionTile(
                          key: ValueKey('chart-option-${currency.id}'),
                          currency: currency,
                          selected: currency.id == widget.current.id,
                          trailing: currency.id == widget.current.id
                              ? Icon(Icons.check, color: colorScheme.primary)
                              : null,
                          onTap: () => Navigator.pop(context, currency),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색 결과가 없을 때의 안내. 목록 줄과 같은 테두리로 자리를 맞춘다.
class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 차트 통화 선택창을 연다. 후보는 [optionsOf]로 현재 고를 수 있는 통화에서 걸러
/// 만들며, 암호화폐 목록이 늦게 도착해도 창 안에서 갱신된다. 고르지 않고 닫으면 null.
Future<DisplayCurrency?> showChartCurrencyPicker({
  required BuildContext context,
  required String title,
  required DisplayCurrency current,
  required List<DisplayCurrency> Function(List<DisplayCurrency> available)
  optionsOf,
  String? note,
}) => showModalBottomSheet<DisplayCurrency>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (sheetContext) => Consumer<ExchangeDisplayProvider>(
    builder: (_, display, _) => SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.85,
      child: ChartCurrencyPicker(
        title: title,
        current: current,
        options: optionsOf(display.available),
        note: note,
        loading: display.crypto.loading,
        error: display.crypto.catalogError,
        onRetry: display.crypto.refreshCatalog,
      ),
    ),
  ),
);
