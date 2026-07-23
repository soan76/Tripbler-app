import 'package:flutter/material.dart';
import '../models/tab_item.dart';

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Colors.white,
      child: Row(
        children: List.generate(tabs.length, (index) {
          final bool isSelected = selectedIndex == index;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == tabs.length - 1 ? 0 : 8),
              child: GestureDetector(
                onTap: () => onTabTap(index),
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey.shade400,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        tabs[index].icon,
                        color: isSelected ? Colors.blue : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tabs[index].label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? Colors.blue : Colors.grey,
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
