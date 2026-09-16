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
    TabItem(label: '환율', icon: Icons.attach_money),
    TabItem(label: '지도', icon: Icons.map),
    TabItem(label: '번역', icon: Icons.translate),
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
        child: Stack(
          children: [
            Column(
              children: [
                AppTopBar(title: screenTitle),

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
              ],
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomTabBar(
                tabs: tabs,
                selectedIndex: selectedIndex,
                isHomeSelected: tabProvider.isHomeSelected,
                onTabTap: tabProvider.selectTab,
                onHomeTap: tabProvider.selectHome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
