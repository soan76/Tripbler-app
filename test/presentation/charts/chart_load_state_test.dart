import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_load_state.dart';

ChartSample sample(double rate) => ChartSample(
  date: DateTime.utc(2026, 10, 31),
  rate: rate,
  baseCurrencyCode: 'BTC',
  targetCurrencyCode: 'KRW',
);

void main() {
  final fetchedAt = DateTime.utc(2026, 11, 1, 9);
  final data = ChartData(
    history: [sample(100)],
    currentRate: 100,
    fetchedAt: fetchedAt,
    historicalRate: true,
  );
  final loaded = ChartLoadState(hasLoaded: true, stale: true, data: data);

  test('exposes the values of the stored chart data', () {
    expect(loaded.history, same(data.history));
    expect(loaded.currentRate, 100);
    expect(loaded.fetchedAt, fetchedAt);
    expect(loaded.historicalRate, isTrue);
    expect(loaded.showsOldData, isTrue);

    expect(ChartLoadState.initial.history, isEmpty);
    expect(ChartLoadState.initial.currentRate, isNull);
    expect(ChartLoadState.initial.fetchedAt, isNull);
    expect(ChartLoadState.initial.historicalRate, isFalse);
    expect(ChartLoadState.initial.showsOldData, isFalse);
  });

  test('history cannot be changed from outside', () {
    final source = [sample(100)];
    final state = ChartLoadState(
      data: ChartData(history: source, currentRate: 100, fetchedAt: fetchedAt),
    );

    // 넘긴 목록을 나중에 고쳐도 상태는 바뀌지 않는다.
    source.add(sample(200));
    expect(state.history, hasLength(1));

    expect(() => state.history.add(sample(300)), throwsUnsupportedError);
    expect(() => state.history.clear(), throwsUnsupportedError);
    expect(() => loaded.history[0] = sample(400), throwsUnsupportedError);
    expect(
      () => ChartLoadState.initial.history.add(sample(1)),
      throwsUnsupportedError,
    );
  });

  test('copyWith keeps every field that is not passed', () {
    final next = loaded.copyWith(isLoading: true);

    expect(next.isLoading, isTrue);
    expect(next.hasLoaded, isTrue);
    expect(next.failed, isFalse);
    expect(next.stale, isTrue);
    expect(next.data, same(data));
    // 같은 목록을 그대로 써서 뒤집은 그래프 캐시가 유지된다.
    expect(next.history, same(data.history));
  });

  test('copyWith replaces passed values', () {
    final later = ChartData(
      history: [sample(200)],
      currentRate: 200,
      fetchedAt: DateTime.utc(2026, 11, 2),
    );
    final next = loaded.copyWith(failed: true, stale: false, data: later);

    expect(next.failed, isTrue);
    expect(next.stale, isFalse);
    expect(next.data, same(later));
    expect(next.currentRate, 200);
    expect(next.historicalRate, isFalse);
  });

  test('copyWith keeps the data when null is passed', () {
    expect(loaded.copyWith(data: null).data, same(data));
  });
}
