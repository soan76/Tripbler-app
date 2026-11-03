import 'package:shared_preferences/shared_preferences.dart';

/// 통화를 맞바꾼 차트 카드 ID를 저장해 앱을 다시 켜도 방향을 유지한다.
class ChartSwapStore {
  static const _key = 'chart.swapped.v1';
  // 뒤집기·통화 변경·정리가 같은 목록을 고치므로 읽기-수정-쓰기를 순서대로 처리한다.
  // 쓰기가 모두 끝나면 null로 비워, 끝난 Future를 다른 Zone(테스트마다 새로
  // 만들어짐)에서 이어 붙여 멈추는 일이 없게 한다.
  static Future<void>? _writes;

  Future<Set<String>> read() async {
    try {
      await _writes;
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> write(String id, {required bool swapped}) =>
      _update((ids) => swapped ? ids.add(id) : ids.remove(id));

  /// [current]에 없는 ID(지운 카드, 바꾸기 전 통화쌍, 앱 업데이트 전의 옛 저장값)를
  /// 종류(`fiat:`/`crypto:`)와 상관없이 지운다. 국가 통화와 코인 카드가 한
  /// 캐러셀에 섞이고, 이 저장소를 쓰는 캐러셀도 하나뿐이기 때문이다.
  /// [current]가 비어 있으면(목록을 아직 못 받은 상태일 수 있음) 지우지 않는다.
  Future<void> retain(Iterable<String> current) {
    final keep = current.toSet();
    if (keep.isEmpty) return Future.value();
    return _update((ids) {
      final next = retained(ids, keep);
      if (next.length == ids.length) return false;
      ids.retainAll(next);
      return true;
    });
  }

  /// [retain]과 같은 규칙으로 메모리의 ID 목록을 정리한다.
  static Set<String> retained(Set<String> ids, Iterable<String> current) {
    final keep = current.toSet();
    if (keep.isEmpty) return ids;
    return ids.intersection(keep);
  }

  // [change]가 false를 돌려주면 바뀐 것이 없으므로 쓰지 않는다.
  Future<void> _update(bool Function(Set<String> ids) change) {
    final next = (_writes ?? Future<void>.value()).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ids = (prefs.getStringList(_key) ?? const []).toSet();
        if (!change(ids)) return;
        await prefs.setStringList(_key, ids.toList());
      } catch (_) {
        /* 저장 실패에도 화면의 현재 방향은 유지한다. */
      }
    });
    _writes = next;
    return next.whenComplete(() {
      if (identical(_writes, next)) _writes = null;
    });
  }
}
