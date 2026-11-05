import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/exchange/exchange_calculator.dart';
import '../exchange/amount_input_field.dart';
import '../exchange/exchange_chart_axis_helper.dart';

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
class ChartAmountConverter extends StatefulWidget {
  const ChartAmountConverter({
    super.key,
    required this.rate,
    required this.baseCode,
    required this.targetCode,
    required this.historicalRate,
    this.message,
  });

  final double? rate;
  final String baseCode;
  final String targetCode;

  /// 현재 시세를 받지 못해 기록의 마지막 값으로 계산하는지.
  final bool historicalRate;
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
    if (!result.isFinite) return null;
    // 1 미만 값은 반전된 코인 환율처럼 아주 작을 수 있어 유효숫자 기준으로 표시한다.
    return result.abs() < 1
        ? ExchangeChartAxisHelper.formatRate(result)
        : _resultFormat.format(result);
  }

  static final _resultFormat = NumberFormat('#,##0.######');

  @override
  State<ChartAmountConverter> createState() => _ChartAmountConverterState();
}

class _ChartAmountConverterState extends State<ChartAmountConverter> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ChartAmountScope.maybeOf(context)?.text ?? '',
    );
  }

  void _onChanged(String text) {
    ChartAmountScope.maybeOf(context)?.onChanged(text);
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = TextStyle(color: theme.colorScheme.onSurfaceVariant);

    final message = widget.message;
    if (message != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(message, style: mutedStyle),
        ),
      );
    }

    final rate = widget.rate;
    final hasRate = const ExchangeCalculator().isValidRate(rate);
    final converted = hasRate
        ? ChartAmountConverter.convertedText(_controller.text, rate!)
        : null;

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('market-chart-amount'),
            controller: _controller,
            onChanged: _onChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ThousandsSeparatorInputFormatter(decimalPlaces: -1),
            ],
            style: theme.textTheme.titleMedium,
            decoration: InputDecoration(
              hintText: '${widget.baseCode} 금액',
              // isDense를 쓰지 않아 글꼴과 관계없이 터치 높이 48dp가 보장된다.
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: !hasRate
                ? Text(
                    '현재 환율 정보 없음',
                    textAlign: TextAlign.end,
                    style: mutedStyle,
                  )
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
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
