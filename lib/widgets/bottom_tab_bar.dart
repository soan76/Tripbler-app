import 'package:flutter/material.dart';

import '../models/tab_item.dart';

// 하단 탭 바 위젯
class BottomTabBar extends StatelessWidget {
  final List<TabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabTap;

  const BottomTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const selectedColor = Colors.blue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),

      // 라이트/다크 모드에 따라 배경색 변경
      color: colorScheme.surface,

      child: Row(
        children: List.generate(tabs.length, (index) {
          final bool isSelected = selectedIndex == index;

          final borderColor = isSelected ? selectedColor : colorScheme.outline;

          final contentColor = isSelected
              ? selectedColor
              : colorScheme.onSurfaceVariant;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == tabs.length - 1 ? 0 : 8),
              child: GestureDetector(
                onTap: () => onTabTap(index),
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    // 탭 버튼 배경도 시스템 테마를 따라감
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(tabs[index].icon, color: contentColor, size: 24),
                      const SizedBox(height: 4),
                      Text(
                        tabs[index].label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: contentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
