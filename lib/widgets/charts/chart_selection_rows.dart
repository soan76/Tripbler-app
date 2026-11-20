import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/chart_point.dart';
import '../../presentation/charts/chart_amount_format.dart';
import '../../presentation/charts/chart_rate_comparison.dart';
import '../exchange/amount_input_field.dart';
import '../exchange/exchange_chart_axis_helper.dart';

// 선택 전환의 두 구간. 앞 구간에서 금액이 평소 자리를 떠나고, 뒤 구간에서 그 자리와
// 그래프 위 줄의 나머지 글자가 나타나 서로 겹쳐 보이지 않게 한다.
const chartLeaveInterval = Interval(0, 0.35);
const chartSettleInterval = Interval(0.35, 1);

// 내려오는 금액이 거의 도착한 뒤에 그 칸의 라벨을 보여 준다.
const _arrivedInterval = Interval(0.8, 1);

/// 오른쪽 자리에 보여 주는 선택 기록의 날짜와 환율.
class ChartSelectedRate extends StatelessWidget {
  const ChartSelectedRate({
    super.key,
    required this.point,
    required this.baseCode,
    required this.targetCode,
    this.maxDecimals,
  });

  final ChartPoint point;
  final String baseCode;
  final String targetCode;
  final int? maxDecimals;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            ExchangeChartAxisHelper.formatTooltipDate(
              point.date,
              includesTime: point.includesTime,
            ),
            key: const ValueKey('market-chart-selected-date'),
            maxLines: 1,
            style: textTheme.bodySmall?.copyWith(color: mutedColor),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '1 $baseCode = '
            '${ChartAmountFormat.formatAmount(point.rate, maxDecimals: maxDecimals)}'
            ' $targetCode',
            key: const ValueKey('market-chart-selected-rate'),
            maxLines: 1,
            style: textTheme.titleSmall?.copyWith(
              fontFeatures: amountFontFeatures,
            ),
          ),
        ),
      ],
    );
  }
}

/// 그래프 바로 위의 선택일 환산액, 최신 환산액, 차이.
/// 칸 폭보다 긴 금액은 잘라내지 않고 글자를 줄여 맞춘다.
class ChartComparisonRow extends StatelessWidget {
  const ChartComparisonRow({
    super.key,
    required this.comparison,
    required this.targetCode,
    this.maxDecimals,
    required this.latestLabel,
    required this.progress,
  });

  final ChartRateComparison comparison;
  final String targetCode;
  final int? maxDecimals;
  final String latestLabel;
  final double progress;

  static const _cellGap = 8.0;

