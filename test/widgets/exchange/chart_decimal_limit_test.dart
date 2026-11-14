import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/providers/settings_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/widgets/charts/chart_amount_converter.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';
import 'package:tripbler/widgets/charts/chart_rate_summary.dart';

import '../../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../../helpers/exchange_handles.dart';
import '../../helpers/memory_chart_snapshots.dart';
import 'chart_rate_selection_test.dart'
    show
        compareDifference,
        compareLatest,
        compareSelected,
        select,
        selectedRate;

/// 기간 첫 기록은 [start], 현재 시세는 [rate]인 조회.
class _Source implements ChartDataSource {
  _Source(this.rate, {required this.start});

  final double rate;
  final double start;

  @override
  Future<ChartData> load(ChartPeriod period) async => ChartData(
    history: [
      for (var i = 0; i < 3; i++)
        ChartSample(
          date: DateTime(2026, 1, 1 + i),
          rate: i == 0 ? start : rate,
          baseCurrencyCode: 'USD',
          targetCurrencyCode: 'KRW',
        ),
    ],
    currentRate: rate,
    historicalRate: false,
    fetchedAt: DateTime(2026, 1, 3),
  );

  @override
  void dispose() {}
}

const _usd = ChartPair.fiat('USD', 'KRW');
const _btc = ChartPair.crypto('BTC');

final _amount = find.byKey(const ValueKey('market-chart-amount'));
final _converted = find.byKey(const ValueKey('market-chart-converted'));
final _rate = find.byKey(const ValueKey('market-chart-current-rate'));
final _change = find.byKey(const ValueKey('market-chart-period-change'));
final _swap = find.byKey(const ValueKey('market-chart-swap'));

Widget _charts(ChartPair pair, {int? decimalPlaces, _Source? source}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChartPairCarousel(
            pairs: [pair],
            currencies: const [],
            snapshotStore: MemorySnapshots(),
            decimalPlaces: decimalPlaces,
            createDataSource: (pair) =>
                source ??
                (pair.isCrypto
                    ? _Source(100000000.123456, start: 99000000)
                    : _Source(1300.123456, start: 1290.1)),
          ),
        ),
      ),
    );

/// 기간 시작이 1,300.12이고 현재가 1,300.1249라, 2자리에서는 둘 다 1,300.12로 보인다.
_Source _tinyMove() => _Source(1300.1249, start: 1300.12);

List<ChartPoint> _history(double start) => [
  ChartSample(
    date: DateTime(2026, 1, 1),
    rate: start,
    baseCurrencyCode: 'USD',
    targetCurrencyCode: 'KRW',
  ),
];

