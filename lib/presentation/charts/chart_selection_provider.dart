import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/currency_model.dart';
import '../exchange/display_currency.dart';
import 'chart_pair.dart';

/// 차트 통화쌍 변경([ChartSelectionNotifier.replace], [ChartSelectionNotifier.replaceSide])의 결과.
enum ChartPairChange {
  changed,
  unchanged,

  /// 다른 카드에 같은 차트(방향만 다른 쌍 포함)가 있어 바꾸지 않았다.
  duplicate,

  /// 고른 차트가 다른 카드에 있어 두 카드의 위치를 서로 바꿨다.
  swappedPositions,

  /// 선택창이 열린 사이 카드가 지워지거나 바뀌어 반영하지 않았다.
  stale,

  /// 만들 수 없는 조합이라 바꾸지 않았다.
  invalid,

  /// 저장된 선택을 읽기 전이라 무시했다.
  notLoaded,
}

/// 차트 카드들의 통화쌍과 저장된 선택을 읽었는지.
class ChartSelectionState {
  ChartSelectionState({
    List<ChartPair> pairs = ChartSelectionNotifier.defaults,
    this.loaded = false,
    this.lastSideEdit,
  }) : pairs = List.unmodifiable(pairs);

  /// 카드 순서대로의 통화쌍. 같은 차트(방향만 다른 쌍 포함)는 두 번 들어가지 않는다.
  final List<ChartPair> pairs;

  /// 저장된 선택을 읽었는지. 읽기 전에는 카드를 그리지 않아 기본값으로 먼저
  /// 조회했다가 바뀌는 일이 없게 한다.
  final bool loaded;

  /// 마지막 [ChartSelectionNotifier.replaceSide]로 자리를 차지한 카드([to])와 그
  /// 카드를 보여 줄 방향. [exchanged]이면 [from] 카드와 위치를 바꿔 옮겨 온 카드다.
  /// 카드 목록이 다른 경로로 바뀌면 비운다.
  final ({String from, String to, bool swapped, bool exchanged})? lastSideEdit;

  bool get canAdd => pairs.length < ChartSelectionNotifier.maxCards;
  bool get canRemove => pairs.length > 1;

  ChartSelectionState copyWith({
    List<ChartPair>? pairs,
    bool? loaded,
    ({String from, String to, bool swapped, bool exchanged})? lastSideEdit,
    bool clearLastSideEdit = false,
  }) {
    return ChartSelectionState(
      pairs: pairs ?? this.pairs,
      loaded: loaded ?? this.loaded,
      lastSideEdit: clearLastSideEdit
          ? null
          : (lastSideEdit ?? this.lastSideEdit),
    );
  }
}

/// 차트 카드들의 통화쌍. 위쪽 환율 계산용 통화 선택과 따로 관리하며,
/// 어느 쪽을 바꿔도 다른 쪽에는 영향을 주지 않는다. 앱을 다시 켜도 유지한다.
class ChartSelectionNotifier extends Notifier<ChartSelectionState> {
  static const storageKey = 'chart.pairs.v1';
  static const maxCards = 5;
  static const defaults = [
    ChartPair.fiat('USD', 'KRW'),
    ChartPair.fiat('JPY', 'KRW'),
    ChartPair.crypto('BTC'),
  ];

  Future<void>? _initialization;

  // 이미 알려 준 [ChartSelectionState.lastSideEdit]. 위젯 build 중에 불리는 조회는
  // 상태를 바꿀 수 없으므로, 비우는 대신 어떤 변경을 썼는지 기억해 다시 쓰지 않게 한다.
  bool _sideEditConsumed = false;

