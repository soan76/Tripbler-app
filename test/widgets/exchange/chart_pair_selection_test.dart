import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import 'package:tripbler/presentation/exchange/exchange_display_provider.dart';
import 'package:tripbler/providers/exchange_provider.dart';
import 'package:tripbler/providers/settings_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/widgets/exchange/chart_currency_picker_sheet.dart';
import 'package:tripbler/widgets/exchange/currency_search_parts.dart';
import '../../crypto/crypto_test.dart' show makeApi, FiatApi;

const swapKey = ValueKey('market-chart-swap');

Finder pick(String id) => find.byKey(ValueKey('market-chart-pick-$id'));
Finder option(String id) => find.byKey(ValueKey('chart-option-$id'));

void main() {
  late CryptoProvider crypto;
  late ExchangeProvider exchange;
  late ExchangeDisplayProvider display;
  late ChartSelectionProvider charts;
  late FiatApi fiatApi;

  Future<void> pumpScreen(WidgetTester tester) async {
    final api = makeApi();
    crypto = CryptoProvider(api: api);
    fiatApi = FiatApi();
    exchange = ExchangeProvider(apiService: fiatApi);
    display = ExchangeDisplayProvider(exchange, crypto, fiatApi: fiatApi);
    charts = ChartSelectionProvider();
    await display.initialize();
    addTearDown(() {
      charts.dispose();
      display.dispose();
      exchange.dispose();
      crypto.dispose();
      api.dispose();
      fiatApi.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: crypto),
          ChangeNotifierProvider.value(value: exchange),
          ChangeNotifierProvider.value(value: display),
          ChangeNotifierProvider.value(value: charts),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: ExchangeScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'chart currencies are picked from a searchable sheet, apart from the top list',
    (tester) async {
      await pumpScreen(tester);
      final visibleBefore = exchange.visibleCurrencies.map((c) => c.code);
      final baseBefore = exchange.baseCurrency.code;
      expect(charts.pairs, ChartSelectionProvider.defaults);

      // 두 통화명 옆에 드롭다운 표시가 있고 스왑 버튼도 그대로 있다.
      expect(pick('fiat:USD'), findsOneWidget);
      expect(pick('fiat:KRW'), findsOneWidget);
      expect(
        find.descendant(
          of: pick('fiat:USD'),
          matching: find.byIcon(Icons.arrow_drop_down),
        ),
        findsOneWidget,
      );
      expect(find.byKey(swapKey), findsOneWidget);

      await tapVisible(tester, pick('fiat:USD'));
      expect(find.byType(ChartCurrencyPicker), findsOneWidget);
      // 통화 관리의 '통화 추가'와 같은 검색 입력과 통화/암호 전환을 쓴다.
      expect(find.byType(CurrencySearchField), findsOneWidget);
      expect(find.byType(CurrencyCategoryFilter), findsOneWidget);
      // 반대쪽과 같은 통화(KRW)는 고를 수 없다.
      expect(option('fiat:KRW'), findsNothing);
      expect(
        find.descendant(
          of: option('fiat:USD'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).last, 'eur');
      await tester.pumpAndSettle();
      expect(option('fiat:USD'), findsNothing);
      await tester.tap(option('fiat:EUR'));
      await tester.pumpAndSettle();

      expect(find.byType(ChartCurrencyPicker), findsNothing);
      expect(charts.pairs.first, const ChartPair.fiat('EUR', 'KRW'));
      expect(pick('fiat:EUR'), findsOneWidget);
      // 위쪽 환율 계산용 선택은 바뀌지 않는다.
      expect(exchange.visibleCurrencies.map((c) => c.code), visibleBefore);
      expect(exchange.baseCurrency.code, baseBefore);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          ChartSelectionProvider.storageKey,
        ),
        ['fiat:EUR/KRW', 'fiat:JPY/KRW', 'crypto:BTC/KRW'],
      );

      // 다른 카드에 이미 있는 쌍은 만들지 않고 알려 준다.
      await tapVisible(tester, pick('fiat:EUR'));
      await tester.enterText(find.byType(TextField).last, 'jpy');
      await tester.pumpAndSettle();
      await tester.tap(option('fiat:JPY'));
      await tester.pumpAndSettle();
      expect(find.text('이미 같은 통화쌍의 차트가 있습니다.'), findsOneWidget);
      expect(charts.pairs.first, const ChartPair.fiat('EUR', 'KRW'));

      // 위쪽 기준 통화를 바꿔도 차트 선택은 그대로다.
      await exchange.changeBaseCurrency(findCurrencyByCode('USD')!);
      await tester.pumpAndSettle();
      expect(charts.pairs.first, const ChartPair.fiat('EUR', 'KRW'));
    },
  );

  testWidgets('picking a coin fixes the other side to KRW', (tester) async {
    await pumpScreen(tester);

    await tapVisible(tester, pick('fiat:USD'));
    await tester.tap(find.text('암호'));
    await tester.pumpAndSettle();
    await tester.tap(option('crypto:ETH'));
    await tester.pumpAndSettle();
    expect(charts.pairs.first, const ChartPair.crypto('ETH'));

    // 코인 차트의 KRW 쪽은 KRW만 보이고 통화/암호 전환도 없다.
    await tapVisible(tester, pick('fiat:KRW').first);
    expect(find.text('코인 차트는 KRW 기준만 지원합니다.'), findsOneWidget);
    expect(find.byType(CurrencyCategoryFilter), findsNothing);
    expect(option('fiat:KRW'), findsOneWidget);
    expect(option('fiat:USD'), findsNothing);
    expect(option('crypto:BTC'), findsNothing);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(charts.pairs.first, const ChartPair.crypto('ETH'));
  });

  testWidgets('cards can be added up to five and removed down to one', (
    tester,
  ) async {
    await pumpScreen(tester);
    final addButton = find.byKey(const ValueKey('market-chart-add'));
    final pageView = find.byType(PageView);

    Future<void> goToLastPage() async {
      await tester.ensureVisible(pageView);
      for (var i = 0; i < 6; i++) {
        await tester.drag(pageView, const Offset(-700, 0));
        await tester.pumpAndSettle();
      }
    }

    await goToLastPage();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(charts.pairs, hasLength(4));
    // 추가하면 새 카드로 넘어간다.
    expect(pick('fiat:${charts.pairs.last.baseCode}').hitTestable(), findsOne);

    await goToLastPage();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    expect(charts.pairs, hasLength(5));
    await goToLastPage();
    expect(addButton, findsNothing);

    // 삭제는 실수로 누르지 않도록 더보기 메뉴 안에 있다.
    final menu = find.byKey(const ValueKey('market-chart-menu'));
    final remove = find.byKey(const ValueKey('market-chart-remove'));
    expect(remove, findsNothing);
    while (charts.pairs.length > 1) {
      await tester.tap(menu.hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('차트 삭제'), findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
    }
    expect(charts.pairs, hasLength(1));
    expect(menu, findsNothing);
    expect(remove, findsNothing);
    expect(tester.takeException(), isNull);
  });

  double x(WidgetTester tester, String id) =>
      tester.getCenter(pick(id).first).dx;

  Future<List<String>> storedSwaps() async =>
      (await SharedPreferences.getInstance()).getStringList(
        'chart.swapped.v1',
      ) ??
      const [];

  testWidgets('changing a swapped card keeps both sides where they are', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tapVisible(tester, find.byKey(swapKey));
    expect(x(tester, 'fiat:KRW'), lessThan(x(tester, 'fiat:USD')));

    // "KRW ⇄ USD"의 왼쪽 KRW를 EUR로 바꾸면 "EUR ⇄ USD"로 보인다.
    await tapVisible(tester, pick('fiat:KRW'));
    await tester.enterText(find.byType(TextField).last, 'eur');
    await tester.pumpAndSettle();
    await tester.tap(option('fiat:EUR'));
    await tester.pumpAndSettle();

    expect(charts.pairs.first, const ChartPair.fiat('USD', 'EUR'));
    expect(x(tester, 'fiat:EUR'), lessThan(x(tester, 'fiat:USD')));
    expect(await storedSwaps(), ['fiat:USD/EUR']);
  });

  testWidgets('a coin picked on the right side is shown on the right', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(x(tester, 'fiat:USD'), lessThan(x(tester, 'fiat:KRW')));

    await tapVisible(tester, pick('fiat:KRW'));
    await tester.tap(find.text('암호'));
    await tester.pumpAndSettle();
    await tester.tap(option('crypto:ETH'));
    await tester.pumpAndSettle();

    expect(charts.pairs.first, const ChartPair.crypto('ETH'));
    expect(x(tester, 'fiat:KRW'), lessThan(x(tester, 'crypto:ETH')));
    expect(await storedSwaps(), ['crypto:ETH/KRW']);
  });

  testWidgets(
    'a pick is dropped if the card changed while the sheet was open',
    (tester) async {
      await pumpScreen(tester);
      await tapVisible(tester, pick('fiat:USD'));
      expect(find.byType(ChartCurrencyPicker), findsOneWidget);

      // 선택창이 열린 사이 다른 경로로 카드가 바뀐다.
      charts.replace(0, const ChartPair.fiat('EUR', 'KRW'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'gbp');
      await tester.pumpAndSettle();
      await tester.tap(option('fiat:GBP'));
      await tester.pumpAndSettle();
      expect(find.byType(ChartCurrencyPicker), findsNothing);
      expect(charts.pairs.first, const ChartPair.fiat('EUR', 'KRW'));
      expect(find.text('이미 같은 통화쌍의 차트가 있습니다.'), findsNothing);
    },
  );
}
