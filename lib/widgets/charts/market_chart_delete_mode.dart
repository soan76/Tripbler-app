import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus_history.dart';
import 'chart_swap_motion.dart';

/// [MarketChartDeleteMode]가 감싼 내용에 넘겨 주는 값.
class ChartDeleteControls {
  const ChartDeleteControls({
    required this.active,
    required this.open,
    required this.moreFocusNode,
  });

  /// 삭제 모드가 열려 있는지.
  final bool active;

  /// 삭제 모드를 연다. 지울 수 없는 카드면 null이다.
  final VoidCallback? open;

  /// 더보기 버튼의 포커스. 삭제 모드를 닫으면 이 버튼으로 초점을 돌려준다.
  final FocusNode moreFocusNode;
}

/// 더보기를 눌러 카드 위에 '차트 삭제' 버튼을 띄우는 삭제 모드.
/// 모드의 상태와 닫는 조건, 초점 이동, 삭제 층을 맡고 카드 내용은 [builder]로 받는다.
class MarketChartDeleteMode extends StatefulWidget {
  const MarketChartDeleteMode({
    super.key,
    required this.onRemove,
    required this.shouldLoad,
    required this.borderRadius,
    required this.builder,
  });

  /// 카드를 지울 때. null이면 모드를 열 수 없다.
  final VoidCallback? onRemove;

  /// 지금 페이지의 카드인지. 다른 페이지로 넘어가 꺼지면 모드를 닫는다.
  final bool shouldLoad;

  /// 삭제 층을 카드 모양에 맞춰 자르는 둥글기.
  final double borderRadius;

  final Widget Function(BuildContext context, ChartDeleteControls controls)
  builder;

  @override
  State<MarketChartDeleteMode> createState() => _MarketChartDeleteModeState();
}

