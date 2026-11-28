import 'package:flutter/material.dart';

import '../../models/schedule/schedule_item.dart';

/// 입력 카드의 알림 선택 창(docs/mockups/schedule.md 2-3절). 날짜·시간은 카드 안에서
/// 펼치는 선택기(`schedule_date_time_field.dart`)로 고른다.
///
/// 고르면 그 값을, 바깥을 누르거나 뒤로 가면 null을 돌려준다.
class SchedulePickers {
  const SchedulePickers._();

  static Future<ScheduleAlarm?> pickAlarm(
    BuildContext context, {
    required ScheduleAlarm selected,
  }) {
    return showDialog<ScheduleAlarm>(
      context: context,
      builder: (context) => _ScheduleDialog(
        title: '일정 시작 몇 분 전에 알릴까요?',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final alarm in ScheduleAlarm.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ChoiceButton(
                  label: alarm.label,
                  selected: alarm == selected,
                  onPressed: () => Navigator.of(context).pop(alarm),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleDialog extends StatelessWidget {
  const _ScheduleDialog({required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    );
    final text = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    );
    const minimumSize = Size(0, 48);
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                shape: shape,
                minimumSize: minimumSize,
                padding: EdgeInsets.zero,
              ),
              child: text,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                shape: shape,
                minimumSize: minimumSize,
                padding: EdgeInsets.zero,
                foregroundColor: colorScheme.onSurface,
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: text,
            ),
    );
  }
}
