import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/crypto/models/crypto_history.dart';
import 'package:tripbler/crypto/presentation/crypto_chart_data_source.dart';
import 'package:tripbler/crypto/services/crypto_api_service.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_axis_helper.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_data_calculator.dart';

Map<String, dynamic> historyJson(String symbol, String period) => {
  'symbol': symbol,
  'currency': 'KRW',
  'period': period,
  'days': CryptoHistory.supportedPeriods[period],
  'fetchedAt': '2026-10-03T00:00:00Z',
  'prices': [
    {
      'timestamp': DateTime.utc(2026, 10, 1, 10).millisecondsSinceEpoch,
      'price': 100000000,
    },
    {
      'timestamp': DateTime.utc(2026, 10, 1, 11).millisecondsSinceEpoch,
      'price': 101000000,
    },
  ],
};

http.Response historyResponse(String symbol, String period) =>
    http.Response(jsonEncode(historyJson(symbol, period)), 200);

void main() {
  test(
    'all supported periods call separate crypto endpoint with symbol and KRW',
    () async {
      final requests = <http.Request>[];
      final api = CryptoApiService(
        client: MockClient((request) async {
          requests.add(request);
          return historyResponse(
            request.url.queryParameters['coin']!,
            request.url.queryParameters['period']!,
          );
        }),
      );
      addTearDown(api.dispose);
      for (final symbol in [
        'BTC',
        'ETH',
        'SOL',
        'XRP',
        'DOGE',
        'ADA',
        'DASH',
      ]) {
        for (final period in CryptoHistory.supportedPeriods.keys) {
          final history = await api.fetchHistory(
            symbol: symbol,
            period: period,
          );
          expect(history.symbol, symbol);
          expect(
            history.prices[1].timestamp.difference(history.prices[0].timestamp),
            const Duration(hours: 1),
          );
          expect(history.fetchedAt.isUtc, isTrue);
        }
      }
      expect(requests.length, 35);
      for (final request in requests) {
        expect(request.url.path, '/api/v1/crypto/history');
        expect(request.url.queryParameters['currency'], 'KRW');
      }
    },
  );

  test('2Y and 5Y fail without consuming API calls', () async {
    var calls = 0;
    final api = CryptoApiService(
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    final source = CryptoChartDataSource(symbol: 'BTC', api: api);
    for (final period in [ChartPeriod.twoYears, ChartPeriod.fiveYears]) {
      await expectLater(source.load(period), throwsA(isA<ApiException>()));
    }
    expect(calls, 0);
    source.dispose();
    api.dispose();
  });

  test(
    'history validates prices, period, sorting and symbol identity',
    () async {
      for (final data in [
        {...historyJson('BTC', '7D'), 'days': 365},
        {
          ...historyJson('BTC', '7D'),
          'prices': [
            {'timestamp': 1, 'price': 0},
          ],
        },
        {
          ...historyJson('BTC', '7D'),
          'prices': [
            {'timestamp': 2, 'price': 1},
            {'timestamp': 1, 'price': 2},
          ],
        },
      ]) {
        expect(() => CryptoHistory.fromJson(data), throwsFormatException);
      }
      final api = CryptoApiService(
        client: MockClient((_) async => historyResponse('ETH', '7D')),
      );
      await expectLater(
        api.fetchHistory(symbol: 'BTC', period: '7D'),
        throwsFormatException,
      );
      api.dispose();
    },
  );

  test(
    'four-letter coin history adapts to common chart with intraday tooltip and limited labels',
    () async {
      final api = CryptoApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/history')) {
            return historyResponse('DOGE', '1M');
          }
          return http.Response(
            jsonEncode({
              'symbol': 'DOGE',
              'currency': 'KRW',
              'price': 250,
              'fetchedAt': '2026-10-03T00:00:00Z',
            }),
            200,
          );
        }),
      );
      final source = CryptoChartDataSource(symbol: 'DOGE', api: api);
      final data = await source.load(ChartPeriod.oneMonth);
      expect(data.history.first.baseCurrencyCode, 'DOGE');
      expect(data.history.first.targetCurrencyCode, 'KRW');
      expect(data.currentRate, 250);
      expect(data.history.first.includesTime, isTrue);
      expect(
        ExchangeChartAxisHelper.formatTooltipDate(
          DateTime(2026, 10, 1, 10),
          includesTime: true,
        ),
        '2026.10.01 10:00',
      );
      final labels = ExchangeChartDataCalculator.buildLimitedXLabelIndexes(
        721,
        6,
      );
      expect(labels.length, 6);
      expect(labels, containsAll([0, 720]));
      source.dispose();
      api.dispose();
    },
  );
}
