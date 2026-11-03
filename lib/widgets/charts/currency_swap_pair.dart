import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../presentation/exchange/display_currency.dart';
import '../exchange/currency_icon.dart';

/// 시스템의 애니메이션 줄이기 설정이 켜져 있는지.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 방향이 바뀐 것을 움직임으로 보여 줄지 정한다.
/// 저장된 방향을 처음 읽을 때는 버튼이 비활성이었으므로([wasEnabled]가 false)
/// 바로 표시하고, 활성 버튼을 눌러 바뀐 경우에만 움직인다.
bool animatesSwap(BuildContext context, {required bool wasEnabled}) =>
    wasEnabled && !reduceMotionOf(context);

/// [기준 아이콘] 기준 코드 ⇄ [대상 아이콘] 대상 코드.
/// [swapped]가 바뀌면 두 통화가 서로의 자리로 옮겨 가고 아이콘이 반 바퀴 돈다.
/// [baseCurrency]와 [targetCurrency]는 뒤집기 전의 원래 방향이다.
class CurrencySwapPair extends StatefulWidget {
  const CurrencySwapPair({
    super.key,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.swapped,
    required this.onSwap,
    this.onPickShownBase,
    this.onPickShownTarget,
  });

  final DisplayCurrency baseCurrency;
  final DisplayCurrency targetCurrency;
  final bool swapped;

  /// 저장된 방향을 읽기 전에는 null이며, 이때 버튼은 비활성이다.
  final VoidCallback? onSwap;

  /// 화면 왼쪽(현재 기준)·오른쪽(현재 대상) 통화명을 눌렀을 때. null이면 누를 수 없고
  /// 드롭다운 표시(▾)도 두지 않는다.
  final VoidCallback? onPickShownBase;
  final VoidCallback? onPickShownTarget;

  @override
  State<CurrencySwapPair> createState() => _CurrencySwapPairState();
}

