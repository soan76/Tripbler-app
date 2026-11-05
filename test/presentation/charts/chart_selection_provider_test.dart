import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/crypto/models/crypto_coin.dart';
import 'package:tripbler/models/currency_model.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import 'package:tripbler/presentation/exchange/display_currency.dart';

const key = ChartSelectionProvider.storageKey;

Future<List<String>?> stored() async =>
    (await SharedPreferences.getInstance()).getStringList(key);

DisplayCurrency fiat(String code) =>
    DisplayCurrency.fromFiat(findCurrencyByCode(code)!);
DisplayCurrency coin(String symbol) =>
    DisplayCurrency.fromCrypto(CryptoCoin(symbol: symbol, name: symbol));

void main() {
  test('starts with USD/KRW, JPY/KRW and BTC/KRW', () async {
    SharedPreferences.setMockInitialValues({});
    final charts = ChartSelectionProvider();
    expect(charts.loaded, isFalse);
    await charts.initialize();
    expect(charts.loaded, isTrue);
    expect(charts.pairs.map((p) => p.id), [
      'fiat:USD/KRW',
      'fiat:JPY/KRW',
      'crypto:BTC/KRW',
    ]);
    // 처음 상태는 저장하지 않아 기본값이 바뀌면 그대로 따라간다.
    expect(await stored(), isNull);
    charts.dispose();
  });

  test(
    'restores saved pairs, skipping invalid, duplicate and extra ids',
    () async {
      SharedPreferences.setMockInitialValues({
        key: [
          'crypto:ETH/KRW',
          'fiat:XXX/KRW',
          'fiat:EUR/USD',
          'crypto:ETH/KRW',
          'fiat:USD/KRW',
          'fiat:JPY/KRW',
          'crypto:BTC/KRW',
          'fiat:GBP/KRW',
        ],
      });
      final charts = ChartSelectionProvider();
      await charts.initialize();
      expect(charts.pairs.map((p) => p.id), [
        'crypto:ETH/KRW',
        'fiat:EUR/USD',
        'fiat:USD/KRW',
        'fiat:JPY/KRW',
        'crypto:BTC/KRW',
      ]);
      expect(charts.canAdd, isFalse);
      charts.dispose();
    },
  );

  test(
    'an empty or unreadable saved list falls back to the defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        key: ['nonsense'],
      });
      final charts = ChartSelectionProvider();
      await charts.initialize();
      expect(charts.pairs, ChartSelectionProvider.defaults);
      charts.dispose();
    },
  );

  test('replace changes one card, refuses duplicates and saves', () async {
    SharedPreferences.setMockInitialValues({});
    final charts = ChartSelectionProvider();
    await charts.initialize();
    var notified = 0;
    charts.addListener(() => notified++);

    expect(
      charts.replace(0, const ChartPair.fiat('EUR', 'KRW')),
      ChartPairChange.changed,
    );
    expect(charts.pairs.first.id, 'fiat:EUR/KRW');
    expect(notified, 1);
    await pumpEventQueue();
    expect(await stored(), ['fiat:EUR/KRW', 'fiat:JPY/KRW', 'crypto:BTC/KRW']);

    expect(
      charts.replace(0, const ChartPair.crypto('BTC')),
      ChartPairChange.duplicate,
    );
    expect(
      charts.replace(1, const ChartPair.fiat('JPY', 'KRW')),
      ChartPairChange.unchanged,
    );
    expect(notified, 1);
    expect(charts.pairs.first.id, 'fiat:EUR/KRW');
    charts.dispose();
  });

  test('add stops at five cards and remove keeps at least one', () async {
    SharedPreferences.setMockInitialValues({});
    final charts = ChartSelectionProvider();
    await charts.initialize();

    final added = [charts.add(), charts.add()];
    expect(added.every((pair) => pair != null), isTrue);
    expect(charts.pairs, hasLength(ChartSelectionProvider.maxCards));
    expect(charts.pairs.toSet(), hasLength(5));
    // 새 카드는 아직 없는 통화/KRW 쌍이다.
    for (final pair in added) {
      expect(pair!.isCrypto, isFalse);
      expect(pair.targetCode, 'KRW');
    }
    expect(charts.canAdd, isFalse);
    expect(charts.add(), isNull);
    expect(charts.pairs, hasLength(5));

    charts.remove(1);
    expect(charts.pairs, hasLength(4));
    expect(charts.pairs.map((p) => p.id), isNot(contains('fiat:JPY/KRW')));
    while (charts.canRemove) {
      charts.remove(0);
    }
    expect(charts.pairs, hasLength(1));
    charts.remove(0);
    expect(charts.pairs, hasLength(1));

    await pumpEventQueue();
    expect(await stored(), [charts.pairs.single.id]);
    charts.dispose();
  });

  test('pairs cannot be changed from outside', () async {
    SharedPreferences.setMockInitialValues({});
    final charts = ChartSelectionProvider();
    await charts.initialize();
    expect(
      () => charts.pairs.add(const ChartPair.crypto('ETH')),
      throwsUnsupportedError,
    );
    charts.dispose();
  });

  test('pairs that differ only in direction count as one chart', () async {
    SharedPreferences.setMockInitialValues({
      key: ['fiat:KRW/USD', 'fiat:USD/KRW', 'fiat:JPY/KRW', 'fiat:KRW/JPY'],
    });
    final charts = ChartSelectionProvider();
    await charts.initialize();
    // 저장값을 읽을 때도 먼저 나온 방향만 남긴다.
    expect(charts.pairs.map((p) => p.id), ['fiat:KRW/USD', 'fiat:JPY/KRW']);

    expect(
      charts.replace(1, const ChartPair.fiat('USD', 'KRW')),
      ChartPairChange.duplicate,
    );
    expect(charts.pairs[1].id, 'fiat:JPY/KRW');

    // 기본 후보 USD/KRW는 KRW/USD와 같은 차트라 건너뛴다.
    expect(charts.add(), const ChartPair.crypto('BTC'));
    final next = charts.add()!;
    expect(next.isSameChart(const ChartPair.fiat('KRW', 'USD')), isFalse);
    expect(next.isSameChart(const ChartPair.fiat('KRW', 'JPY')), isFalse);
    charts.dispose();
  });

  test('changes before the saved pairs are read are ignored', () async {
    SharedPreferences.setMockInitialValues({
      key: ['fiat:EUR/KRW', 'crypto:ETH/KRW'],
    });
    final charts = ChartSelectionProvider();
    var notified = 0;
    charts.addListener(() => notified++);

    expect(
      charts.replace(0, const ChartPair.fiat('GBP', 'KRW')),
      ChartPairChange.notLoaded,
    );
    expect(
      charts.replaceSide(
        0,
        expected: charts.pairs.first,
        base: true,
        swapped: false,
        currency: fiat('GBP'),
      ),
      ChartPairChange.notLoaded,
    );
    expect(charts.add(), isNull);
    charts.remove(0);
    expect(charts.pairs, ChartSelectionProvider.defaults);
    expect(notified, 0);
    await pumpEventQueue();
    expect(await stored(), ['fiat:EUR/KRW', 'crypto:ETH/KRW']);

    await charts.initialize();
    // 읽은 저장값과 화면이 어긋나지 않는다.
    expect(charts.pairs.map((p) => p.id), ['fiat:EUR/KRW', 'crypto:ETH/KRW']);
    await pumpEventQueue();
    expect(await stored(), ['fiat:EUR/KRW', 'crypto:ETH/KRW']);
    charts.dispose();
  });

  test('replaceSide computes the pair and the direction to show', () async {
    SharedPreferences.setMockInitialValues({});
    final charts = ChartSelectionProvider();
    await charts.initialize();
    const usdKrw = ChartPair.fiat('USD', 'KRW');

    // "KRW ⇄ USD"로 보는 중 왼쪽 KRW를 EUR로 바꾸면 "EUR ⇄ USD".
    expect(
      charts.replaceSide(
        0,
        expected: usdKrw,
        base: false,
        swapped: true,
        currency: fiat('EUR'),
      ),
      ChartPairChange.changed,
    );
    expect(charts.pairs.first, const ChartPair.fiat('USD', 'EUR'));
    expect(charts.swappedAfterReplace(usdKrw.id, 'fiat:USD/EUR'), isTrue);
    // 한 번 알려 준 결과는 비워 같은 변경이 다시 쓰이지 않는다.
    expect(charts.swappedAfterReplace(usdKrw.id, 'fiat:USD/EUR'), isNull);
    expect(charts.swappedAfterReplace('fiat:JPY/KRW', 'fiat:USD/EUR'), isNull);

    // 정방향 "JPY ⇄ KRW"의 오른쪽에서 코인을 고르면 "KRW ⇄ ETH".
    expect(
      charts.replaceSide(
        1,
        expected: const ChartPair.fiat('JPY', 'KRW'),
        base: false,
        swapped: false,
        currency: coin('ETH'),
      ),
      ChartPairChange.changed,
    );
    expect(charts.pairs[1], const ChartPair.crypto('ETH'));
    expect(charts.swappedAfterReplace('fiat:JPY/KRW', 'crypto:ETH/KRW'), true);
    // 이전 변경의 방향은 더 이상 알려 주지 않는다.
    expect(charts.swappedAfterReplace(usdKrw.id, 'fiat:USD/EUR'), isNull);

    // 다른 경로(추가·삭제)로 목록이 바뀌면 마지막 replaceSide 결과를 비운다.
    charts.replaceSide(
      1,
      expected: const ChartPair.crypto('ETH'),
      base: true,
      swapped: true,
      currency: coin('SOL'),
    );
    charts.add();
    expect(
      charts.swappedAfterReplace('crypto:ETH/KRW', 'crypto:SOL/KRW'),
      isNull,
    );
    charts.dispose();
  });

  test(
    'replaceSide exchanges positions when the chart already exists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final charts = ChartSelectionProvider();
      await charts.initialize();
      var notified = 0;
      charts.addListener(() => notified++);

      expect(
        charts.replaceSide(
          0,
          expected: const ChartPair.fiat('USD', 'KRW'),
          base: true,
          swapped: false,
          currency: fiat('JPY'),
        ),
        ChartPairChange.swappedPositions,
      );
      expect(notified, 1);
      expect(charts.pairs.map((p) => p.id), [
        'fiat:JPY/KRW',
        'fiat:USD/KRW',
        'crypto:BTC/KRW',
      ]);
      // 교환 결과는 같은 자리 변경(swappedAfterReplace)으로 알려 주지 않고,
      // 바뀐 순서를 저장한다.
      expect(
        charts.swappedAfterReplace('fiat:USD/KRW', 'fiat:JPY/KRW'),
        isNull,
      );
      await pumpEventQueue();
      expect(await stored(), [
        'fiat:JPY/KRW',
        'fiat:USD/KRW',
        'crypto:BTC/KRW',
      ]);

      // 코인을 고른 경우도 같다.
      expect(
        charts.replaceSide(
          1,
          expected: const ChartPair.fiat('USD', 'KRW'),
          base: false,
          swapped: false,
          currency: coin('BTC'),
        ),
        ChartPairChange.swappedPositions,
      );
      expect(charts.pairs.map((p) => p.id), [
        'fiat:JPY/KRW',
        'crypto:BTC/KRW',
        'fiat:USD/KRW',
      ]);

      // 방향만 다른 쌍도 같은 차트이며, 있던 카드의 ID는 그대로 옮긴다.
      charts.replace(2, const ChartPair.fiat('KRW', 'USD'));
      expect(
        charts.replaceSide(
          0,
          expected: const ChartPair.fiat('JPY', 'KRW'),
          base: true,
          swapped: false,
          currency: fiat('USD'),
        ),
        ChartPairChange.swappedPositions,
      );
      expect(charts.pairs.map((p) => p.id), [
        'fiat:KRW/USD',
        'crypto:BTC/KRW',
        'fiat:JPY/KRW',
      ]);
      charts.dispose();
    },
  );

  group('exchanging positions shows the pick on the pressed side', () {
    /// 카드의 화면 표시(왼쪽, 오른쪽).
    (String, String) shown(ChartPair pair, bool swapped) => swapped
        ? (pair.targetCode, pair.baseCode)
        : (pair.baseCode, pair.targetCode);

    const usdKrw = ChartPair.fiat('USD', 'KRW');
    const eth = ChartPair.crypto('ETH');
    const btc = ChartPair.crypto('BTC');

    // (제목, 누른 카드, 누른 카드 뒤집힘, 왼쪽을 눌렀는지, 고른 통화, 있던 카드, 기대 표시)
    final cases =
        <
          (
            String,
            ChartPair,
            bool,
            bool,
            DisplayCurrency,
            ChartPair,
            (String, String),
          )
        >[
          for (final existing in const [
            ChartPair.fiat('JPY', 'KRW'),
            ChartPair.fiat('KRW', 'JPY'),
          ]) ...[
            // 정방향 "USD ⇄ KRW"의 왼쪽 USD를 JPY로.
            (
              'forward left fiat',
              usdKrw,
              false,
              true,
              fiat('JPY'),
              existing,
              ('JPY', 'KRW'),
            ),
            // 뒤집힌 "KRW ⇄ USD"의 오른쪽 USD를 JPY로.
            (
              'flipped right fiat',
              usdKrw,
              true,
              false,
              fiat('JPY'),
              existing,
              ('KRW', 'JPY'),
            ),
          ],
          for (final existing in const [
            ChartPair.fiat('USD', 'JPY'),
            ChartPair.fiat('JPY', 'USD'),
          ]) ...[
            // 정방향 "USD ⇄ KRW"의 오른쪽 KRW를 JPY로.
            (
              'forward right fiat',
              usdKrw,
              false,
              false,
              fiat('JPY'),
              existing,
              ('USD', 'JPY'),
            ),
            // 뒤집힌 "KRW ⇄ USD"의 왼쪽 KRW를 JPY로.
            (
              'flipped left fiat',
              usdKrw,
              true,
              true,
              fiat('JPY'),
              existing,
              ('JPY', 'USD'),
            ),
          ],
          // 국가 통화 카드에서 코인을 고르면 고른 쪽에 코인이 보인다.
          for (final swapped in const [false, true]) ...[
            (
              'swapped $swapped left coin',
              usdKrw,
              swapped,
              true,
              coin('BTC'),
              btc,
              ('BTC', 'KRW'),
            ),
            (
              'swapped $swapped right coin',
              usdKrw,
              swapped,
              false,
              coin('BTC'),
              btc,
              ('KRW', 'BTC'),
            ),
          ],
          // 코인 카드에서 다른 코인을 고르는 경우(KRW 쪽은 KRW만 고를 수 있다).
          (
            'coin card forward left coin',
            eth,
            false,
            true,
            coin('BTC'),
            btc,
            ('BTC', 'KRW'),
          ),
          (
            'coin card flipped right coin',
            eth,
            true,
            false,
            coin('BTC'),
            btc,
            ('KRW', 'BTC'),
          ),
          // 코인 카드에서 국가 통화를 고르면 코인 자리에 그 통화가 온다.
          for (final existing in const [
            ChartPair.fiat('USD', 'KRW'),
            ChartPair.fiat('KRW', 'USD'),
          ]) ...[
            (
              'coin card forward left fiat',
              eth,
              false,
              true,
              fiat('USD'),
              existing,
              ('USD', 'KRW'),
            ),
            (
              'coin card flipped right fiat',
              eth,
              true,
              false,
              fiat('USD'),
              existing,
              ('KRW', 'USD'),
            ),
          ],
        ];

    for (final (title, pressed, swapped, left, picked, existing, want)
        in cases) {
      test(
        '$title: ${pressed.id} picks ${picked.code}, has ${existing.id}',
        () async {
          SharedPreferences.setMockInitialValues({
            key: [pressed.id, existing.id],
          });
          final charts = ChartSelectionProvider();
          await charts.initialize();

          expect(
            charts.replaceSide(
              0,
              expected: pressed,
              // ChartPair.replaceShown의 규칙: 왼쪽을 누른 것은 base != swapped.
              base: left != swapped,
              swapped: swapped,
              currency: picked,
            ),
            ChartPairChange.swappedPositions,
          );
          expect(charts.pairs, [existing, pressed]);

          final direction = charts.swappedAfterExchange(
            pressed.id,
            existing.id,
          )!;
          // 방향만 정하고 옮겨 온 카드의 ID는 그대로다.
          expect(direction.id, existing.id);
          expect(shown(existing, direction.swapped), want);
          charts.dispose();
        },
      );
    }

    test('the answer is given once and only for the exchanged cards', () async {
      SharedPreferences.setMockInitialValues({});
      const usd = ChartPair.fiat('USD', 'KRW');
      const jpy = ChartPair.fiat('JPY', 'KRW');
      final charts = ChartSelectionProvider();
      await charts.initialize();
      void exchange(ChartPair pressed) => charts.replaceSide(
        0,
        expected: pressed,
        base: true,
        swapped: false,
        currency: fiat(pressed == usd ? 'JPY' : 'USD'),
      );

      // 두 ID의 순서는 상관없고, 항상 옮겨 온 카드를 알려 준다.
      exchange(usd);
      expect(charts.swappedAfterExchange(usd.id, jpy.id)?.id, jpy.id);
      expect(charts.swappedAfterExchange(usd.id, jpy.id), isNull);
      exchange(jpy);
      expect(charts.swappedAfterExchange(jpy.id, usd.id)?.id, usd.id);

      // 다른 카드를 물으면 알려 주지 않고 비운다.
      exchange(usd);
      expect(charts.swappedAfterExchange(usd.id, 'crypto:BTC/KRW'), isNull);
      expect(charts.swappedAfterExchange(usd.id, jpy.id), isNull);

      // 다른 경로로 목록이 바뀌면 비운다.
      exchange(jpy);
      charts.add();
      expect(charts.swappedAfterExchange(usd.id, jpy.id), isNull);

      // 같은 자리 변경의 결과는 교환으로 알려 주지 않는다.
      charts.replaceSide(
        0,
        expected: usd,
        base: true,
        swapped: false,
        currency: coin('SOL'),
      );
      expect(charts.swappedAfterExchange(usd.id, 'crypto:SOL/KRW'), isNull);
      charts.dispose();
    });
  });

  test('replaceSide ignores stale and impossible picks', () async {
    SharedPreferences.setMockInitialValues({});
    final charts = ChartSelectionProvider();
    await charts.initialize();
    const usdKrw = ChartPair.fiat('USD', 'KRW');

    // 선택창이 열린 사이 카드가 바뀌었거나 지워졌으면 반영하지 않는다.
    expect(
      charts.replaceSide(
        0,
        expected: const ChartPair.fiat('EUR', 'KRW'),
        base: true,
        swapped: false,
        currency: fiat('GBP'),
      ),
      ChartPairChange.stale,
    );
    expect(
      charts.replaceSide(
        3,
        expected: usdKrw,
        base: true,
        swapped: false,
        currency: fiat('GBP'),
      ),
      ChartPairChange.stale,
    );
    // 두 쪽이 같아지는 조합은 만들지 않는다.
    expect(
      charts.replaceSide(
        0,
        expected: usdKrw,
        base: true,
        swapped: false,
        currency: fiat('KRW'),
      ),
      ChartPairChange.invalid,
    );

    charts.replace(0, const ChartPair.fiat('KRW', 'USD'));
    var notified = 0;
    charts.addListener(() => notified++);
    expect(
      charts.replaceSide(
        2,
        expected: const ChartPair.crypto('BTC'),
        base: false,
        swapped: false,
        currency: fiat('KRW'),
      ),
      ChartPairChange.unchanged,
    );
    expect(notified, 0);
    expect(charts.pairs.map((p) => p.id), [
      'fiat:KRW/USD',
      'fiat:JPY/KRW',
      'crypto:BTC/KRW',
    ]);
    charts.dispose();
  });
}
