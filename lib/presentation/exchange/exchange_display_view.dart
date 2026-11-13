import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../../crypto/providers/crypto_provider.dart';
import '../../models/currency_model.dart';
import '../../providers/exchange_provider.dart';
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
