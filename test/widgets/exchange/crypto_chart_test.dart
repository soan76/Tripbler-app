import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/crypto/services/crypto_api_service.dart';
import 'package:tripbler/crypto/widgets/crypto_chart_carousel.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';
import '../../crypto/crypto_history_test.dart' show historyResponse;

const btc = CryptoCoin(symbol: 'BTC', name: 'Bitcoin');
const doge = CryptoCoin(symbol: 'DOGE', name: 'Dogecoin');

http.Response quote(String symbol) => http.Response(
  jsonEncode({
    'symbol': symbol,
    'currency': 'KRW',
    'price': 12345,
    'fetchedAt': '2026-10-03T00:00:00Z',
  }),
  200,
);

Widget app(
  CryptoApiService api,
  List<CryptoCoin> coins, {
  bool active = true,
}) => MaterialApp(
  home: Scaffold(
    body: CryptoChartCarousel(coins: coins, api: api, active: active),
  ),
);

void main() {
  testWidgets(
    'shared chart keeps all period buttons; 2Y/5Y show failure and valid periods recover',
    (tester) async {
      final requests = <Uri>[];
      final api = CryptoApiService(
        client: MockClient((request) async {
          requests.add(request.url);
          return request.url.path.endsWith('/history')
              ? historyResponse(
                  request.url.queryParameters['coin']!,
                  request.url.queryParameters['period']!,
                )
              : quote(request.url.queryParameters['coin']!);
        }),
      );
      await tester.pumpWidget(app(api, [btc]));
      await tester.pumpAndSettle();
      expect(find.byType(ExchangeRateLineChart), findsOneWidget);
      expect(find.text('BTC / KRW'), findsOneWidget);
      expect(find.text('1 BTC'), findsOneWidget);
      final initialCount = requests.length;
      for (final period in ['2Y', '5Y']) {
        await tester.tap(find.text(period));
        await tester.pumpAndSettle();
        expect(find.text('암호화폐 차트를 불러오지 못했습니다.'), findsOneWidget);
        expect(find.byType(ExchangeRateLineChart), findsNothing);
      }
      expect(requests.length, initialCount);
      await tester.tap(find.text('7D'));
      await tester.pumpAndSettle();
      expect(find.byType(ExchangeRateLineChart), findsOneWidget);
      expect(find.text('암호화폐 차트를 불러오지 못했습니다.'), findsNothing);
      expect(
        requests
            .where((uri) => uri.path.endsWith('/history'))
            .last
            .queryParameters['period'],
        '7D',
      );
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'only selected visible coin loads; last-card removal resets page safely',
    (tester) async {
      final symbols = <String>[];
      final api = CryptoApiService(
        client: MockClient((request) async {
          final symbol = request.url.queryParameters['coin']!;
          if (request.url.path.endsWith('/history')) {
            symbols.add(symbol);
            return historyResponse(
              symbol,
              request.url.queryParameters['period']!,
            );
          }
          return quote(symbol);
        }),
      );
      await tester.pumpWidget(app(api, [btc, doge], active: false));
      await tester.pumpAndSettle();
      expect(symbols, isEmpty);
      await tester.pumpWidget(app(api, [btc, doge]));
      await tester.pumpAndSettle();
      expect(symbols, ['BTC']);
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(symbols, ['BTC', 'DOGE']);
      expect(find.text('DOGE / KRW').hitTestable(), findsOneWidget);
      await tester.pumpWidget(app(api, [btc]));
      await tester.pumpAndSettle();
      expect(find.text('BTC / KRW').hitTestable(), findsOneWidget);
      expect(find.text('DOGE / KRW'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(api, []));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'late response after period switch and removal cannot replace current chart',
    (tester) async {
      final pending = Completer<http.Response>();
      final api = CryptoApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/history')) {
            if (request.url.queryParameters['period'] == '1M') {
              return pending.future;
            }
            return historyResponse('BTC', '7D');
          }
          return quote('BTC');
        }),
      );
      await tester.pumpWidget(app(api, [btc]));
      await tester.pump();
      await tester.tap(find.text('7D'));
      await tester.pumpAndSettle();
      expect(find.byType(ExchangeRateLineChart), findsOneWidget);
      pending.complete(historyResponse('BTC', '1M'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExchangeRateLineChart>(find.byType(ExchangeRateLineChart))
            .period
            .name,
        'sevenDays',
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      api.dispose();
    },
  );
}
