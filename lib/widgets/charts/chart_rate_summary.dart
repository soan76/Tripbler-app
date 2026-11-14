import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/chart_point.dart';
import '../../models/exchange_rate_history_model.dart';
import '../exchange/amount_input_field.dart';
import 'chart_amount_converter.dart';

/// 차트 카드 위쪽의 현재 환율과 기간 동안의 변화.
///
/// 현재 환율을 크게 보여 주고, 그 아래 "▲ 13.2 (0.96%) 1개월 전보다"처럼 기간 첫 기록과의
/// 차이를 한 줄로 보여 준다. 값이 아직 없거나 계산할 수 없을 때도 같은 높이를 차지해,
/// 불러오는 동안이나 카드를 넘길 때 아래 내용이 움직이지 않게 한다.
class ChartRateSummary extends StatelessWidget {
  const ChartRateSummary({
    super.key,
    required this.rate,
    required this.history,
    required this.period,
    required this.baseCode,
    required this.targetCode,
    this.historicalRate = false,
    this.decimalPlaces,
  });

  /// 화면 방향(뒤집혀 있으면 뒤집은 값)의 현재 환율. 없으면 null.
  final double? rate;

  /// 화면 방향의 기록. 첫 기록을 기간 시작 값으로 쓴다.
  final List<ChartPoint> history;
  final ChartPeriod period;
  final String baseCode;
  final String targetCode;

  /// [rate]가 지금 시세가 아니라 기록의 마지막 값인지. 단위 뒤에 "최근 기록"을 붙인다.
  final bool historicalRate;

  /// 환율과 변화량의 최대 소수점 자릿수(설정의 자릿수 제한). null이면 제한 없음.
  final int? decimalPlaces;

  /// 기간 시작 값과의 차이와 그 표시 글자(부호 없는 크기). 계산할 수 없으면 null.
  ///
  /// 표시 규칙은 [ChartAmountConverter.formatChange]를 따른다. 기간 시작 값이나 현재
  /// 환율이 제한 없이 보이면 차이도 제한 없이, 아니면 [maxDecimals]로 반올림해 보여
  /// 준다. 표시가 0이면 [value]도 0(변동 없음)이다.
  static ({double value, String text})? changeOf(
    double? rate,
    List<ChartPoint> history, {
    int? maxDecimals,
  }) {
    if (rate == null || !rate.isFinite || history.isEmpty) return null;
    final start = history.first.rate;
    if (!start.isFinite || start <= 0) return null;
    final change = rate - start;
    if (!change.isFinite) return null;
    // 표시하면 0이 되는 차이는 오르내림으로 보지 않는다.
    final text = ChartAmountConverter.formatChange(
      change.abs(),
      maxDecimals: maxDecimals,
      compared: [start, rate],
    );
    return ChartAmountConverter.isZeroText(text)
        ? (value: 0.0, text: '0')
        : (value: change, text: text);
  }

  /// 큰 환율의 글자 배율 상한. 이미 큰 글자라 더 키우지 않아도 읽히고, 높이가 고정된
  /// 카드에서 그래프 자리를 지킨다(Android 14의 비선형 글자 배율과 같은 생각).
  static const _rateMaxTextScale = 1.3;

  /// 변화 줄의 자리. 실제 문구가 없거나 줄어들어도 이 한 줄 높이를 지킨다.
  static const _reservedChange = '▲ 0 (0.00%)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final mutedColor = colorScheme.onSurfaceVariant;
    final rate = this.rate;
    final hasRate = rate != null && rate.isFinite;

    // 카드에서 가장 먼저 읽을 숫자다. 아래 금액 환산 결과(titleLarge)보다 한 단계 크게 써
    // 두 숫자가 경쟁하지 않게 한다. 굵기는 환율 화면의 입력·원화 금액과 같은 이유로
    // 사용자가 정한 금지 목록 예외다.
    final rateStyle = textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: amountFontFeatures,
    );
    final unitStyle = textTheme.bodyMedium?.copyWith(color: mutedColor);
    final changeStyle = textTheme.labelLarge;

    final periodChange = changeOf(rate, history, maxDecimals: decimalPlaces);
    Widget? changeText;
    if (periodChange != null) {
      final change = periodChange.value;
      final start = history.first.rate;
      final fixedPercent = (change / start * 100).abs().toStringAsFixed(2);
      // 변화량은 보이는데 퍼센트가 0.00으로 반올림되면 오르내림과 어긋나 보이므로 "<0.01"로 쓴다.
      final tinyPercent = change != 0 && fixedPercent == '0.00';
      final percent = tinyPercent ? '<0.01' : fixedPercent;
      final up = change > 0;
      final down = change < 0;
      final color = up
          ? colorScheme.gain
          : down
          ? colorScheme.loss
          : mutedColor;
      final sign = up
          ? '▲ '
          : down
          ? '▼ '
          : '';
      final amount = periodChange.text;
      changeText = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: change == 0 ? '변동 없음' : '$sign$amount ($percent%)',
              style: changeStyle?.copyWith(
                color: color,
                fontFeatures: amountFontFeatures,
              ),
            ),
            TextSpan(
              text: '  ${period.label} 전보다',
              style: textTheme.labelMedium?.copyWith(color: mutedColor),
            ),
          ],
        ),
        key: const ValueKey('market-chart-period-change'),
        // 화면 낭독기가 ▲·▼를 도형 이름으로 읽지 않게 말로 풀어 준다.
        semanticsLabel: change == 0
            ? '${period.label} 전보다 변동 없음'
            : '${period.label} 전보다 $amount ${up ? '오름' : '내림'}, '
                  '${tinyPercent ? '0.01% 미만' : '$percent%'}',
        maxLines: 1,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          // 큰 숫자 아래 끝에 단위를 맞춘다. FittedBox는 기준선을 주지 않아 아래 끝으로 맞춘다.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 큰 글자 배율에서도 단위가 숫자 자리를 빼앗지 않게 숫자에 폭의 2/3까지 준다.
            // 넘치는 쪽은 잘리지 않고 글자를 줄여 맞춘다(긴 코인 코드, 아주 작은 환율).
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  hasRate
                      ? ChartAmountConverter.formatAmount(
                          rate,
                          maxDecimals: decimalPlaces,
                        )
                      : '—',
                  key: const ValueKey('market-chart-current-rate'),
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: _rateMaxTextScale),
                  style: rateStyle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.bottomStart,
                child: Text(
                  // 금액 환산 줄과 같은 말로 기록에서 온 값임을 알린다.
                  '$targetCode / 1 $baseCode'
                  '${hasRate && historicalRate ? ' · 최근 기록' : ''}',
                  maxLines: 1,
                  style: unitStyle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 긴 문구는 "…"로 자르지 않고 줄여서 "1개월 전보다"까지 읽히게 한다. 줄어도
        // 자리는 [_reservedChange] 한 줄 높이를 지켜, 불러오는 동안과 높이가 같다.
        Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            // 투명도 0은 그리지 않고 화면 낭독기에서도 빠진다.
            Opacity(
              opacity: 0,
              child: Text(_reservedChange, maxLines: 1, style: changeStyle),
            ),
            if (changeText != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: changeText,
              ),
          ],
        ),
      ],
    );
  }
}
