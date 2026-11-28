import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule/schedule_data.dart';
import '../providers/schedule/schedule_provider.dart';
import '../utils/schedule/schedule_labels.dart';
import '../widgets/schedule/schedule_impact_dialog.dart';
import '../widgets/schedule/schedule_sheet_parts.dart';

/// 일정 보관함(docs/mockups/schedule.md 4절 "보관함", 목업 schedule-backup.html).
///
/// 타임라인에서 뺀 일정을 보관한 시각이 최근인 것부터 보인다. 항목을 누르면 `삭제 | 다시 꺼내기`.
/// 자동으로 지우지 않는다.
class ScheduleArchiveScreen extends ConsumerWidget {
  const ScheduleArchiveScreen({super.key});

  static const String title = '보관함';
  static const String emptyMessage = '보관한 일정이 없어요';

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ScheduleArchiveScreen()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(scheduleProvider.select((s) => s.archived));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sorted = [...archived]
      ..sort((a, b) => b.archivedAt.compareTo(a.archivedAt));

    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: sorted.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      emptyMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '일정을 누르고 "보관함으로 이동"을 고르면 여기에 모여요.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Text(
                    '타임라인에서 뺀 일정이에요. 직접 지우기 전까지 그대로 남아요.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final entry in sorted) ...[
                  _ArchivedRow(
                    entry: entry,
                    onTap: () => _openEntry(context, ref, entry),
                  ),
                  Divider(height: 1, color: colorScheme.outlineVariant),
                ],
              ],
            ),
    );
  }

  Future<void> _openEntry(
    BuildContext context,
    WidgetRef ref,
    ArchivedScheduleItem entry,
  ) async {
    final action = await ScheduleSheetFrame.show<_ArchiveAction>(
      context,
      (_) => _ArchivedSheet(entry: entry),
    );
    if (action == null || !context.mounted) return;
    final notifier = ref.read(scheduleProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    void show(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    if (action == _ArchiveAction.unarchive) {
      try {
        await notifier.unarchive(entry.item.id);
        show('타임라인으로 다시 꺼냈어요');
      } catch (_) {
        show('다시 꺼내지 못했어요. 다시 시도해 주세요');
      }
      return;
    }

    final item = entry.item;
    final confirmed = await confirmScheduleImpact(
      context,
      title: '보관함의 "${item.title}"을(를) 삭제할까요?',
      lines: [
        ScheduleImpactLine('${ScheduleLabels.dateTime(item.startsAt)} 일정이에요.'),
        const ScheduleImpactLine('보관함에서만 지워져요. 지금 타임라인의 일정은 바뀌지 않아요.'),
        const ScheduleImpactLine(
          '삭제한 일정은 되돌릴 수 없어요. 백업에 있으면 백업에서 되살릴 수 있어요.',
          warning: true,
        ),
      ],
      confirmLabel: '삭제',
    );
    if (!confirmed) return;
    try {
      await notifier.deleteArchived(item.id);
      show('보관함에서 삭제했어요');
    } catch (_) {
      show('삭제하지 못했어요. 다시 시도해 주세요');
    }
  }
}

enum _ArchiveAction { unarchive, delete }

class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.entry, required this.onTap});

  final ArchivedScheduleItem entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final item = entry.item;
    final archivedAt = ScheduleLabels.dateTime(entry.archivedAt);
    // 낭독기는 일정 시각·제목·보관 시각을 한 버튼으로 읽는다.
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: '삭제하거나 다시 꺼내기',
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ScheduleLabels.dateTime(item.startsAt),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(item.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '$archivedAt에 보관',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchivedSheet extends StatelessWidget {
  const _ArchivedSheet({required this.entry});

  final ArchivedScheduleItem entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = entry.item;
    final place = item.place;
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    );
    return ScheduleSheetFrame(
      title: item.title,
      rows: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              // 목록 줄과 같은 위계: 일정 시각(강조색) → 장소 → 메모 → 보관 시각.
              Text(
                ScheduleLabels.dateTime(item.startsAt),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              if (place != null) Text(place.name, style: style),
              if (item.memo.isNotEmpty)
                Text(
                  item.memo,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              Text(
                '${ScheduleLabels.dateTime(entry.archivedAt)}에 보관',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
      footer: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(_ArchiveAction.delete),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error),
            shape: buttonShape,
          ),
          child: const Text('삭제'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ArchiveAction.unarchive),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: buttonShape,
          ),
          child: const Text('다시 꺼내기'),
        ),
      ],
    );
  }
}
