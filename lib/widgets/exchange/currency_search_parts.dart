import 'package:flutter/material.dart';

import '../../presentation/exchange/display_currency.dart';
import '../focus_history.dart';
import 'currency_icon.dart';

/// 통화 목록을 국가 통화/암호화폐로 나눠 보여 줄 때의 종류.
enum CurrencyCategory { fiat, crypto }

extension CurrencyCategoryOf on DisplayCurrency {
  CurrencyCategory get category =>
      isCrypto ? CurrencyCategory.crypto : CurrencyCategory.fiat;
}

/// 통화 관리의 '통화 추가'와 차트 통화 선택이 함께 쓰는 검색 입력.
class CurrencySearchField extends StatelessWidget {
  const CurrencySearchField({
    super.key,
    required this.controller,
    required this.category,
    required this.onChanged,
  });

  final TextEditingController controller;
  final CurrencyCategory category;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: category == CurrencyCategory.fiat
            ? '통화 코드, 국가명, 통화 이름 검색'
            : '코인 심볼·이름 검색',
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

/// 통화/암호 목록 전환.
class CurrencyCategoryFilter extends StatelessWidget {
  const CurrencyCategoryFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final CurrencyCategory selected;
  final ValueChanged<CurrencyCategory> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<CurrencyCategory>(
    segments: const [
      ButtonSegment(value: CurrencyCategory.fiat, label: Text('통화')),
      ButtonSegment(value: CurrencyCategory.crypto, label: Text('암호')),
    ],
    selected: {selected},
    onSelectionChanged: (selection) => onChanged(selection.single),
  );
}

/// 암호화폐 목록을 불러오는 중이거나 실패했을 때의 안내.
class CurrencyCatalogStatus extends StatelessWidget {
  const CurrencyCatalogStatus({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          ListTile(
            title: Text(error),
            trailing: TextButton(
              // 오류가 사라지면 이 버튼도 사라져 초점이 전에 쓴 검색칸으로 돌아가므로 먼저 푼다.
              // 검색칸에 초점을 둔 채 터치했으면 그대로 둔다.
              onPressed: onRetry == null
                  ? null
                  : () {
                      if (!primaryFocusInTextField) releaseFocusHistory();
                      onRetry!();
                    },
              child: const Text('다시 시도'),
            ),
          ),
      ],
    );
  }
}

/// 고를 수 있는 통화 한 줄. [trailing]이 없으면 끝 아이콘을 두지 않는다.
class CurrencyOptionTile extends StatelessWidget {
  const CurrencyOptionTile({
    super.key,
    required this.currency,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });

  final DisplayCurrency currency;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerLowest,
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
        trailing: trailing,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
