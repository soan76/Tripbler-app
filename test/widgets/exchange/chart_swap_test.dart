import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_inversion.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import 'package:tripbler/presentation/charts/chart_swap_store.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';
import 'package:tripbler/widgets/charts/market_chart_card.dart';
import 'package:tripbler/widgets/charts/market_chart_carousel.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_axis_helper.dart';
import 'package:tripbler/widgets/exchange/exchange_chart_tooltip.dart';
import 'package:tripbler/widgets/exchange/exchange_rate_line_chart.dart';

import '../../helpers/memory_chart_snapshots.dart';

class Source implements ChartDataSource {
  Source({
    this.symbol = 'BTC',
    this.rates = const [100, 200],
    this.stale = false,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();
  final String symbol;
  final List<double> rates;
  final bool stale;
  final DateTime fetchedAt;
  final List<ChartPeriod> loads = [];
  @override
  Future<ChartData> load(ChartPeriod period) async {
    loads.add(period);
    final now = DateTime.now();
    return ChartData(
      history: [
        for (var i = 0; i < rates.length; i++)
          ChartSample(
            date: now.subtract(Duration(days: rates.length - 1 - i)),
            rate: rates[i],
            baseCurrencyCode: symbol,
            targetCurrencyCode: 'KRW',
          ),
      ],
      currentRate: rates.first,
      fetchedAt: fetchedAt,
      stale: stale,
    );
  }

  @override
  void dispose() {}
}

const id = 'crypto:BTC/KRW';
const swapKey = ValueKey('market-chart-swap');
const storeKey = 'chart.swapped.v1';

String coinId(String symbol) => 'crypto:$symbol/KRW';

Widget carousel(
  Source source, {
  bool reduceMotion = false,
  TextDirection textDirection = TextDirection.ltr,
}) => coinCarousel(
  const ['BTC'],
  (_) => source,
  reduceMotion: reduceMotion,
  textDirection: textDirection,
);

/// [snapshots]를 비우면 호출마다 빈 메모리 저장소를 쓴다. 카드는 처음 받은
/// 저장소만 쓰므로, 다시 그려도 이미 만들어진 카드의 저장소는 그대로다.
Widget coinCarousel(
  List<String> symbols,
  Source Function(String symbol) sourceFor, {
  bool reduceMotion = false,
  TextDirection textDirection = TextDirection.ltr,
  MemorySnapshots? snapshots,
}) {
  final store = snapshots ?? MemorySnapshots();
  return MaterialApp(
    builder: (context, child) => Directionality(
      textDirection: textDirection,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
    ),
    home: Scaffold(
      body: MarketChartCarousel(
        itemIds: symbols.map(coinId).toList(),
        cardBuilder: (context, index, period, shouldLoad, swapped, onSwap) {
          final symbol = symbols[index];
          return MarketChartCard(
            key: ValueKey('${coinId(symbol)}/${period.name}'),
            baseCurrency: DisplayCurrency.fromCrypto(
              CryptoCoin(symbol: symbol, name: symbol),
            ),
            targetCurrency: DisplayCurrency.fromFiat(supportedCurrencies.first),
            swapped: swapped,
            onSwap: onSwap,
            title: '차트',
            errorText: '실패',
            requestKey: coinId(symbol),
            createDataSource: () => sourceFor(symbol),
            period: period,
            shouldLoad: shouldLoad,
            snapshotStore: store,
          );
        },
      ),
    ),
  );
}

Widget fiatCarousel(String base, List<String> targets) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: ChartPairCarousel(
        pairs: [for (final code in targets) ChartPair.fiat(base, code)],
        currencies: const [],
        // 실제 API를 부르지 않도록 조회는 하지 않고 헤더와 저장만 확인한다.
        active: false,
        snapshotStore: MemorySnapshots(),
      ),
    ),
  ),
);

List<ChartPoint> shownHistory(WidgetTester tester) => tester
    .widget<ExchangeRateLineChart>(find.byType(ExchangeRateLineChart))
    .history;

VoidCallback? swapCallback(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(swapKey)).onPressed;

double turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byKey(swapKey),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

double chartOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byKey(const ValueKey('market-chart-fade')))
    .opacity
    .value;

double codeX(WidgetTester tester, String code) =>
    tester.getTopLeft(find.text(code)).dx;

double codeY(WidgetTester tester, String code) =>
    tester.getTopLeft(find.text(code)).dy;

/// 통화 코드가 들어 있는 한쪽 묶음(아이콘 + 코드)의 영역.
Rect sideRect(WidgetTester tester, String code) => tester.getRect(
  find.ancestor(
    of: find.text(code),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is KeyedSubtree &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('pair-'),
    ),
  ),
);

/// 한쪽 묶음이 줄이지 않고 그려질 때의 폭.
double naturalSideWidth(WidgetTester tester, String code) => tester
    .renderObject<RenderBox>(
      find.ancestor(
        of: find.text(code),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is KeyedSubtree &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('pair-'),
        ),
      ),
    )
    .getMaxIntrinsicWidth(double.infinity);

/// 통화 두 개와 스왑 버튼을 배치하는 RenderObject.
RenderBox swapPair(WidgetTester tester) {
  RenderObject? node = tester.renderObject(find.byKey(swapKey));
  while (node != null && node.runtimeType.toString() != '_RenderSwapPair') {
    node = node.parent;
  }
  return node! as RenderBox;
}

/// 조회를 직접 끝낼 수 있는 데이터 소스.
class PendingSource implements ChartDataSource {
  final List<Completer<ChartData>> requests = [];
  final List<ChartPeriod> periods = [];
  bool disposed = false;
  @override
  Future<ChartData> load(ChartPeriod period) {
    periods.add(period);
    final request = Completer<ChartData>();
    requests.add(request);
    return request.future;
  }

  @override
  void dispose() => disposed = true;
}

