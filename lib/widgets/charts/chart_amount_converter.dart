import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/exchange/exchange_calculator.dart';
import '../../models/chart_point.dart';
import '../../presentation/charts/chart_amount_format.dart';
import '../../presentation/charts/chart_rate_comparison.dart';
import '../exchange/amount_input_field.dart';
import '../exchange/exchange_chart_data_calculator.dart';
import 'chart_amount_scope.dart';
import 'chart_selection_rows.dart';
import 'chart_swap_motion.dart';

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
    this.inputDecimalPlaces,
    this.resultDecimalPlaces,
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

  /// 입력칸([baseCode] 금액)에 넣을 수 있는 최대 소수점 자릿수. null이면 제한 없음.
  final int? inputDecimalPlaces;

  /// [targetCode]로 보여 주는 금액·환율의 최대 소수점 자릿수. null이면 제한 없음.
  final int? resultDecimalPlaces;

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
    // 다른 방향·카드에서 이어 받은 금액이 이 칸의 자릿수보다 길면 자른다.
    final scope = ChartAmountScope.maybeOf(context);
    final saved = scope?.text ?? '';
    final text = ChartAmountFormat.trimDecimals(
      saved,
      widget.inputDecimalPlaces,
    );
    if (text != saved) scope?.onChanged(text);
    _controller = TextEditingController(text: text);
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
    if (oldWidget.inputDecimalPlaces != widget.inputDecimalPlaces) {
      _trimInput();
    }
  }

  // 방향을 바꾸거나 설정을 바꿔 입력 자릿수가 줄면, 이미 넣은 금액도 그 자릿수로 자른다.
  // 그대로 두면 줄인 자릿수보다 긴 글자를 지울 수도 고칠 수도 없게 된다.
  void _trimInput() {
    final text = ChartAmountFormat.trimDecimals(
      _controller.text,
      widget.inputDecimalPlaces,
    );
    if (text == _controller.text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    ChartAmountScope.maybeOf(context)?.onChanged(text);
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
        ? ChartAmountFormat.convertedText(
            _controller.text,
            rate!,
            maxDecimals: widget.resultDecimalPlaces,
          )
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
            ThousandsSeparatorInputFormatter(
              decimalPlaces: widget.inputDecimalPlaces ?? -1,
            ),
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
        final leave = chartLeaveInterval.transform(progress);
        final point = _selectedPoint ?? _lastPoint;
        final comparison = point == null
            ? null
            : ChartRateComparison.of(
                amount: ChartAmountFormat.parseAmount(_controller.text),
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
                          opacity: chartSettleInterval.transform(progress),
                          child: ChartSelectedRate(
                            point: point,
                            baseCode: widget.baseCode,
                            targetCode: widget.targetCode,
                            maxDecimals: widget.resultDecimalPlaces,
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
                      child: ChartComparisonRow(
                        comparison: comparison,
                        targetCode: widget.targetCode,
                        maxDecimals: widget.resultDecimalPlaces,
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
