import '../../models/schedule/schedule_data.dart';
import '../../models/schedule/schedule_item.dart';

/// 백업에서 되살릴 일정이 지금 어디에 있는지.
enum ScheduleRestoreMatch {
  /// 지금 일정·보관함 어디에도 없다(처음부터 고른다).
  none,

  /// 지금 타임라인에 이미 있다.
  inTimeline,

  /// 보관함에 있다.
  inArchive,
}

/// 백업 되살리기·삭제 안내의 판단(docs/mockups/schedule.md 4절 "복원"·"삭제 확인창").
class ScheduleBackupRules {
  const ScheduleBackupRules._();

  /// 같은 일정으로 보는지: id가 같거나, 제목과 시작 시각이 같다.
  static bool same(ScheduleItem a, ScheduleItem b) =>
      a.id == b.id || (a.title == b.title && a.startsAt == b.startsAt);

  static ScheduleRestoreMatch match(ScheduleData current, ScheduleItem item) {
    if (current.items.any((i) => same(i, item))) {
      return ScheduleRestoreMatch.inTimeline;
    }
    if (current.archived.any((a) => same(a.item, item))) {
      return ScheduleRestoreMatch.inArchive;
    }
    return ScheduleRestoreMatch.none;
  }

  /// 되살릴 [picked]를 지금 일정에 넣을 값으로 바꾼다. id가 이미 타임라인·보관함에 있으면
  /// 새 id를 붙인다(같은 id 일정이 둘이 되지 않게).
  static List<ScheduleItem> prepareRestore(
    ScheduleData current,
    List<ScheduleItem> picked, {
    required DateTime now,
  }) {
    final ids = {
      for (final i in current.items) i.id,
      for (final a in current.archived) a.item.id,
    };
    var sequence = 0;
    return [
      for (final item in picked)
        if (ids.add(item.id))
          item
        else
          ScheduleItem(
            id: '${now.microsecondsSinceEpoch}-r${sequence++}',
            title: item.title,
            startsAt: item.startsAt,
            place: item.place,
            alarm: item.alarm,
            memo: item.memo,
            createdAt: item.createdAt,
          ),
    ];
  }

  /// [removed] 백업을 지우면 더는 되살릴 수 없게 되는 일정: 지금 타임라인·보관함과 남는
  /// 백업([kept]) 어디에도 없는 것. 같은 일정은 한 번만 센다.
  static List<ScheduleItem> lostIfDeleted({
    required ScheduleData current,
    required Iterable<ScheduleData> removed,
    required Iterable<ScheduleData> kept,
  }) {
    bool inData(ScheduleData data, ScheduleItem item) =>
        data.items.any((i) => same(i, item)) ||
        data.archived.any((a) => same(a.item, item));

    final lost = <ScheduleItem>[];
    for (final data in removed) {
      for (final item in [
        ...data.items,
        for (final a in data.archived) a.item,
      ]) {
        if (inData(current, item)) continue;
        if (kept.any((k) => inData(k, item))) continue;
        if (lost.any((l) => same(l, item))) continue;
        lost.add(item);
      }
    }
    return lost;
  }
}
