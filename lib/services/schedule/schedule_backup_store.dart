import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/schedule/schedule_data.dart';
import 'schedule_storage_exception.dart';

/// 일정 기기 백업 목록(docs/mockups/schedule.md 4절 "개수"·"백업 동작").
///
/// 한 키에 `[{"id", "savedAt", "kind", "seen", "raw"}, ...]`(오래된 것부터)로 두어 한 번에
/// 쓴다. 직접 백업은 최근 [maxManual]개만 남기고, 읽지 못해 보관한 백업은 개수에 세지 않으며
/// 사용자가 지우기 전에는 지우지 않는다. 백업 원문과 일정 내용은 로그에 남기지 않는다.
///
/// 목록 저장값 자체가 깨져 읽지 못한 부분이 있으면, 다음 쓰기가 그 값을 덮어쓰기 전에 원래
/// 문자열을 [damagedKey]에 따로 남긴다(같은 문자열은 한 번만). 남기지 못하면 쓰지 않고
/// [ScheduleStorageException]을 던진다.
class ScheduleBackupStore {
  ScheduleBackupStore({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  /// 예전에는 읽지 못한 값 백업만 `{savedAt, raw}`로 두던 키다. 그 항목도 그대로 읽는다.
  static const String storageKey = 'schedule.items.v1.backups';
  static const int maxManual = 3;

  /// 깨져서 읽지 못한 목록 저장값의 원래 문자열 목록(JSON 문자열 배열).
  static const String damagedKey = 'schedule.items.v1.backups.damaged';

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;

  /// 같은 마이크로초에 만든 백업의 id가 겹치지 않게 붙인다.
  int _sequence = 0;

  /// 보관한 백업(새 것부터). 형식이 틀린 항목은 버린다.
  Future<List<ScheduleBackup>> list() async {
    final (:backups, damaged: _) = await _read();
    return backups.reversed.toList();
  }

  /// 읽지 못하거나 바꿔 읽은 저장값 [raw]를 보관한다. 같은 원문이 이미 있으면 다시 넣지 않는다.
  /// 지금 있는 백업은 지우지 않는다.
  Future<void> addAuto(String raw) async {
    final (:backups, :damaged) = await _read();
    if (backups.any((b) => b.raw == raw)) return;
    backups.add(_create(ScheduleBackupKind.auto, raw));
    await _write(backups, damaged: damaged);
  }

  /// 지금 일정 원문 [raw]로 직접 백업을 만든다. 직접 백업이 이미 [maxManual]개면 가장 오래된
  /// 직접 백업 하나만 지운다(읽지 못해 보관한 백업은 그대로).
  Future<ScheduleBackup> addManual(String raw) async {
    final (:backups, :damaged) = await _read();
    final manual = backups.where((b) => b.kind == ScheduleBackupKind.manual);
    if (manual.length >= maxManual) backups.remove(manual.first);
    final backup = _create(ScheduleBackupKind.manual, raw);
    backups.add(backup);
    await _write(backups, damaged: damaged);
    return backup;
  }

  /// [ids] 백업을 지운다.
  Future<void> delete(Set<String> ids) async {
    final (:backups, :damaged) = await _read();
    await _write(
      backups.where((b) => !ids.contains(b.id)).toList(),
      damaged: damaged,
    );
  }

  /// [ids] 백업을 확인한 것으로 기억한다(읽지 못한 일정 알림을 다시 띄우지 않는다).
  Future<void> markSeen(Set<String> ids) async {
    final (:backups, :damaged) = await _read();
    if (!backups.any((b) => ids.contains(b.id) && !b.seen)) return;
    await _write([
      for (final b in backups) ids.contains(b.id) ? b.copyWith(seen: true) : b,
    ], damaged: damaged);
  }

  ScheduleBackup _create(ScheduleBackupKind kind, String raw) {
    final savedAt = _now();
    return ScheduleBackup(
      id: '${kind.name}-${savedAt.microsecondsSinceEpoch}-${_sequence++}',
      savedAt: savedAt,
      kind: kind,
      raw: raw,
    );
  }

  /// 저장된 목록. 저장값이 깨져 읽지 못한 부분(전체, 형식이 틀린 항목, 겹친 id)이 있으면
  /// [damaged]에 원래 문자열을 돌려준다(쓰기 전에 따로 남기도록).
  Future<({List<ScheduleBackup> backups, String? damaged})> _read() async {
    final String? value;
    try {
      value = (await _prefs()).getString(storageKey);
    } catch (_) {
      throw const ScheduleStorageException('일정 백업을 읽지 못했습니다.');
    }
    if (value == null) return (backups: <ScheduleBackup>[], damaged: null);
    Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! List) return (backups: <ScheduleBackup>[], damaged: value);
    final ids = <String>{};
    final backups = [
      for (final json in decoded)
        if (ScheduleBackup.tryParse(json) case final backup?)
          if (ids.add(backup.id)) backup,
    ];
    return (
      backups: backups,
      damaged: backups.length == decoded.length ? null : value,
    );
  }

  /// [backups]를 저장한다. [damaged]가 있으면 먼저 [damagedKey]에 남기고, 남기지 못하면
  /// 목록을 쓰지 않는다(깨진 원래 값을 덮어쓰지 않게).
  Future<void> _write(List<ScheduleBackup> backups, {String? damaged}) async {
    final SharedPreferences prefs;
    try {
      prefs = await _prefs();
    } catch (_) {
      throw const ScheduleStorageException('일정 백업을 저장하지 못했습니다.');
    }
    if (damaged != null) await _keepDamaged(prefs, damaged);
    final bool saved;
    try {
      saved = await prefs.setString(
        storageKey,
        jsonEncode([for (final b in backups) b.toJson()]),
      );
    } catch (_) {
      throw const ScheduleStorageException('일정 백업을 저장하지 못했습니다.');
    }
    if (!saved) {
      throw const ScheduleStorageException('일정 백업을 저장하지 못했습니다.');
    }
  }

  static Future<void> _keepDamaged(
    SharedPreferences prefs,
    String damaged,
  ) async {
    final bool saved;
    try {
      final kept = <String>[];
      final value = prefs.getString(damagedKey);
      if (value != null) {
        Object? decoded;
        try {
          decoded = jsonDecode(value);
        } on FormatException {
          decoded = null;
        }
        final list = decoded is List ? decoded : null;
        if (list != null && list.every((e) => e is String)) {
          kept.addAll(list.cast<String>());
        } else {
          // 이 키도 깨졌으면 그 값까지 함께 남긴다.
          kept.add(value);
        }
      }
      if (kept.contains(damaged)) return;
      saved = await prefs.setString(damagedKey, jsonEncode([...kept, damaged]));
    } catch (_) {
      throw const ScheduleStorageException('깨진 일정 백업을 보관하지 못했습니다.');
    }
    if (!saved) {
      throw const ScheduleStorageException('깨진 일정 백업을 보관하지 못했습니다.');
    }
  }
}
