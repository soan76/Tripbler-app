import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../models/schedule/schedule_item.dart';
import '../../utils/schedule/schedule_labels.dart';
import 'schedule_timeline_drag.dart';
import 'schedule_timeline_motion.dart';
import 'schedule_timeline_rail.dart';

/// 방금 바뀐 일정을 어떻게 보일지.
enum ScheduleHighlight {
  /// 새로 추가함: 점이 커지며 나타나고 제목이 옆에서 들어온다.
  added,

  /// 수정함: 줄 배경이 잠깐 강조색으로 빛났다가 사라진다.
  edited,
}

/// 저장된 일정의 세로 타임라인(docs/mockups/schedule.md 2-2절).
///
/// 왼쪽에 시각·제목·장소, 오른쪽에 점 노드를 두고 점 사이를 실선으로 잇는다. 마지막 일정
/// 아래로 점선을 잇고 끝에 `+` 노드와 "다음 일정을 추가해 보세요"를 둔다. 전체가 세로로
/// 스크롤되고 `+` 노드도 목록 끝에 함께 있다.
///
/// 줄을 길게 눌러 끌면 순서를 바꾼다([onMove], 날짜·시간은 그대로). 위·아래 끝 가까이 끌면
/// 목록이 따라 스크롤된다. 낭독기에서는 줄마다 "위로 옮기기"·"아래로 옮기기" 동작이 있다.
class ScheduleTimeline extends StatefulWidget {
  const ScheduleTimeline({
    super.key,
    required this.items,
    required this.now,
    required this.onOpen,
    required this.onAdd,
    this.onMove,
    this.highlightId,
    this.highlight = ScheduleHighlight.added,
    this.bottomPadding = 0,
  });

  static const double nodeColumnWidth = 56;
  static const double rowMinHeight = 84;
  static const double dotSize = 18;
  static const double tailHeight = 100;
  static const double plusSize = 40;
  static const double lineWidth = 2;
  static const String addHint = '다음 일정을 추가해 보세요';

  /// 타임라인 순서로 정렬된 일정.
  final List<ScheduleItem> items;
  final DateTime now;
  final ValueChanged<ScheduleItem> onOpen;
  final VoidCallback onAdd;

  /// [item]을 [to] 자리(옮긴 뒤 목록 기준)로 옮긴다. null이면 순서를 바꿀 수 없다.
  final void Function(ScheduleItem item, int to)? onMove;

  /// 방금 추가하거나 수정한 일정. [highlight]대로 보이고, 그 줄이 보이게 스크롤한다.
  final String? highlightId;
  final ScheduleHighlight highlight;

  /// 목록 끝 여백(아래 하단 메뉴 점에 가리지 않게).
  final double bottomPadding;

  @override
  State<ScheduleTimeline> createState() => _ScheduleTimelineState();
}

class _ScheduleTimelineState extends State<ScheduleTimeline> {
  final GlobalKey _highlightKey = GlobalKey();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _revealHighlight();
  }

  @override
  void didUpdateWidget(covariant ScheduleTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightId != oldWidget.highlightId ||
        widget.highlight != oldWidget.highlight) {
      _revealHighlight();
    }
  }

  /// 방금 바뀐 일정이 보이게 스크롤한다. 추가한 일정은 화면 가운데로, 수정해 자리가
  /// 옮겨진 일정은 화면 밖일 때만 가장 가까운 끝으로 옮긴다.
  void _revealHighlight() {
    if (widget.highlightId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var target = _highlightKey.currentContext;
      if (!mounted) return;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300);
      if (target == null) {
        // 목록은 보이는 줄만 만든다. 화면 밖 줄이면 대략의 위치로 옮긴 뒤 다시 찾는다.
        final index = widget.items.indexWhere(
          (i) => i.id == widget.highlightId,
        );
        if (index < 0 || !_scroll.hasClients) return;
        final position = _scroll.position;
        _scroll.jumpTo(
          (index * ScheduleTimeline.rowMinHeight).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
        target = _highlightKey.currentContext;
      }
      if (!mounted || target == null || !target.mounted) return;
      if (widget.highlight == ScheduleHighlight.added) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: duration,
        );
        return;
      }
      for (final policy in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ]) {
        final row = _highlightKey.currentContext;
        if (!mounted || row == null || !row.mounted) return;
        await Scrollable.ensureVisible(
          row,
          alignmentPolicy: policy,
          duration: duration,
        );
      }
    });
  }

  /// 끌어 놓았을 때. [to]는 빠진 자리를 뺀 뒤의 자리다.
  void _onReorder(int from, int to) {
    if (to == from) return;
    widget.onMove?.call(widget.items[from], to);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final canMove = widget.onMove != null;
    return ReorderableListView.builder(
      scrollController: _scroll,
      buildDefaultDragHandles: false,
      padding: EdgeInsets.only(top: 20, bottom: 48 + widget.bottomPadding),
      proxyDecorator: timelineLiftedDecorator,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: _onReorder,
      itemCount: items.length,
      itemBuilder: (context, i) => TimelineDragListener(
        key: ValueKey(items[i].id),
        index: i,
        enabled: canMove,
        child: _TimelineRow(
          key: items[i].id == widget.highlightId ? _highlightKey : null,
          item: items[i],
          withDate:
              i == 0 ||
              !ScheduleLabels.isSameDay(
                items[i - 1].startsAt,
                items[i].startsAt,
              ),
          isFirst: i == 0,
          isLast: i == items.length - 1,
          isPast: items[i].isPast(widget.now),
          highlight: items[i].id == widget.highlightId
              ? widget.highlight
              : null,
          onTap: () => widget.onOpen(items[i]),
          onMoveUp: canMove && i > 0
              ? () => widget.onMove!(items[i], i - 1)
              : null,
          onMoveDown: canMove && i < items.length - 1
              ? () => widget.onMove!(items[i], i + 1)
              : null,
        ),
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: ScheduleTimeline.tailHeight,
            child: TimelineRail(
              top: TimelineLine.dashed,
              bottom: TimelineLine.dashed,
            ),
          ),
          TimelineAddRow(onAdd: widget.onAdd),
        ],
      ),
    );
  }
}

