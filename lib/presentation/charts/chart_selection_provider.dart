import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/currency_model.dart';
import '../exchange/display_currency.dart';
import 'chart_pair.dart';

/// 차트 통화쌍 변경([ChartSelectionProvider.replace], [ChartSelectionProvider.replaceSide])의 결과.
enum ChartPairChange {
  changed,
  unchanged,

  /// 다른 카드에 같은 차트(방향만 다른 쌍 포함)가 있어 바꾸지 않았다.
  duplicate,

  /// 선택창이 열린 사이 카드가 지워지거나 바뀌어 반영하지 않았다.
  stale,

  /// 만들 수 없는 조합이라 바꾸지 않았다.
  invalid,

  /// 저장된 선택을 읽기 전이라 무시했다.
  notLoaded,
}

/// 차트 카드들의 통화쌍. 위쪽 환율 계산용 통화 선택과 따로 관리하며,
/// 어느 쪽을 바꿔도 다른 쪽에는 영향을 주지 않는다. 앱을 다시 켜도 유지한다.
class ChartSelectionProvider extends ChangeNotifier {
  static const storageKey = 'chart.pairs.v1';
  static const maxCards = 5;
  static const defaults = [
    ChartPair.fiat('USD', 'KRW'),
    ChartPair.fiat('JPY', 'KRW'),
    ChartPair.crypto('BTC'),
  ];

  List<ChartPair> _pairs = defaults;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _initialization;

  // 마지막 [replaceSide]로 바뀐 카드와 그 카드를 보여 줄 방향. 한 번 알려 주거나
  // 카드 목록이 다른 경로로 바뀌면 비운다.
  ({String from, String to, bool swapped})? _lastSideEdit;

  /// 카드 순서대로의 통화쌍. 같은 차트(방향만 다른 쌍 포함)는 두 번 들어가지 않는다.
  List<ChartPair> get pairs => List.unmodifiable(_pairs);

  /// 저장된 선택을 읽었는지. 읽기 전에는 카드를 그리지 않아 기본값으로 먼저
  /// 조회했다가 바뀌는 일이 없게 한다.
  bool get loaded => _loaded;
  bool get canAdd => _pairs.length < maxCards;
  bool get canRemove => _pairs.length > 1;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(storageKey);
      if (saved != null) {
        final pairs = <ChartPair>[];
        for (final id in saved) {
          final pair = ChartPair.tryParse(id);
          if (pair != null && !pairs.any(pair.isSameChart)) pairs.add(pair);
          if (pairs.length == maxCards) break;
        }
        if (pairs.isNotEmpty) _pairs = pairs;
      }
    } catch (_) {
      /* 읽지 못하면 기본 카드로 시작한다. */
    }
    _loaded = true;
    _notify();
  }

  /// [index] 카드의 통화쌍을 [next]로 바꾼다. 다른 카드에 같은 차트(방향만 다른
  /// 쌍 포함)가 있으면 바꾸지 않는다. 저장된 선택을 읽기 전에는 무시한다.
  ChartPairChange replace(int index, ChartPair next) {
    if (!_loaded) return ChartPairChange.notLoaded;
    if (index < 0 || index >= _pairs.length) return ChartPairChange.stale;
    if (_pairs[index] == next) return ChartPairChange.unchanged;
    for (var i = 0; i < _pairs.length; i++) {
      if (i != index && _pairs[i].isSameChart(next)) {
        return ChartPairChange.duplicate;
      }
    }
    _pairs = [..._pairs]..[index] = next;
    _changed();
    return ChartPairChange.changed;
  }

  /// 선택창에서 고른 [currency]로 [index] 카드의 한쪽 통화를 바꾼다.
  /// [base]는 원래 방향 기준의 쪽, [swapped]는 고를 때 카드가 뒤집혀 보였는지다.
  /// 선택창이 열린 사이 카드가 [expected]에서 바뀌었거나 지워졌으면 반영하지 않는다.
  /// 바뀐 카드를 보여 줄 방향은 [swappedAfterReplace]로 알려 준다.
  ChartPairChange replaceSide(
    int index, {
    required ChartPair expected,
    required bool base,
    required bool swapped,
    required DisplayCurrency currency,
  }) {
    if (!_loaded) return ChartPairChange.notLoaded;
    if (index < 0 || index >= _pairs.length || _pairs[index] != expected) {
      return ChartPairChange.stale;
    }
    final next = expected.replaceShown(
      base: base,
      swapped: swapped,
      currency: currency,
    );
    if (next == null) return ChartPairChange.invalid;
    final result = replace(index, next.pair);
    if (result == ChartPairChange.changed) {
      _lastSideEdit = (
        from: expected.id,
        to: next.pair.id,
        swapped: next.swapped,
      );
    }
    return result;
  }

  /// 같은 자리 카드가 [fromId]에서 [toId]로 바뀌었을 때 새 카드의 표시 방향.
  /// 마지막 [replaceSide]의 변경이 아니면 null(새 카드는 정방향)이다. 같은 변경이
  /// 다시 쓰이지 않도록 한 번 물으면 결과와 상관없이 비운다.
  bool? swappedAfterReplace(String fromId, String toId) {
    final edit = _lastSideEdit;
    _lastSideEdit = null;
    if (edit == null || edit.from != fromId || edit.to != toId) return null;
    return edit.swapped;
  }

  /// 카드를 끝에 하나 더한다. 아직 없는 `통화/KRW` 쌍으로 시작하며, 추가한 쌍을 돌려준다.
  /// 방향만 다른 쌍(예: KRW/USD가 있을 때 USD/KRW)도 이미 있는 것으로 본다.
  ChartPair? add() {
    if (!_loaded || !canAdd) return null;
    final candidates = [
      ...defaults,
      for (final currency in supportedCurrencies)
        if (currency.code != ChartPair.cryptoQuote)
          ChartPair.fiat(currency.code, ChartPair.cryptoQuote),
    ];
    final next = candidates.firstWhere((pair) => !_pairs.any(pair.isSameChart));
    _pairs = [..._pairs, next];
    _changed();
    return next;
  }

  /// [index] 카드를 지운다. 마지막 한 장은 지우지 않는다. 읽기 전에는 무시한다.
  void remove(int index) {
    if (!_loaded || !canRemove || index < 0 || index >= _pairs.length) return;
    _pairs = [..._pairs]..removeAt(index);
    _changed();
  }

  void _changed() {
    // 다른 경로(추가·삭제·[replace])의 변경에 옛 [replaceSide] 결과가 쓰이지 않게 한다.
    // [replaceSide]는 이 뒤에 결과를 다시 적는다.
    _lastSideEdit = null;
    _notify();
    unawaited(_save(_pairs));
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