class _MarketChartDeleteModeState extends State<MarketChartDeleteMode>
    with WidgetsBindingObserver {
  // 라이트 테마에서 빨간 글자가 가운데에 올 수 있는 내용(그래프 선, 흐린 안내문)
  // 위에서도 대비 4.5:1을 넘도록 정했다. 내용은 알아볼 만큼 비친다.
  static const _deleteLayerOpacity = 0.82;
  static const _deleteLayerFadeDuration = Duration(milliseconds: 150);
  static const _removePressedOpacity = 0.55;
  static const _removePressDuration = Duration(milliseconds: 120);

  // 더보기를 눌러 '차트 삭제' 버튼을 카드 위에 띄운 상태.
  bool _deleteMode = false;
  final _moreFocus = FocusNode(debugLabel: 'market-chart-more');
  final _removeFocus = FocusNode(debugLabel: 'market-chart-remove');

  // 카드를 품은 세로 스크롤. 없으면(스크롤 없는 화면) 카드가 밀려날 일이 없다.
  ScrollableState? _outerScrollable;
  ScrollPosition? _outerPosition;
  bool _viewportCheckPending = false;

  // 이번에 연 모드에서 삭제 버튼이 보인 적이 있는지. 버튼이 가린 채 열린 모드를 바로 닫지 않는다.
  bool _removeSeen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _removeFocus.addListener(_onRemoveFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 다른 탭으로 가서 숨겨지면 닫아, 보이지 않는 카드가 뒤로 가기를 막지 않게 한다.
    if (!Visibility.of(context)) _deleteMode = false;

    // 가로로 넘기는 PageView가 아니라 그 바깥의 세로 스크롤을 듣는다. 스크롤 위치 객체가
    // 교체되어도 여기로 다시 알림이 온다.
    final outer = Scrollable.maybeOf(context, axis: Axis.vertical);
    _outerScrollable = outer;
    final position = outer?.position;
    if (!identical(position, _outerPosition)) {
      _outerPosition?.removeListener(_onOuterViewportChanged);
      _outerPosition = position?..addListener(_onOuterViewportChanged);
    }
  }

  @override
  void didUpdateWidget(covariant MarketChartDeleteMode oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 다른 페이지로 넘어갔거나 더 지울 수 없게 되면(마지막 한 장) 삭제 모드를 닫는다.
    // 사용자가 취소한 것이 아니므로 초점은 돌려주지 않는다.
    if (_deleteMode &&
        (widget.onRemove == null ||
            (oldWidget.shouldLoad && !widget.shouldLoad))) {
      _deleteMode = false;
    }
  }

  void _openDeleteMode() {
    _removeSeen = false;
    setState(() => _deleteMode = true);
    // 삭제 버튼은 다음 프레임에 생기므로 그 뒤에 초점을 옮긴다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_deleteMode) return;
      // 삭제나 서랍으로 버튼이 초점을 잃을 때 전에 쓴 입력칸으로 돌아가지 않게 한다.
      releaseFocusHistory();
      _removeFocus.requestFocus();
      _closeIfScrolledAway();
    });
  }

  // 화면 크기가 바뀔 때(회전, 키보드). 스크롤 위치는 그대로라 위치 알림이 오지 않는다.
  @override
  void didChangeMetrics() => _onOuterViewportChanged();

  // 레이아웃이 끝나야 새 위치를 잴 수 있고 setState도 안전하므로 프레임 뒤에 한 번만 잰다.
  void _onOuterViewportChanged() {
    if (!_deleteMode || _viewportCheckPending) return;
    _viewportCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportCheckPending = false;
      _closeIfScrolledAway();
    });
  }

  // 삭제 버튼이 세로 스크롤 영역 밖으로 밀려났으면 닫는다. 그대로 두면 보이지 않는 모드가
  // 뒤로 가기를 먹고 Enter로 카드가 지워진다. 사용자가 취소한 것이 아니므로 초점은 돌려주지
  // 않는다. 버튼 가운데가 영역 안이면 보이는 것으로 보아, 세로로 조금 끄는 것은 모드를 유지한다.
  void _closeIfScrolledAway() {
    if (!mounted || !_deleteMode) return;
    final scrollable = _outerScrollable;
    if (scrollable == null) return;
    // 위에 바텀시트나 다른 화면이 있으면 닫지 않는다. 돌아오면 그대로 이어진다.
    if (ModalRoute.isCurrentOf(context) == false) return;
    // 모드에서는 초점이 버튼에 있어 키보드가 있다면 열리거나 닫히는 중이다(모드를 열어 내려가는
    // 중, 위의 입력창이 닫힌 직후). 영역이 잠시 좁아진 것이므로 키보드가 내려간 뒤에 잰다.
    if (View.of(context).viewInsets.bottom > 0) return;

    final viewport = scrollable.context.findRenderObject();
    final card = context.findRenderObject();
    final button = _removeFocus.context?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    if (card is! RenderBox || !card.hasSize) return;
    if (button is! RenderBox || !button.hasSize) return;

    // 세로 위치만 비교해 넘기는 중인 가로 위치와 섞이지 않게 한다.
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    final buttonCenter = button
        .localToGlobal(button.size.center(Offset.zero))
        .dy;
    if (buttonCenter >= top && buttonCenter <= bottom) {
      _removeSeen = true;
      return;
    }
    // 더보기만 보이는 자리에서 열면 버튼은 처음부터 가려져 있으므로, 카드까지 밖으로 나갔을
    // 때만 닫는다.
    final cardTop = card.localToGlobal(Offset.zero).dy;
    final cardVisible = cardTop < bottom && cardTop + card.size.height > top;
    if (_removeSeen || !cardVisible) setState(() => _deleteMode = false);
  }

  // 취소하면 더보기 버튼은 다음 프레임에 다시 초점을 받을 수 있으므로 그 뒤에 돌려준다.
  void _closeDeleteMode() {
    if (!_deleteMode) return;
    setState(() => _deleteMode = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_deleteMode) _moreFocus.requestFocus();
    });
  }

  // 초점이 삭제 버튼을 떠나 층 밖으로 나갔으면(서랍, 입력창, Tab 이동) 사용자가 다른 일을
  // 시작한 것이므로 닫는다. 초점은 옮겨 간 곳에 두어야 하므로 돌려주지 않는다.
  // 이 알림은 이 버튼의 초점이 실제로 바뀔 때만 오므로, 모드를 연 뒤 버튼이 초점을 받기
  // 전의 순간에는 오지 않는다.
  void _onRemoveFocusChanged() {
    if (!mounted || !_deleteMode || _removeFocus.hasFocus) return;
    // 앱이 비활성화되면 초점이 잠시 최상위로 갔다가 돌아올 때 버튼으로 돌아온다.
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary == FocusManager.instance.rootScope) return;
    // 위에 올라온 바텀시트나 화면은 닫힐 때 초점을 버튼으로 돌려주므로 그대로 둔다.
    // 서랍은 route를 쌓지 않아 여기서 걸러지지 않고 닫는 쪽으로 간다.
    if (ModalRoute.isCurrentOf(context) == false) return;
    setState(() => _deleteMode = false);
  }

  @override
  Widget build(BuildContext context) {
    final controls = ChartDeleteControls(
      active: _deleteMode,
      open: widget.onRemove == null ? null : _openDeleteMode,
      moreFocusNode: _moreFocus,
    );

    // 삭제 모드에서는 뒤로 가기가 모드만 닫고, 아래 내용은 초점과 화면 낭독기에서
    // 빠진다. 위젯 구조는 그대로 두어 내용의 상태가 유지되게 한다.
    return PopScope(
      canPop: !_deleteMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeDeleteMode();
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          ExcludeFocus(
            excluding: _deleteMode,
            child: ExcludeSemantics(
              excluding: _deleteMode,
              child: widget.builder(context, controls),
            ),
          ),
          if (_deleteMode) Positioned.fill(child: _buildDeleteLayer()),
        ],
      ),
    );
  }

  // 카드 내용을 가볍게 흐리는 층과 가운데의 '차트 삭제' 버튼.
  // 버튼 밖을 누르면 닫는다. 끌기는 잡지 않아 페이지를 넘길 수 있고, 넘기면 닫힌다.
  // 나타날 때만 서서히 보이고 닫으면 바로 사라진다. 투명도만 바뀌므로 첫 프레임부터
  // 버튼을 누를 수 있고 초점과 화면 낭독기도 그대로 받는다.
  Widget _buildDeleteLayer() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = reduceMotionOf(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _closeDeleteMode,
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion ? Duration.zero : _deleteLayerFadeDuration,
        curve: Curves.easeOut,
        builder: (_, opacity, child) => Opacity(
          opacity: opacity,
          alwaysIncludeSemantics: true,
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: GestureDetector(
            key: const ValueKey('market-chart-delete-layer'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _closeDeleteMode,
            child: ColoredBox(
              color: colorScheme.surface.withValues(alpha: _deleteLayerOpacity),
              child: Center(
                child: TextButton(
                  key: const ValueKey('market-chart-remove'),
                  focusNode: _removeFocus,
                  onPressed: widget.onRemove,
                  style: _removeButtonStyle(theme, reduceMotion),
                  // 라이브 영역은 라벨이 있는 노드라야 알릴 수 있다. 버튼 노드에 합쳐
                  // 라벨 '차트 삭제'가 한 노드에만 있게 하고, 층에 라벨 없는 칸이나
                  // 같은 라벨이 하나 더 생기지 않게 한다.
                  child: Semantics(
                    liveRegion: true,
                    onDismiss: _closeDeleteMode,
                    child: const Text('차트 삭제'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 눌러도 면이 나타나지 않고 글자만 옅어진다. 면은 키보드 초점과 마우스를 올렸을
  // 때만 보인다(터치로 초점이 옮겨 온 경우에는 InkWell이 그리지 않는다).
  ButtonStyle _removeButtonStyle(ThemeData theme, bool reduceMotion) {
    final error = theme.colorScheme.error;
    return TextButton.styleFrom(
      textStyle: theme.textTheme.titleMedium,
      minimumSize: const Size(88, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      splashFactory: NoSplash.splashFactory,
      animationDuration: reduceMotion ? Duration.zero : _removePressDuration,
    ).copyWith(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? error.withValues(alpha: _removePressedOpacity)
            : error,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)
            ? error.withValues(alpha: 0.12)
            : error.withValues(alpha: 0),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _outerPosition?.removeListener(_onOuterViewportChanged);
    _moreFocus.dispose();
    _removeFocus
      ..removeListener(_onRemoveFocusChanged)
      ..dispose();
    super.dispose();
  }
}
