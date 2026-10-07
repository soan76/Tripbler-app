import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/crypto/services/crypto_api_service.dart';
import 'package:tripbler/services/market_snapshot_store.dart';
import 'package:tripbler/crypto/presentation/crypto_chart_data_source.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'crypto_history_test.dart' show historyResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cached price is available before slow network ends and remains after failure',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('crypto.selected.v1', ['BTC']);
      await prefs.setString(
        'crypto.catalog.v1',
        '[{"symbol":"BTC","name":"Bitcoin"}]',
      );
      final time = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await MarketSnapshotStore().write('crypto.price.BTC.KRW', {
        'symbol': 'BTC',
        'currency': 'KRW',
        'price': 50000,
        'fetchedAt': time.toIso8601String(),
      });
      final pending = Completer<http.Response>();
      final api = CryptoApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/coins')) {
            return http.Response('[{"symbol":"BTC","name":"Bitcoin"}]', 200);
          }
          return pending.future;
        }),
      );
      final provider = CryptoProvider(api: api);
      await provider.initialize();
      expect(provider.priceFor('BTC')!.price, 50000);
      expect(provider.priceFor('BTC')!.fetchedAt, time);
      expect(provider.isStale('BTC'), isTrue);
      pending.complete(http.Response('{}', 503));
      await provider.refresh();
      expect(provider.priceFor('BTC')!.price, 50000);
      expect(provider.errorFor('BTC'), isNotNull);
      provider.dispose();
      api.dispose();
    },
  );

  test(
    'new success persists without changing its timestamp on reload',
    () async {
      final time = DateTime.now().toUtc();
      final api = CryptoApiService(
        client: MockClient(
          (request) async => request.url.path.endsWith('/coins')
              ? http.Response('[{"symbol":"BTC","name":"Bitcoin"}]', 200)
              : http.Response(
                  jsonEncode({
                    'symbol': 'BTC',
                    'currency': 'KRW',
                    'price': 60000,
                    'fetchedAt': time.toIso8601String(),
                  }),
                  200,
                ),
        ),
      );
      final provider = CryptoProvider(api: api);
      await provider.initialize();
      await provider.refresh();
      await provider.select(['BTC']);
      expect(provider.isStale('BTC'), isFalse);
      final saved = await MarketSnapshotStore().read(
        'crypto.price.BTC.KRW',
        const Duration(minutes: 15),
      );
      expect(saved!['price'], 60000);
      expect(DateTime.parse(saved['fetchedAt'] as String), time);
      provider.dispose();
      api.dispose();
    },
  );

  test(
    'history survives current-price failure and labels its quote as historical',
    () async {
      final api = CryptoApiService(
        client: MockClient(
          (request) async => request.url.path.endsWith('/history')
              ? historyResponse('BTC', '7D')
              : http.Response('{}', 503),
        ),
      );
      final source = CryptoChartDataSource(symbol: 'BTC', api: api);
      final data = await source.load(ChartPeriod.sevenDays);
      expect(data.history, hasLength(2));
      expect(data.currentRate, data.history.last.rate);
      expect(data.historicalRate, isTrue);
      source.dispose();
      api.dispose();
    },
  );

  test('expired and corrupt disk snapshots are ignored', () async {
    final store = MarketSnapshotStore();
    await store.write('old', {
      'fetchedAt': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
    });
    expect(await store.read('old', const Duration(hours: 1)), isNull);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('market.snapshot.v1.bad', '{broken');
    expect(await store.read('bad', const Duration(hours: 1)), isNull);
  });
}
