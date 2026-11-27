import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../models/tab_item.dart';
import 'bottom_menu_capture_marks.dart';

/// 같은 배경의 크기·둥글기와 버튼 좌표를 하나의 진행률로 보간한다.
class BottomMenuSurface extends StatelessWidget {
  const BottomMenuSurface({
    super.key,
    required this.circle,
    required this.progress,
    required this.scale,
    required this.current,
    required this.tabs,
    required this.selectedIndex,
    required this.dot,
    required this.canCapture,
    this.capturing = false,
    this.captureScreen = false,
    this.canExpand = true,
    this.pressed = false,
    required this.tapGroup,
    required this.onOutside,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
    required this.onActivate,
    required this.onExpand,
    required this.onChoose,
  });

  final double circle, progress, scale;
  final TabItem current;
  final List<TabItem> tabs;
  final int selectedIndex;
  final bool dot, canCapture, capturing;

  /// 누르면 촬영하는 화면(번역 촬영 화면)인지. 카메라가 준비되기 전에도 true다.
  /// false면 [canCapture]·[capturing]이 있어도 촬영 표시(카메라 아이콘·고리·꼬리표·낭독 문구)를 하지 않는다.
  final bool captureScreen;

  /// 펼칠 수 있는지. 받은 높이가 확장 버튼이 들어가기에 작으면(키보드·가로 화면) false로,
  /// 끌어 펼치기 안내와 "메뉴 펼치기" 접근성 동작을 주지 않는다.
  final bool canExpand;

  /// 아이콘 상태에서 손가락이 닿아 있는지(누름 표시).
  final bool pressed;
  final Object tapGroup;

  static const double _innerSize = BottomMenuMetrics.innerSize;
  static const double _outer = BottomMenuMetrics.outerSize;

  static const double _glyphSize = BottomMenuMetrics.glyphSize;

  bool get _canCapture => captureScreen && canCapture;
  bool get _capturing => captureScreen && capturing;

  /// 안쪽 버튼(과 촬영 고리)은 바깥 원이 60%쯤 커진 뒤에 나타나고, 접힐 때 그만큼 먼저 사라진다.
  double get _innerAppear => ((circle - .6) / .4).clamp(0.0, 1.0);

  Offset get _currentPosition => Offset.lerp(
    BottomMenuMetrics.iconCenter,
    _targetOf(selectedIndex),
    progress,
  )!;

  // 버튼 중심 자리(하단 가운데 기준). 지도가 가운데 AI 버튼에 가리지 않도록 위로 올린 설계 값이다.
  Offset _targetOf(int index) => switch (index) {
    0 => Offset(-93 * scale, 72),
    1 => const Offset(0, 122),
    2 => Offset(93 * scale, 72),
    // 확장 메뉴(bottom-nav.md 10-2절): 지도를 가운데 점으로 한 오점형의 위 두 자리.
    3 => Offset(93 * scale, 172),
    4 => Offset(-93 * scale, 172),
    _ => const Offset(0, 42),
  };

  /// 확장 버튼(일정·면세)은 가장 멀리 가므로 조금 늦게(p 0.3부터) 나타난다(10-4절).
  static bool _isExtra(int index) => index >= 3;
  final VoidCallback onOutside, onActivate, onExpand;
  final void Function(PointerDownEvent, int?) onDown;
  final PointerMoveEventListener onMove;
  final PointerUpEventListener onUp;
  final PointerCancelEventListener onCancel;
  final ValueChanged<int> onChoose;

