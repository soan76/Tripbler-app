import 'package:flutter/material.dart';

class TabProvider extends ChangeNotifier {
  int _selectedIndex = -1;

  int get selectedIndex => _selectedIndex;

  void selectTab(int index) {
    if (_selectedIndex == index) {
      _selectedIndex = -1;
    } else {
      _selectedIndex = index;
    }

    notifyListeners();
  }

  bool isSelected(int index) {
    return _selectedIndex == index;
  }

  bool get isHomeSelected {
    return _selectedIndex == -1;
  }
}
