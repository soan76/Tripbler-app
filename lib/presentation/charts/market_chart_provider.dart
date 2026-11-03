import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/exchange_rate_history_model.dart';
import 'chart_data_source.dart';
import 'chart_load_state.dart';
import 'chart_period_policy.dart';
import 'chart_snapshot_store.dart';

/// 차트 카드 하나의 조회 상태를 관리한다.
/// 저장값을 먼저 보여 준 뒤 다시 조회하고(stale-while-revalidate), 요청이나 기간이
/// 바뀌거나 해제된 뒤 도착한 이전 응답은 버린다. 데이터 소스는 이 객체가 소유한다.
class MarketChartProvider extends ChangeNotifier {
  MarketChartProvider({
    required String requestKey,
    required bool crypto,
    required ChartDataSource dataSource,
    required ChartPeriod period,
    ChartSnapshotStore? snapshots,
  }) : _requestKey = requestKey,
       _crypto = crypto,
       _dataSource = dataSource,
       _period = period,
       _snapshots = snapshots ?? ChartSnapshotStore();

  final ChartSnapshotStore _snapshots;
  String _requestKey;
  bool _crypto;
  ChartDataSource _dataSource;
  ChartPeriod _period;
  int _generation = 0;
  bool _disposed = false;

  ChartLoadState _state = ChartLoadState.initial;
  ChartLoadState get state => _state;

  ChartPeriod get period => _period;

  /// 다른 통화쌍으로 바꾼다. 이전 데이터 소스는 해제하고 상태를 비운다.
  void changeRequest({
    required String requestKey,
    required bool crypto,
    required ChartDataSource dataSource,
  }) {
    _dataSource.dispose();
    _requestKey = requestKey;
    _crypto = crypto;
    _dataSource = dataSource;
    _reset();
  }

  /// 다른 기간으로 바꾼다. 상태를 비우고 다음 조회를 기다린다.
  void changePeriod(ChartPeriod period) {
    if (period == _period) return;
    _period = period;
    _reset();
  }

  void _reset() {
    _generation++;
    _emit(ChartLoadState.initial);
  }

  /// 아직 값을 받지 않았고 조회 중도 아니면 조회한다.
  Future<void> loadIfNeeded() async {
    if (_state.hasLoaded || _state.isLoading) return;
    await reload();
  }

  /// 새로 조회한다(새로고침, 다시 시도). 조회 중이면 무시한다.
  Future<void> reload() async {
    if (_disposed || _state.isLoading) return;
    _emit(_state.copyWith(isLoading: true, failed: false));

    final generation = ++_generation;
    final period = _period;
    final crypto = _crypto;
    final snapshotKey = '$_requestKey/${period.name}';
    try {
      if (_state.history.isEmpty &&
          ChartPeriodPolicy.supports(period, crypto: crypto)) {
        final cached = await _snapshots.read(snapshotKey, crypto: crypto);
        if (!_isCurrent(generation)) return;
        if (cached != null) {
          _emit(
            ChartLoadState(
              isLoading: true,
              hasLoaded: true,
              stale: true,
              data: cached,
            ),
          );
        }
      }
      final data = await _dataSource.load(period);
      if (!_isCurrent(generation)) return;
      _emit(ChartLoadState(hasLoaded: true, stale: data.stale, data: data));
      unawaited(_snapshots.write(snapshotKey, data));
    } catch (_) {
      if (!_isCurrent(generation)) return;
      // 실패해도 마지막 성공값과 원래 조회 시각은 그대로 두고 오래된 값으로 표시한다.
      final hasHistory = _state.history.isNotEmpty;
      _emit(
        _state.copyWith(
          isLoading: false,
          failed: true,
          hasLoaded: hasHistory,
          stale: hasHistory,
        ),
      );
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _emit(ChartLoadState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _dataSource.dispose();
    super.dispose();
  }
}
