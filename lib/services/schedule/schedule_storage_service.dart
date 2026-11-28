import 'package:shared_preferences/shared_preferences.dart';

import '../../models/schedule/schedule_data.dart';
import 'schedule_backup_store.dart';
import 'schedule_payload.dart';
import 'schedule_storage_exception.dart';

export 'schedule_storage_exception.dart';

/// 일정(타임라인 순서와 보관함)을 기기(shared_preferences)에 저장한다(docs/mockups/schedule.md 4절).
///
/// 한 키에 [SchedulePayload] 형식으로 둔다. 읽을 때 형식이 틀린 항목은 버리고 나머지는 살린다.
/// 해석하지 못했거나 읽으며 바뀐 값이 있으면 다음 저장이 덮어쓰기 전에 원래 저장값을
/// [ScheduleBackupStore]에 "읽지 못해 보관"으로 남긴다. 제목·메모는 개인정보이므로 로그에
/// 남기지 않는다.
class ScheduleStorageService {
  ScheduleStorageService({
    Future<SharedPreferences> Function()? prefs,
    ScheduleBackupStore? backups,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _backups = backups ?? ScheduleBackupStore(prefs: prefs);

  static const String storageKey = 'schedule.items.v1';

  /// 이번 브랜치 개발 중에 쓰던 단일 백업 키. 지금은 쓰지 않고, 남아 있어도 건드리지 않는다.
  static const String backupKey = 'schedule.items.v1.backup';

  final Future<SharedPreferences> Function() _prefs;
  final ScheduleBackupStore _backups;

  /// 저장된 일정. 저장값이 없으면 빈 값. 손상·새 버전이면 원래 값을 보관한 뒤 빈 값, 일부만
  /// 틀리거나 살린 값이 바뀌면 보관한 뒤 살린 값을 돌려준다.
  ///
  /// 저장소를 열지 못하거나 보관하지 못하면 [ScheduleStorageException]을 던진다. 이때 빈
  /// 값으로 보고 새로 저장하면 기존 일정을 덮어쓰므로 구분한다.
  Future<ScheduleData> load() async {
    final String? raw;
    try {
      raw = (await _prefs()).getString(storageKey);
    } catch (_) {
      throw const ScheduleStorageException('일정 저장소를 열지 못했습니다.');
    }
    if (raw == null) return ScheduleData.empty;

    final result = SchedulePayload.decode(raw);
    if (result.changed) {
      try {
        await _backups.addAuto(raw);
      } on ScheduleStorageException {
        throw const ScheduleStorageException('손상된 일정을 보관하지 못했습니다.');
      }
    }
    return result.data;
  }

  /// 일정 전체를 저장한다. 실패하면 [ScheduleStorageException]을 던진다.
  Future<void> save(ScheduleData data) async {
    final raw = SchedulePayload.encode(data);
    final bool saved;
    try {
      saved = await (await _prefs()).setString(storageKey, raw);
    } catch (_) {
      throw const ScheduleStorageException('일정을 저장하지 못했습니다.');
    }
    if (!saved) {
      throw const ScheduleStorageException('일정을 저장하지 못했습니다.');
    }
  }
}
