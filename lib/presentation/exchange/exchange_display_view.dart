import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../../crypto/providers/crypto_provider.dart';
import '../../models/currency_model.dart';
import '../../providers/exchange/exchange_provider.dart';
import 'display_currency.dart';
import 'exchange_display_provider.dart';

/// 환산 화면의 한 행. 표시 금액과 입력 행 여부를 함께 담는다.
class DisplayRowView {
  const DisplayRowView({
    required this.currency,
    required this.amount,
    required this.isActive,
  });

  final DisplayCurrency currency;

  // 표시 금액. 코인 시세나 KRW 연결 환율이 없으면 null.
  final double? amount;

  // 지금 금액을 입력하고 있는 행인지
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisplayRowView &&
          other.currency == currency &&
          other.amount == amount &&
          other.isActive == isActive);

  @override
  int get hashCode => Object.hash(currency, amount, isActive);
}

/// 환율·암호화폐·표시 순서를 합친 화면용 값.
class ExchangeDisplayView {
  const ExchangeDisplayView({
    required this.base,
    required this.available,
    required this.rows,
  });

  final DisplayCurrency base;

  // 고를 수 있는 모든 통화(국가 통화 + 지원 코인)
  final List<DisplayCurrency> available;

  // 첫 행은 기준 통화이고, 그 뒤는 사용자가 정한 순서의 표시 통화다.
  final List<DisplayRowView> rows;

  /// 기준 통화를 뺀 표시 통화.
  List<DisplayCurrency> get visible => [
    for (final row in rows.skip(1)) row.currency,
  ];

  DisplayRowView rowOf(DisplayCurrency currency) =>
      rows.firstWhere((row) => row.currency.id == currency.id);

  /// 금액·입력 행을 뺀 통화 목록. 통화 목록만 쓰는 화면은 이 값을 `select`로 읽어
  /// 금액·시세가 바뀔 때 다시 그려지지 않게 한다.
  ExchangeDisplayCurrencies get currencies => ExchangeDisplayCurrencies(
    base: base,
    visible: visible,
    available: available,
  );

  // 값이 같으면 Provider가 구독자에게 알리지 않는다(Riverpod 3의 Provider는
  // 이전 값과 `!=`로 비교한다). 그래서 로딩 표시처럼 화면 값과 무관한 변경은 전파되지 않는다.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeDisplayView &&
          other.base == base &&
          listEquals(other.available, available) &&
          listEquals(other.rows, rows));

  @override
  int get hashCode =>
      Object.hash(base, Object.hashAll(available), Object.hashAll(rows));
}

/// 기준 통화·표시 통화·고를 수 있는 통화. 금액은 담지 않는다.
class ExchangeDisplayCurrencies {
  const ExchangeDisplayCurrencies({
    required this.base,
    required this.visible,
    required this.available,
  });

  final DisplayCurrency base;

  // 기준 통화를 뺀 표시 통화(화면 순서)
  final List<DisplayCurrency> visible;

  // 고를 수 있는 모든 통화(국가 통화 + 지원 코인)
  final List<DisplayCurrency> available;

  /// 화면에 보이는 순서의 모든 통화(기준 통화 먼저).
  List<DisplayCurrency> get displayed => [base, ...visible];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeDisplayCurrencies &&
          other.base == base &&
          listEquals(other.visible, visible) &&
          listEquals(other.available, available));

  @override
  int get hashCode =>
      Object.hash(base, Object.hashAll(visible), Object.hashAll(available));
}

final exchangeDisplayViewProvider = Provider<ExchangeDisplayView>((ref) {
  final exchange = ref.watch(exchangeProvider);
  final crypto = ref.watch(cryptoProvider);
  final display = ref.watch(exchangeDisplayProvider);

  final base = DisplayCurrency.fromFiat(exchange.baseCurrency);

  final candidates = [
    ...exchange.visibleCurrencies.map(DisplayCurrency.fromFiat),
    ...crypto.selectedCoins.map(DisplayCurrency.fromCrypto),
  ];
  final byId = {for (final row in candidates) row.id: row};
  final visible = [
    for (final id in display.order)
      if (byId.containsKey(id)) byId.remove(id)!,
    ...byId.values,
  ];

  final krwRate = exchange.baseCurrency.code == 'KRW' ? 1.0 : display.krwRate;

  double? amountFor(DisplayCurrency row) {
    if (!row.isCrypto) return exchange.convertedAmount(row.code);
    final price = crypto.priceFor(row.code)?.price;
    if (price == null || krwRate == null) return null;
    final value = exchange.inputAmount * krwRate / price;
    return value.isFinite ? value : null;
  }

  bool isActive(DisplayCurrency row) => row.isCrypto
      ? display.activeCrypto == row.code
      : display.activeCrypto == null &&
            exchange.activeInputCurrencyCode == row.code;

  return ExchangeDisplayView(
    base: base,
    available: List.unmodifiable([
      ...supportedCurrencies.map(DisplayCurrency.fromFiat),
      ...crypto.coins.map(DisplayCurrency.fromCrypto),
    ]),
    rows: List.unmodifiable([
      for (final row in [base, ...visible])
        DisplayRowView(
          currency: row,
          amount: amountFor(row),
          isActive: isActive(row),
        ),
    ]),
  );
});
