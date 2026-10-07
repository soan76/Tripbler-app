import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 마지막 성공 응답을 보관한다. 저장 실패가 네트워크 성공을 실패로 바꾸지 않는다.
class MarketSnapshotStore {
  static const _prefix = 'market.snapshot.v1.';
  static Future<void> _writes = Future.value();

  Future<Map<String, dynamic>?> read(String key, Duration maximumAge) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = DateTime.parse(json['fetchedAt'] as String);
      final age = DateTime.now().difference(fetchedAt);
      if (age > maximumAge || age.isNegative) return null;
      return json;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> json) {
    final encoded = jsonEncode(json);
    final next = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('$_prefix$key', encoded);
        final keys = prefs
            .getKeys()
            .where((key) => key.startsWith(_prefix))
            .toList();
        if (keys.length <= 64) return;
        keys.sort(
          (a, b) =>
              _time(prefs.getString(a)).compareTo(_time(prefs.getString(b))),
        );
        for (final expired in keys.take(keys.length - 64)) {
          await prefs.remove(expired);
        }
      } catch (_) {
        /* 캐시 저장 실패에도 화면의 최신 값 유지. */
      }
    });
    _writes = next;
    return next;
  }

  String _time(String? raw) {
    try {
      return (jsonDecode(raw!) as Map)['fetchedAt'] as String;
    } catch (_) {
      return '';
    }
  }
}
