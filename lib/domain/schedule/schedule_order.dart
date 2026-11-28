import '../../models/schedule/schedule_item.dart';

/// 타임라인 순서 규칙(docs/mockups/schedule.md 2-2절 "순서 바꾸기").
///
/// 순서는 날짜·시간과 따로 저장한다. 새로 넣는 일정은 지금 순서에서 처음으로 더 늦은 일정
/// 앞에 넣고, 그런 일정이 없으면 맨 끝에 붙인다.
class ScheduleOrder {
  const ScheduleOrder._();

  /// [item]을 [items]의 규칙대로 넣은 새 목록.
  static List<ScheduleItem> insert(
    List<ScheduleItem> items,
    ScheduleItem item,
  ) {
    final index = items.indexWhere((i) => i.startsAt.isAfter(item.startsAt));
    return [...items]..insert(index < 0 ? items.length : index, item);
  }

  /// [id] 일정을 [item]으로 바꾼다. 날짜·시간이 바뀌었으면 빼고 규칙대로 다시 넣고, 아니면
  /// 자리를 그대로 둔다. 그 id가 없으면 null.
  static List<ScheduleItem>? replace(
    List<ScheduleItem> items,
    ScheduleItem item,
  ) {
    final index = items.indexWhere((i) => i.id == item.id);
    if (index < 0) return null;
    if (items[index].startsAt == item.startsAt) {
      return [...items]..[index] = item;
    }
    return insert([...items]..removeAt(index), item);
  }

  /// [id] 일정을 [to] 자리(옮긴 뒤 목록 기준 0부터)로 옮긴다. 범위를 벗어나면 끝으로 맞춘다.
  /// 그 id가 없으면 null.
  static List<ScheduleItem>? move(List<ScheduleItem> items, String id, int to) {
    final from = items.indexWhere((i) => i.id == id);
    if (from < 0) return null;
    final next = [...items];
    final item = next.removeAt(from);
    next.insert(to.clamp(0, next.length), item);
    return next;
  }
}