  @override
  ChartSelectionState build() => ChartSelectionState();

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    var pairs = state.pairs;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      final saved = prefs.getStringList(storageKey);
      if (saved != null) {
        final restored = <ChartPair>[];
        for (final id in saved) {
          final pair = ChartPair.tryParse(id);
          if (pair != null && !restored.any(pair.isSameChart)) {
            restored.add(pair);
          }
          if (restored.length == maxCards) break;
        }
        if (restored.isNotEmpty) pairs = restored;
      }
    } catch (_) {
      /* 읽지 못하면 기본 카드로 시작한다. */
    }
    if (!ref.mounted) return;
    state = state.copyWith(pairs: pairs, loaded: true);
  }

  /// [index] 카드의 통화쌍을 [next]로 바꾼다. 다른 카드에 같은 차트(방향만 다른
  /// 쌍 포함)가 있으면 바꾸지 않는다. 저장된 선택을 읽기 전에는 무시한다.
  ChartPairChange replace(int index, ChartPair next) => _replace(index, next);

  ChartPairChange _replace(
    int index,
    ChartPair next, {
    ({String from, String to, bool swapped, bool exchanged})? sideEdit,
  }) {
    final pairs = state.pairs;
    if (!state.loaded) return ChartPairChange.notLoaded;
    if (index < 0 || index >= pairs.length) return ChartPairChange.stale;
    if (pairs[index] == next) return ChartPairChange.unchanged;
    for (var i = 0; i < pairs.length; i++) {
      if (i != index && pairs[i].isSameChart(next)) {
        return ChartPairChange.duplicate;
      }
    }
    _commit([...pairs]..[index] = next, sideEdit: sideEdit);
    return ChartPairChange.changed;
  }

  /// 선택창에서 고른 [currency]로 [index] 카드의 한쪽 통화를 바꾼다.
  /// [base]는 원래 방향 기준의 쪽, [swapped]는 고를 때 카드가 뒤집혀 보였는지다.
  /// 선택창이 열린 사이 카드가 [expected]에서 바뀌었거나 지워졌으면 반영하지 않는다.
  /// 바뀐 카드를 보여 줄 방향은 [swappedAfterReplace]로 알려 준다.
  /// 고른 결과와 같은 차트(방향만 다른 쌍 포함)가 다른 카드에 있으면 새로 만들지
  /// 않고 두 카드의 위치를 서로 바꾼다. 옮겨 온 카드는 고른 통화가 누른 쪽에 보이는
  /// 방향으로 표시하고([swappedAfterExchange]), 밀려난 카드는 자기 방향을 유지한다.
  ChartPairChange replaceSide(
    int index, {
    required ChartPair expected,
    required bool base,
    required bool swapped,
    required DisplayCurrency currency,
  }) {
    final pairs = state.pairs;
    if (!state.loaded) return ChartPairChange.notLoaded;
    if (index < 0 || index >= pairs.length || pairs[index] != expected) {
      return ChartPairChange.stale;
    }
    final next = expected.replaceShown(
      base: base,
      swapped: swapped,
      currency: currency,
    );
    if (next == null) return ChartPairChange.invalid;
    for (var other = 0; other < pairs.length; other++) {
      if (other != index && pairs[other].isSameChart(next.pair)) {
        final moved = pairs[other];
        // 있던 카드가 계산한 쌍과 반대 방향으로 저장돼 있으면 뒤집어 보여야 같은 배치다.
        _commit(
          [...pairs]
            ..[index] = moved
            ..[other] = expected,
          sideEdit: (
            from: expected.id,
            to: moved.id,
            swapped: moved == next.pair ? next.swapped : !next.swapped,
            exchanged: true,
          ),
        );
        return ChartPairChange.swappedPositions;
      }
    }
    return _replace(
      index,
      next.pair,
      sideEdit: (
        from: expected.id,
        to: next.pair.id,
        swapped: next.swapped,
        exchanged: false,
      ),
    );
  }

  /// 같은 자리 카드가 [fromId]에서 [toId]로 바뀌었을 때 새 카드의 표시 방향.
  /// 마지막 [replaceSide]의 변경이 아니면 null(새 카드는 정방향)이다. 같은 변경이
  /// 다시 쓰이지 않도록 한 번 물으면 결과와 상관없이 쓴 것으로 친다.
  bool? swappedAfterReplace(String fromId, String toId) {
    final edit = _takeSideEdit();
    if (edit == null || edit.exchanged) return null;
    if (edit.from != fromId || edit.to != toId) return null;
    return edit.swapped;
  }

  /// [firstId]와 [secondId] 두 카드의 위치가 서로 바뀌었을 때 고른 자리로 옮겨 온
  /// 카드의 ID와 표시 방향. 두 ID의 순서는 상관없다. 마지막 [replaceSide]의 위치
  /// 교환이 아니면 null(두 카드 모두 방향 유지)이다. 한 번 물으면 결과와 상관없이
  /// 쓴 것으로 친다.
  ({String id, bool swapped})? swappedAfterExchange(
    String firstId,
    String secondId,
  ) {
    final edit = _takeSideEdit();
    if (edit == null || !edit.exchanged) return null;
    final sameCards =
        (edit.from == firstId && edit.to == secondId) ||
        (edit.from == secondId && edit.to == firstId);
    return sameCards ? (id: edit.to, swapped: edit.swapped) : null;
  }

  ({String from, String to, bool swapped, bool exchanged})? _takeSideEdit() {
    final edit = state.lastSideEdit;
    if (edit == null || _sideEditConsumed) return null;
    _sideEditConsumed = true;
    return edit;
  }

  /// 카드를 끝에 하나 더한다. 아직 없는 `통화/KRW` 쌍으로 시작하며, 추가한 쌍을 돌려준다.
  /// 방향만 다른 쌍(예: KRW/USD가 있을 때 USD/KRW)도 이미 있는 것으로 본다.
  ChartPair? add() {
    if (!state.loaded || !state.canAdd) return null;
    final pairs = state.pairs;
    final candidates = [
      ...defaults,
      for (final currency in supportedCurrencies)
        if (currency.code != ChartPair.cryptoQuote)
          ChartPair.fiat(currency.code, ChartPair.cryptoQuote),
    ];
    final next = candidates.firstWhere((pair) => !pairs.any(pair.isSameChart));
    _commit([...pairs, next]);
    return next;
  }

  /// [index] 카드를 지운다. 마지막 한 장은 지우지 않는다. 읽기 전에는 무시한다.
  void remove(int index) {
    final pairs = state.pairs;
    if (!state.loaded ||
        !state.canRemove ||
        index < 0 ||
        index >= pairs.length) {
      return;
    }
    _commit([...pairs]..removeAt(index));
  }

  // [sideEdit]이 없으면 옛 [replaceSide] 결과를 비워, 다른 경로(추가·삭제·[replace])의
  // 변경에 쓰이지 않게 한다.
  void _commit(
    List<ChartPair> pairs, {
    ({String from, String to, bool swapped, bool exchanged})? sideEdit,
  }) {
    _sideEditConsumed = false;
    state = state.copyWith(
      pairs: pairs,
      lastSideEdit: sideEdit,
      clearLastSideEdit: sideEdit == null,
    );
    unawaited(_save(pairs));
  }

  // SharedPreferences는 메모리 값을 바로 바꾸므로 호출 순서대로 마지막 값이 남는다.
  Future<void> _save(List<ChartPair> pairs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(storageKey, [for (final p in pairs) p.id]);
    } catch (_) {
      /* 저장에 실패해도 화면의 현재 선택은 유지한다. */
    }
  }
}

final chartSelectionProvider =
    NotifierProvider<ChartSelectionNotifier, ChartSelectionState>(
      ChartSelectionNotifier.new,
    );