/// 일정 한 줄: 왼쪽 글자(누를 수 있는 줄 전체), 오른쪽 점(누르는 영역 48×48).
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.item,
    required this.withDate,
    required this.isFirst,
    required this.isLast,
    required this.isPast,
    required this.highlight,
    required this.onTap,
    this.onMoveUp,
    this.onMoveDown,
  });

  final ScheduleItem item;
  final bool withDate;
  final bool isFirst;
  final bool isLast;
  final bool isPast;
  final ScheduleHighlight? highlight;
  final VoidCallback onTap;

  /// 낭독기 "위로 옮기기"·"아래로 옮기기". null이면 그 동작이 없다.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final when = ScheduleLabels.timelineWhen(item.startsAt, withDate: withDate);
    final place = item.place;
    final motion = MediaQuery.disableAnimationsOf(context) ? null : highlight;
    // 끌고 있는 줄은 위아래 연결선을 숨긴다(빈자리에 선이 끊겨 보이지 않게).
    final lifted = TimelineLiftedScope.of(context);

    // 지난 일정은 글자를 한 단계 흐린 색으로 둔다. 투명도 대신 테마의 보조 글자색을 써서
    // 밝은 야외에서도 읽을 만한 대비를 지킨다.
    final muted = colorScheme.onSurfaceVariant;
    Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          when,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isPast ? muted : colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: isPast ? muted : colorScheme.onSurface,
          ),
        ),
        if (place != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  place.name,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    // 선이 점 밑으로 지나가지 않게 배경색 고리(4)로 점을 감싼다.
    Widget dot = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: ScheduleTimeline.dotSize,
          height: ScheduleTimeline.dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPast ? colorScheme.surface : colorScheme.primary,
            border: isPast
                ? Border.all(
                    color: colorScheme.primary,
                    width: ScheduleTimeline.lineWidth,
                  )
                : null,
          ),
        ),
      ),
    );
    if (motion == ScheduleHighlight.added) {
      text = TimelineEntrance(slide: true, child: text);
      dot = TimelineEntrance(slide: false, child: dot);
    }

    final semanticsLabel = [
      when,
      item.title,
      if (place != null) place.name,
      if (isPast) '지난 일정',
    ].join(', ');

    return Semantics(
      button: true,
      label: '$semanticsLabel, 수정하기',
      // 아래 두 누르기 영역의 의미 정보를 이 이름 하나로 바꾸므로 누르기 동작도 여기서 넘긴다.
      onTap: onTap,
      customSemanticsActions: {
        if (onMoveUp != null)
          const CustomSemanticsAction(label: '위로 옮기기'): onMoveUp!,
        if (onMoveDown != null)
          const CustomSemanticsAction(label: '아래로 옮기기'): onMoveDown!,
      },
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: ScheduleTimeline.rowMinHeight,
        ),
        child: Stack(
          // 줄이 최소 높이보다 낮으면 가운데에 둔다(선이 점의 가운데에서 나뉜다).
          alignment: AlignmentDirectional.centerStart,
          children: [
            Positioned.fill(
              child: TimelineRail(
                top: isFirst || lifted ? TimelineLine.none : TimelineLine.solid,
                bottom: lifted
                    ? TimelineLine.none
                    : isLast
                    ? TimelineLine.dashed
                    : TimelineLine.solid,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(4),
                    child: TimelineFlash(
                      play: motion == ScheduleHighlight.edited,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 4, 12),
                        child: text,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: ScheduleTimeline.nodeColumnWidth,
                  child: Center(
                    child: InkResponse(
                      onTap: onTap,
                      radius: 24,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(child: dot),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
