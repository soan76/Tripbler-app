import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/exchange/display_currency.dart';
import '../../providers/settings_provider.dart';
import 'amount_input_field.dart';
import 'currency_icon.dart';

/// 환율 화면에서 통화 행이 놓이는 자리.
enum CurrencyRowLayout {
  /// 일반 목록의 한 줄.
  list,

  /// 지금 금액을 입력하는 통화. 화면 맨 위에 크게 둔다.
  input,

  /// 자국 통화. 입력칸 바로 아래에 두어 환산 결과를 먼저 보게 한다.
  home,
}

// 통화 행 위젯
class CurrencyRow extends StatefulWidget {
  final DisplayCurrency currency;
  final double? amount;
  final VoidCallback onCurrencyTap;
  final String? status;
  final ValueChanged<double>? onAmountChanged;
  final VoidCallback? onAmountTap;
  final CurrencyRowLayout layout;

  const CurrencyRow({
    super.key,
    required this.currency,
    required this.amount,
    required this.onCurrencyTap,
    this.status,
    this.onAmountChanged,
    this.onAmountTap,
    this.layout = CurrencyRowLayout.list,
  });

  @override
  State<CurrencyRow> createState() => _CurrencyRowState();
}

class _CurrencyRowState extends State<CurrencyRow> {
  // 자리(layout)가 바뀌어 위젯 구성이 달라져도 입력칸의 글자·초점을 잃지 않게 한다.
  final _fieldKey = GlobalKey();

  @override
  void didUpdateWidget(covariant CurrencyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 아래쪽 줄이 입력 칸으로 올라오면, 스크롤을 내려 둔 상태라도 "입력 중" 라벨까지 보이게 한다.
    // 입력칸의 기본 스크롤은 커서 주변만 보이게 해 라벨이 화면 위로 잘릴 수 있다.
    if (oldWidget.layout != CurrencyRowLayout.input &&
        widget.layout == CurrencyRowLayout.input) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 설정 화면에서 선택한 자릿수 설정을 가져옴
    // 자동이면 국가 통화 2자리, 암호화폐 5자리
    final decimalPlaces = context.watch<SettingsProvider>().decimalPlacesFor(
      isCrypto: widget.currency.isCrypto,
    );

    final layout = widget.layout;
    // 강조 배경 위에 놓이는지. 자국 통화 칸만 강조 배경을 쓴다.
    final onContainer = layout == CurrencyRowLayout.home;
    final foreground = onContainer
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final mutedForeground = onContainer
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    final currencyButton = InkWell(
      onTap: widget.onCurrencyTap,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CurrencyIcon(currency: widget.currency),
            const SizedBox(width: 8),
            // 통화 코드
            Text(
              widget.currency.code,
              style: theme.textTheme.titleMedium?.copyWith(color: foreground),
            ),
            const SizedBox(width: 4),
            // 통화 선택 화살표
            Icon(Icons.keyboard_arrow_down, size: 22, color: mutedForeground),
          ],
        ),
      ),
    );

    final amountColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AmountInputField(
          key: _fieldKey,
          amount: widget.amount ?? 0,
          unavailable: widget.amount == null,
          // 강조 배경 위 글자색 여부
          isBase: onContainer,
          // 입력값과 원화 결과를 목록보다 굵게 보여 준다(사용자 결정).
          fontWeight: layout == CurrencyRowLayout.list
              ? FontWeight.w500
              : FontWeight.w700,
          maxFontSize: switch (layout) {
            CurrencyRowLayout.input => 30,
            CurrencyRowLayout.home => 26,
            CurrencyRowLayout.list => 20,
          },
          // SettingsProvider에서 가져온 자릿수 설정을 전달
          decimalPlaces: decimalPlaces,
          // 입력 영역을 터치하면 해당 통화를 선택
          onTap: widget.onAmountTap,
          // 금액 변경 시 환율 재계산
          onChanged: widget.onAmountChanged ?? (_) {},
        ),
        if (widget.status != null)
          Tooltip(
            message: widget.status!,
            child: Text(
              widget.status!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: mutedForeground,
              ),
            ),
          ),
      ],
    );

    final row = Row(
      children: [
        currencyButton,
        const SizedBox(width: 12),
        // 환율 금액 영역
        Expanded(child: amountColumn),
      ],
    );

    switch (layout) {
      case CurrencyRowLayout.input:
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          // 테두리 2dp와 합쳐 안쪽 여백이 12dp가 되게 해, 아래 자국 통화 칸과 글자 줄을 맞춘다.
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.primary, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '입력 중',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              row,
            ],
          ),
        );
      case CurrencyRowLayout.home:
        return Container(
          constraints: const BoxConstraints(minHeight: 64),
          // 아래 여백은 '다른 통화' 제목이 맡는다. 자국 통화 칸이 없을 때도 간격이 같다.
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: row,
        );
      case CurrencyRowLayout.list:
        return Container(
          // 위 두 칸보다 낮은 64dp로 두어 보조 목록임을 드러낸다.
          // 코인 행의 상태 문구는 글자를 크게 키우면 64dp를 넘으므로 잘리지 않게 늘린다.
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            // 현재 라이트/다크 테마에 맞는 구분선
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
            ),
          ),
          child: row,
        );
    }
  }
}
