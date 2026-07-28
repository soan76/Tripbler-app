import 'package:flutter/material.dart';

// 탭 화면에서 선택된 탭의 상태를 관리
class TabProvider extends ChangeNotifier {
  int _selectedIndex = -1;

  int get selectedIndex => _selectedIndex;
  // 선택된 탭을 변경하는 메서드
  // 선택된 탭이 이미 선택된 상태라면 선택을 해제하고, 그렇지 않으면 해당 탭을 선택
  void selectTab(int index) {
    if (_selectedIndex == index) {
      _selectedIndex = -1;
    } else {
      _selectedIndex = index;
    }

    notifyListeners();
  }
  // 선택된 탭이 특정 인덱스와 일치하는지 확인하는 메서드
  bool isSelected(int index) {
    return _selectedIndex == index;
  }

  // 선택된 탭이 없는 상태인지 확인하는 메서드
  bool get isHomeSelected {
    return _selectedIndex == -1;
  }
}
