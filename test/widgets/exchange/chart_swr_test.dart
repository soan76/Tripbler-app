import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_snapshot_store.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/widgets/charts/market_chart_card.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

class Source implements ChartDataSource {
  final List<Completer<ChartData>> requests = [];
  @override
  Future<ChartData> load(ChartPeriod period) {
    final request = Completer<ChartData>();
    requests.add(request);
    return request.future;
  }

  @override
  void dispose() {}
}

ChartData data(double rate) => ChartData(
  history: [
    ChartSample(
      date: DateTime.now().subtract(const Duration(hours: 1)),
      rate: rate,
      baseCurrencyCode: 'BTC',
      targetCurrencyCode: 'KRW',
    ),
    ChartSample(
      date: DateTime.now(),
      rate: rate + 1,
      baseCurrencyCode: 'BTC',
      targetCurrencyCode: 'KRW',
    ),
  ],
  currentRate: rate,
  fetchedAt: DateTime.now(),
);

void main() {
  testWidgets(
    'persisted chart stays visible during revalidation, failure and successful retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await ChartSnapshotStore().write('crypto:BTC/KRW/oneMonth', data(100));
      final source = Source();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 430,
              child: MarketChartCard(
                iconCurrency: DisplayCurrency.fromCrypto(
                  const CryptoCoin(symbol: 'BTC', name: 'Bitcoin'),
                ),
                baseCode: 'BTC',
                targetCode: 'KRW',
                title: '차트',
                errorText: '실패',
                requestKey: 'crypto:BTC/KRW',
                createDataSource: () => source,
                period: ChartPeriod.oneMonth,
                shouldLoad: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(ExchangeRateLineChart), findsOneWidget);
      expect(find.text('저장된 데이터 · 갱신 중'), findsOneWidget);
      source.requests.single.completeError(StateError('timeout'));
      await tester.pumpAndSettle();
      expect(find.byType(ExchangeRateLineChart), findsOneWidget);
      expect(find.text('마지막 성공 데이터 · 갱신 지연'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(find.byType(ExchangeRateLineChart), findsOneWidget);
      source.requests.last.complete(data(200));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ExchangeRateLineChart>(find.byType(ExchangeRateLineChart))
            .history
            .first
            .rate,
        200,
      );
      expect(find.text('마지막 성공 데이터 · 갱신 지연'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
