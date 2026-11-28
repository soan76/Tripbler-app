import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/schedule/schedule_item.dart';
import '../../providers/schedule/schedule_draft_provider.dart';
import '../../utils/schedule/schedule_labels.dart';
import 'schedule_calendar.dart';
import 'schedule_sheet_parts.dart';
import 'schedule_time_wheel.dart';

/// 입력·수정 카드의 항목 조각(docs/mockups/schedule.md 2-3·2-4절).
///
/// 값은 [ScheduleDraft]에서 받아 그리고, 바꾸는 일은 콜백으로 카드에 넘긴다.

/// 날짜·시간 두 줄과 그 아래에 펼치는 선택기(달력, 오전/오후·시·분 휠).
///
/// 처음에는 접혀 있고, 줄을 누르면 바로 아래로 펼쳐지며 다시 누르면 접힌다. 고른 값은 줄에
/// 바로 보이고 선택기는 닫지 않는다. 펼침 여부만 화면에서 기억하고 값은 [draft]에 있어,
/// 접었다 펼쳐도 고른 값이 그대로다. 날짜와 시간 선택기는 따로 펼친다.
///
/// 휠은 굴리던 칸이 멈춰야 값을 알리므로, 카드가 값을 읽기 전(저장·닫기 등)에
/// [timeWheelKey]로 [ScheduleTimeWheelState.flush]를 부른다. 시간 선택기를 접을 때는 이
/// 위젯이 직접 부른다(접힌 뒤 휠이 사라지며 굴리던 값을 잃지 않게).
class ScheduleDateTimeField extends StatefulWidget {
  const ScheduleDateTimeField({
    super.key,
    required this.draft,
    required this.today,
    required this.onDate,
    required this.onTime,
    required this.timeWheelKey,
  });

  final ScheduleDraft draft;
  final DateTime today;

  /// null이면 바꿀 수 없다(저장 중).
  final ValueChanged<DateTime>? onDate;
  final void Function(int hour, int minute)? onTime;

  /// 시간 휠의 키. 휠이 펼쳐져 있을 때만 상태가 있다.
  final GlobalKey<ScheduleTimeWheelState> timeWheelKey;

  @override
  State<ScheduleDateTimeField> createState() => _ScheduleDateTimeFieldState();
}

class _ScheduleDateTimeFieldState extends State<ScheduleDateTimeField> {
  bool _dateOpen = false;
  bool _timeOpen = false;

  void _toggleTime() {
    if (_timeOpen) widget.timeWheelKey.currentState?.flush();
    setState(() => _timeOpen = !_timeOpen);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final enabled = widget.onDate != null;
    final dateLabel = ScheduleLabels.date(draft.date, today: widget.today);
    final timeLabel = ScheduleLabels.time(draft.hour, draft.minute);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScheduleFlatButton(
          key: const ValueKey('schedule-date'),
          icon: Icons.calendar_today_outlined,
          label: dateLabel,
          semanticsLabel: '날짜, $dateLabel',
          expanded: _dateOpen,
          onPressed: enabled
              ? () => setState(() => _dateOpen = !_dateOpen)
              : null,
        ),
        ScheduleFold(
          open: _dateOpen,
          child: ScheduleCalendar(
            selected: draft.date,
            today: widget.today,
            onSelected: widget.onDate,
          ),
        ),
        const SizedBox(height: 8),
        ScheduleFlatButton(
          key: const ValueKey('schedule-time'),
          icon: Icons.schedule,
          label: timeLabel,
          semanticsLabel: '시간, $timeLabel',
          expanded: _timeOpen,
          onPressed: enabled ? _toggleTime : null,
        ),
        ScheduleFold(
          open: _timeOpen,
          child: ScheduleTimeWheel(
            key: widget.timeWheelKey,
            hour: draft.hour,
            minute: draft.minute,
            onChanged: widget.onTime,
          ),
        ),
      ],
    );
  }
}

/// 장소 칸: 왼쪽 지도 버튼과 직접 입력칸, 지도에서 골랐으면 아래에 주소·좌표.
class SchedulePlaceField extends StatelessWidget {
  const SchedulePlaceField({
    super.key,
    required this.controller,
    required this.pickedPlace,
    required this.enabled,
    required this.onPickOnMap,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ScheduledPlace? pickedPlace;
  final bool enabled;
  final VoidCallback onPickOnMap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final picked = pickedPlace;
    final details = picked == null
        ? null
        : [
            picked.address,
            ScheduleLabels.coordinates(picked),
          ].whereType<String>().join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton.outlined(
              onPressed: enabled ? onPickOnMap : null,
              tooltip: '지도에서 장소 고르기',
              style: IconButton.styleFrom(
                foregroundColor: colorScheme.primary,
                minimumSize: const Size.square(48),
                side: BorderSide(color: colorScheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              icon: const Icon(Icons.map_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ScheduleFieldLabel(
                label: '장소',
                child: TextField(
                  key: const ValueKey('schedule-place'),
                  controller: controller,
                  enabled: enabled,
                  textInputAction: TextInputAction.next,
                  onChanged: onChanged,
                  decoration: const InputDecoration(
                    hintText: '직접 입력하거나 지도에서 고르기',
                  ),
                ),
              ),
            ),
          ],
        ),
        if (details != null && details.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              details,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// 알림 칸과 그 아래 안내(지난 알림 시각, 알림 예약 준비 중).
class ScheduleAlarmField extends StatelessWidget {
  const ScheduleAlarmField({
    super.key,
    required this.alarm,
    required this.isPassed,
    required this.onPressed,
  });

  static const String passedMessage = '알림 시각이 지나 알림을 보낼 수 없어요';

  /// 알림 예약은 아직 만들지 않아 고른 값만 저장한다는 안내.
  static const String notSentMessage = '알림 보내기는 준비 중이에요. 고른 값만 저장돼요.';

  final ScheduleAlarm alarm;
  final bool isPassed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final String? note;
    final Color noteColor;
    if (isPassed) {
      note = passedMessage;
      noteColor = colorScheme.tertiary;
    } else if (alarm != ScheduleAlarm.none) {
      note = notSentMessage;
      noteColor = colorScheme.onSurfaceVariant;
    } else {
      note = null;
      noteColor = colorScheme.onSurfaceVariant;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScheduleFlatButton(
          label: alarm.summary,
          semanticsLabel: '알림, ${alarm.summary}',
          onPressed: onPressed,
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(color: noteColor),
            ),
          ),
      ],
    );
  }
}

/// 카드 위의 실패 안내(저장·삭제 실패). 낭독기가 바로 읽는다.
class ScheduleFailureBanner extends StatelessWidget {
  const ScheduleFailureBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 버리기·삭제 같은 확인 창. 확인을 누르면 true, 취소·바깥 누르기는 false.
Future<bool> confirmScheduleAction(
  BuildContext context, {
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      // 판·버튼과 같은 둥글기(4). 글자를 키운 작은 화면에서도 버튼이 밀려나지 않게
      // 본문은 스크롤한다.
      return AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppTheme.cornerRadius),
          ),
        ),
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: colorScheme.error)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
