import 'package:flutter/material.dart';

import '../../models/exchange_rate_history_model.dart';

/// 환율 차트의 조회 기간을 선택하는 위젯.
///
/// 지원 기간:
/// 7D / 1M / 3M / 6M / 1Y / 2Y / 5Y
///
/// 버튼은 높이 32로 그리고, 위아래 여백까지 48dp를 눌리는 영역으로 쓴다. 그래서 위젯
/// 높이는 48이고, 버튼 위아래에 8씩 빈 자리가 있다.
class ExchangeChartPeriodSelector extends StatefulWidget {
  final ChartPeriod selectedPeriod;

  /// 기간을 바꿀 때. [focused]는 누른 버튼에 초점이 있었는지(키보드로 눌렀는지)다.
  /// null이면 버튼을 모두 끈다(조회할 수 없는 카드).
  final void Function(ChartPeriod period, {required bool focused})?
  onPeriodChanged;

  /// 처음 그릴 때 선택된 버튼에 초점을 준다. 키보드로 기간을 바꿔 선택기가 새로
  /// 만들어졌을 때 초점을 이어 주는 데 쓴다.
  final bool focusSelected;

  const ExchangeChartPeriodSelector({
    super.key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
    this.focusSelected = false,
  });

  @override
  State<ExchangeChartPeriodSelector> createState() =>
      _ExchangeChartPeriodSelectorState();
}

class _ExchangeChartPeriodSelectorState
    extends State<ExchangeChartPeriodSelector> {
  /// 기간 글자의 배율 상한. 일곱 칸이 한 줄에 들어가야 하는 짧은 약어라, 하단 탭처럼
  /// 배율을 제한하고 그래도 넘치면 글자를 줄인다.
  static const _labelMaxTextScale = 1.5;

  // 누른 버튼에 초점이 있었는지 알고, 새로 만들어졌을 때 선택된 버튼에 초점을 주는 데 쓴다.
  final _focusNodes = {
    for (final period in ChartPeriod.values)
      period: FocusNode(debugLabel: 'chart-period-${period.name}'),
  };

  @override
  void initState() {
    super.initState();
    if (widget.focusSelected) {
      // 버튼이 초점 트리에 붙은 뒤에 요청한다. 초점에서 빠진 카드(넘겨 둔 카드, 삭제
      // 모드)의 버튼은 요청해도 초점을 받지 않는다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNodes[widget.selectedPeriod]!.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _labelMaxTextScale);
    final selectedPeriod = widget.selectedPeriod;
    final onPeriodChanged = widget.onPeriodChanged;

    return Row(
      spacing: 4,
      children: ChartPeriod.values.map((period) {
        final isSelected = selectedPeriod == period;

        return Expanded(
          child: Semantics(
            selected: isSelected,
            inMutuallyExclusiveGroup: true,
            child: TextButton(
              focusNode: _focusNodes[period],
              onPressed: onPeriodChanged == null
                  ? null
                  : () {
                      if (selectedPeriod == period) {
                        return;
                      }

                      onPeriodChanged(
                        period,
                        focused: _focusNodes[period]!.hasPrimaryFocus,
                      );
                    },
              style: TextButton.styleFrom(
                backgroundColor: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                // 꺼진 카드도 같은 자리에 버튼을 두되 누를 수 없음을 보여 준다. 선택된 기간은
                // 다른 칸보다 조금 진하게 남긴다.
                disabledBackgroundColor: isSelected
                    ? colorScheme.onSurface.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerHighest,
                disabledForegroundColor: colorScheme.onSurface.withValues(
                  alpha: 0.38,
                ),
                textStyle: theme.textTheme.labelMedium,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                // 그리는 버튼은 32지만 눌리는 영역은 48dp로 넓힌다.
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                // 자주 누르는 버튼이라 선택 표시를 바로 바꾼다. 배경은 바로 바뀌는데 글자색만
                // 서서히 바뀌면 잠깐 글자가 배경에 묻힌다.
                animationDuration: Duration.zero,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  period.shortLabel.toUpperCase(),
                  maxLines: 1,
                  textScaler: textScaler,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
