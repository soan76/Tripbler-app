import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/schedule/schedule_labels.dart';

/// 오전/오후 · 시(1~12) · 분(00~59) 세 칸 휠 피커(docs/mockups/schedule.md 2-3절).
///
/// 칸을 위아래로 굴리면 가운데 칸이 고른 값이 되고, 굴리던 칸이 모두 멈추면 [onChanged]로
/// 한 번 알린다(지나가는 칸마다 알리지 않는다). 멈추기 전에 값이 필요하면(저장·접기·닫기 등)
/// [GlobalKey]로 [ScheduleTimeWheelState.flush]를 부른다. 칸을 누르면 그 값으로 굴러간다.
/// 다섯 칸이 보이고 위아래 끝은 흐리게 사라진다. 별도 배경·테두리는 없고 가운데 칸 위아래에만
/// 얇은 선을 둔다. 저장 중(onChanged 없음)에는 흐리게 보인다.
class ScheduleTimeWheel extends StatefulWidget {
  const ScheduleTimeWheel({
    super.key,
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  /// 칸 높이 기본값. 글자를 키우면 함께 커진다.
  static const double itemExtent = 40;
  static const int visibleItems = 5;
  static const double columnMaxWidth = 72;

  /// 0~23.
  final int hour;

  /// 0~59.
  final int minute;

  /// 고른 시각(시 0~23, 분 0~59). null이면 굴릴 수 없다(저장 중).
  final void Function(int hour, int minute)? onChanged;

  @override
  State<ScheduleTimeWheel> createState() => ScheduleTimeWheelState();
}

/// [ScheduleTimeWheel]의 상태. 바깥에서는 [flush]만 쓴다.
class ScheduleTimeWheelState extends State<ScheduleTimeWheel> {
  static const List<String> _meridiems = ['오전', '오후'];
  static final List<String> _hours = [for (var h = 1; h <= 12; h++) '$h'];
  static final List<String> _minutes = [
    for (var m = 0; m < 60; m++) m.toString().padLeft(2, '0'),
  ];

  // 칸 번호: 오전 0·오후 1, 시 0~11(1~12시), 분 0~59.
  late int _meridiem = _meridiemIndex(widget.hour);
  late int _hour = _hourIndex(widget.hour);
  late int _minute = widget.minute;

  late final FixedExtentScrollController _meridiemController =
      FixedExtentScrollController(initialItem: _meridiem);
  late final FixedExtentScrollController _hourController =
      FixedExtentScrollController(initialItem: _hour);
  late final FixedExtentScrollController _minuteController =
      FixedExtentScrollController(initialItem: _minute);

  static int _meridiemIndex(int hour) => hour < 12 ? 0 : 1;
  static int _hourIndex(int hour) => ScheduleLabels.hour12(hour) - 1;

  int get _hour24 => (_hour + 1) % 12 + (_meridiem == 1 ? 12 : 0);

  @override
  void didUpdateWidget(covariant ScheduleTimeWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 바깥 값이 바뀐 경우에만 휠을 옮긴다. 굴리는 중(아직 알리기 전)에 다른 이유로 다시
    // 그려질 때는 휠을 건드리지 않는다.
    if (widget.hour == oldWidget.hour && widget.minute == oldWidget.minute) {
      return;
    }
    _moveTo(widget.hour, widget.minute);
  }

  bool get _matchesWidget => widget.hour == _hour24 && widget.minute == _minute;

  /// 휠을 [hour]:[minute] 자리로 옮긴다(알리지 않는다).
  void _moveTo(int hour, int minute) {
    _meridiem = _meridiemIndex(hour);
    _hour = _hourIndex(hour);
    _minute = minute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final (controller, index) in [
        (_meridiemController, _meridiem),
        (_hourController, _hour),
        (_minuteController, _minute),
      ]) {
        if (controller.hasClients && controller.selectedItem != index) {
          controller.jumpToItem(index);
        }
      }
    });
  }

  @override
  void dispose() {
    _meridiemController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  /// 굴리는 동안에는 휠 안의 가운데 칸 표시만 바꾼다.
  void _select(void Function() change) => setState(change);

  /// [flush]가 휠을 멈추는 동안에는 멈춤 알림으로 다시 알리지 않는다.
  bool _flushing = false;

  /// 굴러가는 중이면 지금 가운데 칸(사용자가 마지막으로 본 값)에 바로 멈추고, 그 값이 바깥
  /// 값과 다르면 [ScheduleTimeWheel.onChanged]로 바로 알린다. 저장·접기·닫기처럼 바깥 값을
  /// 읽기 직전에 불러, 휠이 멈추기를 기다리지 않고 보이는 값을 반영한다.
  ///
  /// 이미 멈췄고 값이 같거나, 꺼져 있으면(저장 중) 아무것도 하지 않는다.
  void flush() {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    _flushing = true;
    try {
      for (final (controller, index) in [
        (_meridiemController, _meridiem),
        (_hourController, _hour),
        (_minuteController, _minute),
      ]) {
        if (!controller.hasClients) continue;
        final position = controller.position;
        if (position.isScrollingNotifier.value ||
            controller.selectedItem != index) {
          controller.jumpToItem(index);
        }
      }
    } finally {
      _flushing = false;
    }
    if (!_matchesWidget) onChanged(_hour24, _minute);
  }

  /// [ended] 칸이 멈췄을 때. 다른 칸도 모두 멈췄으면 최종 값을 한 번만 알린다.
  ///
  /// 저장 중(onChanged 없음)이라 알릴 수 없으면 휠을 바깥 값으로 되돌려, 휠과 바깥 값
  /// (draft)이 어긋나지 않게 한다.
  bool _onScrollEnd(
    ScrollEndNotification notification,
    FixedExtentScrollController ended,
  ) {
    if (notification.depth != 0 || _flushing) return false;
    for (final controller in [
      _meridiemController,
      _hourController,
      _minuteController,
    ]) {
      // 끝난 칸은 이 알림 뒤에야 멈춘 상태가 된다.
      if (identical(controller, ended) || !controller.hasClients) continue;
      if (controller.position.isScrollingNotifier.value) return false;
    }
    if (_matchesWidget) return false;
    final onChanged = widget.onChanged;
    if (onChanged != null) {
      onChanged(_hour24, _minute);
    } else {
      setState(() => _moveTo(widget.hour, widget.minute));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final extent = math.max(
      ScheduleTimeWheel.itemExtent,
      textScaler.scale(28) + 12,
    );
    final height = extent * ScheduleTimeWheel.visibleItems;
    final enabled = widget.onChanged != null;
    final theme = Theme.of(context);
    final line = Divider(
      height: 1,
      thickness: 1,
      color: theme.colorScheme.outlineVariant,
    );

    final columns = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _column(
          key: const ValueKey('schedule-wheel-meridiem'),
          label: '오전 오후',
          controller: _meridiemController,
          extent: extent,
          selected: _meridiem,
          labels: _meridiems,
          valueOf: (i) => _meridiems[i],
          enabled: enabled,
          onSelected: (i) => _select(() => _meridiem = i),
        ),
        _column(
          key: const ValueKey('schedule-wheel-hour'),
          label: '시',
          controller: _hourController,
          extent: extent,
          selected: _hour,
          labels: _hours,
          valueOf: (i) => '${i + 1}시',
          enabled: enabled,
          onSelected: (i) => _select(() => _hour = i),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 12,
            child: Text(
              ':',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        _column(
          key: const ValueKey('schedule-wheel-minute'),
          label: '분',
          controller: _minuteController,
          extent: extent,
          selected: _minute,
          labels: _minutes,
          valueOf: (i) => '$i분',
          enabled: enabled,
          onSelected: (i) => _select(() => _minute = i),
        ),
      ],
    );

    // 저장 중에는 굴리거나 누를 수 없고, 흐리게 보여 꺼진 것을 알린다.
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: SizedBox(
          height: height,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 가운데(고른) 칸 위아래의 얇은 선. 밝은 야외에서도 어느 칸이 값인지 보인다.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        line,
                        SizedBox(height: extent - 2),
                        line,
                      ],
                    ),
                  ),
                ),
                columns,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _column({
    required Key key,
    required String label,
    required FixedExtentScrollController controller,
    required double extent,
    required int selected,
    required List<String> labels,
    required String Function(int index) valueOf,
    required bool enabled,
    required ValueChanged<int> onSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canIncrease = enabled && selected + 1 < labels.length;
    final canDecrease = enabled && selected > 0;
    void moveTo(int index) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (reduceMotion) {
        controller.jumpToItem(index);
      } else {
        controller.animateToItem(
          index,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }

    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ScheduleTimeWheel.columnMaxWidth,
        ),
        child: Semantics(
          slider: true,
          enabled: enabled,
          label: label,
          value: valueOf(selected),
          increasedValue: canIncrease ? valueOf(selected + 1) : null,
          decreasedValue: canDecrease ? valueOf(selected - 1) : null,
          onIncrease: canIncrease ? () => moveTo(selected + 1) : null,
          onDecrease: canDecrease ? () => moveTo(selected - 1) : null,
          child: ExcludeSemantics(
            child: ShaderMask(
              // 위아래 끝을 흐리게: 가운데 40%는 그대로, 끝으로 갈수록 투명.
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [0, 0.3, 0.7, 1],
              ).createShader(bounds),
              blendMode: BlendMode.dstIn,
              child: NotificationListener<ScrollEndNotification>(
                onNotification: (n) => _onScrollEnd(n, controller),
                child: ListWheelScrollView.useDelegate(
                  key: key,
                  controller: controller,
                  itemExtent: extent,
                  physics: const FixedExtentScrollPhysics(),
                  // 거의 평평하게(목업처럼 원통 모양 없이) 보이게 한다.
                  diameterRatio: 100,
                  perspective: 0.0001,
                  onSelectedItemChanged: onSelected,
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: labels.length,
                    builder: (context, index) {
                      final isSelected = index == selected;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => moveTo(index),
                        // 좁은 화면·큰 글자에서는 칸 폭에 맞춰 줄인다(잘리거나 두 줄로 넘치지 않게).
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              labels[index],
                              style:
                                  (isSelected
                                          ? theme.textTheme.titleLarge
                                          : theme.textTheme.bodyLarge)
                                      ?.copyWith(
                                        color: isSelected
                                            ? colorScheme.onSurface
                                            : colorScheme.outline,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                            ),
                          ),
                        ),
                      );
                    },
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
