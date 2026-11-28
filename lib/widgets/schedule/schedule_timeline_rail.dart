import 'package:flutter/material.dart';

import 'schedule_timeline.dart';

/// 세로선 한 칸의 모양.
enum TimelineLine { none, solid, dashed }

/// 오른쪽 노드 열의 세로선. 위 절반과 아래 절반을 따로 그린다.
class TimelineRail extends StatelessWidget {
  const TimelineRail({super.key, required this.top, required this.bottom});

  final TimelineLine top;
  final TimelineLine bottom;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: ScheduleTimeline.nodeColumnWidth,
        child: CustomPaint(
          painter: _TimelineRailPainter(
            top: top,
            bottom: bottom,
            solidColor: colorScheme.primary,
            dashedColor: colorScheme.outline,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TimelineRailPainter extends CustomPainter {
  const _TimelineRailPainter({
    required this.top,
    required this.bottom,
    required this.solidColor,
    required this.dashedColor,
  });

  static const double _dash = 6, _gap = 4;

  final TimelineLine top;
  final TimelineLine bottom;
  final Color solidColor;
  final Color dashedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final middle = size.height / 2;
    _segment(canvas, x, 0, middle, top);
    _segment(canvas, x, middle, size.height, bottom);
  }

  void _segment(
    Canvas canvas,
    double x,
    double from,
    double to,
    TimelineLine line,
  ) {
    if (line == TimelineLine.none || to <= from) return;
    final paint = Paint()
      ..strokeWidth = ScheduleTimeline.lineWidth
      ..color = line == TimelineLine.solid ? solidColor : dashedColor;
    if (line == TimelineLine.solid) {
      canvas.drawLine(Offset(x, from), Offset(x, to), paint);
      return;
    }
    for (var y = from; y < to; y += _dash + _gap) {
      final end = (y + _dash).clamp(from, to);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRailPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.solidColor != solidColor ||
      old.dashedColor != dashedColor;
}

/// 목록 끝의 `+` 노드와 안내 글자. 둘 다 누르면 입력 카드가 열린다.
class TimelineAddRow extends StatelessWidget {
  const TimelineAddRow({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
                child: Text(
                  ScheduleTimeline.addHint,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: ScheduleTimeline.nodeColumnWidth,
            child: Center(
              child: Semantics(
                button: true,
                label: '다음 일정 추가',
                onTap: onAdd,
                excludeSemantics: true,
                child: InkResponse(
                  key: const ValueKey('schedule-add-next'),
                  onTap: onAdd,
                  radius: 24,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Container(
                        width: ScheduleTimeline.plusSize,
                        height: ScheduleTimeline.plusSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.surface,
                          border: Border.all(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Icon(Icons.add, color: colorScheme.primary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