class _CurrencySwapPairState extends State<CurrencySwapPair>
    with SingleTickerProviderStateMixin {
  // 통화 이동과 아이콘 회전은 누른 반응이 바로 보이도록 짧게 끝낸다.
  static const _swapDuration = Duration(milliseconds: 300);

  // 0이면 원래 방향, 1이면 뒤집은 방향의 배치. 사용자가 누를 때만 움직인다.
  late final AnimationController _motion;
  late final Animation<double> _turns;

  DisplayCurrency get _shownBase =>
      widget.swapped ? widget.targetCurrency : widget.baseCurrency;

  DisplayCurrency get _shownTarget =>
      widget.swapped ? widget.baseCurrency : widget.targetCurrency;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: _swapDuration,
      value: widget.swapped ? 1 : 0,
    );
    _turns = _motion.drive(Tween(begin: 0, end: 0.5));
  }

  @override
  void didUpdateWidget(covariant CurrencySwapPair oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.swapped == widget.swapped) return;
    final target = widget.swapped ? 1.0 : 0.0;
    if (animatesSwap(context, wasEnabled: oldWidget.onSwap != null)) {
      _motion.animateTo(target, curve: Curves.easeInOutCubic);
    } else {
      _motion.value = target;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const iconBox = 24.0;
    final colorScheme = Theme.of(context).colorScheme;
    final codeStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w900,
      color: colorScheme.onSurface,
    );

    Widget side(DisplayCurrency currency, VoidCallback? onPick) {
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 국기 이모지(Text)는 글꼴 줄 높이 때문에 이미지 로고보다 커 보여서
          // 같은 정사각형 안에 맞춰 두 종류의 크기와 기준선을 맞춘다.
          SizedBox.square(
            dimension: iconBox,
            child: FittedBox(child: CurrencyIcon(currency: currency, size: 24)),
          ),
          const SizedBox(width: 6),
          // 좁은 화면이나 4자리 심볼(DOGE)은 잘라내지 않고 글자를 줄여 맞춘다.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(currency.code, style: codeStyle, maxLines: 1),
            ),
          ),
          if (onPick != null)
            Icon(
              Icons.arrow_drop_down,
              size: 22,
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      );
      if (onPick == null) return content;
      // 옅은 배경의 둥근 칸으로 감싸 누를 수 있는 선택 칸임을 보여 주고,
      // 배경 없이 강조색 아이콘만 있는 스왑 버튼과 구분한다. 높이는 스왑
      // 버튼과 같은 48dp라 줄 높이는 늘지 않고 터치 영역은 충분하다.
      return Semantics(
        button: true,
        label: '${currency.code} 다른 통화로 바꾸기',
        excludeSemantics: true,
        child: Material(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('market-chart-pick-${currency.id}'),
            onTap: onPick,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 2),
                child: content,
              ),
            ),
          ),
        ),
      );
    }

    // 평소에는 배경 없이 강조색 아이콘만 두고, 누르는 동안에만 예전 톤 배경
    // 원을 보여 준다. 기본 밀도로 48dp 터치 영역을 유지한다.
    // tooltip은 길게 누를 때와 화면 낭독기에서 누르면 어느 통화 기준이
    // 되는지 알려 준다. 비활성일 때는 저장된 방향을 읽기 전이라 문구가
    // 틀릴 수 있어 tooltip을 숨기고, 방향 없는 라벨만 화면 낭독기에 준다.
    final swapButton = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: IconButton(
        key: const ValueKey('market-chart-swap'),
        onPressed: widget.onSwap,
        tooltip: widget.onSwap == null ? null : '${_shownTarget.code} 기준으로 바꾸기',
        iconSize: 24,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colorScheme.onSurface.withValues(alpha: 0.38)
                : colorScheme.primary,
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.secondaryContainer;
            }
            if (states.contains(WidgetState.hovered)) {
              return colorScheme.primary.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.focused)) {
              return colorScheme.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
        // 통화 이동과 같은 진행값으로 아이콘을 반 바퀴 돌려 눌렀다는 반응과
        // 현재 방향이 바뀌었음을 함께 보여 준다.
        icon: RotationTransition(
          turns: _turns,
          child: Icon(
            Icons.swap_horiz,
            semanticLabel: widget.onSwap == null ? '기준 통화 바꾸기' : null,
          ),
        ),
      ),
    );

    // 화면 낭독기와 포커스 순서가 보이는 순서(왼쪽 → 버튼 → 오른쪽)를 따르도록
    // 자식은 현재 방향 순서로 넘기고, 위치는 [_motion]에 맞춰 배치한다.
    return _SwapPairLayout(
      progress: _motion,
      swapped: widget.swapped,
      children: [
        KeyedSubtree(
          key: ValueKey('pair-${_shownBase.id}'),
          child: side(_shownBase, widget.onPickShownBase),
        ),
        swapButton,
        KeyedSubtree(
          key: ValueKey('pair-${_shownTarget.id}'),
          child: side(_shownTarget, widget.onPickShownTarget),
        ),
      ],
    );
  }
}

/// [기준 통화, 스왑 버튼, 대상 통화]를 한 줄에 배치한다.
/// 각 통화는 버튼을 뺀 폭의 절반까지 쓰고(기존 Row + Flexible과 같은 규칙),
/// [progress]가 0이면 원래 방향, 1이면 뒤집은 방향의 위치에 놓는다.
/// 중간 값에서는 두 통화가 서로의 자리로 옮겨 가며, 겹치지 않게 위아래로
/// 살짝 비켜 지나간다. 폭이 달라도 양 끝 위치를 직접 계산하므로 자연스럽다.
/// 기존 Row처럼 [Directionality]를 따라 오른쪽→왼쪽 언어에서는 좌우를 뒤집는다.
class _SwapPairLayout extends MultiChildRenderObjectWidget {
  const _SwapPairLayout({
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
  void updateRenderObject(BuildContext context, _RenderSwapPair renderObject) {
    renderObject
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
