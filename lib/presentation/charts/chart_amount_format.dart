import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../domain/exchange/exchange_calculator.dart';
import '../../widgets/exchange/exchange_chart_axis_helper.dart';

/// 차트의 금액·환율·변화량 표시 글자와 입력 글자 처리.
class ChartAmountFormat {
  ChartAmountFormat._();

  /// 입력 글자를 금액으로 바꾼다. 비었거나 숫자가 아니면 null이다.
  static double? parseAmount(String text) {
    final amount = double.tryParse(text.replaceAll(',', ''));
    return amount != null && amount.isFinite ? amount : null;
  }

  /// 환산 금액을 표시 글자로 바꾼다. 계산할 수 없으면 null이다.
  static String? convertedText(String text, double rate, {int? maxDecimals}) {
    final amount = parseAmount(text);
    if (amount == null) return null;
    final result = const ExchangeCalculator().convertFromBase(
      baseAmount: amount,
      rate: rate,
    );
    return result.isFinite
        ? formatAmount(result, maxDecimals: maxDecimals)
        : null;
  }

  /// 금액이나 환율(현재 환율, 환산 결과, 선택일 환율, 비교 금액)을 표시 글자로 바꾼다.
  ///
  /// [maxDecimals]가 있으면 설정의 자릿수 제한에 맞춰 반올림한다. 다만 0이 아니고
  /// 절댓값이 표시 단위(10^-[maxDecimals])보다 작은 값(예: 1원의 달러 환율)은 제한하면
  /// 0이나 단위 하나로 뭉개지므로, 제한 없이 아래 기본 표시를 쓴다.
  /// 예: 2자리에서 0.006은 "0.006", 0.0123은 "0.01". 0자리에서 0.4는 "0.4", 0.6은 "0.6",
  /// 1.4는 "1".
  ///
  /// 제한이 없으면 1 미만 값은 반전된 코인 환율처럼 아주 작을 수 있어 유효숫자 기준으로
  /// 표시한다. 0(-0.0 포함)은 언제나 "0"이다.
  ///
  /// 변화량·차이는 [formatChange]를 쓴다.
  static String formatAmount(double value, {int? maxDecimals}) {
    // 0(-0.0 포함)은 아래 기본 표시로 가고, 거기서 "0"이 된다.
    if (maxDecimals != null &&
        value.isFinite &&
        value != 0 &&
        !usesFullPrecision(value, maxDecimals)) {
      return _limitedFormat(maxDecimals).format(value);
    }

    return value.abs() < 1
        ? ExchangeChartAxisHelper.formatRate(value)
        : _resultFormat.format(value);
  }

  /// [formatAmount]가 [maxDecimals] 제한 대신 제한 없는 기본 표시를 쓰는 값인지.
  /// 0이 아니고 절댓값이 표시 단위(10^-[maxDecimals])보다 작은 유한한 값이다.
  /// [formatAmount]와 [formatChange]가 이 한 곳의 판정을 함께 쓴다.
  static bool usesFullPrecision(double value, int maxDecimals) =>
      value.isFinite &&
      value != 0 &&
      value.abs() < 1 / math.pow(10, maxDecimals);

  /// 기간 변화량이나 비교 차이를 표시 글자로 바꾼다. [compared]는 차이를 낸 두 값
  /// (기간 시작 값과 현재 환율, 또는 선택일 금액과 최신 금액)이다.
  ///
  /// - 제한이 없으면 [formatAmount]와 같다.
  /// - [compared] 중 하나라도 [usesFullPrecision]이면(화면에 제한 없이 보이면) 차이도
  ///   제한 없이 [formatAmount] 기본 표시로 보여 준다. 두 값이 서로 다르게 보이는데
  ///   차이만 반올림돼 0이 되지 않게 한다. 이때 "0"은 차이가 정확히 0일 때뿐이다.
  /// - 두 값이 모두 제한 자릿수로 보이면 차이도 제한대로 반올림한다. 두 값이 같게
  ///   보이는데 차이만 더 긴 소수로 보이지 않게 한다. 반올림해 0이 되면 "0"이다.
  ///
  /// 화면은 "0"([isZeroText])을 "변동 없음"(부호·색 없음)으로 본다.
  /// 예(2자리): 0.00070 → 0.00072는 "0.00002"(▲), 1,300.12 → 1,300.1249는 "0"(변동 없음),
  /// 선택일 0.0072 → 최신 0.01은 "0.0028".
  static String formatChange(
    double value, {
    int? maxDecimals,
    List<double> compared = const [],
  }) {
    if (maxDecimals == null ||
        !value.isFinite ||
        compared.any((v) => usesFullPrecision(v, maxDecimals))) {
      return formatAmount(value);
    }
    final text = _limitedFormat(maxDecimals).format(value);
    return isZeroText(text) ? '0' : text;
  }

  /// 표시 글자가 0을 나타내는지("0", "-0", "0.00" 등).
  static bool isZeroText(String text) =>
      double.tryParse(text.replaceAll(',', '')) == 0;

  static final _resultFormat = NumberFormat('#,##0.######');

  static final _limitedFormats = <int, NumberFormat>{};

  static NumberFormat _limitedFormat(int maxDecimals) =>
      _limitedFormats.putIfAbsent(
        maxDecimals,
        () => NumberFormat(
          maxDecimals > 0 ? '#,##0.${'#' * maxDecimals}' : '#,##0',
        ),
      );

  /// 입력 글자의 소수 부분을 [maxDecimals]자리까지 자른다(반올림하지 않음).
  /// 0자리면 소수점도 지운다("1,234." → "1,234").
  static String trimDecimals(String text, int? maxDecimals) {
    if (maxDecimals == null) return text;
    final dot = text.indexOf('.');
    if (dot < 0) return text;
    if (maxDecimals == 0) return text.substring(0, dot);
    final decimals = text.length - dot - 1;
    if (decimals <= maxDecimals) return text;
    return text.substring(0, dot + 1 + maxDecimals);
  }
}
