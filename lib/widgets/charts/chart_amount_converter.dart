import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/theme/app_theme.dart';
import '../../domain/exchange/exchange_calculator.dart';
import '../../models/chart_point.dart';
import '../../presentation/charts/chart_rate_comparison.dart';
import '../exchange/amount_input_field.dart';
import '../exchange/exchange_chart_axis_helper.dart';
import '../exchange/exchange_chart_data_calculator.dart';
import 'chart_swap_motion.dart';

// 선택 전환의 두 구간. 앞 구간에서 금액이 평소 자리를 떠나고, 뒤 구간에서 그 자리와
// 그래프 위 줄의 나머지 글자가 나타나 서로 겹쳐 보이지 않게 한다.
const _leaveInterval = Interval(0, 0.35);
const _settleInterval = Interval(0.35, 1);

// 내려오는 금액이 거의 도착한 뒤에 그 칸의 라벨을 보여 준다.
const _arrivedInterval = Interval(0.8, 1);

/// 카드가 새로 만들어져도(통화·기간 변경) 입력한 금액을 이어 쓰게 한다.
/// 입력칸을 만들 때와 글자가 바뀔 때만 읽으므로 의존을 만들지 않는다.
class ChartAmountScope extends InheritedWidget {
  const ChartAmountScope({
    super.key,
    required this.text,
    required this.onChanged,
    required super.child,
  });

  /// 보관 중인 입력 글자.
  final String text;
  final ValueChanged<String> onChanged;

  static ChartAmountScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChartAmountScope>();

  @override
  bool updateShouldNotify(ChartAmountScope oldWidget) => false;
}

/// 왼쪽 입력칸의 금액을 오른쪽에 환산해 보여 주는 줄. 글자가 바뀌면 바로 계산한다.
/// [rate]는 화면에 보이는 방향(1 [baseCode] = rate [targetCode])의 환율이다.
/// [message]가 있으면 입력칸 대신 안내 문구를 보여 준다.
///
/// 그래프에서 날짜를 고르면 오른쪽 자리에 그 날짜와 환율을 보여 주고, 환산 금액은
/// 그래프 바로 위([status] 자리)로 내려가 선택일과 비교한다. [status] 자리만 쓰므로
/// 선택 중에도 그래프의 크기와 위치는 그대로다.
class ChartAmountConverter extends StatefulWidget {
  const ChartAmountConverter({
    super.key,
    required this.rate,
    required this.baseCode,
    required this.targetCode,
    required this.historicalRate,
    this.staleRate = false,
    this.history = const [],
    this.selectedDate,
    this.selectionKey,
    this.status = const SizedBox.shrink(),
    this.message,
  });

  final double? rate;
  final String baseCode;
  final String targetCode;

  /// 현재 시세를 받지 못해 기록의 마지막 값으로 계산하는지.
  final bool historicalRate;

  /// 저장값이나 갱신에 실패한 마지막 값으로 계산하는지.
  final bool staleRate;

  /// 화면에 보이는 방향의 기록. 그래프와 같은 목록이다.
  final List<ChartPoint> history;

  /// 그래프에서 선택한 날짜.
  final ValueListenable<DateTime?>? selectedDate;

  /// 그래프의 selectionKey와 같은 값. 바뀌면 같은 날짜의 선택을 이어 간다(스왑).
  final Object? selectionKey;

  /// 평소 아래에 보여 줄 갱신 상태.
  final Widget status;
  final String? message;

  /// 입력 글자를 금액으로 바꾼다. 비었거나 숫자가 아니면 null이다.
  static double? parseAmount(String text) {
    final amount = double.tryParse(text.replaceAll(',', ''));
    return amount != null && amount.isFinite ? amount : null;
  }

  /// 환산 금액을 표시 글자로 바꾼다. 계산할 수 없으면 null이다.
  static String? convertedText(String text, double rate) {
    final amount = parseAmount(text);
    if (amount == null) return null;
    final result = const ExchangeCalculator().convertFromBase(
      baseAmount: amount,
      rate: rate,
    );
    return result.isFinite ? formatAmount(result) : null;
  }

  /// 금액이나 환율을 표시 글자로 바꾼다.
  /// 1 미만 값은 반전된 코인 환율처럼 아주 작을 수 있어 유효숫자 기준으로 표시한다.
  static String formatAmount(double value) => value.abs() < 1
      ? ExchangeChartAxisHelper.formatRate(value)
      : _resultFormat.format(value);

