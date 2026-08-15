import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tab_item.dart';
import '../providers/tab_provider.dart';
import '../widgets/bottom_tab_bar.dart';
import 'ai_chat_screen.dart';
import 'exchange_screen.dart';
import 'map_screen.dart';
import 'translation_screen.dart';

// 메인 화면을 구성하는 StatelessWidget
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  static const List<TabItem> tabs = [
    TabItem(
      label: '환율',
      icon: Icons.attach_money,
      backgroundColor: Color(0xFFB3E5FC),
    ),
    TabItem(label: '맵', icon: Icons.map, backgroundColor: Color(0xFFFFCC80)),
    TabItem(
      label: '번역',
      icon: Icons.translate,
      backgroundColor: Color(0xFFC5E1A5),
    ),
  ];

  // 선택된 탭 인덱스에 따라 해당 화면을 반환하는 메서드
  Widget getCurrentScreen(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return const ExchangeScreen();
      case 1:
        return const MapScreen();
      case 2:
        return const TranslationScreen();
      default:
        return const AiChatScreen();
    }
  }

  // 메인 화면을 구성하는 위젯 트리를 반환하는 build 메서드
  @override
  Widget build(BuildContext context) {
    final tabProvider = context.watch<TabProvider>();
    final selectedIndex = tabProvider.selectedIndex;
    // 선택된 탭 인덱스가 유효한지 확인
    final isValidTabIndex =
        selectedIndex >= TabProvider.firstTabIndex &&
        selectedIndex < tabs.length;

    final stackIndex = isValidTabIndex ? selectedIndex : tabs.length;

    final backgroundColor = isValidTabIndex
        ? tabs[selectedIndex].backgroundColor
        : Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: stackIndex,
                children: const [
                  ExchangeScreen(),
                  MapScreen(),
                  TranslationScreen(),
                  AiChatScreen(),
                ],
              ),
            ),
            BottomTabBar(
              tabs: tabs,
              selectedIndex: selectedIndex,
              onTabTap: tabProvider.selectTab,
            ),
          ],
        ),
      ),
    );
  }
}
