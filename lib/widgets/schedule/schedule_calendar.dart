import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/schedule/schedule_labels.dart';

/// 입력 카드 안에 펼쳐지는 한 달 달력(docs/mockups/schedule.md 2-3절).
///
/// 날짜를 누르면 [onSelected]로 알리고 달력은 그대로 둔다(닫지 않는다). 지난 날도 고를 수
/// 있지만 흐리게 보인다. 달 넘기기는 화면에서만 기억한다.
class ScheduleCalendar extends StatefulWidget {
  const ScheduleCalendar({
    super.key,
    required this.selected,
    required this.today,
    required this.onSelected,
  });

  final DateTime selected;
  final DateTime today;

  /// 날짜를 골랐을 때. null이면 누를 수 없다(저장 중).
  final ValueChanged<DateTime>? onSelected;

  @override
  State<ScheduleCalendar> createState() => _ScheduleCalendarState();
}

class _ScheduleCalendarState extends State<ScheduleCalendar> {
  static const List<String> _weekHeader = ['일', '월', '화', '수', '목', '금', '토'];

  /// 날짜 칸 높이(누르기 영역). 폭은 화면 폭의 1/7이라 좁은 화면에서 48보다 작다.
  static const double _cellHeight = 48;

  /// 고른 날·오늘 표시 정사각형의 최대 크기.
  static const double _markMaxSize = 40;

  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  void _moveMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = DateTime(
      widget.today.year,
      widget.today.month,
      widget.today.day,
    );
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // 일요일 시작. DateTime.weekday는 월요일 1 ~ 일요일 7이다.
    final leading = DateTime(_month.year, _month.month).weekday % 7;

    final enabled = widget.onSelected != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => _moveMonth(-1),
              tooltip: '이전 달',
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${_month.year}년 ${_month.month}월',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: () => _moveMonth(1),
              tooltip: '다음 달',
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Row(
            children: [
              for (final label in _weekHeader)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 저장 중에는 누를 수 없고 흐리게 보인다. 달 넘기기는 보기만 바꾸므로 그대로 둔다.
        Opacity(
          opacity: enabled ? 1 : 0.38,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 칸 폭은 좁은 화면(폭 320)에서 48보다 작으므로 높이로 누르기 영역을 48 확보한다.
              final cellWidth = constraints.maxWidth / 7;
              final mark = math.min(cellWidth, _markMaxSize);
              return GridView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: _cellHeight,
                ),
                children: [
                  for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                  for (var day = 1; day <= daysInMonth; day++)
                    _dayCell(
                      context,
                      DateTime(_month.year, _month.month, day),
                      today,
                      mark,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    DateTime today,
    double mark,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = ScheduleLabels.isSameDay(day, widget.selected);
    final isToday = ScheduleLabels.isSameDay(day, today);
    final isPast = day.isBefore(today);
    final color = isSelected
        ? colorScheme.onPrimary
        : isPast
        ? colorScheme.outline
        : colorScheme.onSurface;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: isToday && !isSelected
          ? BorderSide(color: colorScheme.primary)
          : BorderSide.none,
    );
    final onSelected = widget.onSelected;
    final pick = onSelected == null ? null : () => onSelected(day);

    return Semantics(
      button: true,
      enabled: pick != null,
      selected: isSelected,
      label: ScheduleLabels.date(day, today: today),
      // 아래 InkWell의 의미 정보를 이 이름으로 바꾸므로 누르기 동작도 여기서 넘긴다.
      onTap: pick,
      excludeSemantics: true,
      // 누르는 영역은 칸 전체(높이 48), 고른 날·오늘 표시는 가운데 정사각형에만 둔다.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          onTap: pick,
          child: Center(
            child: SizedBox.square(
              dimension: mark,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: isSelected ? colorScheme.primary : null,
                  shape: shape,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  // 큰 글자에서도 두 자리 날짜가 칸을 넘지 않게 줄인다.
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${day.day}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: color),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