ChartData btcData(double rate) => ChartData(
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

/// 캐러셀 없이 카드 하나만 띄운다. [intrinsicHeight]이면 IntrinsicHeight로,
/// [intrinsicWidth]이면 IntrinsicWidth로 감싼다.
Widget btcCard(
  ChartDataSource source, {
  bool shouldLoad = true,
  bool intrinsicHeight = false,
  bool intrinsicWidth = false,
  String symbol = 'BTC',
}) {
  Widget card = MarketChartCard(
    baseCurrency: DisplayCurrency.fromCrypto(
      CryptoCoin(symbol: symbol, name: symbol),
    ),
    targetCurrency: DisplayCurrency.fromFiat(supportedCurrencies.first),
    onSwap: () {},
    title: '차트',
    errorText: '실패',
    requestKey: coinId(symbol),
    createDataSource: () => source,
    period: ChartPeriod.oneMonth,
    shouldLoad: shouldLoad,
    snapshotStore: MemorySnapshots(),
  );
  if (intrinsicHeight) card = IntrinsicHeight(child: card);
  if (intrinsicWidth) card = IntrinsicWidth(child: card);
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: intrinsicWidth ? null : 400,
          height: intrinsicHeight ? null : 430,
          child: card,
        ),
      ),
    ),
  );
}

/// key 없이 같은 자리에 다시 그려 카드 State를 재사용하게 한다.
Widget reusedCard({
  required String symbol,
  required ChartPeriod period,
  required ChartDataSource Function() createDataSource,
  MemorySnapshots? snapshots,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 430,
      child: MarketChartCard(
        baseCurrency: DisplayCurrency.fromCrypto(
          CryptoCoin(symbol: symbol, name: symbol),
        ),
        targetCurrency: DisplayCurrency.fromFiat(supportedCurrencies.first),
        title: '차트',
        errorText: '실패',
        requestKey: coinId(symbol),
        createDataSource: createDataSource,
        period: period,
        shouldLoad: true,
        snapshotStore: snapshots ?? MemorySnapshots(),
      ),
    ),
  ),
);

double shownFirstRate(WidgetTester tester) => shownHistory(tester).first.rate;

/// 이전 값이 모두 사라지고 로딩 중으로 표시되는지 확인한다.
void expectClearedAndLoading(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ExchangeRateLineChart), findsNothing);
  expect(find.text('현재 환율 정보 없음'), findsOneWidget);
  expect(find.textContaining('업데이트:'), findsNothing);
  expect(find.text('저장된 데이터 · 갱신 중'), findsNothing);
  // 헤더의 새로고침 자리와 차트 영역에 하나씩 보인다.
  expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
}

Future<List<String>?> stored() async =>
    (await SharedPreferences.getInstance()).getStringList(storeKey);

