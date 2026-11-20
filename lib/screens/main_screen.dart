import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tab_item.dart';
import '../providers/auth/auth_provider.dart';
import '../providers/tab_provider.dart';
import '../widgets/auth/session_restore_banner.dart';
import '../widgets/bottom_tab_bar.dart';
import '../widgets/navigation/app_drawer.dart';
import '../widgets/navigation/app_top_bar.dart';

import 'ai_chat_screen.dart';
import 'exchange_screen.dart';
import 'map_screen.dart';
import 'translation_screen.dart';

// 메인 화면을 구성하는 StatelessWidget
class MainScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tabState = ref.watch(tabProvider);
    // 세션 복구 배너에 쓰는 값만 읽는다. 배너가 없을 때의 로딩 변경이나 닉네임 같은
    // 다른 인증 필드가 바뀔 때는 화면 전체(탭 스택)를 다시 그리지 않는다.
    final restoreBanner = ref.watch(
      authProvider.select(
        (auth) => (
          show: auth.sessionRestoreFailed,
          retrying: auth.sessionRestoreFailed && auth.isLoading,
        ),
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;

    final selectedIndex = tabState.selectedIndex;

    final isValidTabIndex =
        selectedIndex >= TabState.firstTabIndex && selectedIndex < tabs.length;

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

                // 세션 만료가 확인되지 않은 오류로 세션 복구에 실패하면 상단 바 아래에서 다시 시도를 안내한다.
                if (restoreBanner.show)
                  SessionRestoreBanner(
                    isRetrying: restoreBanner.retrying,
                    onRetry: ref
                        .read(authProvider.notifier)
                        .retryRestoreSession,
                  ),

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
                isHomeSelected: tabState.isHomeSelected,
                onTabTap: ref.read(tabProvider.notifier).selectTab,
                onHomeTap: ref.read(tabProvider.notifier).selectHome,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
