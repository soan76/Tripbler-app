import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/main.dart' show buildAppScope;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import '../../helpers/chart_selection_handle.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/providers/settings_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';
import 'package:tripbler/widgets/exchange/amount_input_field.dart';
import 'package:tripbler/widgets/exchange/currency_management_bottom_sheet.dart';
import 'package:tripbler/widgets/exchange/currency_row.dart';
import '../../crypto/crypto_test.dart' show coinFixture, makeApi, FiatApi;
import '../../helpers/exchange_handles.dart';

void main() {
  final coins = coinFixture
      .map((json) => DisplayCurrency.fromCrypto(CryptoCoin.fromJson(json)))
      .toList();
  final base = DisplayCurrency.fromFiat(findCurrencyByCode('KRW')!);

  testWidgets(
    'main screen adds/removes crypto without touching the chart selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = makeApi();
      final fiatApi = FiatApi();
      final harness = ExchangeHarness.create(cryptoApi: api, fiatApi: fiatApi);
      final crypto = harness.crypto;
      final exchange = harness.exchange;
      final display = harness.display;
      await display.initialize();
      final charts = ChartSelectionHandle.of(tester);
      await tester.pumpWidget(
        harness.scope(
          const MaterialApp(home: Scaffold(body: ExchangeScreen())),
        ),
      );
      await tester.pumpAndSettle();
      // 차트는 위쪽 목록과 상관없이 기본 통화쌍으로 시작하고 통화/암호 전환이 없다.
      expect(find.byType(ChartPairCarousel), findsOneWidget);
      expect(charts.pairs, ChartSelectionNotifier.defaults);
      expect(
        find.byWidgetPredicate((widget) => widget is SegmentedButton),
        findsNothing,
      );
      await tester.tap(find.text('통화 추가 / 편집'));
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(CurrencyManagementBottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'bitcoin');
      await tester.pumpAndSettle();
      expect(find.text('BTC · Bitcoin'), findsNothing);
      await tester.tap(find.text('암호'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('BTC · Bitcoin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BTC · Bitcoin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyRow), findsNWidgets(2));
      expect(find.byKey(const ValueKey('crypto:BTC')), findsOneWidget);
      expect(find.text('환율 흐름'), findsOneWidget);
      expect(charts.pairs, ChartSelectionNotifier.defaults);
      expect(exchange.visibleCurrencies, isEmpty);
      await tester.tap(find.text('통화 추가 / 편집'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyRow), findsOneWidget);
      expect(crypto.selectedCoins, isEmpty);
      expect(charts.pairs, ChartSelectionNotifier.defaults);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      harness.dispose();
      api.dispose();
      fiatApi.dispose();
    },
  );

  testWidgets(
    'all seven use common management rows; symbol/name search, add and delete',
    (tester) async {
      List<DisplayCurrency>? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CurrencyManagementBottomSheet(
              baseCurrency: base,
              visibleCurrencies: const [],
              availableCurrencies: [base, ...coins],
              onApply: (rows) => applied = rows,
            ),
          ),
        ),
      );
      expect(find.text('BTC · Bitcoin'), findsNothing);
      await tester.tap(find.text('암호'));
      await tester.pump();
      for (final row in coins) {
        await tester.enterText(
          find.byType(TextField),
          ' ${row.code.toLowerCase()} ',
        );
        await tester.pump();
        expect(find.text('${row.code} · ${row.countryName}'), findsOneWidget);
      }
      await tester.enterText(find.byType(TextField), 'bitcoin');
      await tester.pump();
      await tester.tap(find.text('BTC · Bitcoin'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.byIcon(Icons.remove), findsOneWidget);
      await tester.tap(find.text('통화'));
      await tester.pump();
      expect(find.text('BTC · Bitcoin'), findsOneWidget);
      expect(find.text('ETH · Ethereum'), findsNothing);
      await tester.tap(find.text('암호'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(find.byIcon(Icons.remove), findsNothing);
      await tester.enterText(find.byType(TextField), 'dogecoin');
      await tester.pump();
      await tester.tap(find.text('DOGE · Dogecoin'));
      await tester.pump();
      await tester.tap(find.text('완료'));
      expect(applied!.map((e) => e.id), ['crypto:DOGE']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared CurrencyRow supports four-character symbols and no crypto graph',
    (tester) async {
      double? amount;
      await tester.pumpWidget(
        buildAppScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: CurrencyRow(
                  currency: coins.firstWhere((e) => e.code == 'DASH'),
                  amount: 0.00012345,
                  onCurrencyTap: () {},
                  onAmountChanged: (value) => amount = value,
                  status: '1 DASH = 100000 KRW',
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(AmountInputField), findsOneWidget);
      expect(find.byIcon(Icons.show_chart), findsNothing);
      await tester.enterText(find.byType(TextField), '0.002');
      expect(amount, 0.002);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing quote disables input and renders dash instead of zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildAppScope(
        child: MaterialApp(
          home: Scaffold(
            body: CurrencyRow(
              currency: coins.first,
              amount: null,
              onCurrencyTap: () {},
            ),
          ),
        ),
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);
    expect(field.controller!.text, '—');
    expect(tester.takeException(), isNull);
  });
  Future<String> rowText(
    WidgetTester tester,
    DisplayCurrency currency,
    double amount, {
    int? decimalPlaces,
  }) async {
    await tester.pumpWidget(
      buildAppScope(
        overrides: [
          if (decimalPlaces != null)
            settingsProvider.overrideWithBuild(
              (ref, notifier) => SettingsState(decimalPlaces: decimalPlaces),
            ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: CurrencyRow(
                currency: currency,
                amount: amount,
                onCurrencyTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    return tester.widget<TextField>(find.byType(TextField)).controller!.text;
  }

  testWidgets('자동 자릿수: 국가 통화는 소수 2자리, 코인은 5자리까지 표시', (tester) async {
    final usd = DisplayCurrency.fromFiat(findCurrencyByCode('USD')!);
    final btc = coins.firstWhere((e) => e.code == 'BTC');

    expect(await rowText(tester, usd, 1234.56789), '1,234.57');
    expect(await rowText(tester, base, 1500), '1,500');
    expect(await rowText(tester, btc, 0.0123456789), '0.01235');
    expect(await rowText(tester, btc, 2), '2');
  });

  testWidgets('자동 자릿수: 입력도 국가 통화 2자리, 코인 5자리까지만 받는다', (tester) async {
    final usd = DisplayCurrency.fromFiat(findCurrencyByCode('USD')!);
    final btc = coins.firstWhere((e) => e.code == 'BTC');

    await rowText(tester, usd, 0);
    await tester.enterText(find.byType(TextField), '1.23');
    await tester.enterText(find.byType(TextField), '1.234');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1.23',
    );

    await rowText(tester, btc, 0);
    await tester.enterText(find.byType(TextField), '0.12345');
    await tester.enterText(find.byType(TextField), '0.123456');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '0.12345',
    );
  });

  testWidgets('직접 고른 자릿수는 국가 통화와 코인에 똑같이 적용', (tester) async {
    final usd = DisplayCurrency.fromFiat(findCurrencyByCode('USD')!);
    final btc = coins.firstWhere((e) => e.code == 'BTC');

    expect(await rowText(tester, usd, 1.23456, decimalPlaces: 3), '1.235');
    expect(await rowText(tester, btc, 1.23456, decimalPlaces: 3), '1.235');
  });
}
