import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/widgets/charts/market_chart_card.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

import '../../helpers/memory_chart_snapshots.dart';

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

Widget btcCard(Source source, MemorySnapshots snapshots) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 430,
      child: MarketChartCard(
        baseCurrency: DisplayCurrency.fromCrypto(
          const CryptoCoin(symbol: 'BTC', name: 'Bitcoin'),
        ),
        targetCurrency: DisplayCurrency.fromFiat(supportedCurrencies.first),
        title: '차트',
        errorText: '실패',
        requestKey: 'crypto:BTC/KRW',
        createDataSource: () => source,
        period: ChartPeriod.oneMonth,
        shouldLoad: true,
        snapshotStore: snapshots,
      ),
    ),
  ),
);

const btcKey = 'crypto:BTC/KRW/oneMonth';

double shownFirstRate(WidgetTester tester) => tester
    .widget<ExchangeRateLineChart>(find.byType(ExchangeRateLineChart))
    .history
    .first
    .rate;

double chartOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byKey(const ValueKey('market-chart-fade')))
    .opacity
    .value;

void main() {
  testWidgets(
    'persisted chart stays visible during revalidation, failure and successful retry',
    (tester) async {
      final snapshots = MemorySnapshots()..saved[btcKey] = data(100);
      final source = Source();
      await tester.pumpWidget(btcCard(source, snapshots));
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
      expect(shownFirstRate(tester), 200);
      expect(find.text('마지막 성공 데이터 · 갱신 지연'), findsNothing);
      // 새로 받은 값이 저장소에 남는다.
      expect(snapshots.saved[btcKey]!.currentRate, 200);
      await tester.pumpWidget(const SizedBox());
    },
  );

  // 같은 파일의 두 번째 위젯 테스트에서도 카드의 스냅샷 쓰기와 저장값 읽기가
  // 멈추지 않는지 확인한다(실제 저장소의 정적 쓰기 큐를 거치지 않는다).
  testWidgets('a later widget test still saves and reads chart snapshots', (
    tester,
  ) async {
    final first = MemorySnapshots();
    final firstSource = Source();
    await tester.pumpWidget(btcCard(firstSource, first));
    await tester.pump();
    expect(first.reads, [btcKey]);
    firstSource.requests.single.complete(data(300));
    await tester.pumpAndSettle();
    expect(shownFirstRate(tester), 300);
    expect(first.saved[btcKey]!.currentRate, 300);
    expect(first.saved[btcKey]!.history.first.rate, 300);
    await tester.pumpWidget(const SizedBox());

    // 앞에서 저장한 값을 새 카드가 먼저 보여 주고, 다시 받은 값으로 덮어쓴다.
    final source = Source();
    await tester.pumpWidget(btcCard(source, first));
    await tester.pump();
    await tester.pump();
    expect(find.text('저장된 데이터 · 갱신 중'), findsOneWidget);
    expect(shownFirstRate(tester), 300);
    source.requests.single.complete(data(400));
    await tester.pumpAndSettle();
    expect(shownFirstRate(tester), 400);
    expect(find.text('저장된 데이터 · 갱신 중'), findsNothing);
    expect(first.saved[btcKey]!.currentRate, 400);
    await tester.pumpWidget(const SizedBox());
  });

  // 실제 저장소를 쓰면 앞선 테스트가 남긴 쓰기 큐 때문에 저장값을 미리 넣을 수
  // 없어 이 파일에 두지 못했던 경우다.
  testWidgets('fresh data after a stored chart does not fade again', (
    tester,
  ) async {
    final snapshots = MemorySnapshots()..saved[btcKey] = data(100);
    final source = Source();
    await tester.pumpWidget(btcCard(source, snapshots));
    for (
      var i = 0;
      i < 10 && find.byType(ExchangeRateLineChart).evaluate().isEmpty;
      i++
    ) {
      await tester.pump();
    }
    expect(find.text('저장된 데이터 · 갱신 중'), findsOneWidget);
    // 저장값이 처음 나타날 때의 페이드(0.5초)가 끝날 때까지 기다린다.
    await tester.pump(const Duration(milliseconds: 500));
    expect(chartOpacity(tester), 1);

    source.requests.single.complete(data(200));
    await tester.pump();
    expect(shownFirstRate(tester), 200);
    expect(chartOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(chartOpacity(tester), 1);
    await tester.pumpAndSettle();
    // 앞선 위젯 테스트가 있어도 새로 받은 값이 저장된다.
    expect(snapshots.saved[btcKey]!.currentRate, 200);
    await tester.pumpWidget(const SizedBox());
  });
}
