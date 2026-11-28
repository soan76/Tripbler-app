import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 타임라인 줄을 길게 눌러 끌어 순서를 바꾸는 조각(docs/mockups/schedule.md 2-2절 "순서 바꾸기").

/// 약 0.45초 눌러야 끌기가 시작되는 손잡이. 그 전에 손가락이 움직이면(스크롤) 끌지 않고,
/// 짧게 누르면 아래 줄의 누르기(수정 화면 열기)가 그대로 동작한다.
class TimelineDragListener extends ReorderableDragStartListener {
  const TimelineDragListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });

  static const Duration delay = Duration(milliseconds: 450);

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this);
}

/// 끌고 있는 줄(떠오른 줄) 안인지 알린다. 떠오른 줄은 위아래 연결선을 그리지 않는다.
class TimelineLiftedScope extends InheritedWidget {
  const TimelineLiftedScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TimelineLiftedScope>() != null;

  @override
  bool updateShouldNotify(covariant TimelineLiftedScope oldWidget) => false;
}

/// 떠오른 줄의 모양: 살짝 커지고(1.02배) 그림자가 생기며, 연결선은 숨긴다.
/// 애니메이션 줄이기 설정이면 크기 변화 없이 그림자만 바로 보인다.
Widget timelineLiftedDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    child: TimelineLiftedScope(child: child),
    builder: (context, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final t = reduceMotion
          ? 1.0
          : Curves.easeOut.transform(animation.value.clamp(0, 1));
      return Transform.scale(
        scale: 1 + 0.02 * t,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 6 * t,
          // 그림자는 위 움직임(t)을 그대로 따른다. Material의 자체 그림자 애니메이션(200ms)이
          // 겹치면 놓을 때 그림자가 줄보다 늦게 사라진다.
          animationDuration: Duration.zero,
          borderRadius: BorderRadius.circular(4),
          child: child,
        ),
      );
    },
  );
}
