import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tab_item.dart';
import '../providers/auth/auth_provider.dart';
import '../providers/tab_provider.dart';
import '../widgets/auth/session_restore_banner.dart';
import '../widgets/bottom_tab_bar.dart';
import '../widgets/navigation/app_drawer.dart';
import '../widgets/navigation/app_top_bar.dart';
import '../widgets/navigation/navigation_capture_controller.dart';

import 'coming_soon_screen.dart';
import 'duty_free_screen.dart';
import 'exchange_screen.dart';
import 'map_screen.dart';
import 'photo_translation_screen.dart';
import 'schedule_archive_screen.dart';
import 'schedule_backup_screen.dart';
import 'schedule_screen.dart';

// 메인 화면을 구성하는 StatelessWidget
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();

  static const List<TabItem> tabs = [
    TabItem(label: '환율', icon: Icons.attach_money),
    TabItem(label: '지도', icon: Icons.map),
    TabItem(label: '번역', icon: Icons.translate),
    // 확장 메뉴(bottom-nav.md 10절).
    TabItem(label: '일정', icon: Icons.event_note),
    TabItem(label: '면세', icon: Icons.shopping_bag),
  ];
}

class _MainScreenState extends ConsumerState<MainScreen> {
  static const int _scheduleTabIndex = 3;

  final _capture = NavigationCaptureController();
  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  // 현재 선택된 화면 이름
  String _getScreenTitle(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return '환율';

      case 1:
        return '맵';

      case 2:
        return '번역';

      case 3:
        return '일정';

      case 4:
        return '면세';

      default:
        return 'AI';
    }
  }

  @override
  Widget build(BuildContext context) {
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
        selectedIndex >= TabState.firstTabIndex &&
        selectedIndex < MainScreen.tabs.length;

    final stackIndex = isValidTabIndex ? selectedIndex : MainScreen.tabs.length;

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
                // 번역 촬영 화면(기존·사진 번역 모두)은 카메라가 화면 전체를 채우고 위에 "Tripbler"를 두므로 상단 바를 숨긴다
                // (목업 translation-camera.html). 앱 서랍은 화면 가장자리에서 끌어 연다.
                ValueListenableBuilder<bool>(
                  valueListenable: _capture.cameraScreen,
                  builder: (context, cameraScreen, child) =>
                      selectedIndex == 2 && cameraScreen
                      ? const SizedBox.shrink()
                      : child!,
                  child: AppTopBar(
                    title: screenTitle,
                    // 일정 탭: 보관함·백업(docs/mockups/schedule.md 4절).
                    actions: selectedIndex == _scheduleTabIndex
                        ? [
                            IconButton(
                              key: const ValueKey('schedule-open-archive'),
                              tooltip: ScheduleArchiveScreen.title,
                              onPressed: () =>
                                  ScheduleArchiveScreen.open(context),
                              icon: const Icon(Icons.inventory_2_outlined),
                            ),
                            IconButton(
                              key: const ValueKey('schedule-open-backup'),
                              tooltip: ScheduleBackupScreen.title,
                              onPressed: () =>
                                  ScheduleBackupScreen.open(context),
                              icon: const Icon(Icons.history),
                            ),
                          ]
                        : const [],
                  ),
                ),

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
                    children: [
                      const ExchangeScreen(),
                      const MapScreen(),
                      // 번역 탭은 늘 사진 번역 화면(찍은 사진 위 흰 상자 결과)이다. 번역 방식(기기 읽기 + 글자 번역,
                      // 사진 AI 번역, 개발용 가짜)은 photoAiTranslationProvider·photoFakeTranslationProvider가 정한다.
                      PhotoTranslationScreen(navigationCapture: _capture),
                      const ScheduleScreen(),
                      const DutyFreeScreen(),
                      // AI 버튼(홈)은 화면을 정하기 전까지 준비 중 화면을 보여 준다.
                      const ComingSoonScreen(title: 'AI'),
                    ],
                  ),
                ),
              ],
            ),

            // 하단 메뉴는 펼치면 배경이 화면 전체로 커지므로 본문 전체 크기를 받는다(빈 곳은 아래 화면이 받는다).
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  _capture.action,
                  _capture.busy,
                  _capture.cameraScreen,
                ]),
                builder: (context, _) => BottomTabBar(
                  tabs: MainScreen.tabs,
                  selectedIndex: selectedIndex,
                  isHomeSelected: tabState.isHomeSelected,
                  onTabTap: ref.read(tabProvider.notifier).selectTab,
                  onHomeTap: ref.read(tabProvider.notifier).selectHome,
                  onCurrentScreenTap: selectedIndex == 2
                      ? _capture.action.value
                      : null,
                  isCapturing: selectedIndex == 2 && _capture.busy.value,
                  isCaptureScreen:
                      selectedIndex == 2 && _capture.cameraScreen.value,
                  // 번역 화면은 사진·미리보기를 만지는 일이 잦아 바깥 누르기로 메뉴를 접지 않는다.
                  alwaysShowIcon: selectedIndex == 2,
                  onExpansionChanged: (value) =>
                      _capture.expansion.value = value,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
