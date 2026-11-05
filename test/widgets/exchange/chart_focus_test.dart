import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/models/exchange_rate_response.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/presentation/exchange/exchange_display_provider.dart';
import 'package:tripbler/providers/exchange_provider.dart';
import 'package:tripbler/providers/settings_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';
import 'package:tripbler/widgets/charts/market_chart_header.dart';
import 'package:tripbler/widgets/exchange/chart_currency_picker_sheet.dart';
import 'package:tripbler/widgets/exchange/currency_management_bottom_sheet.dart';
import 'package:tripbler/widgets/exchange/currency_selection_sheet.dart';

import '../../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../../helpers/memory_chart_snapshots.dart';
import 'chart_delete_mode_test.dart' show revealVertically;

Finder pick(String id) => find.byKey(ValueKey('market-chart-pick-$id'));
Finder option(String id) => find.byKey(ValueKey('chart-option-$id'));

final refreshButton = find.ancestor(
  of: find.byTooltip('새로고침'),
  matching: find.byType(IconButton),
);
final headerSpinner = find.descendant(
  of: refreshButton,
  matching: find.byType(CircularProgressIndicator),
);

/// [target] 안쪽 글자나 아이콘을 품은 버튼의 초점 노드.
FocusNode focusOf(WidgetTester tester, Finder target) =>
    Focus.of(tester.element(target));

FocusNode pickFocus(WidgetTester tester, String id) => focusOf(
  tester,
  find.descendant(of: pick(id), matching: find.byType(Icon)).first,
);

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// 첫 호출의 응답 지연 표시를 켜고 끌 수 있는 환율 조회.
class StaleApi extends FiatApi {
  bool stale = false;

  @override
  Future<ExchangeRateResponse> fetchLatestRatesResponse({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) async {
    final response = await super.fetchLatestRatesResponse(
      baseCurrency: baseCurrency,
      targetCurrencies: targetCurrencies,
    );
    return ExchangeRateResponse(
      baseCurrency: response.baseCurrency,
      rates: response.rates,
      rateDate: response.rateDate,
      fetchedAt: response.fetchedAt,
      stale: stale,
    );
  }
}

/// 실제 환율 화면. 차트까지 내려도 입력칸은 화면 밖으로 나간다.
class RealScreen {
  RealScreen(this.tester);

  final WidgetTester tester;
  late final ChartSelectionProvider charts;
  late final ExchangeProvider exchange;
  late final ExchangeDisplayProvider display;
  late final StaleApi fiatApi;

  Future<void> pump() async {
    tester.view.physicalSize = const Size(2400, 1800);
    addTearDown(tester.view.reset);
    final api = makeApi();
    final crypto = CryptoProvider(api: api);
    fiatApi = StaleApi();
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

  Finder get amount => find.byType(TextField).first;

  EditableText get amountEditable =>
      tester.widget<EditableText>(find.byType(EditableText).first);

  ScrollPosition get position =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Future<void> tapAmount() async {
    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(amountEditable.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  }

  /// 입력칸을 쓰고 차트까지 내린다. 첫 카드에서 시작한다.
  Future<double> useAmountThenScrollToChart() async {
    await tapAmount();
    await revealVertically(tester, pick('fiat:USD'), position);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(position.pixels, greaterThan(100));
    return position.pixels;
  }

  void expectStayed(double pixels) {
    expect(amountEditable.focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(position.pixels, pixels);
    expect(tester.takeException(), isNull);
  }
}

const krwRow = 'fiat:KRW';
const usdRow = 'fiat:USD';
const eurRow = 'fiat:EUR';
const btcRow = 'crypto:BTC';

Finder rowField(String id) => find.descendant(
  of: find.byKey(ValueKey(id)),
  matching: find.byType(TextField),
);

/// 통화 행의 통화명(▾).
Finder rowCurrency(String id) => find.descendant(
  of: find.byKey(ValueKey(id)),
  matching: find.byIcon(Icons.keyboard_arrow_down),
);

final managementButton = find.text('통화 추가 / 편집');

/// 위쪽 환산 통화 행까지 쓰는 경우. 기준 행, 일반 행, 코인 행이 모두 있다.
class RowsScreen extends RealScreen {
  RowsScreen(super.tester);

  /// 기준 행 입력칸의 윗부분이 잘리는 위치. 입력칸에 초점이 돌아가면 스크롤이 움직인다.
  static const partlyScrolled = 69.0;

  Future<void> showRows() async {
    await pump();
    unawaited(
      display.apply([
        DisplayCurrency.fromFiat(findCurrencyByCode('USD')!),
        DisplayCurrency.fromFiat(findCurrencyByCode('EUR')!),
        DisplayCurrency.fromCrypto(
          const CryptoCoin(symbol: 'BTC', name: 'Bitcoin'),
        ),
      ]),
    );
    unawaited(display.crypto.refresh());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(rowIds, [krwRow, usdRow, eurRow, btcRow]);
  }

  List<String> get rowIds => [
    display.base.id,
    ...display.visible.map((row) => row.id),
  ];

  /// 화면에 있는 모든 입력칸의 글자.
  List<String> get amounts => [
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    ))
      field.controller.text,
  ];

  Future<void> type(String id, String text) async {
    await tester.tap(rowField(id));
    await tester.pumpAndSettle();
    await tester.enterText(rowField(id), text);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
  }

  /// 기준 행에 금액을 넣고 입력칸이 조금 잘리게 내린다.
  Future<void> typeThenScrollPartly() async {
    await type(krwRow, '250');
    position.jumpTo(partlyScrolled);
    await tester.pumpAndSettle();
    expect(position.pixels, partlyScrolled);
  }

  void expectNoFieldFocus(double pixels) {
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(field.focusNode.hasFocus, isFalse);
    }
    expect(tester.testTextInput.isVisible, isFalse);
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    expect(position.pixels, pixels);
    expect(tester.takeException(), isNull);
  }

