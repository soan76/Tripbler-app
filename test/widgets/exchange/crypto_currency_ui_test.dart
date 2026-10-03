import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/crypto/widgets/crypto_chart_carousel.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/presentation/exchange/exchange_display_provider.dart';
import 'package:tripbler/providers/exchange_provider.dart';
import 'package:tripbler/providers/settings_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/widgets/exchange/amount_input_field.dart';
import 'package:tripbler/widgets/exchange/currency_management_bottom_sheet.dart';
import 'package:tripbler/widgets/exchange/currency_row.dart';
import '../../crypto/crypto_test.dart' show coinFixture, makeApi, FiatApi;

void main() {
  final coins = coinFixture
      .map((json) => DisplayCurrency.fromCrypto(CryptoCoin.fromJson(json)))
      .toList();
  final base = DisplayCurrency.fromFiat(findCurrencyByCode('KRW')!);

  testWidgets(
    'main screen defaults to fiat charts and adds/removes selected crypto',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
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
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: crypto),
            ChangeNotifierProvider.value(value: exchange),
            ChangeNotifierProvider.value(value: display),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: const MaterialApp(home: Scaffold(body: ExchangeScreen())),
        ),
      );
      await tester.pumpAndSettle();
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
      expect(find.text('차트'), findsOneWidget);
      expect(find.byType(CryptoChartCarousel), findsNothing);
      expect(
        tester
            .widget<SegmentedButton<ChartCategory>>(
              find.byType(SegmentedButton<ChartCategory>),
            )
            .selected,
        {ChartCategory.fiat},
      );
      expect(exchange.visibleCurrencies, isEmpty);
      await tester.tap(find.text('통화 추가 / 편집'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.text('완료'));
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyRow), findsOneWidget);
      expect(crypto.selectedCoins, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      display.dispose();
      exchange.dispose();
      crypto.dispose();
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
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: CurrencyRow(
                  currency: coins.firstWhere((e) => e.code == 'DASH'),
                  isBase: false,
                  amount: 0.00012345,
                  rate: null,
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
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: CurrencyRow(
              currency: coins.first,
              isBase: false,
              amount: null,
              rate: null,
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
}
