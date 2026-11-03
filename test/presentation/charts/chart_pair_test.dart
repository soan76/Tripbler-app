import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';

DisplayCurrency fiat(String code) =>
    DisplayCurrency.fromFiat(findCurrencyByCode(code)!);
DisplayCurrency coin(String symbol) =>
    DisplayCurrency.fromCrypto(CryptoCoin(symbol: symbol, name: symbol));

void main() {
  const usdKrw = ChartPair.fiat('USD', 'KRW');
  const btc = ChartPair.crypto('BTC');

  test('ids round trip and invalid ids are rejected', () {
    expect(usdKrw.id, 'fiat:USD/KRW');
    expect(btc.id, 'crypto:BTC/KRW');
    expect(ChartPair.tryParse('fiat:USD/KRW'), usdKrw);
    expect(ChartPair.tryParse('crypto:BTC/KRW'), btc);
    for (final id in [
      '',
      'fiat:USD',
      'fiat:USD/USD',
      'fiat:XXX/KRW',
      'crypto:BTC/USD',
      'stock:USD/KRW',
      'fiat:usd/krw',
    ]) {
      expect(ChartPair.tryParse(id), isNull, reason: id);
    }
  });

  test('replacing a fiat side keeps the other side', () {
    expect(
      usdKrw.replace(base: true, currency: fiat('JPY')),
      const ChartPair.fiat('JPY', 'KRW'),
    );
    expect(
      usdKrw.replace(base: false, currency: fiat('EUR')),
      const ChartPair.fiat('USD', 'EUR'),
    );
    // 두 쪽이 같아지는 조합은 만들지 않는다.
    expect(usdKrw.replace(base: true, currency: fiat('KRW')), isNull);
    expect(usdKrw.replace(base: false, currency: fiat('USD')), isNull);
  });

  test('picking a coin on either side makes a coin/KRW pair', () {
    expect(
      usdKrw.replace(base: true, currency: coin('ETH')),
      const ChartPair.crypto('ETH'),
    );
    expect(
      const ChartPair.fiat(
        'USD',
        'JPY',
      ).replace(base: false, currency: coin('SOL')),
      const ChartPair.crypto('SOL'),
    );
    expect(
      btc.replace(base: true, currency: coin('DOGE')),
      const ChartPair.crypto('DOGE'),
    );
  });

  test('the KRW side of a coin pair only accepts KRW', () {
    expect(btc.replace(base: false, currency: fiat('KRW')), btc);
    expect(btc.replace(base: false, currency: fiat('USD')), isNull);
    expect(btc.replace(base: false, currency: coin('ETH')), isNull);
    // 코인 쪽을 국가 통화로 바꾸면 KRW 기준 국가 통화 쌍이 된다.
    expect(
      btc.replace(base: true, currency: fiat('USD')),
      const ChartPair.fiat('USD', 'KRW'),
    );
    expect(btc.replace(base: true, currency: fiat('KRW')), isNull);
  });

  test('options keep the current currency and drop impossible ones', () {
    final all = [
      fiat('KRW'),
      fiat('USD'),
      fiat('JPY'),
      coin('BTC'),
      coin('ETH'),
    ];
    String ids(List<DisplayCurrency> list) => list.map((c) => c.code).join(',');

    expect(ids(usdKrw.options(base: true, currencies: all)), 'USD,JPY,BTC,ETH');
    expect(
      ids(usdKrw.options(base: false, currencies: all)),
      'KRW,JPY,BTC,ETH',
    );
    expect(ids(btc.options(base: true, currencies: all)), 'USD,JPY,BTC,ETH');
    expect(ids(btc.options(base: false, currencies: all)), 'KRW');
  });

  test('currencyOf finds display models and falls back to the symbol', () {
    final eth = DisplayCurrency.fromCrypto(
      const CryptoCoin(symbol: 'ETH', name: 'Ethereum'),
    );
    const ethPair = ChartPair.crypto('ETH');
    expect(ethPair.currencyOf(base: true, currencies: [eth]), same(eth));
    expect(ethPair.currencyOf(base: false, currencies: [eth]).code, 'KRW');

    final unknown = btc.currencyOf(base: true, currencies: const []);
    expect(unknown.isCrypto, isTrue);
    expect(unknown.code, 'BTC');
    expect(usdKrw.currencyOf(base: true, currencies: const []).fiat, isNotNull);
  });

  test('pairs that differ only in direction are the same chart', () {
    const krwUsd = ChartPair.fiat('KRW', 'USD');
    expect(krwUsd == usdKrw, isFalse);
    expect(krwUsd.isSameChart(usdKrw), isTrue);
    expect(usdKrw.chartKey, krwUsd.chartKey);
    expect(usdKrw.isSameChart(const ChartPair.fiat('USD', 'EUR')), isFalse);
    expect(btc.isSameChart(const ChartPair.crypto('BTC')), isTrue);
    expect(btc.isSameChart(const ChartPair.crypto('ETH')), isFalse);
  });

  group('replaceShown keeps what the user sees on each side', () {
    test('a swapped fiat card keeps its direction', () {
      // "KRW ⇄ USD"로 보는 중 왼쪽 KRW(원래 대상)를 EUR로 바꾸면 "EUR ⇄ USD".
      final edit = usdKrw.replaceShown(
        base: false,
        swapped: true,
        currency: fiat('EUR'),
      )!;
      expect(edit.pair, const ChartPair.fiat('USD', 'EUR'));
      expect(edit.swapped, isTrue);
      // 오른쪽 USD(원래 기준)를 JPY로 바꾸면 "KRW ⇄ JPY".
      final right = usdKrw.replaceShown(
        base: true,
        swapped: true,
        currency: fiat('JPY'),
      )!;
      expect(right.pair, const ChartPair.fiat('JPY', 'KRW'));
      expect(right.swapped, isTrue);
    });

    test('a coin stays on the side it was picked on', () {
      // 정방향 "USD ⇄ KRW"의 오른쪽에서 코인을 고르면 "KRW ⇄ ETH".
      final right = usdKrw.replaceShown(
        base: false,
        swapped: false,
        currency: coin('ETH'),
      )!;
      expect(right.pair, const ChartPair.crypto('ETH'));
      expect(right.swapped, isTrue);
      // 뒤집힌 "KRW ⇄ USD"의 왼쪽에서 고르면 "ETH ⇄ KRW".
      final left = usdKrw.replaceShown(
        base: false,
        swapped: true,
        currency: coin('ETH'),
      )!;
      expect(left.pair, const ChartPair.crypto('ETH'));
      expect(left.swapped, isFalse);
      // 뒤집힌 코인 카드 "KRW ⇄ BTC"의 코인을 바꾸면 그대로 오른쪽에 둔다.
      final coinSide = btc.replaceShown(
        base: true,
        swapped: true,
        currency: coin('SOL'),
      )!;
      expect(coinSide.pair, const ChartPair.crypto('SOL'));
      expect(coinSide.swapped, isTrue);
    });

    test('a coin side changed to fiat keeps the KRW side in place', () {
      // "KRW ⇄ BTC"의 오른쪽 BTC를 USD로 바꾸면 "KRW ⇄ USD".
      final edit = btc.replaceShown(
        base: true,
        swapped: true,
        currency: fiat('USD'),
      )!;
      expect(edit.pair, usdKrw);
      expect(edit.swapped, isTrue);
      expect(
        btc.replaceShown(base: false, swapped: true, currency: fiat('KRW')),
        (pair: btc, swapped: true),
      );
      expect(
        btc.replaceShown(base: false, swapped: true, currency: fiat('USD')),
        isNull,
      );
    });
  });

  test('coins are unsupported only once a coin list was received', () {
    const old = ChartPair.crypto('OLD');
    expect(old.isUnsupportedIn(const []), isFalse);
    expect(old.isUnsupportedIn([fiat('KRW'), fiat('USD')]), isFalse);
    expect(old.isUnsupportedIn([fiat('KRW'), coin('BTC')]), isTrue);
    expect(old.isUnsupportedIn([coin('BTC'), coin('OLD')]), isFalse);
    expect(usdKrw.isUnsupportedIn([coin('BTC')]), isFalse);
  });
}
