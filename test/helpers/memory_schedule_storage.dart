import 'dart:async';

import 'package:tripbler/models/schedule/schedule_data.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/services/schedule/schedule_storage_service.dart';

/// 메모리에 두는 일정 저장소 대역. 실패와 지연을 테스트가 정한다.
class MemoryScheduleStorage extends ScheduleStorageService {
  MemoryScheduleStorage([
    List<ScheduleItem> items = const [],
    List<ArchivedScheduleItem> archived = const [],
  ]) : stored = [...items],
       archived = [...archived];

  /// 타임라인 순서 그대로의 일정.
  List<ScheduleItem> stored;

  /// 보관함.
  List<ArchivedScheduleItem> archived;
  bool failLoad = false;
  bool failSave = false;
  int saveCount = 0;

  /// 정하면 저장이 이 Completer가 끝날 때까지 기다린다.
  Completer<void>? holdSave;

  @override
  Future<ScheduleData> load() async {
    if (failLoad) throw const ScheduleStorageException('load');
    return ScheduleData(items: [...stored], archived: [...archived]);
  }

  @override
  Future<void> save(ScheduleData data) async {
    saveCount++;
    final hold = holdSave;
    if (hold != null) await hold.future;
    if (failSave) throw const ScheduleStorageException('save');
    stored = [...data.items];
    archived = [...data.archived];
  }
}

ScheduleItem scheduleItem(
  String id, {
  required DateTime startsAt,
  String? title,
  ScheduledPlace? place,
  ScheduleAlarm alarm = ScheduleAlarm.none,
  String memo = '',
  DateTime? createdAt,
}) {
  return ScheduleItem(
    id: id,
    title: title ?? '일정 $id',
    startsAt: startsAt,
    place: place,
    alarm: alarm,
    memo: memo,
    createdAt: createdAt ?? DateTime(2026, 11, 1),
  );
}
