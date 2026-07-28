import 'package:flutter/material.dart';

// 하단 내비게이션 바 또는 탭 메뉴의 정보를 저장하는 클래스
class TabItem {
  final String label;
  final IconData icon;
  final Color backgroundColor;

  const TabItem({
    required this.label,
    required this.icon,
    required this.backgroundColor,
  });
}