  // 환산 금액이 오른쪽 자리에서 내려오는 세로 거리. 입력칸 높이의 절반(12 + 글자 12),
  // 간격 8, 칸 안 값의 중심(라벨 12 + 값 절반 10)을 더한 값이다.
  static const _dropFixed = 20.0;
  static const _dropScaled = 34.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final differenceText = ChartAmountFormat.formatChange(
      comparison.difference.abs(),
      maxDecimals: maxDecimals,
      compared: [comparison.selectedAmount, comparison.latestAmount],
    );
    // 표시 글자가 0이면(제한 자릿수에서 반올림해 0이 된 경우 포함) 부호와 색도 없다.
    final difference = ChartAmountFormat.isZeroText(differenceText)
        ? 0.0
        : comparison.difference;
    final differenceColor = difference > 0
        ? colorScheme.gain
        : difference < 0
        ? colorScheme.loss
        : colorScheme.onSurfaceVariant;
    final sign = difference > 0
        ? '+'
        : difference < 0
        ? '-'
        : '';
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final drop =
        _dropFixed + MediaQuery.textScalerOf(context).scale(_dropScaled);
    final settle = chartSettleInterval.transform(progress);
    final rest = 1 - progress;
    // 내려오는 금액은 오른쪽 자리의 글자 크기에서 시작해 칸의 크기로 줄어든다.
    final startScale =
        (textTheme.titleLarge?.fontSize ?? 1) /
        (textTheme.bodyMedium?.fontSize ?? 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 세 칸의 폭이 같아, 가운데 칸 끝에서 줄 끝까지는 한 칸과 간격 하나만큼이다.
        final toRowEnd = (constraints.maxWidth - _cellGap * 2) / 3 + _cellGap;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Opacity(
                opacity: settle,
                child: _ComparisonCell(
                  valueKey: 'market-chart-compare-selected',
                  label: '선택일',
                  value:
                      '${ChartAmountFormat.formatAmount(comparison.selectedAmount, maxDecimals: maxDecimals)}'
                      ' $targetCode',
                  alignment: AlignmentDirectional.centerStart,
                ),
              ),
            ),
            const SizedBox(width: _cellGap),
            Expanded(
              // 오른쪽 자리에 있던 환산 금액이 이 칸으로 내려온다. 라벨은 움직이지 않는다.
              child: _ComparisonCell(
                valueKey: 'market-chart-compare-latest',
                label: latestLabel,
                value:
                    '${ChartAmountFormat.formatAmount(comparison.latestAmount, maxDecimals: maxDecimals)}'
                    ' $targetCode',
                alignment: AlignmentDirectional.center,
                labelOpacity: _arrivedInterval.transform(progress),
                valueOpacity: chartLeaveInterval.transform(progress),
                valueOffset: Offset(direction * toRowEnd * rest, -drop * rest),
                valueScale: 1 + (startScale - 1) * rest,
                valueAlignment: AlignmentDirectional.lerp(
                  AlignmentDirectional.centerEnd,
                  AlignmentDirectional.center,
                  progress,
                ),
              ),
            ),
            const SizedBox(width: _cellGap),
            Expanded(
              child: Opacity(
                opacity: settle,
                child: _ComparisonCell(
                  valueKey: 'market-chart-compare-difference',
                  label: '차이',
                  value: '$sign$differenceText $targetCode',
                  // 이 줄의 결론이라 같은 크기에서 굵기로 구분한다.
                  valueStyle: textTheme.labelLarge,
                  valueColor: differenceColor,
                  alignment: AlignmentDirectional.centerEnd,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 라벨과 값을 위아래로 둔 칸. 줄 높이는 갱신 상태 두 줄(16 + 16)과 같은 32
/// (라벨 12 + 값 20)이고, 긴 금액을 줄여도 라벨 크기와 값의 세로 중심은 그대로다.
class _ComparisonCell extends StatelessWidget {
  const _ComparisonCell({
    required this.valueKey,
    required this.label,
    required this.value,
    required this.alignment,
    this.valueStyle,
    this.valueColor,
    this.labelOpacity = 1,
    this.valueOpacity = 1,
    this.valueOffset = Offset.zero,
    this.valueScale = 1,
    this.valueAlignment,
  });

  // labelSmall(11)의 줄 높이를 12로 좁혀 값에 14 크기를 쓸 자리를 만든다.
  static const _labelLineHeight = 12 / 11;

  final String valueKey;
  final String label;
  final String value;
  final AlignmentDirectional alignment;
  final TextStyle? valueStyle;
  final Color? valueColor;
  final double labelOpacity;
  final double valueOpacity;
  final Offset valueOffset;
  final double valueScale;

  /// 값의 정렬과 크기 변화의 기준점. 없으면 [alignment]를 따른다.
  final AlignmentDirectional? valueAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueAnchor = valueAlignment ?? alignment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Opacity(
          opacity: labelOpacity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: _labelLineHeight,
              ),
            ),
          ),
        ),
        Expanded(
          child: Opacity(
            opacity: valueOpacity,
            child: Transform.translate(
              offset: valueOffset,
              child: Transform.scale(
                scale: valueScale,
                alignment: valueAnchor,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: valueAnchor,
                  child: Text(
                    value,
                    key: ValueKey(valueKey),
                    maxLines: 1,
                    style: (valueStyle ?? theme.textTheme.bodyMedium)?.copyWith(
                      color: valueColor ?? theme.colorScheme.onSurface,
                      fontFeatures: amountFontFeatures,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
