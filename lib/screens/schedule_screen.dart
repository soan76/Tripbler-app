import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule/schedule_item.dart';
import '../providers/schedule/schedule_backup_provider.dart';
import '../providers/schedule/schedule_provider.dart';
import '../widgets/schedule/schedule_editor_sheet.dart';
import '../widgets/schedule/schedule_timeline.dart';
import 'schedule_backup_screen.dart';

/// 일정 탭(docs/mockups/schedule.md 2절): 빈 상태, 세로 타임라인, 입력 카드·수정 화면 열기.
///
/// 저장·검사는 [scheduleProvider]·scheduleDraftProvider가 맡고 이 화면은 표시와 입력만 한다.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  static const String emptyMessage = '첫 일정을 추가해 보세요';
  static const String loadFailedMessage = '일정을 불러오지 못했어요';
  static const String unreadNotice = '읽지 못한 일정이 있어요';

  /// 아래 가운데 하단 메뉴 점에 목록 끝이 가리지 않게 두는 여백.
  static const double bottomMenuClearance = 72;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// 방금 추가하거나 수정한 일정. 강조 움직임이 끝나면 지운다.
  String? _highlightId;
  ScheduleHighlight _highlight = ScheduleHighlight.added;
  Timer? _highlightTimer;

  /// 입력 카드·수정 화면이 열려 있는지(두 번 눌러 겹쳐 열리지 않게).
  bool _sheetOpen = false;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _add() async {
    if (_sheetOpen || !ref.read(scheduleProvider).isReady) return;
    _sheetOpen = true;
    final saved = await ScheduleEditorSheet.open(context, ref);
    _sheetOpen = false;
    _showHighlight(saved, ScheduleHighlight.added);
  }

  /// 저장한 일정을 누르면 값이 채워진 수정 화면을 연다.
  Future<void> _edit(ScheduleItem item) async {
    if (_sheetOpen || !ref.read(scheduleProvider).isReady) return;
    _sheetOpen = true;
    final saved = await ScheduleEditorSheet.openEdit(context, ref, item);
    _sheetOpen = false;
    _showHighlight(saved, ScheduleHighlight.edited);
  }

  /// 길게 눌러 끌어 놓은 자리로 순서를 바꾼다. 날짜·시간은 그대로다.
  Future<void> _move(ScheduleItem item, int to) async {
    try {
      await ref.read(scheduleProvider.notifier).move(item.id, to);
      _showHighlight(item, ScheduleHighlight.edited);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('순서를 바꾸지 못했어요. 다시 시도해 주세요')),
        );
    }
  }

  /// 읽지 못한 일정 알림 `확인`: 확인한 것으로 기억하고 기기 백업 목록을 연다.
  Future<void> _openUnread() async {
    final backups = ref.read(scheduleBackupProvider.notifier);
    final open = ScheduleBackupScreen.open(context);
    try {
      await backups.markAutoSeen();
    } catch (_) {}
    await open;
  }

  /// 알림 닫기: 확인한 것으로 기억한다(앱을 다시 켜도 다시 띄우지 않는다).
  Future<void> _closeUnread() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(scheduleBackupProvider.notifier).markAutoSeen();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('일정 백업에서 언제든 다시 볼 수 있어요')));
    } catch (_) {}
  }

  void _showHighlight(ScheduleItem? saved, ScheduleHighlight highlight) {
    if (saved == null || !mounted) return;
    _highlightTimer?.cancel();
    setState(() {
      _highlightId = saved.id;
      _highlight = highlight;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(
      scheduleBackupProvider.select((s) => s.hasUnseenAuto),
    );
    // 알림이 생기거나 사라져도 본문(타임라인)은 같은 자리의 같은 위젯으로 남아, 스크롤
    // 위치와 진행 중인 강조가 그대로다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unread) _UnreadNotice(onOpen: _openUnread, onClose: _closeUnread),
        Expanded(key: const ValueKey('schedule-body'), child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final state = ref.watch(scheduleProvider);
    switch (state.status) {
      case ScheduleLoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ScheduleLoadStatus.failed:
        return _LoadFailedView(
          onRetry: ref.read(scheduleProvider.notifier).retry,
        );
      case ScheduleLoadStatus.ready:
        if (state.items.isEmpty) return _EmptyView(onAdd: _add);
        return ScheduleTimeline(
          items: state.items,
          now: ref.read(scheduleClockProvider)(),
          highlightId: _highlightId,
          highlight: _highlight,
          bottomPadding: ScheduleScreen.bottomMenuClearance,
          onOpen: _edit,
          onAdd: _add,
          onMove: _move,
        );
    }
  }
}

/// 일정이 없을 때: 가운데 큰 `+`와 안내.
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          24,
          24,
          24,
          ScheduleScreen.bottomMenuClearance,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: colorScheme.primary,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                key: const ValueKey('schedule-add-first'),
                customBorder: const CircleBorder(),
                onTap: onAdd,
                child: SizedBox.square(
                  dimension: 72,
                  child: Icon(
                    Icons.add,
                    size: 36,
                    color: colorScheme.onPrimary,
                    semanticLabel: '일정 추가',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              ScheduleScreen.emptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailedView extends StatelessWidget {
  const _LoadFailedView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          24,
          24,
          24,
          ScheduleScreen.bottomMenuClearance,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ScheduleScreen.loadFailedMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 읽지 못해 보관한 백업이 있을 때 일정 화면 위에 두는 알림. `확인`은 기기 백업 목록으로 간다.
class _UnreadNotice extends StatelessWidget {
  const _UnreadNotice({required this.onOpen, required this.onClose});

  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      container: true,
      child: Material(
        color: colorScheme.primaryContainer,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  // 알림 문구 자체를 알림 영역으로 둬 낭독기가 나타날 때 이 문장을 읽는다
                  // (이름 없는 묶음에 두면 읽을 글자가 없다).
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      ScheduleScreen.unreadNotice,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('schedule-unread-open'),
                  onPressed: onOpen,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('확인', semanticsLabel: '기기 백업에서 확인'),
                ),
                IconButton(
                  key: const ValueKey('schedule-unread-close'),
                  onPressed: onClose,
                  tooltip: '알림 닫기',
                  color: colorScheme.onPrimaryContainer,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