  /// 입력칸을 직접 다시 누르면 키보드가 뜨고 값이 바뀐다.
  Future<void> expectFieldUsable(String id) async {
    await tester.ensureVisible(rowField(id));
    await tester.pumpAndSettle();
    await type(id, '7');
    final row = [
      display.base,
      ...display.visible,
    ].firstWhere((row) => row.id == id);
    expect(display.amountFor(row), closeTo(7, 0.000001));
  }
}

/// 통화 관리 창을 닫는 방법.
enum SheetClose { barrier, back, done }

Future<void> closeSheet(WidgetTester tester, SheetClose how) async {
  switch (how) {
    case SheetClose.barrier:
      await tester.tapAt(const Offset(400, 10));
    case SheetClose.back:
      await tester.binding.handlePopRoute();
    case SheetClose.done:
      await tester.tap(find.text('완료'));
  }
  await tester.pumpAndSettle();
  expect(find.byType(CurrencyManagementBottomSheet), findsNothing);
  expect(find.byType(CurrencySelectionSheet), findsNothing);
}

/// 새로고침 버튼 표면에 그려진 면의 색. 스피너와 아이콘은 빼고 잉크만 본다.
List<int> refreshInk(WidgetTester tester) {
  final material = Material.of(
    tester.element(
      find.descendant(of: refreshButton, matching: find.byType(InkWell)),
    ),
  );
  final colors = <int>[];
  expect(
    material as RenderObject,
    paints..everything((method, arguments) {
      if (method == #drawRect) {
        for (final argument in arguments) {
          if (argument is Paint && argument.color.a > 0) {
            colors.add(argument.color.toARGB32());
          }
        }
      }
      return true;
    }),
  );
  return colors;
}

/// 선택창에서 하는 일. 끝나면 창은 닫혀 있다.
enum PickerAction { closeButton, back, barrier, replace, exchange }

Future<void> act(WidgetTester tester, PickerAction action) async {
  switch (action) {
    case PickerAction.closeButton:
      await tester.tap(find.byTooltip('닫기'));
    case PickerAction.back:
      await tester.binding.handlePopRoute();
    case PickerAction.barrier:
      await tester.tapAt(const Offset(400, 10));
    case PickerAction.replace:
      await tester.tap(option('fiat:EUR'));
    case PickerAction.exchange:
      await tester.tap(option('fiat:JPY'));
  }
  await tester.pumpAndSettle();
  expect(find.byType(ChartCurrencyPicker), findsNothing);
}

void expectResult(RealScreen screen, PickerAction action) {
  final expected = switch (action) {
    PickerAction.replace => const ChartPair.fiat('EUR', 'KRW'),
    PickerAction.exchange => const ChartPair.fiat('JPY', 'KRW'),
    _ => const ChartPair.fiat('USD', 'KRW'),
  };
  expect(screen.charts.pairs.first, expected);
}

class ControlledSource implements ChartDataSource {
  final requests = <Completer<ChartData>>[];

