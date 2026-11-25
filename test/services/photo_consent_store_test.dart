import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/services/photo_consent_store.dart';

/// 메모리 대역 보안 저장소. [throwOnRead]면 복호화 실패를 흉내 낸다.
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  bool throwOnRead = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnRead) throw StateError('decrypt failed');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  late _FakeSecureStorage secure;
  var counter = 0;

  PhotoConsentStore build() => PhotoConsentStore(
    secureStorage: secure,
    prefs: SharedPreferences.getInstance,
    now: () => DateTime.utc(2026, 11, 26),
    newMarker: () => 'marker-${counter++}',
  );

  Future<void> seedPrefs(Object value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('photo.consent.v1', value as String);
  }

  String record({int version = 1, String marker = 'm1'}) => jsonEncode({
    'version': version,
    'acceptedAt': '2026-11-26T00:00:00.000Z',
    'marker': marker,
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = _FakeSecureStorage();
    counter = 0;
  });

  test('noRecord_false', () async {
    expect(await build().hasValidConsent(), isFalse);
  });

  test('afterAccept_true', () async {
    final store = build();
    await store.accept();
    expect(await store.hasValidConsent(), isTrue);
  });

  test('olderVersion_false', () async {
    await seedPrefs(record(version: 0));
    secure.values['photo.consent.marker'] = 'm1';
    expect(await build().hasValidConsent(), isFalse);
  });

  test('restoredPrefsWithoutMarker_false', () async {
    await seedPrefs(record());
    expect(await build().hasValidConsent(), isFalse);
  });

  test('markerMismatch_false', () async {
    await seedPrefs(record(marker: 'm1'));
    secure.values['photo.consent.marker'] = 'other';
    expect(await build().hasValidConsent(), isFalse);
  });

  test('secureStorageThrows_false', () async {
    await seedPrefs(record());
    secure.values['photo.consent.marker'] = 'm1';
    secure.throwOnRead = true;
    expect(await build().hasValidConsent(), isFalse);
  });

  test('brokenJson_false', () async {
    await seedPrefs('{not json');
    secure.values['photo.consent.marker'] = 'm1';
    expect(await build().hasValidConsent(), isFalse);
  });

  test('acceptTwice_keepsSameMarker', () async {
    final store = build();
    await store.accept();
    final first = secure.values['photo.consent.marker'];
    await store.accept();
    expect(secure.values['photo.consent.marker'], first);
    expect(await store.hasValidConsent(), isTrue);
  });
}
