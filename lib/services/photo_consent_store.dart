import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사진 전송 동의를 저장한다.
///
/// 동의 기록(버전·시각·표식)은 shared_preferences에 두고, 같은 표식을 보안 저장소에도
/// 둔다. 자동 백업으로 prefs만 새 기기에 복원되면 보안 저장소의 표식이 없거나
/// 읽히지 않으므로 그 동의는 인정하지 않는다. 읽기 실패는 모두 동의 없음으로 본다.
class PhotoConsentStore {
  PhotoConsentStore({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
    String Function()? newMarker,
  }) : _secure =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(),
             // 새 기기로 옮겨지지 않는 접근성 옵션
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _prefs = prefs ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now,
       _newMarker = newMarker ?? _randomMarker;

  /// 안내 문구가 바뀌면 올린다. 저장된 버전이 더 낮으면 다시 동의를 받는다.
  static const int currentVersion = 1;

  static const String _prefsKey = 'photo.consent.v1';
  static const String _markerKey = 'photo.consent.marker';

  final FlutterSecureStorage _secure;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;
  final String Function() _newMarker;

  static String _randomMarker() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 현재 안내 버전에 대한 동의가 이 설치본에서 이루어졌을 때만 true.
  Future<bool> hasValidConsent() async {
    try {
      final raw = (await _prefs()).getString(_prefsKey);
      if (raw == null) return false;
      final json = jsonDecode(raw);
      if (json is! Map) return false;
      final version = json['version'];
      final marker = json['marker'];
      if (version is! int || version < currentVersion) return false;
      if (marker is! String || marker.isEmpty) return false;
      final stored = await _secure.read(key: _markerKey);
      return stored != null && stored == marker;
    } catch (_) {
      return false;
    }
  }

  /// 동의를 기록한다. 표식이 없거나 읽지 못하면 새로 만든다.
  Future<void> accept() async {
    String? marker;
    try {
      marker = await _secure.read(key: _markerKey);
    } catch (_) {
      marker = null;
    }
    if (marker == null || marker.isEmpty) {
      marker = _newMarker();
      await _secure.write(key: _markerKey, value: marker);
    }
    final prefs = await _prefs();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'version': currentVersion,
        'acceptedAt': _now().toUtc().toIso8601String(),
        'marker': marker,
      }),
    );
  }
}
