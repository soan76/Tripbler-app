import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_snapshot_store.dart';
import 'package:tripbler/services/market_snapshot_store.dart';

const key = 'crypto:BTC/KRW/oneMonth';
const storedKey = 'market.snapshot.v1.chart.$key';

ChartData chartData({
  DateTime? fetchedAt,
  double? currentRate = 100,
  bool historicalRate = false,
  bool stale = false,
}) => ChartData(
  history: [
    ChartSample(
      date: DateTime.utc(2026, 10, 1),
      rate: 99.5,
      baseCurrencyCode: 'BTC',
      targetCurrencyCode: 'KRW',
    ),
    ChartSample(
      date: DateTime(2026, 10, 2, 13, 45, 30, 123),
      rate: 101.25,
      baseCurrencyCode: 'KRW',
      targetCurrencyCode: 'BTC',
      includesTime: true,
    ),
  ],
  currentRate: currentRate,
  fetchedAt: fetchedAt ?? DateTime.now(),
  stale: stale,
  historicalRate: historicalRate,
);

/// 저장소가 쓰는 형식 그대로의 정상 JSON. 손상 사례는 이 값을 고쳐 만든다.
Map<String, dynamic> validJson() => {
  'fetchedAt': DateTime.now()
      .subtract(const Duration(minutes: 1))
      .toIso8601String(),
  'currentRate': 100,
  'historicalRate': false,
  'points': <Map<String, dynamic>>[
    {
      'date': '2026-10-01T00:00:00.000Z',
      'rate': 99.5,
      'base': 'BTC',
      'target': 'KRW',
      'includesTime': false,
    },
  ],
};

Future<ChartData?> readRaw(String raw, {bool crypto = true}) {
  SharedPreferences.setMockInitialValues({storedKey: raw});
  return ChartSnapshotStore().read(key, crypto: crypto);
}

Future<ChartData?> readJson(
  void Function(Map<String, dynamic> json) change, {
  bool crypto = true,
}) {
  final json = validJson();
  change(json);
  return readRaw(jsonEncode(json), crypto: crypto);
}

