import 'package:flutter/material.dart';

// TabProvider는 현재 선택된 탭의 인덱스를 관리하는 ChangeNotifier 클래스.
class TabProvider extends ChangeNotifier {
  static const int homeIndex = -1; // 홈 탭의 인덱스. -1로 설정됨.
  static const int firstTabIndex = 0; // 첫 번째 탭의 인덱스. 0으로 설정됨.
  static const int tabCount = 3;  // 총 탭의 개수. 3으로 설정됨.

  // 현재 선택된 탭의 인덱스를 나타내는 변수. 초기값은 homeIndex로 설정됨.
  int _selectedIndex = homeIndex;
  // 현재 선택된 탭의 인덱스를 반환하는 getter.
  int get selectedIndex => _selectedIndex;
  // 현재 선택된 탭이 홈 탭인지 여부를 반환하는 getter.
  bool get isHomeSelected => _selectedIndex == homeIndex;

  // 선택된 탭을 변경하는 메서드. 유효한 인덱스인지 확인 후, 선택된 탭을 변경하고 리스너에게 알림.
  void selectTab(int index) {
    if (!_isValidTabIndex(index)) {
      return;
    }
    // 선택된 탭이 이미 선택된 탭과 동일한 경우, 홈 탭으로 전환. 그렇지 않으면 해당 인덱스로 전환.
    final nextIndex = _selectedIndex == index ? homeIndex : index;

    if (_selectedIndex == nextIndex) {
      return;
    }

    _selectedIndex = nextIndex;
    notifyListeners();
  }
  
  bool isSelected(int index) {
    if (!_isValidTabIndex(index)) {
      return false;
    }

    return _selectedIndex == index;
  }

  bool _isValidTabIndex(int index) {
    return index >= firstTabIndex && index < tabCount;
  }
}
