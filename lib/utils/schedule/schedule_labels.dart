import '../../models/schedule/schedule_item.dart';

/// 일정 화면의 날짜·시간·장소 글자(docs/mockups/schedule.md 2절).
class ScheduleLabels {
  const ScheduleLabels._();

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 요일 한 글자. 예: "토".
  static String weekday(DateTime date) => _weekdays[date.weekday - 1];

  /// 예: "11월 28일 (토)", 오늘이면 "11월 28일 (토) · 오늘".
  static String date(DateTime date, {DateTime? today}) {
    final base = '${date.month}월 ${date.day}일 (${weekday(date)})';
    return today != null && isSameDay(date, today) ? '$base · 오늘' : base;
  }

  /// 예: (0, 5) → "오전 12:05", (9, 0) → "오전 9:00", (12, 30) → "오후 12:30",
  /// (15, 59) → "오후 3:59".
  static String time(int hour, int minute) =>
      '${meridiem(hour)} ${hour12(hour)}:${minute.toString().padLeft(2, '0')}';

  /// "오전" 또는 "오후".
  static String meridiem(int hour) => hour < 12 ? '오전' : '오후';

  /// 12시간제 시(1~12).
  static int hour12(int hour) => hour % 12 == 0 ? 12 : hour % 12;

  /// 타임라인 위 작은 줄. 날짜가 바뀌는 첫 일정만 날짜를 붙인다.
  /// 예: "11월 28일 (토) · 오전 8:00", "오후 2:30".
  static String timelineWhen(DateTime startsAt, {required bool withDate}) {
    final clock = time(startsAt.hour, startsAt.minute);
    return withDate ? '${date(startsAt)} · $clock' : clock;
  }

  /// 날짜와 시각. 예: "11월 28일 (토) · 오전 8:00".
  static String dateTime(DateTime startsAt) =>
      '${date(startsAt)} · ${time(startsAt.hour, startsAt.minute)}';

  /// 예: "35.7148, 139.7967". 좌표가 없으면 null.
  static String? coordinates(ScheduledPlace place) {
    final lat = place.latitude, lng = place.longitude;
    if (lat == null || lng == null) return null;
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }
}
