import 'dart:convert';

import '../../models/schedule/schedule_data.dart';
import '../../models/schedule/schedule_item.dart';

/// 일정 저장값의 JSON 형식(docs/mockups/schedule.md 4절).
///
/// - 버전 2(지금): `{"version": 2, "items": [...타임라인 순서], "archived": [...]}`.
/// - 버전 1(예전): `{"version": 1, "items": [...]}`. 날짜·시간 순으로 저장했으므로 그 순서로
///   읽고 보관함은 비어 있다. 다음 저장에서 버전 2로 바뀐다(옮겨 오기라 잃는 값은 없다).
/// - 더 높은 버전은 이 앱이 읽지 못하는 새 형식으로 본다.
///
/// 저장값과 백업 원문을 같은 규칙으로 읽는다.
class SchedulePayload {
  const SchedulePayload._();

  static const int formatVersion = 2;
  static const int legacyVersion = 1;

  static String encode(ScheduleData data) => jsonEncode({
    'version': formatVersion,
    'items': [for (final item in data.items) item.toJson()],
    'archived': [for (final entry in data.archived) entry.toJson()],
  });

  /// [raw]를 읽는다. 형식이 틀린 항목은 버리고 나머지는 살린다. 일정 id는 타임라인과
  /// 보관함을 통틀어 하나만 둔다(앞의 것을 살린다).
  static ScheduleReadResult decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const ScheduleReadResult(
        status: ScheduleReadStatus.corrupt,
        changed: true,
      );
    }
    if (decoded is! Map) {
      return const ScheduleReadResult(
        status: ScheduleReadStatus.corrupt,
        changed: true,
      );
    }
    final version = decoded['version'];
    if (version is int && version > formatVersion) {
      return const ScheduleReadResult(
        status: ScheduleReadStatus.newerVersion,
        changed: true,
      );
    }
    final rawItems = decoded['items'];
    final rawArchived = version == formatVersion
        ? (decoded['archived'] ?? const [])
        : const [];
    if ((version != formatVersion && version != legacyVersion) ||
        rawItems is! List ||
        rawArchived is! List) {
      return const ScheduleReadResult(
        status: ScheduleReadStatus.corrupt,
        changed: true,
      );
    }

    final seen = <String>{};
    var unreadable = 0;
    var changed = false;
    final items = <ScheduleItem>[];
    for (final json in rawItems) {
      final item = ScheduleItem.tryParse(json);
      if (item != null && seen.add(item.id)) {
        items.add(item);
        if (!item.matchesJson(json as Map)) changed = true;
      } else {
        unreadable++;
      }
    }
    final archived = <ArchivedScheduleItem>[];
    for (final json in rawArchived) {
      final entry = ArchivedScheduleItem.tryParse(json);
      if (entry != null && seen.add(entry.item.id)) {
        archived.add(entry);
        if (!entry.matchesJson(json as Map)) changed = true;
      } else {
        unreadable++;
      }
    }
    if (version == legacyVersion) items.sort(ScheduleItem.compare);
    return ScheduleReadResult(
      status: ScheduleReadStatus.ok,
      data: ScheduleData(items: items, archived: archived),
      unreadable: unreadable,
      changed: changed || unreadable > 0,
    );
  }
}
