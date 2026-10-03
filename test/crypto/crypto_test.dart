import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/crypto/services/crypto_api_service.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/presentation/exchange/exchange_display_provider.dart';
import 'package:tripbler/providers/exchange_provider.dart';
import 'package:tripbler/services/exchange_rate_api_service.dart';

const coinFixture = [
  {'symbol': 'BTC', 'name': 'Bitcoin'},
  {'symbol': 'ETH', 'name': 'Ethereum'},
  {'symbol': 'SOL', 'name': 'Solana'},
  {'symbol': 'XRP', 'name': 'XRP'},
  {'symbol': 'DOGE', 'name': 'Dogecoin'},
  {'symbol': 'ADA', 'name': 'Cardano'},
  {'symbol': 'DASH', 'name': 'Dash'},
];
http.Response priceResponse(String symbol) => http.Response(
  jsonEncode({
    'symbol': symbol,
    'currency': 'KRW',
    'price': 100000000,
    'fetchedAt': '2026-10-02T01:00:00Z',
  }),
  200,
);

CryptoApiService makeApi() => CryptoApiService(
  client: MockClient((request) async {
    if (request.url.path.endsWith('/coins')) {
      return http.Response(jsonEncode(coinFixture), 200);
    }
    return priceResponse(request.url.queryParameters['coin']!);
  }),
);

class FiatApi extends ExchangeRateApiService {
  final List<List<String>> targets = [];
  @override
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    targets.add(targetCurrencies);
    return ExchangeRateResponse(
      baseCurrency: baseCurrency,
      rates: {
        for (final code in targetCurrencies)
          code: code == 'KRW' ? 1400 : 1 / 1400,
      },
      rateDate: null,
      fetchedAt: DateTime.utc(2026, 10, 2),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'server catalog and all seven prices use public symbols and KRW, no provider keys',
    () async {
      final requests = <http.Request>[];
      final api = CryptoApiService(
        client: MockClient((request) async {
          requests.add(request);
          return request.url.path.endsWith('/coins')
              ? http.Response(jsonEncode(coinFixture), 200)
              : priceResponse(request.url.queryParameters['coin']!);
        }),
      );
      addTearDown(api.dispose);
      final coins = await api.fetchCoins();
      expect(coins.map((e) => e.symbol), [
        'BTC',
        'ETH',
        'SOL',
        'XRP',
        'DOGE',
        'ADA',
        'DASH',
      ]);
      for (final coin in coins) {
        final price = await api.fetchPrice(coin.symbol);
        expect(price.symbol, coin.symbol);
        expect(price.fetchedAt.isUtc, isTrue);
      }
      expect(requests.length, 8);
      for (final request in requests.skip(1)) {
        expect(request.url.path, '/api/v1/crypto/price');
        expect(request.url.queryParameters['currency'], 'KRW');
        expect(request.headers.containsKey('x-cg-demo-api-key'), isFalse);
      }
    },
  );

  test('HTTP error retains backend status and code', () async {
    final api = CryptoApiService(
      client: MockClient(
        (_) async => http.Response(
          '{"code":"INVALID_REQUEST","message":"지원하지 않는 코인입니다."}',
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.fetchPrice('NOPE'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.code, 'code', 'INVALID_REQUEST'),
      ),
    );
  });

  test('zero price and mismatched symbol are rejected', () async {
    for (final body in [
      {
        'symbol': 'BTC',
        'currency': 'KRW',
        'price': 0,
        'fetchedAt': '2026-10-02T01:00:00Z',
      },
      {
        'symbol': 'ETH',
        'currency': 'KRW',
        'price': 100,
        'fetchedAt': '2026-10-02T01:00:00Z',
      },
    ]) {
      final api = CryptoApiService(
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      );
      await expectLater(api.fetchPrice('BTC'), throwsFormatException);
      api.dispose();
    }
  });

  test(
    'selection survives restart with cached catalog even while server is offline',
    () async {
      final api = makeApi();
      final provider = CryptoProvider(api: api);
      await provider.initialize();
      await provider.select(['BTC', 'DOGE', 'DASH', 'INVALID', 'BTC']);
      expect(provider.selectedCoins.map((e) => e.symbol), [
        'BTC',
        'DOGE',
        'DASH',
      ]);
      provider.dispose();
      api.dispose();
      final offlineApi = CryptoApiService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final restored = CryptoProvider(api: offlineApi);
      await restored.initialize();
      expect(restored.coins.length, 7);
      expect(restored.selectedCoins.first.name, 'Bitcoin');
      expect(restored.catalogError, isNotNull);
      expect(restored.priceFor('BTC'), isNull);
      expect(restored.errorFor('BTC'), isNotNull);
      await restored.select([]);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'crypto.selected.v1',
        ),
        isEmpty,
      );
      restored.dispose();
      offlineApi.dispose();
    },
  );

  test(
    'overlapping price requests coalesce and completion after disposal is safe',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final api = CryptoApiService(
        client: MockClient((_) {
          calls++;
          return response.future;
        }),
      );
      final provider = CryptoProvider(api: api);
      final first = provider.fetchPrice('BTC');
      final second = provider.fetchPrice('BTC');
      expect(identical(first, second), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      provider.dispose();
      response.complete(priceResponse('BTC'));
      await Future.wait([first, second]);
      api.dispose();
    },
  );

  test(
    'mixed display preserves order, converts both directions, and isolates fiat requests',
    () async {
      final api = makeApi();
      final crypto = CryptoProvider(api: api);
      final fiatApi = FiatApi();
      final exchange = ExchangeProvider(apiService: fiatApi);
      final display = ExchangeDisplayProvider(
        exchange,
        crypto,
        fiatApi: fiatApi,
      );
      await display.initialize();
      final btc = display.available.firstWhere((row) => row.code == 'BTC');
      final doge = display.available.firstWhere((row) => row.code == 'DOGE');
      final usd = DisplayCurrency.fromFiat(findCurrencyByCode('USD')!);
      await display.apply([btc, usd, doge]);
      expect(display.visible.map((e) => e.id), [
        'crypto:BTC',
        'fiat:USD',
        'crypto:DOGE',
      ]);
      expect(exchange.visibleCurrencies.map((e) => e.code), ['USD']);
      expect(display.amountFor(btc), closeTo(0.0001, 1e-12));
      await display.changeAmount(btc, 0.5);
      expect(exchange.inputAmount, 50000000);
      expect(display.isActive(btc), isTrue);
      await exchange.changeBaseCurrency(findCurrencyByCode('USD')!);
      await display.refreshConversion();
      await display.changeAmount(display.base, 100);
      expect(display.amountFor(btc), closeTo(0.0014, 1e-12));
      await display.changeAmount(btc, 0.0014);
      expect(exchange.inputAmount, closeTo(100, 1e-10));
      expect(
        fiatApi.targets
            .expand((e) => e)
            .every((e) => ['KRW', 'USD'].contains(e)),
        isTrue,
      );
      await display.apply([doge]);
      expect(display.visible.map((e) => e.code), ['DOGE']);
      expect(display.activeCrypto, isNull);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'exchange.displayOrder.v1',
        ),
        ['crypto:DOGE'],
      );
      display.dispose();
      exchange.dispose();
      crypto.dispose();
      api.dispose();
      fiatApi.dispose();
    },
  );
}
