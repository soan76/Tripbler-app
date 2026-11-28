import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 일정 입력 카드·수정 화면이 함께 쓰는 모양(docs/mockups/schedule.md 2-3·2-4절).
///
/// 아래에서 올라오는 판(위 둥글기 4)에 머리글, 구분선으로 나눈 항목, 하단 버튼을 둔다.
/// 판은 화면 높이의 90%를 넘지 않고 넘치는 항목은 판 안에서 스크롤한다. 키보드가 열리면
/// 판 전체가 키보드 위로 올라가 하단 버튼이 키보드 바로 위에 붙는다.
class ScheduleSheetFrame extends StatelessWidget {
  const ScheduleSheetFrame({
    super.key,
    required this.title,
    required this.rows,
    required this.footer,
    this.banner,
    this.leading,
  });

  static const double maxHeightFactor = 0.9;

  final String title;

  /// 머리글 왼쪽 버튼(수정 화면의 뒤로 가기, 48×48).
  final Widget? leading;

  /// 머리글 아래, 항목 위에 붙는 안내(저장 실패 등).
  final Widget? banner;
  final List<Widget> rows;

  /// 하단 버튼 줄.
  final List<Widget> footer;

  /// 모달 판으로 연다. 바깥을 누르거나 뒤로 가면 [Navigator.maybePop]을 거치므로
  /// 판 안의 PopScope가 닫기 전에 확인할 수 있다. 끌어 내리기로는 닫지 않는다.
  static Future<T?> show<T>(BuildContext context, WidgetBuilder builder) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: builder,
    );
  }

  Widget _header(ThemeData theme) {
    final heading = Semantics(
      header: true,
      child: Text(title, style: theme.textTheme.titleLarge),
    );
    final leading = this.leading;
    if (leading == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: heading,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 4),
            Expanded(child: heading),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;
    final maxHeight = math.max(0.0, (height - keyboard) * maxHeightFactor);
    final divider = Divider(height: 1, color: colorScheme.outlineVariant);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme),
            ?banner,
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) divider,
                      rows[i],
                    ],
                  ],
                ),
              ),
            ),
            divider,
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    for (var i = 0; i < footer.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: footer[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 판의 항목 한 줄: 왼쪽 아이콘, 오른쪽 작은 이름표와 내용.
///
/// 이름표는 낭독기에서 빼고, 각 입력칸·값 칸이 이름을 따로 갖는다(겹쳐 읽지 않게).
class ScheduleSheetRow extends StatelessWidget {
  const ScheduleSheetRow({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Icon(icon, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 입력칸에 낭독기 이름을 붙인다. 예: "제목, 필수" 다음에 입력칸의 안내 글자를 읽는다.
class ScheduleFieldLabel extends StatelessWidget {
  const ScheduleFieldLabel({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(label: label, child: child),
    );
  }
}

/// 누르면 선택 창이 열리는 평평한 값 칸(테두리, 높이 48 이상, 둥글기 4).
class ScheduleFlatButton extends StatelessWidget {
  const ScheduleFlatButton({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
    this.icon,
    this.expanded,
  });

  final IconData? icon;
  final String label;

  /// 아래에 선택기를 펼치고 접는 줄이면 펼쳤는지(오른쪽 화살표·강조색 테두리). 아니면 null.
  final bool? expanded;

  /// 낭독기 이름. 예: "날짜, 11월 27일 (금) · 오늘".
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = this.icon;
    final expanded = this.expanded;
    final enabled = onPressed != null;
    final open = expanded ?? false;
    // 저장 중(꺼짐)에는 펼친 줄이라도 강조색을 쓰지 않고 흐린 테두리로 꺼진 것을 알린다.
    final accent = open && enabled ? colorScheme.primary : null;
    final border = enabled
        ? accent ?? colorScheme.outlineVariant
        : colorScheme.onSurface.withValues(alpha: 0.12);
    return Semantics(
      button: true,
      enabled: enabled,
      expanded: expanded,
      label: semanticsLabel,
      // 아래 버튼의 의미 정보를 이 이름으로 바꾸므로 누르기 동작도 여기서 넘긴다.
      onTap: onPressed,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: accent ?? colorScheme.onSurface,
          iconColor: accent ?? colorScheme.onSurfaceVariant,
          textStyle: theme.textTheme.bodyLarge,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon), const SizedBox(width: 12)],
            Expanded(child: Text(label)),
            if (expanded != null)
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : ScheduleFold.duration,
                curve: Curves.easeInOut,
                child: const Icon(Icons.expand_more),
              ),
          ],
        ),
      ),
    );
  }
}

/// 줄 바로 아래에서 미끄러지듯 펼쳐지고 접히는 영역(docs/mockups/schedule.md 2-3절).
///
/// 펼치고 접는 동안 아래 항목도 함께 밀리고 당겨진다. 접힌 뒤에는 [child]를 만들지 않아
/// 숨은 선택기가 낭독기나 초점에 잡히지 않는다. 내용은 높이와 함께 서서히 나타나고, 접을 때는
/// 펼칠 때보다 조금 빨리 사라진다. 애니메이션 줄이기 설정이면 바로 바뀐다.
class ScheduleFold extends StatefulWidget {
  const ScheduleFold({super.key, required this.open, required this.child});

  static const Duration duration = Duration(milliseconds: 280);
  static const Duration reverseDuration = Duration(milliseconds: 200);

  final bool open;
  final Widget child;

  @override
  State<ScheduleFold> createState() => _ScheduleFoldState();
}

class _ScheduleFoldState extends State<ScheduleFold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ScheduleFold.duration,
    reverseDuration: ScheduleFold.reverseDuration,
    value: widget.open ? 1 : 0,
  );

  // 높이는 아래 항목을 밀고 당기는 화면 안 움직임, 내용은 나타나고 사라지는 움직임.
  late final Animation<double> _size = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void didUpdateWidget(covariant ScheduleFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: widget.child,
    );
    return AnimatedBuilder(
      animation: _controller,
      child: content,
      builder: (context, child) {
        // 다 접힌 뒤에는 내용을 만들지 않는다.
        if (_controller.status == AnimationStatus.dismissed) {
          return const SizedBox(width: double.infinity);
        }
        // 접히기 시작하면 사라지는 내용이므로 낭독기와 누르기에서 바로 뺀다. 감싸는 위젯은
        // 늘 두어 다시 펼칠 때 내용의 상태(휠 위치 등)를 잃지 않게 한다.
        final closing = !widget.open;
        return SizeTransition(
          sizeFactor: _size,
          alignment: AlignmentDirectional.topCenter,
          child: FadeTransition(
            opacity: _fade,
            child: ExcludeSemantics(
              excluding: closing,
              child: IgnorePointer(ignoring: closing, child: child),
            ),
          ),
        );
      },
    );
  }
}
