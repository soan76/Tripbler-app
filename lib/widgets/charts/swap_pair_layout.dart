import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [기준 통화, 스왑 버튼, 대상 통화]를 한 줄에 배치한다.
/// 각 통화는 버튼을 뺀 폭의 절반까지 쓰고(기존 Row + Flexible과 같은 규칙),
/// [progress]가 0이면 원래 방향, 1이면 뒤집은 방향의 위치에 놓는다.
/// 중간 값에서는 두 통화가 서로의 자리로 옮겨 가며, 겹치지 않게 위아래로
/// 살짝 비켜 지나간다. 폭이 달라도 양 끝 위치를 직접 계산하므로 자연스럽다.
/// 기존 Row처럼 [Directionality]를 따라 오른쪽→왼쪽 언어에서는 좌우를 뒤집는다.
class SwapPairLayout extends MultiChildRenderObjectWidget {
  const SwapPairLayout({
    super.key,
    required this.progress,
    required this.swapped,
    required super.children,
  });

  final Animation<double> progress;

  /// 자식이 현재 방향 순서로 들어오므로, 원래 기준 통화가 어느 쪽인지 알려 준다.
  final bool swapped;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSwapPair(
    progress: progress,
    swapped: swapped,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSwapPair)
      ..progress = progress
      ..swapped = swapped
      ..textDirection = Directionality.of(context);
  }
}

class _SwapPairParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSwapPair extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SwapPairParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SwapPairParentData> {
  _RenderSwapPair({
    required Animation<double> progress,
    required bool swapped,
    required TextDirection textDirection,
  }) : _progress = progress,
       _swapped = swapped,
       _textDirection = textDirection;

  // 서로 지나갈 때 위아래로 비켜 가는 최대 거리.
  static const _crossLift = 6.0;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(markNeedsLayout);
    _progress = value;
    if (attached) _progress.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  bool _swapped;
  set swapped(bool value) {
    if (value == _swapped) return;
    _swapped = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SwapPairParentData) {
      child.parentData = _SwapPairParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsLayout);
    super.detach();
  }

  RenderBox get _first => firstChild!;
  RenderBox get _button => childAfter(_first)!;
  RenderBox get _last => childAfter(_button)!;

  // 각 통화가 쓸 수 있는 폭: 버튼을 뺀 나머지의 절반.
  static double _sideWidth(double width, double buttonWidth) =>
      width.isFinite ? math.max(0.0, (width - buttonWidth) / 2) : width;

  // 실제 레이아웃과 dry layout이 같은 규칙으로 크기를 정한다.
  Size _computeSize(BoxConstraints constraints, ChildLayouter layoutChild) {
    assert(childCount == 3);
    final buttonSize = layoutChild(_button, constraints.loosen());
    final sideConstraints = BoxConstraints(
      maxWidth: _sideWidth(constraints.maxWidth, buttonSize.width),
      maxHeight: constraints.maxHeight,
    );
    final firstSize = layoutChild(_first, sideConstraints);
    final lastSize = layoutChild(_last, sideConstraints);
    final height = math.max(
      buttonSize.height,
      math.max(firstSize.height, lastSize.height),
    );
    return constraints.constrain(
      Size(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : firstSize.width + buttonSize.width + lastSize.width,
        height,
      ),
    );
  }

  // 레이아웃은 각 통화를 (폭 − 버튼) / 2로 제한하므로, 넓은 쪽이 줄지 않으려면
  // 버튼 + 2 × max(양쪽)이 필요하다(기존 Row + Flexible의 intrinsic 규칙과 같다).
  double _intrinsicWidth(double Function(RenderBox child) childWidth) =>
      childWidth(_button) + 2 * math.max(childWidth(_first), childWidth(_last));

  @override
  double computeMinIntrinsicWidth(double height) =>
      _intrinsicWidth((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _intrinsicWidth((child) => child.getMaxIntrinsicWidth(height));

  double _intrinsicHeight(
    double width,
    double Function(RenderBox child, double width) childHeight,
  ) {
    final side = _sideWidth(
      width,
      _button.getMaxIntrinsicWidth(double.infinity),
    );
    return math.max(
      childHeight(_button, width),
      math.max(childHeight(_first, side), childHeight(_last, side)),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMaxIntrinsicHeight(w));

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _computeSize(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _computeSize(constraints, ChildLayoutHelper.layoutChild);
    final first = _first;
    final button = _button;
    final last = _last;
    final buttonWidth = button.size.width;

    // a는 원래 기준 통화, b는 원래 대상 통화.
    final a = _swapped ? last : first;
    final b = _swapped ? first : last;
    final wa = a.size.width;
    final wb = b.size.width;
    final t = _progress.value.clamp(0.0, 1.0);
    final lift = math.sin(math.pi * t) * _crossLift;

    // 부모가 더 큰 높이를 주어도 실제 높이의 가운데에 맞춘다.
    double centerY(RenderBox child) => (size.height - child.size.height) / 2;

    _place(a, _lerp(0, wb + buttonWidth, t), centerY(a) - lift);
    _place(b, _lerp(wa + buttonWidth, 0, t), centerY(b) + lift);
    _place(button, _lerp(wa, wb, t), centerY(button));
  }

  static double _lerp(double from, double to, double t) =>
      from + (to - from) * t;

  // x는 왼쪽→오른쪽 기준 위치이며, 오른쪽→왼쪽이면 거울처럼 뒤집는다.
  void _place(RenderBox child, double x, double y) {
    final dx = _textDirection == TextDirection.rtl
        ? size.width - x - child.size.width
        : x;
    (child.parentData! as _SwapPairParentData).offset = Offset(dx, y);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  // 이동 중에는 통화 묶음이 버튼 위를 지나가므로, 그리기 순서와 상관없이
  // 버튼을 먼저 판정한다. 그래서 이동 중 버튼 자리를 누르면 통화 선택이 아니라
  // 스왑으로 처리된다.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_button, _last, _first]) {
      final offset = (child.parentData! as _SwapPairParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
