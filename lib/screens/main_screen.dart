import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tab_item.dart';
import '../providers/tab_provider.dart';
import '../widgets/bottom_tab_bar.dart';
import '../widgets/navigation/app_drawer.dart';
import '../widgets/navigation/app_top_bar.dart';

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
    TabItem(
      label: '맵',
      icon: Icons.map,
      backgroundColor: Color(0xFFFFCC80),
    ),
    TabItem(
      label: '번역',
      icon: Icons.translate,
      backgroundColor: Color(0xFFC5E1A5),
    ),
  ];

  // 현재 선택된 화면 이름
  String _getScreenTitle(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return '환율';

      case 1:
        return '맵';

      case 2:
        return '번역';

      default:
        return 'AI 채팅';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabProvider = context.watch<TabProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    final selectedIndex = tabProvider.selectedIndex;

    final isValidTabIndex =
        selectedIndex >= TabProvider.firstTabIndex &&
        selectedIndex < tabs.length;

    final stackIndex = isValidTabIndex ? selectedIndex : tabs.length;

    final screenTitle = _getScreenTitle(selectedIndex);

    return Scaffold(
      backgroundColor: colorScheme.surface,

      // 공통 Navigation Drawer
      drawer: const AppDrawer(),

      body: SafeArea(
        child: Column(
          children: [
            // 모든 화면에 표시되는 90px 공통 상단 영역
            AppTopBar(
              title: screenTitle,
            ),

            // 현재 기능 화면
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

            // 기존 하단 탭
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