String _text(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data!;

String _changeText(WidgetTester tester) =>
    tester.widget<Text>(_change).textSpan!.toPlainText();

String _input(WidgetTester tester) =>
    tester.widget<TextField>(_amount).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('formatAmount maxDecimals', () {
    test('자릿수까지 반올림하고 천 단위 쉼표를 넣는다', () {
      expect(
        ChartAmountConverter.formatAmount(1234.5678, maxDecimals: 2),
        '1,234.57',
      );
      expect(
        ChartAmountConverter.formatAmount(1234.5678, maxDecimals: 0),
        '1,235',
      );
      expect(ChartAmountConverter.formatAmount(0.0123, maxDecimals: 2), '0.01');
      expect(ChartAmountConverter.formatAmount(2, maxDecimals: 5), '2');
      expect(ChartAmountConverter.formatAmount(0, maxDecimals: 2), '0');
    });

    test('0이 아니고 표시 단위보다 작은 값만 제한 없이 표시한다', () {
      expect(
        ChartAmountConverter.formatAmount(0.00072, maxDecimals: 2),
        ChartAmountConverter.formatAmount(0.00072),
      );
      expect(ChartAmountConverter.formatAmount(0.006, maxDecimals: 2), '0.006');
      expect(ChartAmountConverter.formatAmount(0.01, maxDecimals: 2), '0.01');
      // 0자리에서는 1보다 작은 값이 모두 대체 표시라 0.4와 0.6이 같은 규칙을 따른다.
      expect(ChartAmountConverter.formatAmount(0.4, maxDecimals: 0), '0.4');
      expect(ChartAmountConverter.formatAmount(0.6, maxDecimals: 0), '0.6');
      expect(ChartAmountConverter.formatAmount(1.4, maxDecimals: 0), '1');
      expect(
        ChartAmountConverter.formatAmount(-0.006, maxDecimals: 2),
        '-0.006',
      );
    });

    test('음수는 제한대로, -0.0은 "0"으로 표시한다', () {
      expect(
        ChartAmountConverter.formatAmount(-1234.567, maxDecimals: 2),
        '-1,234.57',
      );
      expect(ChartAmountConverter.formatAmount(-0.0, maxDecimals: 2), '0');
      expect(ChartAmountConverter.formatAmount(-0.0, maxDecimals: 0), '0');
      expect(ChartAmountConverter.formatAmount(-0.0), '0');
    });

    test('maxDecimals가 없으면 기존 표시 그대로', () {
      expect(ChartAmountConverter.formatAmount(1234.5678), '1,234.5678');
    });
  });

  group('formatChange', () {
    test('제한이 있으면 대체 표시 없이 반올림하고, 0이 되면 "0"이다', () {
      expect(ChartAmountConverter.formatChange(0.0049, maxDecimals: 2), '0');
      expect(ChartAmountConverter.formatChange(0.3, maxDecimals: 0), '0');
      expect(ChartAmountConverter.formatChange(0.006, maxDecimals: 2), '0.01');
      expect(ChartAmountConverter.formatChange(-0.004, maxDecimals: 2), '0');
      expect(ChartAmountConverter.formatChange(-0.0, maxDecimals: 2), '0');
      expect(
        ChartAmountConverter.formatChange(10.0249, maxDecimals: 2),
        '10.02',
      );
    });

    test('제한이 없으면 formatAmount와 같다', () {
      expect(
        ChartAmountConverter.formatChange(0.0049),
        ChartAmountConverter.formatAmount(0.0049),
      );
      expect(
        ChartAmountConverter.formatChange(0.0049, compared: [0.0001, 0.0050]),
        ChartAmountConverter.formatAmount(0.0049),
      );
    });

    test('비교한 값 중 하나라도 제한 없이 보이면 차이도 제한 없이 보여 준다', () {
      // 둘 다 작은 값.
      expect(
        ChartAmountConverter.formatChange(
          0.00072 - 0.0007,
          maxDecimals: 2,
          compared: [0.0007, 0.00072],
        ),
        '0.00002',
      );
      // 한쪽(0.0072)만 작은 값.
      expect(
        ChartAmountConverter.formatChange(
          0.01 - 0.0072,
          maxDecimals: 2,
          compared: [0.0072, 0.01],
        ),
        '0.0028',
      );
      // 0자리에서는 1 미만 값이 제한 없이 보인다.
      expect(
        ChartAmountConverter.formatChange(
          0.2,
          maxDecimals: 0,
          compared: [0.4, 0.6],
        ),
        '0.2',
      );
      // 제한 없이 보여도 차이가 정확히 0이면 "0"이다.
      expect(
        ChartAmountConverter.formatChange(
          0,
          maxDecimals: 2,
          compared: [0.0007, 0.0007],
        ),
        '0',
      );
    });

    test('두 값이 모두 제한 자릿수로 보이면 차이도 제한대로 반올림한다', () {
      expect(
        ChartAmountConverter.formatChange(
          1300.1249 - 1300.12,
          maxDecimals: 2,
          compared: [1300.12, 1300.1249],
        ),
        '0',
      );
      // 0은 제한 없이 보이는 값이 아니다.
      expect(
        ChartAmountConverter.formatChange(
          0.004,
          maxDecimals: 2,
          compared: [0, 0.004 + 1],
        ),
        '0',
      );
    });
  });

  group('usesFullPrecision', () {
    test('0이 아니고 표시 단위보다 작은 유한한 값만 해당한다', () {
      expect(ChartAmountConverter.usesFullPrecision(0.006, 2), isTrue);
      expect(ChartAmountConverter.usesFullPrecision(-0.006, 2), isTrue);
      expect(ChartAmountConverter.usesFullPrecision(0.4, 0), isTrue);
      expect(ChartAmountConverter.usesFullPrecision(0.01, 2), isFalse);
      expect(ChartAmountConverter.usesFullPrecision(1.4, 0), isFalse);
      expect(ChartAmountConverter.usesFullPrecision(0, 2), isFalse);
      expect(ChartAmountConverter.usesFullPrecision(-0.0, 2), isFalse);
      expect(ChartAmountConverter.usesFullPrecision(double.nan, 2), isFalse);
    });
  });

  group('ChartRateSummary.changeOf', () {
    test('제한 자릿수에서 0이 되는 변화는 변동 없음이다', () {
      final limited = ChartRateSummary.changeOf(
        1300.1249,
        _history(1300.12),
        maxDecimals: 2,
      )!;
      expect(limited.value, 0);
      expect(limited.text, '0');

      final unlimited = ChartRateSummary.changeOf(
        1300.1249,
        _history(1300.12),
      )!;
      expect(unlimited.value, closeTo(0.0049, 1e-9));
      expect(unlimited.text, isNot('0'));
    });

    test('기간 시작 값이나 현재 환율이 제한 없이 보이면 변화량도 제한 없이 보여 준다', () {
      final tiny = ChartRateSummary.changeOf(
        0.00072,
        _history(0.0007),
        maxDecimals: 2,
      )!;
      expect(tiny.value, greaterThan(0));
      expect(tiny.text, '0.00002');

      // 시작 값만 작은 경우.
      final oneSide = ChartRateSummary.changeOf(
        0.01,
        _history(0.0072),
        maxDecimals: 2,
      )!;
      expect(oneSide.value, greaterThan(0));
      expect(oneSide.text, '0.0028');

      final same = ChartRateSummary.changeOf(
        0.0007,
        _history(0.0007),
        maxDecimals: 2,
      )!;
      expect(same.value, 0);
      expect(same.text, '0');
    });

    test('표시 글자는 제한대로 반올림한 크기다', () {
      final change = ChartRateSummary.changeOf(
        1290.1,
        _history(1300.123456),
        maxDecimals: 2,
      )!;
      expect(change.value, lessThan(0));
      expect(change.text, '10.02');
    });
  });

  group('SettingsState.resolveDecimalPlaces', () {
    test('자동이면 통화 2자리·코인 5자리, 아니면 고른 값', () {
      expect(SettingsState.resolveDecimalPlaces(-1, isCrypto: false), 2);
      expect(SettingsState.resolveDecimalPlaces(-1, isCrypto: true), 5);
      expect(SettingsState.resolveDecimalPlaces(0, isCrypto: true), 0);
      expect(SettingsState.resolveDecimalPlaces(3, isCrypto: false), 3);
    });
  });

  group('trimDecimals', () {
    test('소수 부분을 자릿수까지 자르고 반올림하지 않는다', () {
      expect(ChartAmountConverter.trimDecimals('1.23456', 2), '1.23');
      expect(ChartAmountConverter.trimDecimals('1.999', 2), '1.99');
      expect(ChartAmountConverter.trimDecimals('1,234.5', 0), '1,234');
      expect(ChartAmountConverter.trimDecimals('1.2', 2), '1.2');
      expect(ChartAmountConverter.trimDecimals('12', 0), '12');
      expect(ChartAmountConverter.trimDecimals('1.23456', null), '1.23456');
    });

    test('0자리면 끝에 남은 소수점도 지운다', () {
      expect(ChartAmountConverter.trimDecimals('1,234.', 0), '1,234');
      expect(ChartAmountConverter.trimDecimals('1.', 2), '1.');
    });
  });

  testWidgets('이어 받은 금액이 입력 자릿수보다 길면 처음부터 잘라 보관값도 바꾼다', (tester) async {
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChartAmountScope(
            text: '0.12345',
            onChanged: (text) => saved = text,
            child: const ChartAmountConverter(
              rate: 1300,
              baseCode: 'USD',
              targetCode: 'KRW',
              historicalRate: false,
              inputDecimalPlaces: 2,
              resultDecimalPlaces: 2,
            ),
          ),
        ),
      ),
    );

    expect(_input(tester), '0.12');
    expect(saved, '0.12');
    expect(_text(tester, _converted), '156 KRW');
  });

  testWidgets('환율 화면은 설정의 자릿수 값을 차트 카드에 넘긴다', (tester) async {
    final api = makeApi();
    final fiatApi = FiatApi();
    final harness = ExchangeHarness.create(cryptoApi: api, fiatApi: fiatApi);
    addTearDown(() {
      harness.dispose();
      api.dispose();
      fiatApi.dispose();
    });
    await harness.display.initialize();
    await tester.pumpWidget(
      harness.scope(const MaterialApp(home: Scaffold(body: ExchangeScreen()))),
    );
    await tester.pumpAndSettle();

    int? passed() => tester
        .widget<ChartPairCarousel>(find.byType(ChartPairCarousel))
        .decimalPlaces;
    expect(passed(), SettingsState.autoDecimalPlaces);

    harness.container.read(settingsProvider.notifier).changeDecimalPlaces(3);
    await tester.pump();
    expect(passed(), 3);
  });

  group('차트 카드', () {
    testWidgets('설정이 없으면 기존처럼 제한하지 않는다', (tester) async {
      await tester.pumpWidget(_charts(_usd));
      await tester.pumpAndSettle();

      expect(_text(tester, _rate), '1,300.123456');
    });

    testWidgets('자동이면 국가 통화 환율·변화량·환산 금액을 2자리로 보여 준다', (tester) async {
      await tester.pumpWidget(_charts(_usd, decimalPlaces: -1));
      await tester.pumpAndSettle();

      expect(_text(tester, _rate), '1,300.12');
      expect(_changeText(tester), startsWith('▲ 10.02 ('));

      await tester.enterText(_amount, '1.5');
      await tester.pump();
      expect(_text(tester, _converted), '1,950.19 KRW');
    });

    testWidgets('입력칸은 왼쪽 통화의 자릿수까지만 받는다', (tester) async {
      await tester.pumpWidget(_charts(_btc, decimalPlaces: -1));
      await tester.pumpAndSettle();

      // 왼쪽이 코인이면 5자리.
      await tester.enterText(_amount, '0.12345');
      await tester.pump();
      await tester.enterText(_amount, '0.123456');
      await tester.pump();
      expect(_input(tester), '0.12345');
    });

    testWidgets('뒤집어 왼쪽 자릿수가 줄면 입력한 금액을 그 자릿수로 자른다', (tester) async {
      await tester.pumpWidget(_charts(_btc, decimalPlaces: -1));
      await tester.pumpAndSettle();
      await tester.enterText(_amount, '0.12345');
      await tester.pump();

      await tester.tap(_swap);
      await tester.pumpAndSettle();

      // 왼쪽이 KRW(2자리)가 됐다.
      expect(_input(tester), '0.12');
      // 1 KRW의 BTC 환율은 5자리로 반올림하면 0이라 제한 없이 보여 준다.
      expect(_text(tester, _rate), isNot('0'));
      expect(_text(tester, _rate), ChartAmountConverter.formatAmount(1e-8));

      // 지운 뒤 다시 넣을 수 있다.
      await tester.enterText(_amount, '0.1');
      await tester.pump();
      expect(_input(tester), '0.1');
    });

    testWidgets('설정을 바꾸면 표시와 입력한 금액에 바로 적용한다', (tester) async {
      await tester.pumpWidget(_charts(_usd, decimalPlaces: -1));
      await tester.pumpAndSettle();
      await tester.enterText(_amount, '1.25');
      await tester.pump();

      await tester.pumpWidget(_charts(_usd, decimalPlaces: 0));
      await tester.pump();

      expect(_text(tester, _rate), '1,300');
      expect(_input(tester), '1');
      expect(_text(tester, _converted), '1,300 KRW');
    });

    testWidgets('제한 자릿수에서 0이 되는 기간 변화는 변동 없음으로 보여 준다', (tester) async {
      await tester.pumpWidget(
        _charts(_usd, decimalPlaces: -1, source: _tinyMove()),
      );
      await tester.pumpAndSettle();

      expect(_text(tester, _rate), '1,300.12');
      expect(_changeText(tester), startsWith('변동 없음'));
    });

    testWidgets('선택일 환율과 비교 줄도 제한 자릿수로 보여 준다', (tester) async {
      await tester.pumpWidget(
        _charts(
          _usd,
          decimalPlaces: -1,
          source: _Source(1300.5, start: 1290.126),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_amount, '1');
      await tester.pump();

      // 기간 첫 기록(1,290.126)과 현재(1,300.5)를 비교한다.
      await select(tester, 0);
      expect(_text(tester, selectedRate), '1 USD = 1,290.13 KRW');
      expect(_text(tester, compareSelected), '1,290.13 KRW');
      expect(_text(tester, compareLatest), '1,300.5 KRW');
      expect(_text(tester, compareDifference), '+10.37 KRW');
    });

    testWidgets('비교 차이가 제한 자릿수에서 0이면 부호 없이 0이다', (tester) async {
      await tester.pumpWidget(
        _charts(_usd, decimalPlaces: -1, source: _tinyMove()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_amount, '1');
      await tester.pump();

      await select(tester, 0);
      expect(_text(tester, selectedRate), '1 USD = 1,300.12 KRW');
      expect(_text(tester, compareSelected), '1,300.12 KRW');
      expect(_text(tester, compareLatest), '1,300.12 KRW');
      expect(_text(tester, compareDifference), '0 KRW');
    });

    testWidgets('작은 환율의 기간 변화는 제한 없이 보여 준다', (tester) async {
      await tester.pumpWidget(
        _charts(
          _usd,
          decimalPlaces: -1,
          source: _Source(0.00072, start: 0.0007),
        ),
      );
      await tester.pumpAndSettle();

      expect(_text(tester, _rate), '0.00072');
      expect(_changeText(tester), startsWith('▲ 0.00002 ('));
    });

    testWidgets('비교 줄의 한쪽이 제한 없이 보이면 차이도 제한 없이 보여 준다', (tester) async {
      await tester.pumpWidget(
        _charts(_usd, decimalPlaces: -1, source: _Source(0.01, start: 0.0072)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_amount, '1');
      await tester.pump();

      await select(tester, 0);
      expect(_text(tester, compareSelected), '0.0072 KRW');
      expect(_text(tester, compareLatest), '0.01 KRW');
      expect(_text(tester, compareDifference), '+0.0028 KRW');
    });

    testWidgets('결과가 코인이면 환산 금액을 5자리로 보여 준다', (tester) async {
      // 코인 차트는 코인/KRW 고정이라, 결과가 코인인 방향은 뒤집은 KRW → BTC뿐이다.
      await tester.pumpWidget(_charts(_btc, decimalPlaces: -1));
      await tester.pumpAndSettle();
      await tester.tap(_swap);
      await tester.pumpAndSettle();

      await tester.enterText(_amount, '12345678');
      await tester.pump();
      expect(_text(tester, _converted), '0.12346 BTC');
    });
  });
}
