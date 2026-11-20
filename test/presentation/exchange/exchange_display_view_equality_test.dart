import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/presentation/exchange/exchange_display_view.dart';
import 'package:tripbler/services/local_storage_service.dart';

import '../../helpers/exchange_handles.dart';
import 'exchange_display_view_test.dart'
    show HeldFiatApi, PriceApi, btc, seed, settle, usd;

DisplayCurrency fiat(String code) =>
    DisplayCurrency.fromFiat(findCurrencyByCode(code)!);

ExchangeDisplayView viewOf({
  double? usdAmount = 7.5,
  bool usdActive = false,
  List<DisplayCurrency>? order,
}) {
  final krw = fiat('KRW');
  final visible = order ?? [fiat('USD'), fiat('JPY')];
  return ExchangeDisplayView(
    base: krw,
    available: [krw, fiat('USD'), fiat('JPY'), btc],
    rows: [
      DisplayRowView(currency: krw, amount: 10000, isActive: !usdActive),
      for (final row in visible)
        DisplayRowView(
          currency: row,
          amount: row.code == 'USD' ? usdAmount : 1100,
          isActive: row.code == 'USD' && usdActive,
        ),
    ],
  );
}

void main() {
  group('값 동등성', () {
    test('같은 통화를 다시 만들면 같은 값이다', () {
      expect(fiat('USD'), fiat('USD'));
      expect(fiat('USD').hashCode, fiat('USD').hashCode);
      const coin = CryptoCoin(symbol: 'BTC', name: 'Bitcoin');
      expect(DisplayCurrency.fromCrypto(coin), btc);
      expect(DisplayCurrency.fromCrypto(coin).hashCode, btc.hashCode);
    });

    test('이름이 다른 코인이나 다른 통화는 다른 값이다', () {
      expect(fiat('USD'), isNot(fiat('JPY')));
      expect(
        DisplayCurrency.fromCrypto(
          const CryptoCoin(symbol: 'BTC', name: 'Bitcoin (new)'),
        ),
        isNot(btc),
      );
    });

    test('내용이 같은 화면 값은 같고 해시도 같다', () {
      expect(viewOf(), viewOf());
      expect(viewOf().hashCode, viewOf().hashCode);
    });

    test('금액·입력 행·순서가 바뀌면 다른 값이다', () {
      expect(viewOf(usdAmount: 8), isNot(viewOf()));
      expect(viewOf(usdAmount: null), isNot(viewOf()));
      expect(viewOf(usdActive: true), isNot(viewOf()));
      expect(viewOf(order: [fiat('JPY'), fiat('USD')]), isNot(viewOf()));
    });

    test('통화 목록 값은 금액·입력 행과 무관하고 순서에는 반응한다', () {
      expect(viewOf(usdAmount: 8).currencies, viewOf().currencies);
      expect(viewOf(usdActive: true).currencies, viewOf().currencies);
      expect(
        viewOf().currencies.hashCode,
        viewOf(usdAmount: 8).currencies.hashCode,
      );
      expect(
        viewOf(order: [fiat('JPY'), fiat('USD')]).currencies,
        isNot(viewOf().currencies),
      );
      expect(viewOf().currencies.displayed.map((row) => row.code), [
        'KRW',
        'USD',
        'JPY',
      ]);
    });
  });

  group('exchangeDisplayViewProvider 알림', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<(ExchangeHarness, HeldFiatApi, PriceApi)> start() async {
      await seed();
      final fiatApi = HeldFiatApi();
      final prices = PriceApi();
      addTearDown(prices.service.dispose);
      final harness = ExchangeHarness.create(
        fiatApi: fiatApi,
        cryptoApi: prices.service,
        storage: LocalStorageService(),
      );
      await harness.display.initialize();
      await harness.crypto.refresh();
      await settle();
      return (harness, fiatApi, prices);
    }

    test('환율 로딩 표시만 바뀌면 알리지 않는다', () async {
      final (harness, fiatApi, _) = await start();
      var updates = 0;
      harness.container.listen(
        exchangeDisplayViewProvider,
        (_, _) => updates++,
      );

      fiatApi.holdRates = true;
      final fetch = harness.exchange.fetchRates();
      await settle();
      expect(harness.exchange.isLoading, isTrue);
      expect(updates, 0);

      // 같은 환율이 다시 도착한다(로딩 해제·갱신 시각만 바뀜).
      fiatApi.rateRequests.single.complete(
        ExchangeRateResponse(
          baseCurrency: 'KRW',
          rates: const {'USD': 0.00075, 'JPY': 0.11},
          rateDate: null,
          fetchedAt: DateTime.utc(2026, 10, 3),
        ),
      );
      await fetch;
      await settle();
      expect(harness.exchange.isLoading, isFalse);
      expect(harness.exchange.lastUpdated, DateTime.utc(2026, 10, 3));
      expect(updates, 0);
    });

    test('같은 시세가 다시 와도 알리지 않는다', () async {
      final (harness, _, _) = await start();
      var updates = 0;
      harness.container.listen(
        exchangeDisplayViewProvider,
        (_, _) => updates++,
      );

      await harness.crypto.fetchPrice('BTC');
      await settle();

      expect(updates, 0);
    });

    test('금액·환율·코인 시세·순서가 바뀌면 알린다', () async {
      final (harness, fiatApi, prices) = await start();
      var updates = 0;
      harness.container.listen(
        exchangeDisplayViewProvider,
        (_, _) => updates++,
      );

      await harness.exchange.changeAmountFromCurrency(
        currencyCode: 'KRW',
        amount: 20000,
      );
      await settle();
      expect(updates, 1, reason: '금액 변경');

      fiatApi.holdRates = true;
      final fetch = harness.exchange.fetchRates();
      await settle();
      fiatApi.rateRequests.single.complete(
        ExchangeRateResponse(
          baseCurrency: 'KRW',
          rates: const {'USD': 0.0008, 'JPY': 0.11},
          rateDate: null,
          fetchedAt: DateTime.utc(2026, 10, 3),
        ),
      );
      await fetch;
      await settle();
      expect(updates, 2, reason: '환율 변경');
      expect(harness.display.amountFor(usd), closeTo(16, 1e-9));

      prices.btcPrice = 200;
      await harness.crypto.fetchPrice('BTC');
      await settle();
      expect(updates, 3, reason: '코인 시세 변경');

      final before = updates;
      await harness.display.apply([btc, fiat('JPY'), usd]);
      await settle();
      expect(updates, greaterThan(before), reason: '표시 순서 변경');
      expect(harness.display.visible.map((row) => row.id), [
        'crypto:BTC',
        'fiat:JPY',
        'fiat:USD',
      ]);
    });

    test('통화 목록만 고르면 금액·시세 변경에는 알리지 않고 순서 변경에는 알린다', () async {
      final (harness, _, prices) = await start();
      var updates = 0;
      harness.container.listen(
        exchangeDisplayViewProvider.select((view) => view.currencies),
        (_, _) => updates++,
      );

      await harness.exchange.changeAmountFromCurrency(
        currencyCode: 'KRW',
        amount: 20000,
      );
      prices.btcPrice = 300;
      await harness.crypto.fetchPrice('BTC');
      await settle();
      expect(updates, 0);

      await harness.display.apply([btc, fiat('JPY'), usd]);
      await settle();
      expect(updates, greaterThan(0));
    });
  });
}
