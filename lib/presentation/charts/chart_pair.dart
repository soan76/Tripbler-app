import 'package:flutter/foundation.dart';

import '../../crypto/models/crypto_coin.dart';
import '../../models/currency_model.dart';
import '../exchange/display_currency.dart';

/// 차트 카드 하나가 보여 주는 통화쌍. "1 [baseCode] = 환율 [targetCode]" 방향이다.
/// 암호화폐 기간별 시세는 서버가 KRW 기준만 제공하므로 코인 쌍의 상대는 KRW로 고정한다.
@immutable
class ChartPair {
  const ChartPair.fiat(this.baseCode, this.targetCode) : isCrypto = false;
  const ChartPair.crypto(String symbol)
    : baseCode = symbol,
      targetCode = cryptoQuote,
      isCrypto = true;

  static const cryptoQuote = 'KRW';

  final String baseCode;
  final String targetCode;
  final bool isCrypto;

  /// 카드 ID이자 조회·캐시·방향 저장 키. 예: `fiat:USD/KRW`, `crypto:BTC/KRW`.
  String get id => '${isCrypto ? 'crypto' : 'fiat'}:$baseCode/$targetCode';

  /// 저장된 ID를 읽는다. 지원하지 않는 통화나 형식이면 null.
  static ChartPair? tryParse(String id) {
    final match = RegExp(
      r'^(fiat|crypto):([A-Z0-9]+)/([A-Z]+)$',
    ).firstMatch(id);
    if (match == null) return null;
    final base = match.group(2)!;
    final target = match.group(3)!;
    if (match.group(1) == 'crypto') {
      return target == cryptoQuote ? ChartPair.crypto(base) : null;
    }
    if (base == target ||
        findCurrencyByCode(base) == null ||
        findCurrencyByCode(target) == null) {
      return null;
    }
    return ChartPair.fiat(base, target);
  }

  /// 한쪽([base]이면 기준, 아니면 대상) 통화를 [currency]로 바꾼 쌍.
  /// 코인을 고르면 어느 쪽이든 `코인/KRW`가 된다. 두 통화가 같아지거나 코인 쌍의
  /// KRW를 다른 통화로 바꾸려는 경우처럼 만들 수 없는 조합이면 null.
  ChartPair? replace({required bool base, required DisplayCurrency currency}) {
    final code = currency.code;
    // 코인 쌍의 KRW 쪽은 KRW만 고를 수 있다.
    if (isCrypto && !base) {
      return !currency.isCrypto && code == cryptoQuote ? this : null;
    }
    if (currency.isCrypto) return ChartPair.crypto(code);
    if (isCrypto) {
      return code == cryptoQuote ? null : ChartPair.fiat(code, cryptoQuote);
    }
    final next = base
        ? ChartPair.fiat(code, targetCode)
        : ChartPair.fiat(baseCode, code);
    return next.baseCode == next.targetCode ? null : next;
  }

  /// 방향을 뺀 차트 키. USD/KRW와 KRW/USD는 뒤집어 보면 같은 차트이므로 키가 같다.
  String get chartKey {
    if (isCrypto) return id;
    final codes = [baseCode, targetCode]..sort();
    return 'fiat:${codes.join('/')}';
  }

  /// 방향만 다른 쌍까지 같은 차트로 본다.
  bool isSameChart(ChartPair other) => other.chartKey == chartKey;

  /// [swapped] 방향으로 보이는 카드에서 원래 방향 기준 [base] 쪽 통화를 [currency]로
  /// 바꾼 결과. 고른 통화는 누른 자리에, 반대쪽 통화도 원래 자리에 보이도록 새 쌍과
  /// 표시 방향을 돌려준다. 코인을 골라 `코인/KRW`가 되면 코인을 고른 쪽에 코인이
  /// 보이게 방향을 정한다(오른쪽에서 고르면 "KRW ⇄ 코인"). 만들 수 없는 조합이면 null.
  ({ChartPair pair, bool swapped})? replaceShown({
    required bool base,
    required bool swapped,
    required DisplayCurrency currency,
  }) {
    final next = replace(base: base, currency: currency);
    if (next == null) return null;
    // 국가 통화를 고르면 바뀐 쪽만 같은 자리에서 바뀌므로 방향을 그대로 둔다.
    if (!currency.isCrypto) return (pair: next, swapped: swapped);
    final pickedLeft = base != swapped;
    return (pair: next, swapped: !pickedLeft);
  }

  /// 받은 코인 목록에 없는 코인 쌍인지. [currencies]에 코인이 하나도 없으면(목록을
  /// 아직 못 받았거나 조회에 실패해 비어 있음) 판단하지 않고 false다.
  bool isUnsupportedIn(List<DisplayCurrency> currencies) {
    if (!isCrypto) return false;
    var hasCoins = false;
    for (final currency in currencies) {
      if (!currency.isCrypto) continue;
      if (currency.code == baseCode) return false;
      hasCoins = true;
    }
    return hasCoins;
  }

  /// 한쪽 통화의 표시 모델을 [currencies]에서 찾는다. 목록에 없는 코인(목록을 아직
  /// 못 받은 경우)은 심볼만으로 만든다.
  DisplayCurrency currencyOf({
    required bool base,
    required List<DisplayCurrency> currencies,
  }) {
    final crypto = base && isCrypto;
    final code = base ? baseCode : targetCode;
    final id = '${crypto ? 'crypto' : 'fiat'}:$code';
    for (final currency in currencies) {
      if (currency.id == id) return currency;
    }
    return crypto
        ? DisplayCurrency.fromCrypto(CryptoCoin(symbol: code, name: code))
        : DisplayCurrency.fromFiat(findCurrencyByCode(code)!);
  }

  /// 한쪽 통화를 고를 때 보여 줄 후보. 현재 통화도 포함하고(선택 표시용),
  /// 고르면 만들 수 없는 조합이 되는 통화는 뺀다.
  List<DisplayCurrency> options({
    required bool base,
    required List<DisplayCurrency> currencies,
  }) => [
    for (final currency in currencies)
      if (replace(base: base, currency: currency) != null) currency,
  ];

  @override
  bool operator ==(Object other) => other is ChartPair && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ChartPair($id)';
}