  @override
  Future<ChartData> load(ChartPeriod period) {
    final request = Completer<ChartData>();
    requests.add(request);
    return request.future;
  }

  void succeed() {
    final now = DateTime.now();
    requests.last.complete(
      ChartData(
        history: [
          for (var i = 0; i < 5; i++)
            ChartSample(
              date: now.subtract(Duration(days: 4 - i)),
              rate: 100.0 + i,
              baseCurrencyCode: 'USD',
              targetCurrencyCode: 'KRW',
            ),
        ],
        currentRate: 104,
        fetchedAt: now,
      ),
    );
  }

  void fail() => requests.last.completeError(StateError('timeout'));

  @override
  void dispose() {}
}

/// 입력칸 아래에 조회를 조절할 수 있는 캐러셀이 있는 세로 스크롤 화면.
class LoadingPage {
  LoadingPage(this.tester);

  static const offset = 300.0;

  final WidgetTester tester;
  final field = FocusNode(debugLabel: 'amount');
  final scroll = ScrollController();
  final source = ControlledSource();

  Future<void> pump() async {
    addTearDown(() {
      field.dispose();
      scroll.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                TextField(focusNode: field),
                const SizedBox(height: 200),
                ChartPairCarousel(
                  pairs: const [
                    ChartPair.fiat('USD', 'KRW'),
                    ChartPair.fiat('JPY', 'KRW'),
                  ],
                  currencies: const [],
                  snapshotStore: MemorySnapshots(),
                  createDataSource: (_) => source,
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
    // 첫 조회가 걸려 있어 스피너가 돌므로 settle을 기다리지 않는다.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(source.requests, hasLength(1));
  }

  Future<void> loaded() async {
    source.succeed();
    await tester.pumpAndSettle();
    expect(headerSpinner, findsNothing);
  }

  Future<void> useFieldThenScroll() async {
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(field.hasFocus, isTrue);
    scroll.jumpTo(offset);
    await tester.pumpAndSettle();
  }

  FocusNode get refreshFocus =>
      tester.widget<IconButton>(refreshButton).focusNode!;

  void expectStayed() {
    expect(field.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(scroll.offset, offset);
    expect(tester.takeException(), isNull);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the currency picker does not return focus to the amount field', () {
    for (final action in PickerAction.values) {
      testWidgets('touch: ${action.name}', (tester) async {
        final screen = RealScreen(tester);
        await screen.pump();
        final pixels = await screen.useAmountThenScrollToChart();

        await tester.tap(pick('fiat:USD'));
        await tester.pumpAndSettle();
        screen.expectStayed(pixels);

        await act(tester, action);
        expectResult(screen, action);
        screen.expectStayed(pixels);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('keyboard: Esc returns to the currency button', (tester) async {
      final screen = RealScreen(tester);
      await screen.pump();
      final pixels = await screen.useAmountThenScrollToChart();
      final button = pickFocus(tester, 'fiat:USD');
      button.requestFocus();
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(ChartCurrencyPicker), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(ChartCurrencyPicker), findsNothing);
      expect(button.hasFocus, isTrue);
      screen.expectStayed(pixels);

      // 다시 열어도 같다. 초점이 버튼에 있어 기록을 건드리지 않는다.
      await press(tester, LogicalKeyboardKey.enter);
      await act(tester, PickerAction.closeButton);
      expect(button.hasFocus, isTrue);
      screen.expectStayed(pixels);
      await tester.pumpWidget(const SizedBox());
    });

    for (final action in [PickerAction.replace, PickerAction.exchange]) {
      testWidgets('keyboard: ${action.name}', (tester) async {
        final screen = RealScreen(tester);
        await screen.pump();
        final pixels = await screen.useAmountThenScrollToChart();
        pickFocus(tester, 'fiat:USD').requestFocus();
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.enter);

        final id = action == PickerAction.replace ? 'fiat:EUR' : 'fiat:JPY';
        focusOf(
          tester,
          find.descendant(of: option(id), matching: find.byType(Text)).first,
        ).requestFocus();
        await tester.pump();
        await press(tester, LogicalKeyboardKey.enter);

        expect(find.byType(ChartCurrencyPicker), findsNothing);
        expectResult(screen, action);
        screen.expectStayed(pixels);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('touching ▾ keeps focus already on another card button', (
      tester,
    ) async {
      final screen = RealScreen(tester);
      await screen.pump();
      final pixels = await screen.useAmountThenScrollToChart();
      final swap = focusOf(
        tester,
        find
            .descendant(
              of: find.byKey(const ValueKey('market-chart-swap')),
              matching: find.byType(Icon),
            )
            .first,
      );
      swap.requestFocus();
      await tester.pumpAndSettle();

      await tester.tap(pick('fiat:USD'));
      await tester.pumpAndSettle();
      await act(tester, PickerAction.closeButton);
      expect(swap.hasFocus, isTrue);
      screen.expectStayed(pixels);
      await tester.pumpWidget(const SizedBox());
    });

    for (final action in [PickerAction.closeButton, PickerAction.replace]) {
      testWidgets('search field in use, then ${action.name}', (tester) async {
        final screen = RealScreen(tester);
        await screen.pump();
        final pixels = await screen.useAmountThenScrollToChart();
        await tester.tap(pick('fiat:USD'));
        await tester.pumpAndSettle();

        final search = find.byType(TextField).last;
        await tester.tap(search);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.enterText(search, 'eur');
        await tester.pumpAndSettle();

        await act(tester, action);
        expectResult(screen, action);
        screen.expectStayed(pixels);
        expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('search field opened from the keyboard returns to the button', (
      tester,
    ) async {
      final screen = RealScreen(tester);
      await screen.pump();
      final pixels = await screen.useAmountThenScrollToChart();
      final button = pickFocus(tester, 'fiat:USD');
      button.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter);

      final search = find.byType(TextField).last;
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      await act(tester, PickerAction.closeButton);
      expect(button.hasFocus, isTrue);
      screen.expectStayed(pixels);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('typed amount stays and the field can be used again', (
      tester,
    ) async {
      final screen = RealScreen(tester);
      await screen.pump();
      await tester.tap(screen.amount);
      await tester.pumpAndSettle();
      await tester.enterText(screen.amount, '1234.5');
      await tester.pumpAndSettle();
      final controller = screen.amountEditable.controller;
      expect(controller.text, '1,234.5');
      final amountBefore = screen.display.amountFor(screen.display.base);
      expect(amountBefore, 1234.5);

      await revealVertically(tester, pick('fiat:USD'), screen.position);
      final pixels = screen.position.pixels;
      await tester.tap(pick('fiat:USD'));
      await tester.pumpAndSettle();
      await act(tester, PickerAction.replace);
      screen.expectStayed(pixels);

      // 초점을 잃어도 글자와 계산값이 그대로다.
      expect(controller.text, '1,234.5');
      expect(screen.display.amountFor(screen.display.base), amountBefore);

      screen.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(screen.amount);
      await tester.pumpAndSettle();
      expect(screen.amountEditable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(screen.amount, '7');
      await tester.pumpAndSettle();
      expect(screen.display.amountFor(screen.display.base), 7);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('a sheet opened from a currency row leaves the amount field alone', () {
    for (final typed in [krwRow, usdRow, btcRow]) {
      for (final tapped in [krwRow, eurRow, btcRow]) {
        testWidgets('typed in $typed, touched $tapped, then closed', (
          tester,
        ) async {
          final screen = RowsScreen(tester);
          await screen.showRows();
          await screen.type(typed, '250');
          final amounts = screen.amounts;
          final inputAmount = screen.exchange.inputAmount;

          await tester.tap(rowCurrency(tapped));
          await tester.pumpAndSettle();
          // 코인 행은 통화 관리 창을 연다.
          expect(
            find.byType(
              tapped == btcRow
                  ? CurrencyManagementBottomSheet
                  : CurrencySelectionSheet,
            ),
            findsOneWidget,
          );
          screen.expectNoFieldFocus(0);

          await closeSheet(tester, SheetClose.barrier);
          screen.expectNoFieldFocus(0);
          expect(screen.amounts, amounts);
          expect(screen.exchange.inputAmount, inputAmount);

          await screen.expectFieldUsable(typed);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }

    testWidgets('the screen stays where it was', (tester) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      await screen.typeThenScrollPartly();

      await tester.tap(rowCurrency(eurRow));
      await tester.pumpAndSettle();
      await closeSheet(tester, SheetClose.barrier);
      screen.expectNoFieldFocus(RowsScreen.partlyScrolled);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('back closes the sheet without the keyboard', (tester) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      await screen.type(usdRow, '250');

      await tester.tap(rowCurrency(usdRow));
      await tester.pumpAndSettle();
      await closeSheet(tester, SheetClose.back);
      screen.expectNoFieldFocus(0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('changing the base keeps the moved row and drops focus', (
      tester,
    ) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      await screen.type(usdRow, '250');
      final usdState = tester.state(rowField(usdRow));
      final inputAmount = screen.exchange.inputAmount;

      await tester.tap(rowCurrency(krwRow));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('JPY ·'));
      await tester.pumpAndSettle();

      expect(screen.rowIds, ['fiat:JPY', usdRow, eurRow, btcRow, krwRow]);
      screen.expectNoFieldFocus(0);
      // 기준 금액은 그대로이고 같은 키의 행은 상태와 글자를 유지한다.
      expect(screen.exchange.inputAmount, inputAmount);
      expect(tester.state(rowField(usdRow)), same(usdState));
      expect(
        tester.widget<TextField>(rowField(usdRow)).controller!.text,
        '250',
      );
      await screen.expectFieldUsable(usdRow);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('moving the row the field is in keeps focus off it too', (
      tester,
    ) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      await screen.type(krwRow, '250');

      await tester.tap(rowCurrency(krwRow));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('JPY ·'));
      await tester.pumpAndSettle();

      expect(screen.rowIds, ['fiat:JPY', usdRow, eurRow, btcRow, krwRow]);
      screen.expectNoFieldFocus(0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('replacing another row keeps the typed values', (tester) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      await screen.type(usdRow, '250');
      final inputAmount = screen.exchange.inputAmount;

      await tester.tap(rowCurrency(eurRow));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('JPY ·'));
      await tester.pumpAndSettle();

      expect(screen.rowIds, [krwRow, usdRow, btcRow, 'fiat:JPY']);
      screen.expectNoFieldFocus(0);
      expect(screen.exchange.inputAmount, inputAmount);
      expect(
        tester.widget<TextField>(rowField(usdRow)).controller!.text,
        '250',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'replacing the row in use does not fall back to another field',
      (tester) async {
        final screen = RowsScreen(tester);
        await screen.showRows();
        await tester.tap(rowField(krwRow));
        await tester.pumpAndSettle();
        await screen.type(usdRow, '250');

        await tester.tap(rowCurrency(usdRow));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('JPY ·'));
        await tester.pumpAndSettle();

        expect(screen.rowIds, [krwRow, eurRow, btcRow, 'fiat:JPY']);
        screen.expectNoFieldFocus(0);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('touching ▾ keeps focus already on another button', (
      tester,
    ) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      final other = focusOf(tester, managementButton);
      other.requestFocus();
      await tester.pumpAndSettle();

      await tester.tap(rowCurrency(eurRow));
      await tester.pumpAndSettle();
      await closeSheet(tester, SheetClose.barrier);
      expect(other.hasPrimaryFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    for (final tapped in [krwRow, eurRow, btcRow]) {
      testWidgets('keyboard: Esc on $tapped returns to its button', (
        tester,
      ) async {
        final screen = RowsScreen(tester);
        await screen.showRows();
        await screen.type(usdRow, '250');
        final amounts = screen.amounts;
        final button = focusOf(tester, rowCurrency(tapped));
        button.requestFocus();
        await tester.pumpAndSettle();

        await press(tester, LogicalKeyboardKey.enter);
        expect(button.hasFocus, isFalse);
        await press(tester, LogicalKeyboardKey.escape);
        expect(find.byType(CurrencySelectionSheet), findsNothing);
        expect(find.byType(CurrencyManagementBottomSheet), findsNothing);
        expect(button.hasPrimaryFocus, isTrue);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(screen.amounts, amounts);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('the currency management sheet leaves the amount field alone', () {
    late List<String> amounts;

    Future<RowsScreen> openFromField(WidgetTester tester) async {
      final screen = RowsScreen(tester);
      await screen.showRows();
      await screen.typeThenScrollPartly();
      amounts = screen.amounts;
      await tester.tap(managementButton);
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyManagementBottomSheet), findsOneWidget);
      screen.expectNoFieldFocus(RowsScreen.partlyScrolled);
      return screen;
    }

    for (final how in SheetClose.values) {
      testWidgets('touch: ${how.name}', (tester) async {
        final screen = await openFromField(tester);

        await closeSheet(tester, how);
        screen.expectNoFieldFocus(RowsScreen.partlyScrolled);
        expect(screen.amounts, amounts);
        expect(screen.rowIds, [krwRow, usdRow, eurRow, btcRow]);

        await screen.expectFieldUsable(krwRow);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('search field in use, then ${how.name}', (tester) async {
        final screen = await openFromField(tester);
        final search = find.descendant(
          of: find.byType(CurrencyManagementBottomSheet),
          matching: find.byType(TextField),
        );
        await tester.tap(search);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.enterText(search, 'gbp');
        await tester.pumpAndSettle();

        await closeSheet(tester, how);
        screen.expectNoFieldFocus(RowsScreen.partlyScrolled);
        await tester.pumpWidget(const SizedBox());
      });
    }

    for (final how in [SheetClose.back, SheetClose.done]) {
      testWidgets('keyboard: ${how.name} returns to the button', (
        tester,
      ) async {
        final screen = RowsScreen(tester);
        await screen.showRows();
        await screen.typeThenScrollPartly();
        final button = focusOf(tester, managementButton);
        button.requestFocus();
        await tester.pumpAndSettle();
        final pixels = screen.position.pixels;

        await press(tester, LogicalKeyboardKey.enter);
        expect(find.byType(CurrencyManagementBottomSheet), findsOneWidget);
        await closeSheet(tester, how);
        expect(button.hasPrimaryFocus, isTrue);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(screen.position.pixels, pixels);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('the refresh button while loading', () {
    testWidgets('pressed from the keyboard, it keeps focus and asks once', (
      tester,
    ) async {
      final page = LoadingPage(tester);
      await page.pump();
      await page.loaded();
      await page.useFieldThenScroll();
      final node = page.refreshFocus;
      node.requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(headerSpinner, findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(page.source.requests, hasLength(2));
      expect(node.hasFocus, isTrue);
      page.expectStayed();

      // 조회 중에 다시 눌러도 요청이 늘지 않는다.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(page.source.requests, hasLength(2));
      expect(node.hasFocus, isTrue);

      await page.loaded();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(node.hasFocus, isTrue);
      page.expectStayed();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(page.source.requests, hasLength(3));
      await page.loaded();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'touch asks once, keeps a focused field and hides the tooltip',
      (tester) async {
        final page = LoadingPage(tester);
        await page.pump();
        await page.loaded();
        await page.useFieldThenScroll();

        await tester.tap(refreshButton);
        await tester.pump();
        expect(page.source.requests, hasLength(2));
        expect(headerSpinner, findsOneWidget);
        expect(page.field.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);

        await tester.tap(refreshButton);
        await tester.pump();
        expect(page.source.requests, hasLength(2));

        await tester.longPress(refreshButton);
        await tester.pump();
        expect(find.text('새로고침'), findsNothing);

        await page.loaded();
        await tester.longPress(refreshButton);
        await tester.pump();
        expect(find.text('새로고침'), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a screen reader reads a disabled button without a tap', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final page = LoadingPage(tester);
      await page.pump();
      await page.loaded();

      var data = tester.getSemantics(refreshButton).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.tooltip, '새로고침');

      await tester.tap(refreshButton);
      await tester.pump();
      // 안쪽 버튼의 노드는 트리에서 빠졌으므로 감싸는 Semantics의 노드를 본다.
      final wrapper = tester.getSemantics(
        find
            .ancestor(of: refreshButton, matching: find.byType(Semantics))
            .first,
      );
      wrapper.visitChildren((child) {
        fail('조회 중인 버튼 안에 다른 노드가 남아 있다: $child');
      });
      data = wrapper.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.hasEnabledState, isTrue);
      expect(data.flagsCollection.isEnabled, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.focus), isFalse);
      expect(data.tooltip, isEmpty);
      expect(data.label, isEmpty);

      await page.loaded();
      data = tester.getSemantics(refreshButton).getSemanticsData();
      expect(data.flagsCollection.isEnabled, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });

    testWidgets('pressing shows no surface, focus still shows', (tester) async {
      final page = LoadingPage(tester);
      await page.pump();

      final style = tester.widget<IconButton>(refreshButton).style!;
      expect(style.splashFactory, NoSplash.splashFactory);
      for (final state in [WidgetState.pressed, WidgetState.hovered]) {
        expect(style.overlayColor!.resolve({state}), Colors.transparent);
      }
      expect(style.overlayColor!.resolve({WidgetState.focused}), isNull);
      for (final state in [WidgetState.pressed, WidgetState.hovered]) {
        expect(
          style.overlayColor!.resolve({WidgetState.focused, state}),
          Colors.transparent,
        );
      }
      expect(style.mouseCursor!.resolve(const {}), SystemMouseCursors.basic);
      expect(style.enableFeedback, isFalse);

      await page.loaded();
      expect(tester.widget<IconButton>(refreshButton).style, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    group('from the keyboard', () {
      const focusInk = 0x1a49454f;

      Future<LoadingPage> focused(WidgetTester tester) async {
        final strategy = tester.binding.focusManager.highlightStrategy;
        tester.binding.focusManager.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(
          () => tester.binding.focusManager.highlightStrategy = strategy,
        );
        final page = LoadingPage(tester);
        await page.pump();
        await page.loaded();
        await page.useFieldThenScroll();
        page.refreshFocus.requestFocus();
        await tester.pumpAndSettle();
        expect(refreshInk(tester), [focusInk]);
        return page;
      }

      // 눌렀을 때 시작된 물결과 눌림 표시가 끝나기를 기다린다.
      Future<void> startLoading(WidgetTester tester) async {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(headerSpinner, findsOneWidget);
      }

      testWidgets('the focus mark stays while loading and after', (
        tester,
      ) async {
        final page = await focused(tester);
        final button = tester.element(
          find.descendant(of: refreshButton, matching: find.byType(InkWell)),
        );

        await startLoading(tester);
        expect(page.refreshFocus.hasPrimaryFocus, isTrue);
        expect(refreshInk(tester), [focusInk]);
        // 버튼이 새로 만들어지면 초점 표시와 눌림 해제 타이머를 잃는다.
        expect(
          tester.element(
            find.descendant(of: refreshButton, matching: find.byType(InkWell)),
          ),
          same(button),
        );

        await page.loaded();
        expect(page.refreshFocus.hasPrimaryFocus, isTrue);
        expect(refreshInk(tester), [focusInk]);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Enter while loading leaves no press mark', (tester) async {
        final page = await focused(tester);
        await startLoading(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        for (final ms in [0, 16, 50, 100, 300, 1000]) {
          await tester.pump(Duration(milliseconds: ms));
          expect(refreshInk(tester), [focusInk], reason: '+${ms}ms');
        }
        await page.loaded();
        await tester.pumpWidget(const SizedBox());
      });

      for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
        testWidgets('holding a ${kind.name} down shows no press mark', (
          tester,
        ) async {
          final page = await focused(tester);
          await startLoading(tester);

          final gesture = await tester.startGesture(
            tester.getCenter(refreshButton),
            kind: kind,
          );
          for (final ms in [0, 100, 1000]) {
            await tester.pump(Duration(milliseconds: ms));
            expect(refreshInk(tester), [focusInk], reason: 'held +${ms}ms');
          }
          await gesture.up();
          for (final ms in [0, 100, 1000]) {
            await tester.pump(Duration(milliseconds: ms));
            expect(refreshInk(tester), [focusInk], reason: 'up +${ms}ms');
          }
          await gesture.removePointer();
          await tester.pump(const Duration(seconds: 1));
          expect(refreshInk(tester), [focusInk]);
          expect(page.source.requests, hasLength(2));
          await page.loaded();
          await tester.pumpWidget(const SizedBox());
        });
      }
    });

    testWidgets('a press while loading never reaches onRefresh', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarketChartHeader(
              title: '제목',
              pair: const SizedBox(),
              isLoading: true,
              showsOldData: false,
              fetchedAt: null,
              onRefresh: () => presses++,
            ),
          ),
        ),
      );
      await tester.tap(refreshButton);
      await tester.pump();
      expect(presses, 0);
      expect(tester.widget<IconButton>(refreshButton).onPressed, isNotNull);
    });

    for (final isLoading in [false, true]) {
      testWidgets('without onRefresh it stays off (loading: $isLoading)', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarketChartHeader(
                title: '제목',
                pair: const SizedBox(),
                isLoading: isLoading,
                showsOldData: false,
                fetchedAt: null,
                onRefresh: null,
              ),
            ),
          ),
        );
        final button = find.byType(IconButton);
        expect(tester.widget<IconButton>(button).onPressed, isNull);
        expect(
          tester
              .getSemantics(button)
              .getSemanticsData()
              .flagsCollection
              .isEnabled,
          isFalse,
        );
        if (!isLoading) {
          final icon = tester.element(find.byIcon(Icons.refresh));
          // 꺼진 버튼의 회색. 켜진 버튼의 mutedColor와 다르다.
          expect(IconTheme.of(icon).color!.a, closeTo(0.38, 0.01));
        }
        semantics.dispose();
      });
    }
  });

  group('retry buttons that disappear when pressed', () {
    testWidgets('the chart retry moves focus to refresh in the same card', (
      tester,
    ) async {
      final page = LoadingPage(tester);
      await page.pump();
      page.source.fail();
      await tester.pumpAndSettle();
      await page.useFieldThenScroll();
      focusOf(tester, find.text('다시 시도')).requestFocus();
      await tester.pumpAndSettle();
      final refresh = page.refreshFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('다시 시도'), findsNothing);
      expect(page.source.requests, hasLength(2));
      expect(refresh.hasFocus, isTrue);
      page.expectStayed();

      // 또 실패해 버튼이 돌아와도 초점은 새로고침에 있다.
      page.source.fail();
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsOneWidget);
      expect(refresh.hasFocus, isTrue);
      page.expectStayed();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(page.source.requests, hasLength(3));
      await page.loaded();
      expect(refresh.hasFocus, isTrue);
      page.expectStayed();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('touching the chart retry keeps a focused field', (
      tester,
    ) async {
      final page = LoadingPage(tester);
      await page.pump();
      page.source.fail();
      await tester.pumpAndSettle();
      await page.useFieldThenScroll();

      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(page.source.requests, hasLength(2));
      expect(page.field.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(page.scroll.offset, LoadingPage.offset);
      await page.loaded();
      await tester.pumpWidget(const SizedBox());
    });

    Future<void> showCatalogError(WidgetTester tester) async {
      final btc = DisplayCurrency.fromCrypto(
        const CryptoCoin(symbol: 'BTC', name: 'BTC'),
      );
      var error = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ChartCurrencyPicker(
                title: '선택',
                current: btc,
                options: [btc],
                error: error ? '실패' : null,
                onRetry: () => setState(() => error = false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
    }

    testWidgets('the catalog retry from the keyboard leaves the search field', (
      tester,
    ) async {
      await showCatalogError(tester);
      focusOf(tester, find.text('다시 시도')).requestFocus();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);

      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('다시 시도'), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('touching the catalog retry keeps a focused search field', (
      tester,
    ) async {
      await showCatalogError(tester);

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsNothing);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    Future<RealScreen> showErrorBox(WidgetTester tester) async {
      final screen = RealScreen(tester);
      await screen.pump();
      await screen.exchange.addCurrency(findCurrencyByCode('USD')!);
      await tester.pumpAndSettle();
      await screen.tapAmount();
      screen.fiatApi.stale = true;
      await screen.exchange.fetchRates();
      await tester.pumpAndSettle();
      screen.fiatApi.stale = false;
      expect(screen.exchange.errorMessage, isNotNull);
      return screen;
    }

    // 표시 줄의 오류 박스 안 버튼.
    final boxRetry = find.descendant(
      of: find.ancestor(
        of: find.textContaining('응답 지연'),
        matching: find.byType(Row),
      ),
      matching: find.byType(TextButton),
    );

    testWidgets('the rate error box from the keyboard releases focus', (
      tester,
    ) async {
      final screen = await showErrorBox(tester);
      focusOf(
        tester,
        find.descendant(of: boxRetry, matching: find.byType(Text)),
      ).requestFocus();
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.enter);
      expect(screen.exchange.errorMessage, isNull);
      expect(boxRetry, findsNothing);
      screen.expectStayed(screen.position.pixels);
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('touching the rate error box keeps a focused field', (
      tester,
    ) async {
      final screen = await showErrorBox(tester);

      await tester.tap(boxRetry);
      await tester.pumpAndSettle();
      expect(screen.exchange.errorMessage, isNull);
      expect(screen.amountEditable.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
