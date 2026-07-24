import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tab_item.dart';
import '../providers/tab_provider.dart';
import '../widgets/bottom_tab_bar.dart';
import 'ai_chat_screen.dart';
import 'exchange_screen.dart';
import 'map_screen.dart';
import 'translation_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final tabProvider = context.watch<TabProvider>();
    final selectedIndex = tabProvider.selectedIndex;

    return Scaffold(
      backgroundColor: selectedIndex == -1
          ? Colors.white
          : tabs[selectedIndex].backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: getCurrentScreen(selectedIndex)),
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