Map<String, dynamic> firstPoint(Map<String, dynamic> json) =>
    (json['points'] as List).first as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('round trip', () {
    test('read returns every written field and marks it stale', () async {
      final store = ChartSnapshotStore();
      final written = chartData(historicalRate: true, stale: false);
      await store.write(key, written);

      final read = await store.read(key, crypto: true);
      expect(read, isNotNull);
      expect(read!.history, written.history);
      final second = read.history[1];
      expect(second.date, DateTime(2026, 10, 2, 13, 45, 30, 123));
      expect(second.date.isUtc, isFalse);
      expect(read.history.first.date.isUtc, isTrue);
      expect(second.includesTime, isTrue);
      expect(read.history.first.includesTime, isFalse);
      expect(read.currentRate, 100);
      expect(read.historicalRate, isTrue);
      expect(read.fetchedAt, written.fetchedAt);
      // 저장값은 다시 조회하기 전까지 항상 오래된 값으로 표시한다.
      expect(read.stale, isTrue);
    });

    test('null currentRate and false historicalRate survive', () async {
      final store = ChartSnapshotStore();
      await store.write(key, chartData(currentRate: null));

      final read = await store.read(key, crypto: false);
      expect(read, isNotNull);
      expect(read!.currentRate, isNull);
      expect(read.historicalRate, isFalse);
      expect(read.stale, isTrue);
    });

    test('stores under the chart. prefix with the points schema', () async {
      final written = chartData();
      await ChartSnapshotStore().write(key, written);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {storedKey});
      final json = jsonDecode(prefs.getString(storedKey)!);
      expect(json, {
        'fetchedAt': written.fetchedAt.toIso8601String(),
        'currentRate': 100.0,
        'historicalRate': false,
        'points': [
          {
            'date': '2026-10-01T00:00:00.000Z',
            'rate': 99.5,
            'base': 'BTC',
            'target': 'KRW',
            'includesTime': false,
          },
          {
            'date': DateTime(2026, 10, 2, 13, 45, 30, 123).toIso8601String(),
            'rate': 101.25,
            'base': 'KRW',
            'target': 'BTC',
            'includesTime': true,
          },
        ],
      });
    });

    test('a market snapshot without the chart. prefix is not read', () async {
      await MarketSnapshotStore().write(key, validJson());
      expect(await ChartSnapshotStore().read(key, crypto: true), isNull);
    });

    test('keys are kept apart', () async {
      final store = ChartSnapshotStore();
      await store.write('a', chartData(currentRate: 1));
      await store.write('b', chartData(currentRate: 2));
      expect((await store.read('a', crypto: true))!.currentRate, 1);
      expect((await store.read('b', crypto: true))!.currentRate, 2);
      expect(await store.read('c', crypto: true), isNull);
    });
  });

  group('empty history', () {
    test('is not written', () async {
      await ChartSnapshotStore().write(
        key,
        ChartData(history: const [], currentRate: 1, fetchedAt: DateTime.now()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('does not overwrite an earlier snapshot', () async {
      final store = ChartSnapshotStore();
      await store.write(key, chartData(currentRate: 100));
      await store.write(
        key,
        ChartData(history: const [], currentRate: 1, fetchedAt: DateTime.now()),
      );
      expect((await store.read(key, crypto: true))!.currentRate, 100);
    });
  });

  group('damaged values read as null', () {
    test('valid sample is readable (control)', () async {
      expect(await readJson((_) {}), isNotNull);
    });

    test('broken JSON', () async {
      expect(await readRaw('{"fetchedAt":'), isNull);
      expect(await readRaw('[]'), isNull);
    });

    test('missing or invalid fetchedAt', () async {
      expect(await readJson((json) => json.remove('fetchedAt')), isNull);
      expect(await readJson((json) => json['fetchedAt'] = 'yesterday'), isNull);
    });

    test('points with a wrong shape', () async {
      expect(await readJson((json) => json.remove('points')), isNull);
      expect(await readJson((json) => json['points'] = 'x'), isNull);
      expect(await readJson((json) => json['points'] = [1]), isNull);
      expect(await readJson((json) => firstPoint(json).remove('rate')), isNull);
      expect(
        await readJson((json) => firstPoint(json)['rate'] = '99.5'),
        isNull,
      );
      expect(
        await readJson((json) => firstPoint(json)['date'] = 'not a date'),
        isNull,
      );
      expect(await readJson((json) => firstPoint(json).remove('base')), isNull);
      expect(await readJson((json) => firstPoint(json)['target'] = 7), isNull);
    });

    test('one bad point discards the whole snapshot', () async {
      expect(
        await readJson(
          (json) =>
              (json['points'] as List).add({...firstPoint(json), 'rate': -1}),
        ),
        isNull,
      );
    });

    test('point rate of zero, negative or non-finite', () async {
      expect(await readJson((json) => firstPoint(json)['rate'] = 0), isNull);
      expect(await readJson((json) => firstPoint(json)['rate'] = -1), isNull);
      // JSON에는 Infinity가 없지만 범위를 넘는 수는 무한대로 읽힌다.
      final infinite = jsonEncode(validJson()).replaceFirst('99.5', '1e999');
      expect(infinite, contains('1e999'));
      expect(await readRaw(infinite), isNull);
    });

    test('empty points', () async {
      expect(await readJson((json) => json['points'] = []), isNull);
    });

    test('currentRate of zero, negative or non-finite', () async {
      expect(await readJson((json) => json['currentRate'] = 0), isNull);
      expect(await readJson((json) => json['currentRate'] = -5), isNull);
      expect(await readJson((json) => json['currentRate'] = 'x'), isNull);
      final infinite = jsonEncode(
        validJson(),
      ).replaceFirst('"currentRate":100', '"currentRate":1e999');
      expect(infinite, contains('1e999'));
      expect(await readRaw(infinite), isNull);
    });

    test('missing currentRate reads as null rate, not a failure', () async {
      final read = await readJson((json) => json.remove('currentRate'));
      expect(read, isNotNull);
      expect(read!.currentRate, isNull);
    });
  });

  group('maximum age', () {
    Future<ChartData?> writeAndRead(
      Duration age, {
      required bool crypto,
    }) async {
      final store = ChartSnapshotStore();
      await store.write(
        key,
        chartData(fetchedAt: DateTime.now().subtract(age)),
      );
      return store.read(key, crypto: crypto);
    }

    const margin = Duration(minutes: 1);

    test('crypto snapshots last one day', () async {
      expect(
        await writeAndRead(const Duration(days: 1) - margin, crypto: true),
        isNotNull,
      );
      expect(
        await writeAndRead(const Duration(days: 1) + margin, crypto: true),
        isNull,
      );
    });

    test('fiat snapshots last seven days', () async {
      expect(
        await writeAndRead(const Duration(days: 1) + margin, crypto: false),
        isNotNull,
      );
      expect(
        await writeAndRead(const Duration(days: 7) - margin, crypto: false),
        isNotNull,
      );
      expect(
        await writeAndRead(const Duration(days: 7) + margin, crypto: false),
        isNull,
      );
    });

    test('a snapshot from the future is rejected', () async {
      expect(await writeAndRead(-margin, crypto: true), isNull);
      expect(await writeAndRead(-margin, crypto: false), isNull);
    });

    test('an expired snapshot stays stored but is not shown', () async {
      expect(await writeAndRead(const Duration(days: 2), crypto: true), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(storedKey), isNotNull);
      // 같은 값이라도 국가 통화 기준(7일)으로 읽으면 아직 유효하다.
      expect(await ChartSnapshotStore().read(key, crypto: false), isNotNull);
    });
  });

  group('write queue', () {
    test('writes in the same tick finish in order', () async {
      final store = ChartSnapshotStore();
      final first = store.write(key, chartData(currentRate: 1));
      final second = store.write(key, chartData(currentRate: 2));
      await Future.wait([first, second]);
      expect((await store.read(key, crypto: true))!.currentRate, 2);
    });

    test('nothing from the previous test leaks into this one', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(await ChartSnapshotStore().read(key, crypto: true), isNull);
    });
  });
}
