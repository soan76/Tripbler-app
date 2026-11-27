import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../models/tab_item.dart';
import 'navigation/bottom_menu_surface.dart';

enum _MenuStage { dot, icon, fan }

/// 점 → 현재 화면 → 부채꼴로 펼치는 하단 이동 메뉴.
class BottomTabBar extends StatefulWidget {
  const BottomTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.isHomeSelected,
    required this.onTabTap,
    required this.onHomeTap,
    this.onCurrentScreenTap,
    this.isCapturing = false,
    this.isCaptureScreen = false,
    this.alwaysShowIcon = false,
    this.onExpansionChanged,
  });

  final List<TabItem> tabs;
  final int selectedIndex;
  final bool isHomeSelected;
  final ValueChanged<int> onTabTap;
  final VoidCallback onHomeTap;
  final VoidCallback? onCurrentScreenTap;

  /// 현재 화면이 사진을 찍는 중이면 아이콘 자리에 진행 표시를 보인다.
  final bool isCapturing;

  /// 현재 화면이 번역 촬영 화면인지. 카메라가 준비되기 전([onCurrentScreenTap]이 없을 때)에도
  /// 안쪽 버튼을 카메라 아이콘으로, 흐리게 보이기 위해 따로 받는다. false면 [isCapturing]과
  /// [onCurrentScreenTap]이 있어도 카메라 아이콘·촬영 고리·꼬리표·촬영 낭독 문구를 보이지 않는다.
  final bool isCaptureScreen;

  /// 점으로 접지 않고 늘 현재 화면 버튼 상태를 보일지(번역 화면).
  ///
  /// 켜지면 들어오자마자 현재 화면 버튼 상태가 되고, 바깥 누르기·4초 무입력·버튼 선택으로
  /// 접을 때도 점 대신 현재 화면 버튼 상태로 돌아온다. 꺼지면(다른 화면으로 가면) 점으로 접는다.
  final bool alwaysShowIcon;
  final ValueChanged<double>? onExpansionChanged;

  @override
  State<BottomTabBar> createState() => _BottomTabBarState();
}

