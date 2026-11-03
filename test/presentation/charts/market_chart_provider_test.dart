import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_period_policy.dart';
import 'package:tripbler/presentation/charts/chart_snapshot_store.dart';
import 'package:tripbler/presentation/charts/market_chart_provider.dart';

import '../../helpers/memory_chart_snapshots.dart';

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

/// 저장값 읽기를 테스트가 직접 끝내는 저장소.
class GatedSnapshots extends ChartSnapshotStore {
  final List<Completer<ChartData?>> reads = [];
  final List<String> keys = [];
  final Map<String, ChartData> written = {};

  @override
  Future<ChartData?> read(String key, {required bool crypto}) {
    keys.add(key);
    final read = Completer<ChartData?>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<void> write(String key, ChartData data) async => written[key] = data;
}

final _fetchedAt = DateTime.utc(2026, 11, 1, 9);

ChartData data(
  double rate, {
  bool stale = false,
  bool historicalRate = false,
}) => ChartData(
  history: [
    ChartSample(
      date: DateTime.utc(2026, 10, 31),
      rate: rate,
      baseCurrencyCode: 'BTC',
      targetCurrencyCode: 'KRW',
    ),
  ],
  currentRate: rate,
  fetchedAt: _fetchedAt,
  stale: stale,
  historicalRate: historicalRate,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  MarketChartProvider create(
    PendingSource source,
    ChartSnapshotStore snapshots, {
    bool crypto = true,
    ChartPeriod period = ChartPeriod.oneMonth,
  }) => MarketChartProvider(
    requestKey: 'crypto:BTC/KRW',
    crypto: crypto,
    dataSource: source,
    period: period,
    snapshots: snapshots,
  );

  test('shows the stored value first, then replaces it and saves', () async {
    final source = PendingSource();
    final snapshots = MemorySnapshots()
      ..saved['crypto:BTC/KRW/oneMonth'] = data(100, stale: true);
    final chart = create(source, snapshots);

    final load = chart.loadIfNeeded();
    await pumpEventQueue();
    expect(chart.state.isLoading, isTrue);
    expect(chart.state.history.single.rate, 100);
    expect(chart.state.stale, isTrue);
    expect(chart.state.showsOldData, isTrue);

    source.requests.single.complete(data(200));
    await load;
    expect(chart.state.isLoading, isFalse);
    expect(chart.state.history.single.rate, 200);
    expect(chart.state.showsOldData, isFalse);
    expect(snapshots.saved['crypto:BTC/KRW/oneMonth']!.currentRate, 200);

    // 이미 값을 받았으므로 다시 조회하지 않는다.
    await chart.loadIfNeeded();
    expect(source.requests, hasLength(1));
    chart.dispose();
  });

  test('failure keeps the last success and its fetchedAt', () async {
    final source = PendingSource();
    final chart = create(source, MemorySnapshots());

    unawaited(chart.reload());
    await pumpEventQueue();
    // 기본값(false)과 구분되도록 historicalRate가 true인 값으로 확인한다.
    source.requests.single.complete(data(100, historicalRate: true));
    await pumpEventQueue();

    unawaited(chart.reload());
    await pumpEventQueue();
    source.requests.last.completeError(StateError('timeout'));
    await pumpEventQueue();

    expect(chart.state.failed, isTrue);
    expect(chart.state.stale, isTrue);
    expect(chart.state.hasLoaded, isTrue);
    expect(chart.state.history.single.rate, 100);
    expect(chart.state.currentRate, 100);
    expect(chart.state.fetchedAt, _fetchedAt);
    expect(chart.state.historicalRate, isTrue);
    expect(chart.state.showsOldData, isTrue);
    chart.dispose();
  });

  test('failure without any value is not loaded', () async {
    final source = PendingSource();
    final chart = create(source, MemorySnapshots());

    unawaited(chart.reload());
    await pumpEventQueue();
    source.requests.single.completeError(StateError('down'));
    await pumpEventQueue();

    expect(chart.state.failed, isTrue);
    expect(chart.state.hasLoaded, isFalse);
    expect(chart.state.history, isEmpty);
    chart.dispose();
  });

  test('responses for an old period or request are ignored', () async {
    final first = PendingSource();
    final chart = create(first, MemorySnapshots());

    unawaited(chart.reload());
    await pumpEventQueue();
    chart.changePeriod(ChartPeriod.oneYear);
    expect(chart.state.history, isEmpty);
    first.requests.single.complete(data(100));
    await pumpEventQueue();
    expect(chart.state.history, isEmpty);

    unawaited(chart.loadIfNeeded());
    await pumpEventQueue();
    expect(first.periods.last, ChartPeriod.oneYear);

    final second = PendingSource();
    chart.changeRequest(
      requestKey: 'crypto:ETH/KRW',
      crypto: true,
      dataSource: second,
    );
    expect(first.disposed, isTrue);
    first.requests.last.complete(data(300));
    await pumpEventQueue();
    expect(chart.state.history, isEmpty);
    expect(chart.state.isLoading, isFalse);
    chart.dispose();
  });

  test('dispose releases the source and drops late responses', () async {
    final source = PendingSource();
    final chart = create(source, MemorySnapshots());
    var notified = 0;
    chart.addListener(() => notified++);

    unawaited(chart.reload());
    await pumpEventQueue();
    final before = notified;
    chart.dispose();
    expect(source.disposed, isTrue);

    source.requests.single.complete(data(100));
    await pumpEventQueue();
    expect(notified, before);
  });

  test('unsupported crypto periods skip the stored value', () async {
    expect(
      ChartPeriodPolicy.supports(ChartPeriod.fiveYears, crypto: true),
      isFalse,
    );
    expect(
      ChartPeriodPolicy.supports(ChartPeriod.fiveYears, crypto: false),
      isTrue,
    );

    final source = PendingSource();
    final snapshots = MemorySnapshots();
    final chart = create(source, snapshots, period: ChartPeriod.fiveYears);
    unawaited(chart.reload());
    await pumpEventQueue();
    expect(snapshots.reads, isEmpty);
    expect(source.requests, hasLength(1));
    chart.dispose();
  });

  test('changing period while reading the stored value drops it', () async {
    final source = PendingSource();
    final snapshots = GatedSnapshots();
    final chart = create(source, snapshots);

    unawaited(chart.loadIfNeeded());
    await pumpEventQueue();
    expect(snapshots.keys.single, 'crypto:BTC/KRW/oneMonth');
    expect(chart.state.isLoading, isTrue);

    chart.changePeriod(ChartPeriod.oneYear);
    snapshots.reads.single.complete(data(100, stale: true));
    await pumpEventQueue();

    // 이전 기간의 저장값을 보여 주지 않고, 이전 기간으로 조회하지도 않는다.
    expect(chart.state.history, isEmpty);
    expect(chart.state.hasLoaded, isFalse);
    expect(chart.state.isLoading, isFalse);
    expect(source.requests, isEmpty);

    unawaited(chart.loadIfNeeded());
    await pumpEventQueue();
    expect(snapshots.keys.last, 'crypto:BTC/KRW/oneYear');
    snapshots.reads.last.complete(null);
    await pumpEventQueue();
    expect(source.periods, [ChartPeriod.oneYear]);

    source.requests.single.complete(data(200));
    await pumpEventQueue();
    expect(chart.state.history.single.rate, 200);
    expect(snapshots.written.keys, ['crypto:BTC/KRW/oneYear']);
    chart.dispose();
  });

  test('dispose while reading the stored value stays silent', () async {
    // 저장값이 있는 경우와 없는 경우 모두 늦게 끝난 읽기는 아무것도 하지 않는다.
    for (final stored in [data(100, stale: true), null]) {
      final source = PendingSource();
      final snapshots = GatedSnapshots();
      final chart = create(source, snapshots);
      var notified = 0;
      chart.addListener(() => notified++);

      unawaited(chart.loadIfNeeded());
      await pumpEventQueue();
      final before = notified;
      chart.dispose();

      snapshots.reads.single.complete(stored);
      await pumpEventQueue();
      expect(notified, before);
      expect(source.requests, isEmpty);
      expect(snapshots.written, isEmpty);
    }
  });

  test(
    'a failure for an old period does not mark the new one failed',
    () async {
      final source = PendingSource();
      final chart = create(source, MemorySnapshots());

      unawaited(chart.reload());
      await pumpEventQueue();
      chart.changePeriod(ChartPeriod.oneYear);
      source.requests.single.completeError(StateError('timeout'));
      await pumpEventQueue();

      expect(chart.state.failed, isFalse);
      expect(chart.state.isLoading, isFalse);
      expect(chart.state.hasLoaded, isFalse);

      // 새 기간 조회 중에 이전 요청이 실패해도 새 조회는 계속된다.
      unawaited(chart.loadIfNeeded());
      await pumpEventQueue();
      chart.changePeriod(ChartPeriod.sevenDays);
      unawaited(chart.loadIfNeeded());
      await pumpEventQueue();
      expect(source.periods, [
        ChartPeriod.oneMonth,
        ChartPeriod.oneYear,
        ChartPeriod.sevenDays,
      ]);
      source.requests[1].completeError(StateError('timeout'));
      await pumpEventQueue();
      expect(chart.state.failed, isFalse);
      expect(chart.state.isLoading, isTrue);

      source.requests.last.complete(data(300));
      await pumpEventQueue();
      expect(chart.state.failed, isFalse);
      expect(chart.state.history.single.rate, 300);
      chart.dispose();
    },
  );
}
