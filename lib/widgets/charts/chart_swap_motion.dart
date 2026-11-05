import 'package:flutter/widgets.dart';

/// 통화 이동과 아이콘 회전은 누른 반응이 바로 보이도록 짧게 끝낸다.
const chartSwapDuration = Duration(milliseconds: 300);

/// 통화 이동과 아이콘 회전의 곡선.
const Curve chartSwapCurve = Curves.easeInOutCubic;

/// 시스템의 애니메이션 줄이기 설정이 켜져 있는지.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 방향이 바뀐 것을 움직임으로 보여 줄지 정한다.
/// 저장된 방향을 처음 읽을 때는 버튼이 비활성이었으므로([wasEnabled]가 false)
/// 바로 표시하고, 활성 버튼을 눌러 바뀐 경우에만 움직인다. 스왑을 누르지 않았는데
/// 방향이 정해진 카드([InstantSwapScope])도 바로 표시한다.
bool animatesSwap(BuildContext context, {required bool wasEnabled}) =>
    wasEnabled && !reduceMotionOf(context) && !InstantSwapScope.of(context);

/// 이 아래 카드의 방향 변경을 움직임 없이 바로 표시하게 한다. 위치 교환으로 옮겨 온
/// 카드처럼 사용자가 스왑을 누른 것이 아니라 다른 차트로 바뀌어 보이는 경우에 쓴다.
/// 방향이 바뀌는 그 빌드에서만 읽으므로 의존을 만들지 않는다.
class InstantSwapScope extends InheritedWidget {
  const InstantSwapScope({
    super.key,
    required this.instant,
    required super.child,
  });

  final bool instant;

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InstantSwapScope>()?.instant ??
      false;

  @override
  bool updateShouldNotify(InstantSwapScope oldWidget) => false;
}