class _BottomTabBarState extends State<BottomTabBar>
    with TickerProviderStateMixin {
  late final AnimationController _circle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final AnimationController _fan = AnimationController(vsync: this)
    ..addListener(_expansionChanged);
  final Object _tapGroup = Object();

  /// 완전히 펼치는 끌기 거리(bottom-nav.md 10-4절, 6개 버튼과 화면 전체 배경에 맞춰 120에서 늘림).
  static const double _openDistance = 150;

  /// 높이 제한이 없을 때의 높이: 가장 높은 확장 버튼(중심 172, 지름 64) 위 끝과 여유.
  static const double _minHeight = 212;

  /// 받은 높이가 [_minHeight]보다 작은지(키보드가 뜨거나 가로 화면). 그때는 확장 버튼이 잘려 누를 수 없으므로
  /// 펼치지 않는다. 점↔현재 화면 버튼과 누르기(촬영)는 그대로 된다.
  bool _short = false;
  bool _shortCollapseScheduled = false;
  Timer? _idle;
  _MenuStage _stage = _MenuStage.dot;
  int? _pointer;
  int? _target;
  Offset _origin = Offset.zero;
  double _startProgress = 0;
  bool _moved = false;
  bool _startedAsDot = false;

  /// 점으로 접히는 중인지. 접히는 중은 점으로 가는 중이라 누르기로 촬영하지 않는다.
  bool _collapsing = false;
  bool _startedCollapsing = false;

  /// 아이콘 상태에서 손가락이 닿아 있고 아직 끌기가 아닌지(안쪽 버튼 누름 표시).
  bool _pressed = false;
  VelocityTracker? _velocity;
  int _transition = 0;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _expansionChanged() => widget.onExpansionChanged?.call(_fan.value);

  // 촬영 중에는 진행 표시가 보이도록 접지 않고, 촬영이 끝나면 그때부터 다시 센다.
  void _armIdle() {
    _idle?.cancel();
    if (_stage == _MenuStage.icon &&
        !widget.isCapturing &&
        !widget.alwaysShowIcon) {
      _idle = Timer(const Duration(seconds: 4), _collapse);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.alwaysShowIcon) {
      _stage = _MenuStage.icon;
      _circle.value = 1;
    }
  }

  @override
  void didUpdateWidget(BottomTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 번역 화면으로 들어오면 바로 현재 화면 버튼 상태로, 떠나면 점으로 접는다.
    // 다른 화면에서 번역 버튼을 고르면 _choose가 먼저 점으로 접기 시작하는데, 여기서 끊고 되돌린다.
    if (oldWidget.alwaysShowIcon != widget.alwaysShowIcon && _pointer == null) {
      if (widget.alwaysShowIcon) {
        _toIcon();
      } else if (_stage != _MenuStage.dot) {
        _collapse();
      }
      return;
    }
    // 누르는 중이나 접는 중에는 그 흐름이 끝날 때 타이머를 다시 정한다.
    if (oldWidget.isCapturing != widget.isCapturing &&
        _pointer == null &&
        !_collapsing) {
      _armIdle();
    }
  }

  void _interrupt() {
    _transition++;
    _collapsing = false;
    _idle?.cancel();
    _circle.stop();
    _fan.stop();
  }

  void _showIcon() {
    _interrupt();
    setState(() => _stage = _MenuStage.icon);
    if (_reduced) {
      _circle.value = 1;
    } else {
      _circle.animateTo(1, curve: Curves.easeOut);
    }
    _armIdle();
  }

  /// 점까지 접지 않고 현재 화면 버튼 상태로 돌아온다. 부채꼴이 열려 있으면 원형으로 자리 잡는다.
  void _toIcon() {
    if (_fan.value > 0 || _stage == _MenuStage.fan) {
      _interrupt();
      _circle.value = 1;
      _settle(false);
    } else {
      _showIcon();
    }
  }

  Future<void> _settle(bool open, [double velocity = 0]) async {
    final generation = ++_transition;
    setState(() => _stage = open ? _MenuStage.fan : _MenuStage.icon);
    try {
      if (_reduced) {
        _fan.value = open ? 1 : 0;
      } else {
        await _fan
            .animateWith(
              SpringSimulation(
                SpringDescription.withDampingRatio(
                  mass: 1,
                  stiffness: 500,
                  ratio: .9,
                ),
                _fan.value,
                open ? 1 : 0,
                velocity / _openDistance,
                tolerance: const Tolerance(distance: .001, velocity: .01),
              ),
            )
            .orCancel;
        _fan.value = open ? 1 : 0;
      }
      if (mounted && generation == _transition) _armIdle();
    } on TickerCanceled {
      // 재입력은 현재 진행률에서 이어진다.
    }
  }

  Future<void> _collapse() async {
    if (widget.alwaysShowIcon) {
      _toIcon();
      return;
    }
    _interrupt();
    _collapsing = true;
    final generation = _transition;
    try {
      if (_reduced) {
        _fan.value = 0;
        _circle.value = 0;
      } else {
        await _fan
            .animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            )
            .orCancel;
        if (!mounted || generation != _transition) return;
        await _circle.reverse().orCancel;
      }
      if (mounted && generation == _transition) {
        _collapsing = false;
        setState(() => _stage = _MenuStage.dot);
      }
    } on TickerCanceled {
      // 접는 중에도 다시 잡아 움직일 수 있다.
    }
  }

  void _choose(int index) {
    if (index == -1) {
      if (!widget.isHomeSelected) widget.onHomeTap();
    } else if (index != widget.selectedIndex) {
      widget.onTabTap(index);
    }
    _collapse();
  }

  void _down(PointerDownEvent event, int? target) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _target = target;
    _origin = event.position;
    _startProgress = _fan.value;
    _moved = false;
    _startedAsDot = _stage == _MenuStage.dot;
    _startedCollapsing = _collapsing;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    // 접히는 중의 누르기는 촬영하지 않으므로 누름 표시도 하지 않는다.
    _setPressed(
      !_startedAsDot &&
          !_startedCollapsing &&
          target == null &&
          _fan.value == 0,
    );
    _interrupt();
    if (!_startedAsDot && _circle.value < 1) {
      if (_reduced) {
        _circle.value = 1;
      } else {
        _circle.animateTo(1, curve: Curves.easeOut);
      }
    }
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    if ((event.position - _origin).distance > 8) {
      _moved = true;
      _setPressed(false);
    }
    if (!_moved || _startedAsDot || _short) return;
    _fan.value =
        (_startProgress + (_origin.dy - event.position.dy) / _openDistance)
            .clamp(0.0, 1.0);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _velocity?.addPosition(event.timeStamp, event.position);
    _pointer = null;
    _setPressed(false);
    if (_moved) {
      if (!_startedAsDot) {
        final speed = -(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
        _settle(
          !_short && ((_fan.value >= .35 && speed > -500) || speed >= 500),
          speed,
        );
      }
      return;
    }
    if (_startedAsDot) {
      _showIcon();
    } else if (_target != null && _fan.value > .9) {
      _choose(_target!);
    } else if (_fan.value == 0) {
      if (!_startedCollapsing) widget.onCurrentScreenTap?.call();
      _showIcon();
    } else if (_stage == _MenuStage.fan && _fan.value > .9) {
      // 펼친 배경은 화면 전체라 따로 "메뉴 바깥"이 없다. 버튼이 아닌 빈 곳을 누르면 이동 없이 접는다
      // (번역 화면은 alwaysShowIcon이라 현재 화면 버튼 상태로 돌아온다).
      _collapse();
    } else {
      _settle(!_short && _fan.value >= .35);
    }
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _setPressed(false);
    if (!_startedAsDot) _settle(!_short && _fan.value >= .35);
  }

  /// 받은 높이를 기록하고, 펼친 채 높이가 작아지면(키보드가 뜸) 다음 프레임에 접는다.
  void _updateShort(BoxConstraints outer) {
    _short = outer.hasBoundedHeight && outer.maxHeight < _minHeight;
    // 이미 접는 중이면 다시 접기를 걸지 않는다. 키보드가 프레임마다 높이를 바꾸며 올라오는 동안
    // 매번 접기를 처음부터 다시 시작하면 접힘이 늘어지고 끊겨 보인다.
    if (!_short ||
        _stage != _MenuStage.fan ||
        _collapsing ||
        _shortCollapseScheduled) {
      return;
    }
    _shortCollapseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortCollapseScheduled = false;
      if (mounted && _short && _stage == _MenuStage.fan && !_collapsing) {
        _collapse();
      }
    });
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  void dispose() {
    _idle?.cancel();
    _circle.dispose();
    _fan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.isHomeSelected || widget.selectedIndex < 0
        ? const TabItem(label: 'AI', icon: Icons.auto_awesome)
        : widget.tabs[widget.selectedIndex];
    // 펼치면 배경이 화면 전체로 커지므로(bottom-nav.md 10-3절) 받은 높이를 모두 쓴다. 높이 제한이 없으면
    // (하단에만 붙여 둔 경우) 버튼이 들어가는 [_minHeight]를 쓴다.
    return LayoutBuilder(
      builder: (context, outer) {
        _updateShort(outer);
        return SizedBox(
          height: outer.hasBoundedHeight ? outer.maxHeight : _minHeight,
          child: AnimatedBuilder(
            animation: Listenable.merge([_circle, _fan]),
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final scale = math.min(1.0, constraints.maxWidth / 320);
                return BottomMenuSurface(
                  circle: _circle.value,
                  progress: _fan.value,
                  scale: scale,
                  current: current,
                  tabs: widget.tabs,
                  selectedIndex: widget.isHomeSelected
                      ? -1
                      : widget.selectedIndex,
                  dot: _stage == _MenuStage.dot,
                  canCapture: widget.onCurrentScreenTap != null,
                  capturing: widget.isCapturing,
                  captureScreen: widget.isCaptureScreen,
                  canExpand: !_short,
                  pressed: _pressed,
                  tapGroup: _tapGroup,
                  onOutside: () {
                    if (_stage == _MenuStage.dot || _pointer != null) return;
                    // 번역 화면(alwaysShowIcon)에서는 아이콘 상태면 그대로 두고, 부채꼴이면 아이콘으로 돌아온다.
                    if (widget.alwaysShowIcon && _stage == _MenuStage.icon) {
                      return;
                    }
                    _collapse();
                  },
                  onDown: _down,
                  onMove: _move,
                  onUp: _up,
                  onCancel: _cancel,
                  onActivate: () {
                    if (_stage == _MenuStage.dot || _collapsing) {
                      _showIcon();
                    } else {
                      widget.onCurrentScreenTap?.call();
                      _armIdle();
                    }
                  },
                  onExpand: () {
                    _interrupt();
                    _circle.value = 1;
                    _settle(true);
                  },
                  onChoose: _choose,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