  static final _resultFormat = NumberFormat('#,##0.######');

  @override
  State<ChartAmountConverter> createState() => _ChartAmountConverterState();
}

class _ChartAmountConverterState extends State<ChartAmountConverter>
    with SingleTickerProviderStateMixin {
  static const _enterDuration = Duration(milliseconds: 200);
  static const _exitDuration = Duration(milliseconds: 150);

  late final TextEditingController _controller;

  // 0이면 평소 배치, 1이면 선택 중 배치.
  late final AnimationController _motion;
  late final Animation<double> _progress;

  // 선택이 풀려 원래 자리로 돌아가는 동안에도 보여 줄 마지막 선택.
  ChartPoint? _lastPoint;

  // 기록이 바뀌어 그래프가 풀기로 한 선택. 그래프는 프레임 뒤에야 알려 주므로
  // 그 사이에도 마커와 어긋나지 않게 이 날짜를 선택으로 보지 않는다.
  DateTime? _droppedDate;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ChartAmountScope.maybeOf(context)?.text ?? '',
    );
    _motion = AnimationController(
      vsync: this,
      duration: _enterDuration,
      reverseDuration: _exitDuration,
    );
    // 되돌아갈 때도 시간 기준으로 빠르게 시작해 천천히 끝나도록 곡선을 뒤집는다.
    _progress = CurvedAnimation(
      parent: _motion,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeOut.flipped,
    );
    widget.selectedDate?.addListener(_syncSelection);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant ChartAmountConverter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selectedDate, widget.selectedDate)) {
      oldWidget.selectedDate?.removeListener(_syncSelection);
      widget.selectedDate?.addListener(_syncSelection);
    }
    _followHistory(oldWidget);
    _syncSelection();
  }

  // 그래프가 기록 변경을 처리하는 규칙(ExchangeChartTouchController.updateData)을 따른다.
  void _followHistory(ChartAmountConverter oldWidget) {
    if (oldWidget.selectionKey != widget.selectionKey) {
      // 방향이 바뀌면 복귀 중인 값도 같은 날짜의 새 방향 기록으로 옮긴다.
      final last = _lastPoint;
      _lastPoint = last == null ? null : _pointAt(last.date);
    } else if (!listEquals(oldWidget.history, widget.history)) {
      // 복귀하는 동안에는 마커가 마지막으로 가리킨 기록을 그대로 보여 준다.
      _droppedDate = widget.selectedDate?.value;
      if (oldWidget.baseCode != widget.baseCode ||
          oldWidget.targetCode != widget.targetCode) {
        _lastPoint = null;
      }
    }
  }

  // [date]에 가장 가까운 실제 기록. 그래프의 마커와 같은 방법으로 찾는다.
  ChartPoint? _pointAt(DateTime date) {
    final index = ExchangeChartDataCalculator.nearestIndex(
      widget.history,
      date,
    );
    return index == null ? null : widget.history[index];
  }

  ChartPoint? get _selectedPoint {
    final date = widget.selectedDate?.value;
    return date == null || date == _droppedDate ? null : _pointAt(date);
  }

  void _syncSelection() {
    // 그래프가 해제를 알렸거나 새로 골랐으면 더 기다릴 것이 없다.
    if (widget.selectedDate?.value != _droppedDate) _droppedDate = null;
    final point = _selectedPoint;
    if (point != null) _lastPoint = point;
    final target = point == null ? 0.0 : 1.0;
    if (_motion.value == target) return;
    if (reduceMotionOf(context)) {
      _motion.value = target;
    } else if (point == null) {
      _motion.reverse();
    } else {
      _motion.forward();
    }
  }

  void _onChanged(String text) {
    ChartAmountScope.maybeOf(context)?.onChanged(text);
    setState(() {});
  }

  @override
  void dispose() {
    widget.selectedDate?.removeListener(_syncSelection);
    _motion.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = TextStyle(color: theme.colorScheme.onSurfaceVariant);

    final message = widget.message;
    if (message != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(message, style: mutedStyle),
            ),
          ),
          const SizedBox(height: 8),
          widget.status,
        ],
      );
    }

    final rate = widget.rate;
    final hasRate = const ExchangeCalculator().isValidRate(rate);
    final converted = hasRate
        ? ChartAmountConverter.convertedText(_controller.text, rate!)
        : null;

    final Widget current = !hasRate
        ? Text('현재 환율 정보 없음', textAlign: TextAlign.end, style: mutedStyle)
        : converted == null
        ? const SizedBox.shrink()
        // 이 줄의 핵심 정보라 입력 글자보다 크게 쓴다.
        // 긴 금액은 잘라내지 않고 글자를 줄여 맞춘다.
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${widget.historicalRate ? '최근 기록 · ' : ''}'
              '$converted ${widget.targetCode}',
              key: const ValueKey('market-chart-converted'),
              maxLines: 1,
              // 위쪽 금액칸과 같은 굵기로 맞춘다. 금지 목록의 예외로 사용자가 정했다.
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w500,
                fontFeatures: amountFontFeatures,
              ),
            ),
          );

    final field = MergeSemantics(
      // 화면에는 글자가 없으므로 화면 낭독기에는 무엇을 넣는 칸인지 따로 알려 준다.
      // 합치지 않으면 라벨이 입력칸이 아니라 카드의 글자 묶음에 붙는다.
      child: Semantics(
        label: '${widget.baseCode} 금액',
        child: TextField(
          key: const ValueKey('market-chart-amount'),
          controller: _controller,
          onChanged: _onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ThousandsSeparatorInputFormatter(decimalPlaces: -1),
          ],
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: amountFontFeatures,
          ),
          decoration: InputDecoration(
            // 테마의 회색 채움을 받지 않고 위쪽 금액칸처럼 배경 없이 둔다.
            filled: false,
            // isDense를 쓰지 않아 글꼴과 관계없이 터치 높이 48dp가 보장된다.
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
    );

    final listenables = <Listenable>[_progress, ?widget.selectedDate];
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final progress = _progress.value;
        final leave = _leaveInterval.transform(progress);
        final point = _selectedPoint ?? _lastPoint;
        final comparison = point == null
            ? null
            : ChartRateComparison.of(
                amount: ChartAmountConverter.parseAmount(_controller.text),
                selectedRate: point.rate,
                latestRate: rate,
              );
        final compared = comparison != null && progress > 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 12),
                Expanded(
                  child: Stack(
                    alignment: AlignmentDirectional.centerEnd,
                    children: [
                      Opacity(
                        opacity: 1 - leave,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: current,
                        ),
                      ),
                      if (point != null && progress > 0)
                        Opacity(
                          opacity: _settleInterval.transform(progress),
                          child: _SelectedRate(
                            point: point,
                            baseCode: widget.baseCode,
                            targetCode: widget.targetCode,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 높이는 갱신 상태만큼만 쓰되, 폭은 그 글자가 아니라 줄 전체를 쓴다.
            SizedBox(
              width: double.infinity,
              child: Stack(
                children: [
                  Opacity(
                    opacity: compared ? 1 - leave : 1,
                    child: widget.status,
                  ),
                  if (compared)
                    Positioned.fill(
                      child: _ComparisonRow(
                        comparison: comparison,
                        targetCode: widget.targetCode,
                        latestLabel: widget.historicalRate
                            ? '최근 기록'
                            : widget.staleRate
                            ? '저장값'
                            : '최신',
                        progress: progress,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 오른쪽 자리에 보여 주는 선택 기록의 날짜와 환율.
class _SelectedRate extends StatelessWidget {
  const _SelectedRate({
    required this.point,
    required this.baseCode,
    required this.targetCode,
  });

  final ChartPoint point;
  final String baseCode;
  final String targetCode;

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
            '${ChartAmountConverter.formatAmount(point.rate)} $targetCode',
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
class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.comparison,
    required this.targetCode,
    required this.latestLabel,
    required this.progress,
  });

  final ChartRateComparison comparison;
  final String targetCode;
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
    final differenceText = ChartAmountConverter.formatAmount(
      comparison.difference.abs(),
    );
    // 표시 글자가 0이면 부호와 색도 없다.
    final difference = differenceText == '0' ? 0.0 : comparison.difference;
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
    final settle = _settleInterval.transform(progress);
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
                      '${ChartAmountConverter.formatAmount(comparison.selectedAmount)}'
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
                    '${ChartAmountConverter.formatAmount(comparison.latestAmount)}'
                    ' $targetCode',
                alignment: AlignmentDirectional.center,
                labelOpacity: _arrivedInterval.transform(progress),
                valueOpacity: _leaveInterval.transform(progress),
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
