import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/duty_free/duty_free_item.dart';

/// 면세 저장소를 열거나 쓰지 못했다.
class DutyFreeStorageException implements Exception {
  const DutyFreeStorageException(this.message);

  final String message;

  @override
  String toString() => 'DutyFreeStorageException: $message';
}

/// 산 물건·나이·추가한 영수증을 기기(shared_preferences)에 저장한다.
///
/// 형식이 틀린 항목은 버리고 나머지는 살린다. 상품명·금액은 로그에 남기지 않는다.
class DutyFreeStorageService {
  DutyFreeStorageService({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const String storageKey = 'dutyFree.trip.v1';

  final Future<SharedPreferences> Function() _prefs;

  /// 저장값이 없거나 읽을 수 없으면 빈 여행. 저장소를 열지 못하면 [DutyFreeStorageException].
  Future<DutyFreeTrip> load() async {
    final String? raw;
    try {
      raw = (await _prefs()).getString(storageKey);
    } catch (_) {
      throw const DutyFreeStorageException('면세 저장소를 열지 못했습니다.');
    }
    if (raw == null) return DutyFreeTrip.empty;
    return decode(raw);
  }

  Future<void> save(DutyFreeTrip trip) async {
    final bool saved;
    try {
      saved = await (await _prefs()).setString(storageKey, encode(trip));
    } catch (_) {
      throw const DutyFreeStorageException('면세 기록을 저장하지 못했습니다.');
    }
    if (!saved) throw const DutyFreeStorageException('면세 기록을 저장하지 못했습니다.');
  }

  static String encode(DutyFreeTrip trip) => jsonEncode({
    'adult': trip.adult,
    'items': [for (final i in trip.items) i.toJson()],
    'receiptKeys': trip.receiptKeys.toList(),
  });

  static DutyFreeTrip decode(String raw) {
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return DutyFreeTrip.empty;
    }
    if (json is! Map) return DutyFreeTrip.empty;
    final items = json['items'];
    final keys = json['receiptKeys'];
    final seen = <String>{};
    return DutyFreeTrip(
      adult: json['adult'] != false,
      items: [
        if (items is List)
          for (final e in items)
            if (DutyFreeItem.fromJson(e) case final item?)
              if (seen.add(item.id)) item,
      ],
      receiptKeys: {
        if (keys is List)
          for (final k in keys)
            if (k is String) k,
      },
    );
  }
}
