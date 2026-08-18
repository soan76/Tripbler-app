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

    // 선택 상태의 의미 강조색은 기존 파란색 유지
    const selectedColor = Colors.blue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),

      // 현재 앱 테마의 배경색 사용
      color: colorScheme.surface,

      child: Row(
        children: List.generate(tabs.length, (index) {
          final bool isSelected = selectedIndex == index;

          // 선택된 탭은 파란색,
          // 선택되지 않은 탭은 현재 테마의 outline 색상 사용
          final Color borderColor = isSelected
              ? selectedColor
              : colorScheme.outlineVariant;

          // 선택된 탭은 파란색,
          // 선택되지 않은 탭은 현재 테마의 보조 텍스트 색상 사용
          final Color contentColor = isSelected
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
                    // 라이트 / 다크 모드 자동 대응
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
