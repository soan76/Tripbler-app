import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/tab_item.dart';

// 하단 탭 바 위젯
class BottomTabBar extends StatefulWidget {
  final List<TabItem> tabs;
  final bool isHomeSelected;
  final int selectedIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onHomeTap;

  const BottomTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.isHomeSelected,
    required this.onTabTap,
    required this.onHomeTap,
  });

  @override
  State<BottomTabBar> createState() => _BottomTabBarState();
}

class _BottomTabBarState extends State<BottomTabBar> {
  static const double _tabButtonSize = 64;
  static const double _homeButtonSize = 76;
  static const double _expandedHeight = 150;
  static const double _collapsedHeight = 48;
  static const double _gestureAreaWidth = 280;

  static const Duration _animationDuration = Duration(milliseconds: 280);

  bool _isExpanded = false;
  Offset _dragOffset = Offset.zero;

  final Object _menuTapGroup = Object();

  void _handlePanUpdate(DragUpdateDetails details) {
    _dragOffset += details.delta;
  }

  void _handlePanEnd(DragEndDetails details) {
    const dragThreshold = 24.0;

    if (_dragOffset.distance >= dragThreshold) {
      setState(() {
        _isExpanded = !_isExpanded;
      });
    }

    _dragOffset = Offset.zero;
  }

  void _collapseMenu() {
    if (!_isExpanded) {
      return;
    }

    setState(() {
      _isExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _animationDuration,
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: _isExpanded ? _expandedHeight : _collapsedHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final centerX = constraints.maxWidth / 2;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 펼쳐진 레디얼 메뉴의 반원형 드래그 영역
              if (_isExpanded)
                Positioned(
                  left: centerX - (_gestureAreaWidth / 2),
                  bottom: 8,
                  width: _gestureAreaWidth,
                  height: _expandedHeight,
                  child: ClipPath(
                    clipper: const _RadialGestureClipper(),
                    child: TapRegion(
                      groupId: _menuTapGroup,
                      onTapOutside: (_) => _collapseMenu(),
                      child: ClipPath(
                        clipper: const _RadialGestureClipper(),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _collapseMenu,
                          onPanUpdate: _handlePanUpdate,
                          onPanEnd: _handlePanEnd,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),

              // 환율
              AnimatedPositioned(
                duration: _animationDuration,
                curve: Curves.easeOutCubic,
                left: _isExpanded ? centerX - 125 : centerX - 32,
                bottom: _isExpanded ? 20 : 0,
                child: IgnorePointer(
                  ignoring: !_isExpanded,
                  child: AnimatedOpacity(
                    duration: _animationDuration,
                    opacity: _isExpanded ? 1 : 0,
                    child: _buildTabButton(context, index: 0),
                  ),
                ),
              ),

              // 지도
              AnimatedPositioned(
                duration: _animationDuration,
                curve: Curves.easeOutCubic,
                left: centerX - 32,
                bottom: _isExpanded ? 64 : 0,
                child: IgnorePointer(
                  ignoring: !_isExpanded,
                  child: AnimatedOpacity(
                    duration: _animationDuration,
                    opacity: _isExpanded ? 1 : 0,
                    child: _buildTabButton(context, index: 1),
                  ),
                ),
              ),

              // 번역
              AnimatedPositioned(
                duration: _animationDuration,
                curve: Curves.easeOutCubic,
                left: _isExpanded ? centerX + 61 : centerX - 32,
                bottom: _isExpanded ? 20 : 0,
                child: IgnorePointer(
                  ignoring: !_isExpanded,
                  child: AnimatedOpacity(
                    duration: _animationDuration,
                    opacity: _isExpanded ? 1 : 0,
                    child: _buildTabButton(context, index: 2),
                  ),
                ),
              ),

              // AI / Home
              AnimatedPositioned(
                duration: _animationDuration,
                curve: Curves.easeOutCubic,
                left: centerX - 38,
                bottom: _isExpanded ? 8 : 0,
                child: IgnorePointer(
                  ignoring: !_isExpanded,
                  child: AnimatedOpacity(
                    duration: _animationDuration,
                    opacity: _isExpanded ? 1 : 0,
                    child: _buildHomeButton(context),
                  ),
                ),
              ),

              // 도넛 핸들
              Positioned(
                left: centerX - 24,
                bottom: 8,
                child: IgnorePointer(
                  ignoring: _isExpanded,
                  child: AnimatedOpacity(
                    duration: _animationDuration,
                    opacity: _isExpanded ? 0 : 1,
                    child: _buildCollapsedHandle(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton(BuildContext context, {required int index}) {
    final colorScheme = Theme.of(context).colorScheme;

    const selectedColor = Colors.blue;

    final isSelected = widget.selectedIndex == index;

    final backgroundColor = isSelected
        ? selectedColor
        : colorScheme.surfaceContainerHighest;

    final contentColor = isSelected
        ? Colors.white
        : colorScheme.onSurfaceVariant;

    return TapRegion(
      groupId: _menuTapGroup,
      child: GestureDetector(
        onTap: () => widget.onTabTap(index),
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _tabButtonSize,
              height: _tabButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: backgroundColor,
                border: Border.all(
                  color: isSelected
                      ? selectedColor
                      : colorScheme.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: Icon(
                widget.tabs[index].icon,
                size: 26,
                color: contentColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.tabs[index].label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? selectedColor
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeButton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    const selectedColor = Colors.blue;

    final backgroundColor = widget.isHomeSelected
        ? selectedColor
        : colorScheme.primaryContainer;

    final contentColor = widget.isHomeSelected
        ? Colors.white
        : colorScheme.onPrimaryContainer;

    return TapRegion(
      groupId: _menuTapGroup,
      child: GestureDetector(
        onTap: widget.onHomeTap,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: Container(
          width: _homeButtonSize,
          height: _homeButtonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
            border: Border.all(
              color: widget.isHomeSelected
                  ? selectedColor
                  : colorScheme.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 28, color: contentColor),
              const SizedBox(height: 2),
              Text(
                'AI',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: contentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedHandle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.45),
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadialGestureClipper extends CustomClipper<Path> {
  const _RadialGestureClipper();

  @override
  Path getClip(Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 2);

    return Path()
      ..moveTo(0, size.height)
      ..arcTo(rect, math.pi, math.pi, false)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_RadialGestureClipper oldClipper) {
    return false;
  }
}
