import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider;

/// 현재 선택된 하단 탭.
class TabState {
  const TabState({this.selectedIndex = homeIndex});

  static const int homeIndex = -1; // 홈 탭의 인덱스.
  static const int firstTabIndex = 0; // 첫 번째 탭의 인덱스.
  /// 총 탭의 개수: 환율 0·지도 1·번역 2·일정 3·면세 4(bottom-nav.md 10-5절).
  static const int tabCount = 5;

  /// 선택된 탭의 인덱스. 홈이면 [homeIndex].
  final int selectedIndex;

  bool get isHomeSelected => selectedIndex == homeIndex;

  bool isSelected(int index) {
    if (!isValidTabIndex(index)) {
      return false;
    }

    return selectedIndex == index;
  }

  static bool isValidTabIndex(int index) {
    return index >= firstTabIndex && index < tabCount;
  }

  TabState copyWith({int? selectedIndex}) {
    return TabState(selectedIndex: selectedIndex ?? this.selectedIndex);
  }
}

class TabNotifier extends Notifier<TabState> {
  @override
  TabState build() => const TabState();

  /// 유효한 인덱스만 받는다. 이미 선택된 탭은 그대로 유지한다.
  void selectTab(int index) {
    if (!TabState.isValidTabIndex(index)) {
      return;
    }

    _select(index);
  }

  /// AI/Home 화면으로 직접 이동한다.
  void selectHome() => _select(TabState.homeIndex);

  void _select(int index) {
    if (state.selectedIndex == index) {
      return;
    }

    state = state.copyWith(selectedIndex: index);
  }
}

final tabProvider = NotifierProvider<TabNotifier, TabState>(TabNotifier.new);
