import 'package:flutter/material.dart';

/// 타임라인에서 방금 바뀐 일정 줄의 움직임(docs/mockups/schedule.md 2-2·2-4절).
/// 애니메이션 줄이기 설정이면 타임라인이 이 위젯들을 쓰지 않는다.

/// 새 일정이 들어올 때 한 번: 점은 약간 작은 크기에서 커지며, 글자는 왼쪽에서 살짝 밀려
/// 들어오며 나타난다. 애니메이션 줄이기 설정이면 부모가 이 위젯을 쓰지 않는다.
class TimelineEntrance extends StatefulWidget {
  const TimelineEntrance({super.key, required this.slide, required this.child});

  final bool slide;
  final Widget child;

  @override
  State<TimelineEntrance> createState() => _TimelineEntranceState();
}

class _TimelineEntranceState extends State<TimelineEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moved = widget.slide
        ? SlideTransition(
            position: Tween(
              begin: const Offset(-0.04, 0),
              end: Offset.zero,
            ).animate(_curve),
            child: widget.child,
          )
        : ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(_curve),
            child: widget.child,
          );
    return FadeTransition(opacity: _curve, child: moved);
  }
}

/// 수정한 일정 줄의 배경을 강조색 바탕으로 잠깐 보여 준 뒤 짧게 사라지게 한다.
///
/// 바탕은 [holdDuration] 동안 움직이지 않고 머물다 [fadeDuration] 동안 사라진다.
/// 눈이 자리를 찾을 시간은 머무름으로 주고, 움직임 자체는 짧게(300ms 미만) 둔다.
/// 합계는 화면이 강조를 지우는 시각(1.5초)보다 짧다.
class TimelineFlash extends StatelessWidget {
  const TimelineFlash({super.key, required this.play, required this.child});

  static const Duration holdDuration = Duration(milliseconds: 1000);
  static const Duration fadeDuration = Duration(milliseconds: 250);

  final bool play;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!play) return child;
    final color = Theme.of(context).colorScheme.primaryContainer;
    final total = holdDuration + fadeDuration;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: total,
      curve: Interval(
        holdDuration.inMilliseconds / total.inMilliseconds,
        1,
        curve: Curves.easeOut,
      ),
      child: child,
      builder: (context, t, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: color.a * t),
          borderRadius: BorderRadius.circular(4),
        ),
        child: child,
      ),
    );
  }
}