  Widget _input({required Widget child, int? target}) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) => onDown(event, target),
    onPointerMove: onMove,
    onPointerUp: onUp,
    onPointerCancel: onCancel,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diameter = lerpDouble(10, _outer, circle)!;
    // 카메라 미리보기 위에서도 판이 보이도록 밝은 반투명 면을 깐다.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = DecoratedBox(
      key: const ValueKey('bottom-menu-background'),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: dark ? .60 : .72),
        border: Border.all(color: colors.primary.withValues(alpha: .22)),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.expand(),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final center = constraints.maxWidth / 2;
          // 배경은 하나의 원이다(bottom-nav.md 10-3절). 점(지름 10, 중심 아래 31) → 현재 화면 버튼 원(74,
          // 중심 49) → 펼치면 화면 네 모서리까지 덮도록 커진다. 화면 가장자리가 원을 잘라 아래는 평평하고
          // 위는 둥글게 보인다. 반지름은 진행률에 처음과 끝을 부드럽게 한 곡선(smoothstep)을 건다.
          final centerY = lerpDouble(
            31,
            BottomMenuMetrics.iconCenter.dy,
            circle,
          )!;
          final reach =
              math.sqrt(
                center * center + math.pow(constraints.maxHeight - centerY, 2),
              ) +
              2;
          final eased = progress * progress * (3 - 2 * progress);
          final radius = lerpDouble(diameter / 2, reach, eased)!;
          return Stack(
            children: [
              Positioned(
                left: center - radius,
                bottom: centerY - radius,
                width: radius * 2,
                height: radius * 2,
                child: ClipOval(
                  child: TapRegion(
                    groupId: tapGroup,
                    onTapOutside: (_) => onOutside(),
                    child: _input(child: background),
                  ),
                ),
              ),
              if (progress > 0)
                for (var i = 0; i < tabs.length + 1; i++)
                  _button(context, center, i == tabs.length ? -1 : i),
              // 애니메이션 줄이기면 고리 대신 안쪽 카메라 아이콘이 촬영 중을 알린다.
              // 위치 없는 빈 위젯을 Stack에 넣으면 폭이 정해지지 않은 부모에서 Stack 크기가 0이 되므로 넣지 않는다.
              if (_capturing &&
                  progress < .2 &&
                  !MediaQuery.disableAnimationsOf(context))
                _ring(center),
              if (circle > .6) _currentButton(context, center),
              if (progress == 0)
                Positioned(
                  left: center - (dot ? 24 : _outer / 2),
                  bottom: dot ? 7 : BottomMenuMetrics.outerBottom,
                  width: dot ? 48 : _outer,
                  height: dot ? 48 : _outer,
                  child: ClipOval(
                    child: TapRegion(
                      groupId: tapGroup,
                      onTapOutside: (_) => onOutside(),
                      child: Semantics(
                        key: const ValueKey('bottom-menu-current'),
                        button: true,
                        label: dot
                            ? '메뉴 열기'
                            : '현재 화면: ${current.label}${_capturing ? ', 사진 찍는 중' : ''}',
                        hint: dot ? null : _hint,
                        onTap: onActivate,
                        customSemanticsActions: dot || !canExpand
                            ? null
                            : {
                                const CustomSemanticsAction(label: '메뉴 펼치기'):
                                    onExpand,
                              },
                        child: _input(child: const SizedBox.expand()),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String? get _hint {
    final capture = _canCapture && !_capturing ? '두 번 눌러 촬영' : null;
    if (!canExpand) return capture;
    return '위로 끌어 메뉴 열기${capture == null ? '' : ', $capture'}';
  }

  Widget _button(BuildContext context, double center, int index) {
    final item = index == -1
        ? const TabItem(label: 'AI', icon: Icons.auto_awesome)
        : tabs[index];
    final position = Offset.lerp(
      BottomMenuMetrics.iconCenter,
      _targetOf(index),
      progress,
    )!;
    final size = index == -1 ? 76.0 : 64.0;
    final colors = Theme.of(context).colorScheme;
    final selected = selectedIndex == index;
    final enabled = progress > .9;
    return Positioned(
      left: center + position.dx - size / 2,
      bottom: position.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        ignoring: !enabled,
        child: ExcludeSemantics(
          excluding: !enabled,
          child: Opacity(
            opacity: _isExtra(index)
                ? ((progress - .3) / .7).clamp(0.0, 1.0)
                : ((progress - .15) / .85).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: lerpDouble(.6, 1, progress),
              child: ClipOval(
                child: TapRegion(
                  groupId: tapGroup,
                  child: Semantics(
                    key: ValueKey('bottom-menu-tab-$index'),
                    button: true,
                    selected: selected,
                    label: item.label,
                    onTap: () => onChoose(index),
                    // 현재 화면 버튼의 모양은 아이콘 상태에서 옮겨 온 _currentButton이 그린다.
                    // 여기서는 누르기·낭독만 맡아 두 개가 겹쳐 보이지 않게 한다.
                    child: _input(
                      target: index,
                      child: selected
                          ? const SizedBox.expand()
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.surfaceContainerHighest,
                                border: Border.all(
                                  color: colors.primary.withValues(alpha: .25),
                                ),
                              ),
                              child: _label(
                                context,
                                item,
                                colors.onSurfaceVariant,
                              ),
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

  /// 아이콘 상태의 안쪽 불투명 버튼. 끄는 동안 부채꼴의 현재 화면 버튼 자리로 옮겨 가며 그 버튼이 된다.
  Widget _currentButton(BuildContext context, double center) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final home = selectedIndex == -1;
    final position = _currentPosition;
    final size = lerpDouble(_innerSize, home ? 76 : 64, progress)!;
    final appear = _innerAppear;
    final disabled = captureScreen && !canCapture && !capturing;
    final resting = progress == 0;
    // 끌기 시작 후 p 0.2까지 떠 있는 버튼(그림자)에서 부채꼴 버튼(테두리)으로 바뀐다.
    final handoff = (progress / .2).clamp(0.0, 1.0);
    final shadow = disabled || (pressed && resting) || handoff >= 1
        ? null
        : [
            BoxShadow(
              color: colors.shadow.withValues(alpha: .24 * (1 - handoff)),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ];
    // 아이콘만 보이다가 p 0.4~0.8 사이에 부채꼴 버튼의 아이콘·이름으로 바뀐다.
    final swap = ((progress - .4) / .4).clamp(0.0, 1.0);
    final Widget icon;
    if (_capturing && reduced) {
      icon = Icon(
        Icons.photo_camera,
        key: const ValueKey('bottom-menu-capturing'),
        size: _glyphSize,
        color: colors.onPrimary,
      );
    } else if (_capturing) {
      // 둘레의 고리(_ring)가 촬영 중을 알린다. 끌면 고리가 p 0.2까지 사라지는 만큼 카메라 아이콘이
      // 나타나, 아이콘이 이름으로 바뀌기 시작하는 p 0.4 전에 빈 원이 되지 않는다.
      icon = progress == 0
          ? const SizedBox.shrink()
          : Opacity(
              opacity: handoff,
              child: Icon(
                Icons.photo_camera,
                size: _glyphSize,
                color: colors.onPrimary,
              ),
            );
    } else {
      icon = Icon(
        captureScreen ? Icons.photo_camera : current.icon,
        size: _glyphSize,
        color: colors.onPrimary,
      );
    }
    return Positioned(
      key: const ValueKey('bottom-menu-current-button'),
      left: center + position.dx - size / 2,
      bottom: position.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: appear,
            child: Transform.scale(
              scale:
                  lerpDouble(.6, 1, appear)! * (pressed && resting ? .92 : 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 카메라 준비 전의 흐린 버튼도 p=1에서는 부채꼴의 선택 버튼과 같은 색이 된다.
                  color: colors.primary.withValues(
                    alpha: disabled ? lerpDouble(.38, 1, progress)! : 1,
                  ),
                  border: resting
                      ? null
                      : Border.all(
                          color: colors.primary.withValues(
                            alpha: .25 * handoff,
                          ),
                        ),
                  boxShadow: shadow,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (swap < 1) Opacity(opacity: 1 - swap, child: icon),
                    if (swap > 0)
                      Opacity(
                        opacity: swap,
                        child: _label(context, current, colors.onPrimary),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 촬영 중 고리: 안쪽 버튼보다 지름이 ringGrowth만큼 크고 버튼을 따라간다. 애니메이션 줄이기면 그리지 않는다.
  Widget _ring(double center) {
    final position = _currentPosition;
    final size =
        lerpDouble(_innerSize, selectedIndex == -1 ? 76 : 64, progress)! +
        BottomMenuMetrics.ringGrowth;
    return BottomMenuCaptureRing(
      left: center + position.dx - size / 2,
      bottom: position.dy - size / 2,
      size: size,
      opacity: _innerAppear * (1 - progress / .2).clamp(0.0, 1.0),
    );
  }

  Widget _label(BuildContext context, TabItem item, Color color) {
    final text = Theme.of(context).textTheme;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 26, color: color),
              Text(item.label, style: text.labelMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
