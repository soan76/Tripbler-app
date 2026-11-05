import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/widgets/charts/chart_amount_converter.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';

import '../../helpers/memory_chart_snapshots.dart';

const usd = ChartPair.fiat('USD', 'KRW');
const eur = ChartPair.fiat('EUR', 'KRW');
const jpy = ChartPair.fiat('JPY', 'KRW');
const rates = {'USD': 1300.0, 'EUR': 1500.0, 'JPY': 9.0};

final amount = find.byKey(const ValueKey('market-chart-amount'));
final converted = find.byKey(const ValueKey('market-chart-converted'));
final swap = find.byKey(const ValueKey('market-chart-swap'));

class Source implements ChartDataSource {
  Source(this.rate, {this.historical = false});

  final double? rate;
  final bool historical;

  @override
  Future<ChartData> load(ChartPeriod period) async => ChartData(
    history: [
      for (var i = 0; i < 3; i++)
        ChartSample(
          date: DateTime(2026, 1, 1 + i),
          rate: rate ?? 100,
          baseCurrencyCode: 'USD',
          targetCurrencyCode: 'KRW',
        ),
    ],
    currentRate: rate,
    historicalRate: historical,
    fetchedAt: DateTime(2026, 1, 3),
  );

  @override
  void dispose() {}
}

Widget charts(
  List<ChartPair> pairs, {
  MemorySnapshots? snapshots,
  ChartDataSource Function(ChartPair)? source,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: ChartPairCarousel(
        pairs: pairs,
        currencies: const [],
        snapshotStore: snapshots ?? MemorySnapshots(),
        createDataSource: source ?? (pair) => Source(rates[pair.baseCode]),
      ),
    ),
  ),
);

String convertedText(WidgetTester tester) =>
    tester.widget<Text>(converted).data!;

Future<void> enter(WidgetTester tester, String text) async {
  await tester.enterText(amount, text);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parseAmount', () {
    test('reads digits, decimals and display commas', () {
      expect(ChartAmountConverter.parseAmount('1,234.5'), 1234.5);
      expect(ChartAmountConverter.parseAmount('5.'), 5);
    });

    test('is null when empty or not a number', () {
      expect(ChartAmountConverter.parseAmount(''), isNull);
      expect(ChartAmountConverter.parseAmount('.'), isNull);
      expect(ChartAmountConverter.parseAmount('abc'), isNull);
    });
  });

  group('typing', () {
    testWidgets('shows nothing until an amount is entered', (tester) async {
      await tester.pumpWidget(charts(const [usd]));
      await tester.pumpAndSettle();
      expect(find.text('USD 금액'), findsOneWidget);
      expect(converted, findsNothing);
    });

    testWidgets('converts at once and clears when emptied', (tester) async {
      await tester.pumpWidget(charts(const [usd]));
      await tester.pumpAndSettle();

      await enter(tester, '2');
      expect(convertedText(tester), '2,600 KRW');
      await enter(tester, '25');
      expect(convertedText(tester), '32,500 KRW');
      await enter(tester, '');
      expect(converted, findsNothing);
    });

    testWidgets('accepts only digits and a point, and shows commas', (
      tester,
    ) async {
      await tester.pumpWidget(charts(const [usd]));
      await tester.pumpAndSettle();

      await enter(tester, '1234.5');
      expect(tester.widget<TextField>(amount).controller!.text, '1,234.5');
      expect(convertedText(tester), '1,604,850 KRW');

      await enter(tester, 'abc');
      expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
      expect(converted, findsNothing);
    });
  });

  group('changing what is converted', () {
    testWidgets('swap exchanges the sides and converts the same amount', (
      tester,
    ) async {
      await tester.pumpWidget(charts(const [usd]));
      await tester.pumpAndSettle();
      await enter(tester, '2600');
      expect(convertedText(tester), '3,380,000 KRW');

      await tester.tap(swap);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amount).controller!.text, '2,600');
      expect(convertedText(tester), '2 USD');

      await tester.tap(swap);
      await tester.pumpAndSettle();
      expect(convertedText(tester), '3,380,000 KRW');
    });

    testWidgets('a currency changed in place keeps the amount at its rate', (
      tester,
    ) async {
      final snapshots = MemorySnapshots();
      await tester.pumpWidget(charts(const [usd], snapshots: snapshots));
      await tester.pumpAndSettle();
      await enter(tester, '2');

      await tester.pumpWidget(charts(const [eur], snapshots: snapshots));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amount).controller!.text, '2');
      expect(convertedText(tester), '3,000 KRW');
    });

    testWidgets('a new period keeps the amount', (tester) async {
      await tester.pumpWidget(charts(const [usd]));
      await tester.pumpAndSettle();
      await enter(tester, '2');

      await tester.tap(find.text('3M'));
      await tester.pumpAndSettle();
      expect(convertedText(tester), '2,600 KRW');
    });

    testWidgets('each card keeps its own amount', (tester) async {
      await tester.pumpWidget(charts(const [usd, jpy]));
      await tester.pumpAndSettle();
      await enter(tester, '2');

      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      // 넘겨 온 카드에는 앞 카드의 금액이 없다.
      expect(converted, findsNothing);

      await enter(tester, '3');
      expect(convertedText(tester), '27 KRW');

      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(convertedText(tester), '2,600 KRW');
    });

    testWidgets('a removed card forgets its amount', (tester) async {
      final snapshots = MemorySnapshots();
      await tester.pumpWidget(charts(const [usd, jpy], snapshots: snapshots));
      await tester.pumpAndSettle();
      await enter(tester, '2');

      await tester.pumpWidget(charts(const [jpy], snapshots: snapshots));
      await tester.pumpAndSettle();
      await tester.pumpWidget(charts(const [usd, jpy], snapshots: snapshots));
      await tester.pumpAndSettle();

      // 보고 있던 JPY 페이지를 유지하므로 다시 추가한 USD로 넘겨서 확인한다.
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(find.text('USD 금액'), findsOneWidget);
      expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
      expect(converted, findsNothing);
    });
  });

  group('when there is no plain current rate', () {
    testWidgets('a missing rate says so instead of a result', (tester) async {
      await tester.pumpWidget(charts(const [usd], source: (_) => Source(null)));
      await tester.pumpAndSettle();
      await enter(tester, '2');
      expect(find.text('현재 환율 정보 없음'), findsOneWidget);
      expect(converted, findsNothing);
    });

    testWidgets('a rate taken from history is labelled', (tester) async {
      await tester.pumpWidget(
        charts(const [usd], source: (_) => Source(1300, historical: true)),
      );
      await tester.pumpAndSettle();
      await enter(tester, '2');
      expect(convertedText(tester), '최근 기록 · 2,600 KRW');
    });

    testWidgets('a long result fits a 320 wide screen', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(charts(const [usd]));
      await tester.pumpAndSettle();
      await enter(tester, '123456789012.5');
      expect(converted, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