void main() {
  test('inversion swaps codes and drops values that cannot be inverted', () {
    expect(ChartInversion.rate(1400), closeTo(1 / 1400, 1e-15));
    expect(ChartInversion.rate(0), isNull);
    expect(ChartInversion.rate(null), isNull);
    final inverted = ChartInversion.history([
      ChartSample(
        date: DateTime(2026),
        rate: 4,
        baseCurrencyCode: 'USD',
        targetCurrencyCode: 'KRW',
      ),
      ChartSample(
        date: DateTime(2026, 1, 2),
        rate: 0,
        baseCurrencyCode: 'USD',
        targetCurrencyCode: 'KRW',
      ),
    ]);
    expect(inverted, hasLength(1));
    expect(inverted.single.rate, 0.25);
    expect(inverted.single.baseCurrencyCode, 'KRW');
    expect(inverted.single.targetCurrencyCode, 'USD');
    // 뒤집은 기록도 원본처럼 밖에서 고칠 수 없다.
    expect(() => inverted.add(inverted.single), throwsUnsupportedError);
    expect(() => inverted.removeLast(), throwsUnsupportedError);
    // 뒤집으면 무한대가 되는 비정규 수는 차트로 넘기지 않는다.
    expect(1 / 4.9e-324, double.infinity);
    expect(ChartInversion.rate(4.9e-324), isNull);
    expect(
      ChartInversion.history([
        ChartSample(
          date: DateTime(2026),
          rate: 4.9e-324,
          baseCurrencyCode: 'USD',
          targetCurrencyCode: 'KRW',
        ),
      ]),
      isEmpty,
    );
  });

  test('very small inverted rates stay readable', () {
    expect(ExchangeChartAxisHelper.formatRate(0.000714), '0.000714');
    expect(ExchangeChartAxisHelper.formatRate(0.012345678), '0.012346');
    // 1 미만은 소수 6자리 이상, 유효숫자 4자리 이상으로 표시한다.
    expect(ExchangeChartAxisHelper.formatRate(0.000724123), '0.0007241');
    // 0.00012345는 이진 표현상 0.000123449…라 내림된다.
    expect(ExchangeChartAxisHelper.formatRate(0.00012345), '0.0001234');
    // 수십만 원대 코인(SOL, BNB)을 뒤집은 값도 유효숫자가 남는다.
    expect(ExchangeChartAxisHelper.formatRate(4.1e-6), '0.0000041');
    expect(ExchangeChartAxisHelper.formatRate(4.4e-6), '0.0000044');
    expect(ExchangeChartAxisHelper.formatRate(1.13e-6), '0.00000113');
    expect(ExchangeChartAxisHelper.formatRate(1 / 243000), '0.000004115');
    expect(ExchangeChartAxisHelper.formatRate(7.5e-9), '0.0000000075');
    expect(ExchangeChartAxisHelper.formatYAxisRate(7.5e-9, 1e-10), '7.5e-9');
    expect(
      ExchangeChartAxisHelper.formatYAxisRate(0.000715, 0.000005),
      '0.000715',
    );
  });

  test('non-finite rates are formatted without throwing', () {
    for (final interval in [0.0, 1e-8, 0.01]) {
      expect(
        ExchangeChartAxisHelper.formatYAxisRate(double.nan, interval),
        'NaN',
      );
      expect(
        ExchangeChartAxisHelper.formatYAxisRate(double.infinity, interval),
        'Infinity',
      );
      expect(
        ExchangeChartAxisHelper.formatYAxisRate(
          double.negativeInfinity,
          interval,
        ),
        '-Infinity',
      );
    }
    expect(ExchangeChartAxisHelper.formatRate(double.nan), 'NaN');
    expect(ExchangeChartAxisHelper.formatRate(double.infinity), 'Infinity');
    expect(
      ExchangeChartAxisHelper.formatRate(double.negativeInfinity),
      '-Infinity',
    );
  });

  testWidgets(
    'swap inverts header, rate and chart without reloading and is remembered',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final source = Source();
      await tester.pumpWidget(carousel(source));
      await tester.pumpAndSettle();

      expect(find.text('1 BTC'), findsOneWidget);
      expect(find.text('100 KRW'), findsOneWidget);
      expect(shownHistory(tester).first.rate, 100);
      expect(source.loads, hasLength(1));

      await tester.tap(find.byKey(swapKey));
      await tester.pumpAndSettle();

      expect(find.text('1 KRW'), findsOneWidget);
      expect(find.text('0.01 BTC'), findsOneWidget);
      final history = shownHistory(tester);
      expect(history.first.rate, 0.01);
      expect(history.first.baseCurrencyCode, 'KRW');
      expect(history.first.targetCurrencyCode, 'BTC');
      expect(source.loads, hasLength(1));
      expect(await stored(), [id]);

      // 기간을 바꿔 카드가 새로 만들어져도 방향은 유지된다.
      await tester.tap(find.text('3M'));
      await tester.pumpAndSettle();
      expect(source.loads.last, ChartPeriod.threeMonths);
      expect(find.text('1 KRW'), findsOneWidget);

      // 화면을 다시 만들어도(앱 재시작) 저장된 방향을 복원한다.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(carousel(Source()));
      await tester.pumpAndSettle();
      expect(find.text('1 KRW'), findsOneWidget);

      await tester.tap(find.byKey(swapKey));
      await tester.pumpAndSettle();
      expect(find.text('1 BTC'), findsOneWidget);
      expect(await stored(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('fiat carousel swaps and stores fiat ids', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(fiatCarousel('KRW', const ['USD']));
    await tester.pumpAndSettle();
    double x(String code) => tester.getTopLeft(find.text(code)).dx;
    expect(x('KRW'), lessThan(x('USD')));

    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(x('USD'), lessThan(x('KRW')));
    expect(await stored(), ['fiat:KRW/USD']);

    // 다시 만들어도 국가 통화 카드의 방향을 복원한다.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(fiatCarousel('KRW', const ['USD']));
    await tester.pumpAndSettle();
    expect(x('USD'), lessThan(x('KRW')));

    // 선택창(replaceSide)을 거치지 않고 같은 자리 카드가 두 통화 모두 다른 쌍으로
    // 바뀌면, 알려 준 방향이 없으므로 옛 방향을 옮기지 않고 정방향으로 둔다.
    // (예전에는 옛 방향을 새 ID로 옮겼지만, 그러면 관계없는 쌍이 뒤집힌 채 보인다.)
    // 옛 조합 ID는 지운다.
    await tester.pumpWidget(fiatCarousel('USD', const ['JPY']));
    await tester.pumpAndSettle();
    expect(await stored(), isEmpty);
    expect(x('USD'), lessThan(x('JPY')));

    // 카드 구성이 바뀌어 남지 않은 ID는 모두 지운다.
    await tester.pumpWidget(fiatCarousel('EUR', const ['JPY', 'GBP']));
    await tester.pumpAndSettle();
    expect(await stored(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap button is disabled until stored ids are read', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(carousel(Source()));
    expect(swapCallback(tester), isNull);
    // 방향을 읽기 전에는 틀릴 수 있는 tooltip 대신 방향 없는 라벨만 둔다.
    expect(find.byTooltip('KRW 기준으로 바꾸기'), findsNothing);
    expect(find.byTooltip('BTC 기준으로 바꾸기'), findsNothing);
    expect(
      tester.getSemantics(find.byKey(swapKey)),
      containsSemantics(label: '기준 통화 바꾸기', isButton: true, isEnabled: false),
    );
    await tester.pumpAndSettle();
    expect(swapCallback(tester), isNotNull);
    expect(find.byTooltip('KRW 기준으로 바꾸기'), findsOneWidget);
    expect(find.bySemanticsLabel('기준 통화 바꾸기'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('swap tooltip and icon rotation follow the direction', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('KRW 기준으로 바꾸기'), findsOneWidget);
    expect(turns(tester), 0);

    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(find.byTooltip('BTC 기준으로 바꾸기'), findsOneWidget);
    expect(find.byTooltip('KRW 기준으로 바꾸기'), findsNothing);
    expect(turns(tester), 0.5);

    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(find.byTooltip('KRW 기준으로 바꾸기'), findsOneWidget);
    expect(turns(tester), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap button shows a circle only while pressed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(swapKey));
    final colors = Theme.of(context).colorScheme;
    final button = tester.widget<IconButton>(find.byKey(swapKey));
    // 톤 배경 버튼이 아니라 배경 없는 기본 아이콘 버튼이다.
    expect(button.style!.backgroundColor, isNull);
    final material = tester.widget<Material>(
      find.descendant(of: find.byKey(swapKey), matching: find.byType(Material)),
    );
    expect(material.color, anyOf(isNull, Colors.transparent));
    final overlay = button.style!.overlayColor!;
    expect(overlay.resolve({}), isNull);
    expect(overlay.resolve({WidgetState.pressed}), colors.secondaryContainer);
    // 원이 없어도 누를 수 있게 강조색 아이콘을 쓰고, 비활성은 흐리게 그린다.
    final foreground = button.style!.foregroundColor!;
    expect(foreground.resolve({}), colors.primary);
    expect(
      foreground.resolve({WidgetState.disabled}),
      colors.onSurface.withValues(alpha: 0.38),
    );
    expect(tester.getSize(find.byKey(swapKey)), const Size(48, 48));

    // 누르는 동안 물결(원형) 효과가 그려진다.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(swapKey)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 250));
    final ink = Material.of(
      tester.element(
        find.descendant(of: find.byKey(swapKey), matching: find.byType(Icon)),
      ),
    );
    // 물결 뒤에 원 모양으로 잘린 톤 색 강조가 그려진다(보이는 원 40dp, 터치 48dp).
    expect(
      ink,
      paints
        ..rect()
        ..clipPath()
        ..rect(
          rect: const Rect.fromLTRB(0, 0, 40, 40),
          color: colors.secondaryContainer,
        ),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    // 손을 떼면 원이 사라진다.
    expect(ink, isNot(paints..rect(color: colors.secondaryContainer)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping swap moves both currencies and fades the new chart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    final btcStart = codeX(tester, 'BTC');
    final krwStart = codeX(tester, 'KRW');
    expect(btcStart, lessThan(krwStart));
    expect(chartOpacity(tester), 1);

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // 중간에는 두 통화가 서로의 자리로 가는 중이고 그래프는 나타나는 중이다.
    final btcMid = codeX(tester, 'BTC');
    final krwMid = codeX(tester, 'KRW');
    expect(btcMid, greaterThan(btcStart));
    expect(krwMid, lessThan(krwStart));
    expect(turns(tester), inExclusiveRange(0, 0.5));
    expect(chartOpacity(tester), inExclusiveRange(0, 1));
    expect(shownHistory(tester).first.baseCurrencyCode, 'KRW');
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(codeX(tester, 'KRW'), lessThan(codeX(tester, 'BTC')));
    expect(codeX(tester, 'KRW'), closeTo(btcStart, 0.01));
    expect(turns(tester), 0.5);
    expect(chartOpacity(tester), 1);

    // 이동 중에 다시 누르면 그 자리에서 되돌아간다.
    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(codeX(tester, 'KRW'), lessThan(codeX(tester, 'BTC')));
    expect(turns(tester), 0.5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('currencies move in 300ms while the chart fades over 1s', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    final btcStart = codeX(tester, 'BTC');

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 통화 이동과 아이콘 회전은 300ms에 끝난다.
    expect(turns(tester), 0.5);
    expect(codeX(tester, 'KRW'), closeTo(btcStart, 0.01));
    // 그래프는 아직 절반도 나타나지 않았다.
    final at300 = chartOpacity(tester);
    expect(at300, inExclusiveRange(0, 0.5));

    await tester.pump(const Duration(milliseconds: 200));
    // 1초의 한가운데에서 절반쯤 보인다.
    expect(chartOpacity(tester), closeTo(0.5, 0.01));

    await tester.pump(const Duration(milliseconds: 490));
    expect(chartOpacity(tester), inExclusiveRange(0.9, 1));
    await tester.pump(const Duration(milliseconds: 10));
    expect(chartOpacity(tester), 1);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('re-tapping after the motion keeps fading without a flash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    // 통화 이동은 끝났지만 그래프는 아직 나타나는 중이다.
    await tester.pump(const Duration(milliseconds: 600));
    expect(turns(tester), 0.5);
    final before = chartOpacity(tester);
    expect(before, inExclusiveRange(0.5, 1));

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    expect(find.text('1 BTC'), findsOneWidget);
    // 되돌아간 그래프도 투명해지지 않고 지금 투명도에서 이어서 나타난다.
    expect(chartOpacity(tester), greaterThanOrEqualTo(before));
    await tester.pump(const Duration(milliseconds: 150));
    expect(turns(tester), inExclusiveRange(0, 0.5));
    expect(chartOpacity(tester), greaterThanOrEqualTo(before));
    await tester.pumpAndSettle();
    expect(turns(tester), 0);
    expect(chartOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap pair supports dry layout and intrinsic sizes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // IntrinsicHeight는 레이아웃 전에 intrinsic 높이를 묻는다.
    await tester.pumpWidget(
      btcCard(PendingSource(), shouldLoad: false, intrinsicHeight: true),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final pair = swapPair(tester);
    // 실제 레이아웃 결과와 같은 크기를 dry layout으로도 계산한다.
    expect(pair.getDryLayout(pair.constraints), pair.size);
    expect(
      pair.getDryLayout(const BoxConstraints(maxWidth: 300)),
      Size(300, pair.size.height),
    );
    // 폭은 버튼(좌우 여백 8dp 포함) + 2 × 넓은 쪽 통화, 높이는 가장 큰 자식이다.
    final button = tester.getSize(find.byKey(swapKey)).width + 16;
    final btc = sideRect(tester, 'BTC').width;
    final krw = sideRect(tester, 'KRW').width;
    expect(
      pair.getMaxIntrinsicWidth(double.infinity),
      closeTo(button + 2 * (btc > krw ? btc : krw), 0.01),
    );
    expect(pair.getMinIntrinsicWidth(double.infinity), greaterThan(button));
    expect(pair.getMaxIntrinsicHeight(400), pair.size.height);
    expect(pair.getMinIntrinsicHeight(400), pair.size.height);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('intrinsic width fits currencies of different widths', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      btcCard(
        PendingSource(),
        shouldLoad: false,
        intrinsicWidth: true,
        symbol: 'DOGE',
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final doge = naturalSideWidth(tester, 'DOGE');
    final krw = naturalSideWidth(tester, 'KRW');
    // 테스트 글꼴에서 4자리와 3자리 심볼의 폭이 다르다.
    expect(doge - krw, greaterThan(1));
    final button = tester.getSize(find.byKey(swapKey)).width + 16;
    final pair = swapPair(tester);
    expect(
      pair.getMaxIntrinsicWidth(double.infinity),
      closeTo(button + 2 * doge, 0.01),
    );
    // IntrinsicWidth가 준 폭에서도 두 통화가 줄지 않고 자연 폭 그대로 놓인다.
    expect(pair.size.width, greaterThanOrEqualTo(button + 2 * doge - 0.01));
    expect(sideRect(tester, 'DOGE').width, closeTo(doge, 0.01));
    expect(sideRect(tester, 'KRW').width, closeTo(krw, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap pair stays vertically centered in a taller box', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(btcCard(PendingSource(), shouldLoad: false));
    await tester.pump();
    final pair = swapPair(tester);
    final original = pair.constraints;
    final width = pair.size.width;
    // 부모가 더 큰 최소 높이를 주는 경우를 직접 레이아웃해 확인한다.
    pair.layout(
      BoxConstraints.tightFor(width: width, height: 120),
      parentUsesSize: true,
    );
    expect(pair.size, Size(width, 120));
    final children = <RenderBox>[];
    pair.visitChildren((child) => children.add(child as RenderBox));
    expect(children, hasLength(3));
    for (final child in children) {
      final offset = (child.parentData! as BoxParentData).offset;
      expect(offset.dy, closeTo((120 - child.size.height) / 2, 0.01));
    }
    // 원래 제약으로 되돌린다.
    pair.layout(original, parentUsesSize: true);
    expect(pair.size.height, lessThan(120));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap pair mirrors in right-to-left layouts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      carousel(Source(), textDirection: TextDirection.rtl),
    );
    await tester.pumpAndSettle();
    final pair = swapPair(tester);
    final pairRight = pair.localToGlobal(Offset(pair.size.width, 0)).dx;
    // 기준 통화가 오른쪽 끝에서 시작하고, 버튼, 대상 통화 순으로 왼쪽에 놓인다.
    expect(sideRect(tester, 'BTC').right, closeTo(pairRight, 0.01));
    final button = tester.getRect(find.byKey(swapKey));
    expect(button.right + 8, closeTo(sideRect(tester, 'BTC').left, 0.01));
    expect(sideRect(tester, 'KRW').right + 8, closeTo(button.left, 0.01));

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    expect(sideRect(tester, 'KRW').right, closeTo(pairRight, 0.01));
    expect(codeX(tester, 'BTC'), lessThan(codeX(tester, 'KRW')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('re-tapping during the motion does not flash the chart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    // 지나가는 통화가 버튼 위를 덮는 한가운데에서 다시 누른다.
    await tester.pump(const Duration(milliseconds: 150));
    final midOpacity = chartOpacity(tester);
    expect(midOpacity, inExclusiveRange(0, 1));

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    // 반쯤 보이던 그래프가 다시 투명해지지 않고 이어서 나타난다.
    expect(chartOpacity(tester), greaterThanOrEqualTo(midOpacity));
    await tester.pump(const Duration(milliseconds: 50));
    expect(chartOpacity(tester), greaterThanOrEqualTo(midOpacity));
    await tester.pumpAndSettle();
    expect(chartOpacity(tester), 1);
    expect(find.text('1 BTC'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final textDirection in TextDirection.values) {
    for (final ms in const [100, 120, 140, 150, 170, 200, 230]) {
      testWidgets(
        're-tapping at ${ms}ms reverses the swap (${textDirection.name})',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          await tester.pumpWidget(
            carousel(Source(), textDirection: textDirection),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(swapKey));
          await tester.pump();
          await tester.pump(Duration(milliseconds: ms));
          expect(turns(tester), inExclusiveRange(0, 0.5));
          // 통화 묶음이 버튼 위를 지나가는 중이어도 버튼이 눌린다.
          await tester.tap(find.byKey(swapKey));
          await tester.pumpAndSettle();
          expect(find.text('1 BTC'), findsOneWidget);
          expect(turns(tester), 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('currencies of different widths swap to exact positions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      coinCarousel(const ['DOGE'], (symbol) => Source(symbol: symbol)),
    );
    await tester.pumpAndSettle();
    final doge = sideRect(tester, 'DOGE');
    final krw = sideRect(tester, 'KRW');
    // 테스트 글꼴에서 4자리와 3자리 심볼의 폭이 다르다.
    expect((doge.width - krw.width).abs(), greaterThan(1));
    var button = tester.getRect(find.byKey(swapKey));
    expect(button.left, closeTo(doge.right + 8, 0.01));
    expect(krw.left, closeTo(button.right + 8, 0.01));
    final start = doge.left;

    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    final krwAfter = sideRect(tester, 'KRW');
    final dogeAfter = sideRect(tester, 'DOGE');
    button = tester.getRect(find.byKey(swapKey));
    // 버튼은 새 기준 통화(KRW) 폭 바로 뒤에 오고, 두 통화와 겹치지 않는다.
    expect(krwAfter.left, closeTo(start, 0.01));
    expect(button.left, closeTo(krwAfter.right + 8, 0.01));
    expect(dogeAfter.left, closeTo(button.right + 8, 0.01));

    // 옮겨진 버튼 자리를 눌러도 판정된다.
    await tester.tapAt(button.center);
    await tester.pumpAndSettle();
    expect(find.text('1 DOGE'), findsOneWidget);
    expect(sideRect(tester, 'DOGE').left, closeTo(start, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('currencies lift apart while passing each other', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    final btcY = codeY(tester, 'BTC');
    final krwY = codeY(tester, 'KRW');
    expect(btcY, closeTo(krwY, 0.01));

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // 한가운데(easeInOutCubic 0.5)에서 원래 기준 통화는 위로, 대상 통화는
    // 아래로 최대 6dp씩 비켜 간다.
    expect(codeY(tester, 'BTC'), closeTo(btcY - 6, 0.5));
    expect(codeY(tester, 'KRW'), closeTo(krwY + 6, 0.5));

    await tester.pumpAndSettle();
    expect(codeY(tester, 'BTC'), closeTo(btcY, 0.01));
    expect(codeY(tester, 'KRW'), closeTo(krwY, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chart fades in when it first appears', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source()));
    for (
      var i = 0;
      i < 10 && find.byType(ExchangeRateLineChart).evaluate().isEmpty;
      i++
    ) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(chartOpacity(tester), inExclusiveRange(0, 1));
    // 처음 나타날 때도 1초에 걸쳐 나타난다.
    await tester.pump(const Duration(milliseconds: 800));
    expect(chartOpacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(chartOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stored direction is shown without motion', (tester) async {
    SharedPreferences.setMockInitialValues({
      storeKey: [id],
    });
    await tester.pumpWidget(carousel(Source()));
    for (var i = 0; i < 10 && swapCallback(tester) == null; i++) {
      await tester.pump();
    }
    expect(swapCallback(tester), isNotNull);
    // 저장값을 읽은 바로 그 프레임에 이미 뒤집은 배치다.
    expect(turns(tester), 0.5);
    expect(codeX(tester, 'KRW'), lessThan(codeX(tester, 'BTC')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion swaps instantly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(carousel(Source(), reduceMotion: true));
    await tester.pumpAndSettle();
    final btcStart = codeX(tester, 'BTC');

    await tester.tap(find.byKey(swapKey));
    await tester.pump();
    expect(turns(tester), 0.5);
    expect(chartOpacity(tester), 1);
    expect(codeX(tester, 'KRW'), closeTo(btcStart, 0.01));
    expect(find.text('1 KRW'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap row fits a 320 wide screen in both directions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(swapKey));
    // 이동 중간에도 넘침이 없다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1 KRW'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rapid taps leave memory and storage in the same state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final source = Source();
    await tester.pumpWidget(carousel(source));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(swapKey));
    }
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    expect(await stored(), [id]);

    await tester.tap(find.byKey(swapKey));
    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    expect(await stored(), [id]);
    expect(source.loads, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap keeps stale label and original fetchedAt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final source = Source(stale: true, fetchedAt: DateTime(2026, 1, 2, 3, 4));
    await tester.pumpWidget(carousel(source));
    await tester.pumpAndSettle();
    expect(find.text('마지막 성공 데이터 · 갱신 지연'), findsOneWidget);
    expect(find.text('업데이트: 2026.01.02 03:04'), findsOneWidget);

    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    expect(find.text('마지막 성공 데이터 · 갱신 지연'), findsOneWidget);
    expect(find.text('업데이트: 2026.01.02 03:04'), findsOneWidget);
    expect(source.loads, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inverted SOL chart shows readable header, tooltip and axis', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final source = Source(symbol: 'SOL', rates: const [243000, 245000, 247000]);
    await tester.pumpWidget(coinCarousel(const ['SOL'], (_) => source));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();

    expect(find.text('0.000004115 SOL'), findsOneWidget);

    final history = shownHistory(tester);
    final bar = LineChartBarData(
      spots: [
        for (var i = 0; i < history.length; i++)
          FlSpot(i.toDouble(), history[i].rate),
      ],
    );
    final items =
        ExchangeChartTooltip.buildTouchData(
          history: history,
          colorScheme: const ColorScheme.light(),
          onTouch: (_, _) {},
        ).touchTooltipData.getTooltipItems([
          for (final spot in bar.spots) LineBarSpot(bar, 0, spot),
        ]);
    expect(items.map((item) => item!.text.split('\n').last).toList(), [
      'KRW/SOL: 0.000004115',
      'KRW/SOL: 0.000004082',
      'KRW/SOL: 0.000004049',
    ]);

    // 축은 폭이 좁아 지수로 표시하며, 눈금끼리 같은 문자열이 되지 않는다.
    final axisLabels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ExchangeRateLineChart),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .where((label) => label.contains('e-6'))
        .toList();
    expect(axisLabels.length, greaterThanOrEqualTo(2));
    expect(axisLabels.toSet(), hasLength(axisLabels.length));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swap state follows ids across page moves and list changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    Source sourceFor(String symbol) => Source(symbol: symbol);
    await tester.pumpWidget(coinCarousel(const ['BTC', 'ETH'], sourceFor));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(swapKey));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 ETH'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);

    // 순서가 바뀌어도 ID를 따라 방향을 유지한다.
    await tester.pumpWidget(coinCarousel(const ['ETH', 'BTC'], sourceFor));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    expect(await stored(), [coinId('BTC')]);

    // 삭제한 코인의 ID는 메모리와 저장값에서 모두 지운다.
    await tester.pumpWidget(coinCarousel(const ['ETH'], sourceFor));
    await tester.pumpAndSettle();
    expect(await stored(), isEmpty);
    await tester.pumpWidget(coinCarousel(const ['BTC', 'ETH'], sourceFor));
    await tester.pumpAndSettle();
    // 보고 있던 ETH(2번째 페이지)를 유지하므로 BTC로 돌아가 확인한다.
    expect(find.text('1 ETH'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 BTC'), findsOneWidget);
    expect(find.text('1 KRW'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale ids of any kind are pruned only after reading', (
    tester,
  ) async {
    // `fiat:KRW/USD`는 앱 업데이트 전 캐러셀(기준 KRW)이 남긴 저장값이다.
    SharedPreferences.setMockInitialValues({
      storeKey: ['crypto:OLD/KRW', id, 'fiat:KRW/USD'],
    });
    await tester.pumpWidget(carousel(Source()));
    await tester.pumpAndSettle();
    expect(find.text('1 KRW'), findsOneWidget);
    expect(await stored(), [id]);
    await tester.pumpWidget(const SizedBox());
  });

  test('retain keeps everything when the current list is empty', () async {
    SharedPreferences.setMockInitialValues({
      storeKey: ['crypto:OLD/KRW', 'fiat:KRW/USD'],
    });
    final store = ChartSwapStore();
    await store.retain(const []);
    expect((await stored())!.toSet(), {'crypto:OLD/KRW', 'fiat:KRW/USD'});
    expect(
      ChartSwapStore.retained({'crypto:OLD/KRW', 'fiat:KRW/USD'}, const []),
      {'crypto:OLD/KRW', 'fiat:KRW/USD'},
    );
    // 현재 목록에 없는 ID는 종류와 상관없이 지운다.
    expect(
      ChartSwapStore.retained(
        {'crypto:OLD/KRW', 'fiat:KRW/USD', 'fiat:USD/KRW'},
        const ['fiat:USD/KRW', 'crypto:BTC/KRW'],
      ),
      {'fiat:USD/KRW'},
    );
    await store.retain(const ['fiat:KRW/JPY']);
    expect(await stored(), isEmpty);
  });

  testWidgets('reused card drops the old period and ignores its late reply', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final source = PendingSource();
    Widget card(ChartPeriod period) => reusedCard(
      symbol: 'BTC',
      period: period,
      createDataSource: () => source,
    );

    await tester.pumpWidget(card(ChartPeriod.oneMonth));
    await tester.pump();
    source.requests.single.complete(btcData(100));
    await tester.pumpAndSettle();
    expect(shownFirstRate(tester), 100);

    // 새로고침 요청이 남아 있는 동안 key는 그대로 두고 기간만 바꾼다.
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpWidget(card(ChartPeriod.oneYear));
    await tester.pump();
    expectClearedAndLoading(tester);
    expect(source.periods, [
      ChartPeriod.oneMonth,
      ChartPeriod.oneMonth,
      ChartPeriod.oneYear,
    ]);

    source.requests[1].complete(btcData(999));
    await tester.pump();
    await tester.pump();
    expectClearedAndLoading(tester);

    source.requests.last.complete(btcData(300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(shownFirstRate(tester), 300);
    expect(
      tester
          .widget<ExchangeRateLineChart>(find.byType(ExchangeRateLineChart))
          .period,
      ChartPeriod.oneYear,
    );
    // 기간만 바뀌면 같은 데이터 소스를 계속 쓴다.
    expect(source.disposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(source.disposed, isTrue);
  });

  testWidgets('reused card switches request and disposes the old source', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final btc = PendingSource();
    final eth = PendingSource();
    var btcCreated = 0;
    var ethCreated = 0;

    await tester.pumpWidget(
      reusedCard(
        symbol: 'BTC',
        period: ChartPeriod.oneMonth,
        createDataSource: () {
          btcCreated++;
          return btc;
        },
      ),
    );
    await tester.pump();
    btc.requests.single.complete(btcData(100));
    await tester.pumpAndSettle();
    expect(shownFirstRate(tester), 100);

    // 새로고침 요청이 남아 있는 동안 key는 그대로 두고 통화쌍만 바꾼다.
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pumpWidget(
      reusedCard(
        symbol: 'ETH',
        period: ChartPeriod.oneMonth,
        createDataSource: () {
          ethCreated++;
          return eth;
        },
      ),
    );
    await tester.pump();
    expectClearedAndLoading(tester);
    expect(btc.disposed, isTrue);
    expect(btcCreated, 1);
    expect(ethCreated, 1);
    expect(eth.periods, [ChartPeriod.oneMonth]);

    btc.requests.last.complete(btcData(999));
    await tester.pump();
    await tester.pump();
    expectClearedAndLoading(tester);

    eth.requests.single.complete(btcData(300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(shownFirstRate(tester), 300);
    expect(btc.requests, hasLength(2));
    expect(eth.disposed, isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(eth.disposed, isTrue);
  });

  testWidgets('changing or removing the middle card stays on its slot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final loads = <String, bool>{};
    Widget app(List<String> ids) => MaterialApp(
      home: Scaffold(
        body: MarketChartCarousel(
          itemIds: ids,
          cardBuilder: (context, index, period, shouldLoad, swapped, onSwap) {
            loads[ids[index]] = shouldLoad;
            return Center(child: Text('card-${ids[index]}'));
          },
        ),
      ),
    );
    List<String> loading() => [
      for (final entry in loads.entries)
        if (entry.value) entry.key,
    ];

    await tester.pumpWidget(app(const ['a', 'b', 'c']));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('card-b'), findsOneWidget);
    expect(loading(), ['b']);

    // 가운데 카드의 통화를 바꾸면 그 자리의 새 카드를 보여 주고 조회한다.
    loads.clear();
    await tester.pumpWidget(app(const ['a', 'x', 'c']));
    await tester.pumpAndSettle();
    expect(find.text('card-x'), findsOneWidget);
    expect(find.text('card-a'), findsNothing);
    expect(loading(), ['x']);

    // 가운데 카드를 지우면 같은 자리의 다음 카드를 보여 주고 조회한다.
    loads.clear();
    await tester.pumpWidget(app(const ['a', 'c']));
    await tester.pumpAndSettle();
    expect(find.text('card-c'), findsOneWidget);
    expect(find.text('card-a'), findsNothing);
    expect(loading(), ['c']);

    // 마지막 카드를 지우면 그 앞 카드로 간다.
    loads.clear();
    await tester.pumpWidget(app(const ['a']));
    await tester.pumpAndSettle();
    expect(find.text('card-a'), findsOneWidget);
    expect(loading(), ['a']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a card changed in place keeps the direction it is shown in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      storeKey: ['fiat:USD/KRW', 'crypto:SOL/KRW'],
    });
    bool? hint;
    final requested = <(String, String)>[];
    Widget app(List<String> ids) => MaterialApp(
      home: Scaffold(
        body: MarketChartCarousel(
          itemIds: ids,
          swappedAfterReplace: (oldId, newId) {
            requested.add((oldId, newId));
            return hint;
          },
          cardBuilder: (context, index, period, shouldLoad, swapped, onSwap) =>
              Text('${ids[index]} ${swapped ? 'swapped' : 'forward'}'),
        ),
      ),
    );

    await tester.pumpWidget(app(const ['fiat:USD/KRW', 'fiat:JPY/KRW']));
    await tester.pumpAndSettle();
    expect(find.text('fiat:USD/KRW swapped'), findsOneWidget);
    // 현재 카드에 없는 코인 ID도 지운다.
    expect(await stored(), ['fiat:USD/KRW']);

    // 알려 준 방향이 없으면(선택창을 거치지 않은 변경) 옛 방향을 옮기지 않는다.
    await tester.pumpWidget(app(const ['fiat:USD/EUR', 'fiat:JPY/KRW']));
    await tester.pumpAndSettle();
    expect(requested, [('fiat:USD/KRW', 'fiat:USD/EUR')]);
    expect(find.text('fiat:USD/EUR forward'), findsOneWidget);
    expect(await stored(), isEmpty);

    // 알려 준 방향이 있으면 그 방향으로 보인다.
    hint = true;
    await tester.pumpWidget(app(const ['fiat:USD/KRW', 'fiat:JPY/KRW']));
    await tester.pumpAndSettle();
    expect(find.text('fiat:USD/KRW swapped'), findsOneWidget);

    hint = false;
    await tester.pumpWidget(app(const ['crypto:ETH/KRW', 'fiat:JPY/KRW']));
    await tester.pumpAndSettle();
    expect(find.text('crypto:ETH/KRW forward'), findsOneWidget);
    expect(await stored(), isEmpty);

    hint = true;
    await tester.pumpWidget(app(const ['crypto:BTC/KRW', 'fiat:JPY/KRW']));
    await tester.pumpAndSettle();
    expect(find.text('crypto:BTC/KRW swapped'), findsOneWidget);
    expect(await stored(), ['crypto:BTC/KRW']);

    // 카드 수가 바뀌거나 두 장 이상 바뀌면 방향을 옮기지 않는다.
    requested.clear();
    await tester.pumpWidget(app(const ['crypto:DOGE/KRW', 'fiat:EUR/KRW']));
    await tester.pumpAndSettle();
    expect(requested, isEmpty);
    expect(find.text('crypto:DOGE/KRW forward'), findsOneWidget);
    expect(await stored(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  group('with ChartSelectionProvider', () {
    late ChartSelectionProvider charts;

    Future<void> pumpCharts(WidgetTester tester) async {
      charts = ChartSelectionProvider();
      addTearDown(charts.dispose);
      await charts.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: charts,
                builder: (context, _) => ChartPairCarousel(
                  pairs: charts.pairs,
                  currencies: const [],
                  // 실제 API를 부르지 않도록 조회는 하지 않는다.
                  active: false,
                  snapshotStore: MemorySnapshots(),
                  swappedAfterReplace: charts.swappedAfterReplace,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    DisplayCurrency fiat(String code) =>
        DisplayCurrency.fromFiat(findCurrencyByCode(code)!);
    DisplayCurrency coin(String symbol) =>
        DisplayCurrency.fromCrypto(CryptoCoin(symbol: symbol, name: symbol));

    testWidgets('a coin changed to a fiat pair does not leave its direction', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        storeKey: [coinId('BTC')],
      });
      await pumpCharts(tester);
      expect(await stored(), [coinId('BTC')]);

      // 뒤집힌 "KRW ⇄ BTC"의 BTC를 EUR로 바꾸면 "KRW ⇄ EUR"(EUR/KRW 뒤집힘).
      charts.replaceSide(
        2,
        expected: const ChartPair.crypto('BTC'),
        base: true,
        swapped: true,
        currency: fiat('EUR'),
      );
      await tester.pumpAndSettle();
      expect(charts.pairs[2].id, 'fiat:EUR/KRW');
      expect(await stored(), ['fiat:EUR/KRW']);

      // "차트 추가"로 BTC/KRW가 다시 들어오면 정방향이다.
      expect(charts.add(), const ChartPair.crypto('BTC'));
      await tester.pumpAndSettle();
      expect(await stored(), ['fiat:EUR/KRW']);
    });

    testWidgets('changing every fiat card to a coin drops fiat directions', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ChartSelectionProvider.storageKey: ['fiat:USD/KRW'],
        storeKey: ['fiat:USD/KRW'],
      });
      await pumpCharts(tester);

      // 뒤집힌 "KRW ⇄ USD"의 USD를 ETH로 바꾸면 "KRW ⇄ ETH".
      charts.replaceSide(
        0,
        expected: const ChartPair.fiat('USD', 'KRW'),
        base: true,
        swapped: true,
        currency: coin('ETH'),
      );
      await tester.pumpAndSettle();
      expect(charts.pairs.single.id, coinId('ETH'));
      expect(await stored(), [coinId('ETH')]);

      // 다시 추가한 USD/KRW는 정방향이다.
      expect(charts.add(), const ChartPair.fiat('USD', 'KRW'));
      await tester.pumpAndSettle();
      expect(await stored(), [coinId('ETH')]);
    });

    testWidgets('a card replaced without replaceSide is shown forward', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ChartSelectionProvider.storageKey: [
          'fiat:USD/KRW',
          'fiat:JPY/KRW',
          coinId('ETH'),
        ],
        storeKey: [coinId('ETH')],
      });
      await pumpCharts(tester);
      expect(await stored(), [coinId('ETH')]);

      // 삭제와 추가가 한 번에 반영되면 [A, B, C] → [A, B, D]로 같은 자리 교체처럼
      // 보이지만, C의 방향을 D로 옮기지 않는다.
      charts.remove(2);
      charts.add();
      await tester.pumpAndSettle();
      expect(charts.pairs.map((p) => p.id), [
        'fiat:USD/KRW',
        'fiat:JPY/KRW',
        coinId('BTC'),
      ]);
      expect(await stored(), isEmpty);
    });
  });

  testWidgets('a coin missing from the received list is not loaded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final sources = <String, Source>{};
    final snapshots = MemorySnapshots();
    final krw = DisplayCurrency.fromFiat(findCurrencyByCode('KRW')!);
    DisplayCurrency coin(String symbol) =>
        DisplayCurrency.fromCrypto(CryptoCoin(symbol: symbol, name: symbol));
    Widget app(List<DisplayCurrency> currencies) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChartPairCarousel(
            pairs: const [ChartPair.crypto('OLD')],
            currencies: currencies,
            onPick: (index, {required base, required swapped}) {},
            createDataSource: (pair) => sources.putIfAbsent(
              pair.baseCode,
              () => Source(symbol: pair.baseCode),
            ),
            snapshotStore: snapshots,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app([krw, coin('BTC')]));
    await tester.pumpAndSettle();
    expect(find.text(ChartPairCarousel.unsupportedCoinText), findsOneWidget);
    expect(find.text(ChartPairCarousel.unsupportedCoinHint), findsOneWidget);
    expect(find.text('암호화폐 차트를 불러오지 못했습니다.'), findsNothing);
    expect(sources['OLD']?.loads ?? const [], isEmpty);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.refresh),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    // 통화명은 그대로 눌러 다른 코인을 고를 수 있다.
    expect(
      find.byKey(const ValueKey('market-chart-pick-crypto:OLD')),
      findsOneWidget,
    );

    // 목록을 못 받았거나 비어 있으면 판단하지 않고 지금처럼 조회한다.
    await tester.pumpWidget(app([krw]));
    await tester.pumpAndSettle();
    expect(find.text(ChartPairCarousel.unsupportedCoinText), findsNothing);
    expect(sources['OLD']!.loads, hasLength(1));
    expect(find.text('1 OLD'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
