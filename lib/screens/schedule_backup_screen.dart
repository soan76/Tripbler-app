import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule/schedule_data.dart';
import '../providers/schedule/schedule_backup_provider.dart';
import '../providers/schedule/schedule_provider.dart';
import '../services/schedule/schedule_backup_store.dart';
import '../utils/schedule/schedule_labels.dart';
import '../widgets/schedule/schedule_impact_dialog.dart';
import 'schedule_backup_detail_screen.dart';

/// 일정 기기 백업 목록(docs/mockups/schedule.md 4절, 목업 schedule-backup.html).
///
/// `지금 백업`으로 지금 일정의 복사본을 만들고(직접 백업 최근 3개), 줄을 누르면 고른 일정만
/// 되살린다. 줄마다 `삭제`, 위에 `전체 삭제`. 서버 백업은 다음 단계다.
class ScheduleBackupScreen extends ConsumerWidget {
  const ScheduleBackupScreen({super.key});

  static const String title = '일정 백업';

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ScheduleBackupScreen()));

  static void _show(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  /// 백업 한 줄의 내용 안내.
  static String summary(ScheduleBackupEntry entry) {
    return switch (entry.read.status) {
      ScheduleReadStatus.newerVersion => '새 버전 앱에서 만든 형식이라 이 버전에서는 읽을 수 없어요',
      ScheduleReadStatus.corrupt => '내용이 손상돼 읽을 수 없어요',
      ScheduleReadStatus.ok =>
        '되살릴 수 있는 일정 ${entry.items.length}개'
            '${entry.read.unreadable > 0 ? ' · 읽지 못한 항목 ${entry.read.unreadable}개' : ''}',
    };
  }

  /// 지울 백업의 영향 안내(목업 deleteLines).
  static List<ScheduleImpactLine> deleteImpact(
    ScheduleBackupNotifier notifier,
    List<ScheduleBackupEntry> entries,
  ) {
    final lost = notifier.lostIfDeleted({for (final e in entries) e.id});
    return [
      const ScheduleImpactLine('지금 일정과 보관함은 바뀌지 않아요.'),
      if (entries.every((e) => !e.isReadable))
        const ScheduleImpactLine('읽을 수 있는 일정이 없는 백업이라 되살릴 내용은 없어요.')
      else if (lost.isEmpty)
        const ScheduleImpactLine(
          '여기 있는 일정은 모두 지금 일정·보관함·다른 백업에 남아 있어 잃는 일정은 없어요.',
        )
      else
        ScheduleImpactLine(
          '이 백업에만 있는 일정 ${lost.length}개(${lost.take(2).map((i) => i.title).join(', ')}'
          '${lost.length > 2 ? ' 등' : ''})는 다시 되살릴 수 없게 돼요.',
          warning: true,
        ),
      if (entries.any((e) => e.isAuto))
        const ScheduleImpactLine('읽지 못해 보관한 원래 내용도 함께 사라져요.', warning: true),
      const ScheduleImpactLine('삭제한 백업은 되돌릴 수 없어요.'),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(scheduleBackupProvider);
    final schedule = ref.watch(scheduleProvider);
    final notifier = ref.read(scheduleBackupProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final note = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final failed = schedule.status == ScheduleLoadStatus.failed;
    final hasItems = schedule.items.isNotEmpty || schedule.archived.isNotEmpty;
    final same = notifier.isSameAsLastManual(schedule);
    final ready = backups.status == ScheduleBackupLoadStatus.ready;
    final canBackup = ready && schedule.isReady && hasItems && !same;
    final entries = backups.entries;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    );
    // 폭 320·큰 글자에서도 두 버튼 이름이 들어가게 옆 여백을 줄인다.
    const buttonPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    Future<void> backupNow() async {
      final out = notifier.rotatedOut;
      if (out != null) {
        final ok = await confirmScheduleImpact(
          context,
          title: '직접 백업이 이미 ${ScheduleBackupStore.maxManual}개예요',
          lines: [
            ScheduleImpactLine(
              '새로 만들면 가장 오래된 직접 백업(${ScheduleLabels.dateTime(out.backup.savedAt)}, '
              '${summary(out)})이 지워져요.',
            ),
            ...deleteImpact(notifier, [out]).skip(1).take(1),
            const ScheduleImpactLine('읽지 못해 보관한 백업과 지금 일정은 바뀌지 않아요.'),
          ],
          confirmLabel: '백업하고 지우기',
        );
        if (!ok || !context.mounted) return;
      }
      try {
        await notifier.backupNow();
        if (context.mounted) _show(context, '이 기기에 일정을 백업했어요');
      } catch (_) {
        if (context.mounted) _show(context, '백업하지 못했어요. 다시 시도해 주세요');
      }
    }

    Future<void> delete(List<ScheduleBackupEntry> targets) async {
      final ok = await confirmScheduleImpact(
        context,
        title: targets.length > 1
            ? '기기 백업 ${targets.length}개를 모두 삭제할까요?'
            : '기기 백업 · ${ScheduleLabels.dateTime(targets.single.backup.savedAt)}을(를) 삭제할까요?',
        lines: deleteImpact(notifier, targets),
        confirmLabel: targets.length > 1 ? '모두 삭제' : '삭제',
      );
      if (!ok || !context.mounted) return;
      try {
        await notifier.delete({for (final e in targets) e.id});
        if (context.mounted) _show(context, '백업을 삭제했어요');
      } catch (_) {
        if (context.mounted) _show(context, '삭제하지 못했어요. 다시 시도해 주세요');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Text(
              '이 기기에만 저장돼요. 앱을 지우면 함께 사라져요. 직접 백업은 최근 '
              '${ScheduleBackupStore.maxManual}개까지 남아요. 읽지 못해 보관한 백업은 개수에 세지 않고, '
              '직접 지우기 전에는 지우지 않아요.',
              style: note,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('schedule-backup-now'),
                    onPressed: canBackup ? backupNow : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      padding: buttonPadding,
                      shape: buttonShape,
                    ),
                    child: const Text('지금 백업', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('schedule-backup-delete-all'),
                    onPressed: entries.isEmpty ? null : () => delete(entries),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      padding: buttonPadding,
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: entries.isEmpty
                            ? colorScheme.onSurface.withValues(alpha: 0.12)
                            : colorScheme.error,
                      ),
                      shape: buttonShape,
                    ),
                    child: const Text('전체 삭제', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
          if (failed || !hasItems || same)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 꺼진 `지금 백업`의 이유. 불러오기 실패는 색만이 아니라 아이콘으로도 구분한다.
                  Icon(
                    failed ? Icons.error_outline : Icons.info_outline,
                    size: 20,
                    color: failed
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      failed
                          ? '일정을 불러오지 못해 지금은 백업하거나 되살릴 수 없어요. 일정 화면에서 다시 시도해 주세요.'
                          : !hasItems
                          ? '백업할 일정이 없어요.'
                          : '지금 일정이 마지막 직접 백업과 같아요.',
                      style: failed
                          ? note?.copyWith(color: colorScheme.error)
                          : note,
                    ),
                  ),
                ],
              ),
            ),
          if (backups.status == ScheduleBackupLoadStatus.loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (backups.status == ScheduleBackupLoadStatus.failed)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(
                    '백업 목록을 읽지 못했어요',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: notifier.reload,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: buttonShape,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                ],
              ),
            )
          else if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(
                    '기기 백업이 없어요.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  // 백업할 수 있을 때만 다음 행동을 알린다(못 하면 위 안내가 이유를 말한다).
                  if (canBackup) ...[
                    const SizedBox(height: 4),
                    Text(
                      '지금 백업을 누르면 지금 일정의 복사본을 이 기기에 만들어요.',
                      textAlign: TextAlign.center,
                      style: note,
                    ),
                  ],
                ],
              ),
            )
          else ...[
            Divider(height: 1, color: colorScheme.outlineVariant),
            for (final entry in entries) ...[
              _BackupRow(
                entry: entry,
                onOpen: () =>
                    ScheduleBackupDetailScreen.open(context, entry.id),
                onDelete: () => delete([entry]),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
            ],
          ],
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  final ScheduleBackupEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stamp = ScheduleLabels.dateTime(entry.backup.savedAt);
    final tag = entry.isAuto ? '읽지 못해 보관' : '직접 백업';
    return Row(
      children: [
        Expanded(
          // 낭독기는 시각·표시·요약을 한 버튼으로 읽는다(삭제 버튼은 따로).
          child: MergeSemantics(
            child: Semantics(
              button: true,
              child: InkWell(
                onTap: onOpen,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(stamp, style: theme.textTheme.titleMedium),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: entry.isAuto
                                    ? colorScheme.errorContainer
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                child: Text(
                                  tag,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: entry.isAuto
                                        ? colorScheme.onErrorContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ScheduleBackupScreen.summary(entry),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                entry.isReadable && entry.read.unreadable == 0
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: colorScheme.error,
            ),
            child: Text('삭제', semanticsLabel: '$stamp 백업 삭제'),
          ),
        ),
      ],
    );
  }
}
