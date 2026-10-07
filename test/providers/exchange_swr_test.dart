import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/providers/exchange_provider.dart';
import 'package:tripbler/services/exchange_rate_api_service.dart';
import 'package:tripbler/services/local_storage_service.dart';

class SlowApi extends ExchangeRateApiService {
  final pending = Completer<ExchangeRateResponse>();
  @override
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) => pending.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fiat initialization shows saved rates before response and keeps them on timeout',
    () async {
      final storage = LocalStorageService();
      final time = DateTime.now().subtract(const Duration(hours: 1));
      await storage.saveBaseCurrency('KRW');
      await storage.saveVisibleCurrencies(['USD']);
      await storage.saveCachedRates(baseCurrency: 'KRW', rates: {'USD': 0.001});
      await storage.saveLastUpdated(baseCurrency: 'KRW', dateTime: time);
      final api = SlowApi();
      final provider = ExchangeProvider(
        apiService: api,
        localStorageService: storage,
      );
      await provider.initialize();
      expect(provider.rateFor('USD'), 0.001);
      expect(provider.lastUpdated, time);
      expect(provider.isLoading, isTrue);
      final finished = Completer<void>();
      provider.addListener(() {
        if (!provider.isLoading && !finished.isCompleted) finished.complete();
      });
      api.pending.completeError(TimeoutException('slow'));
      await finished.future;
      expect(provider.rateFor('USD'), 0.001);
      expect(provider.errorMessage, contains('마지막 성공'));
      provider.dispose();
      api.dispose();
    },
  );

  test('late fiat response after provider disposal is ignored', () async {
    final storage = LocalStorageService();
    await storage.saveVisibleCurrencies(['USD']);
    final api = SlowApi();
    final provider = ExchangeProvider(
      apiService: api,
      localStorageService: storage,
    );
    await provider.initialize();
    await Future<void>.delayed(Duration.zero);
    provider.dispose();
    api.pending.complete(
      ExchangeRateResponse(
        baseCurrency: 'KRW',
        rates: {'USD': 0.001},
        rateDate: null,
        fetchedAt: DateTime.now(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    api.dispose();
  });
}
