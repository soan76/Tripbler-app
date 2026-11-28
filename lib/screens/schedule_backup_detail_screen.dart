import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/schedule/schedule_backup_rules.dart';
import '../models/schedule/schedule_data.dart';
import '../models/schedule/schedule_item.dart';
import '../providers/schedule/schedule_backup_provider.dart';
import '../providers/schedule/schedule_provider.dart';
import '../utils/schedule/schedule_labels.dart';

/// 백업에서 고른 일정만 되살리는 화면(docs/mockups/schedule.md 4절 "복원").
///
/// 지금 일정·보관함에 이미 있는 일정은 표시하고 처음엔 고르지 않는다. 고른 일정만 지금
/// 타임라인에 더하고, 백업은 그대로 남는다. 일정을 불러오지 못한 상태에서는 되살리기를 막는다.
class ScheduleBackupDetailScreen extends ConsumerStatefulWidget {
  const ScheduleBackupDetailScreen({super.key, required this.entryId});

  final String entryId;

  static const String blockedLabel = '일정을 불러온 뒤에 되살릴 수 있어요';

  static Future<void> open(BuildContext context, String entryId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduleBackupDetailScreen(entryId: entryId),
        ),
      );

  @override
  ConsumerState<ScheduleBackupDetailScreen> createState() =>
      _ScheduleBackupDetailScreenState();
}

class _ScheduleBackupDetailScreenState
    extends ConsumerState<ScheduleBackupDetailScreen> {
  /// 고른 일정 id. 처음 열 때 이미 있는 일정을 뺀 나머지를 고른다.
  Set<String>? _selected;
  bool _restoring = false;

  Set<String> _initialSelection(ScheduleBackupEntry entry, ScheduleData now) =>
      {
        for (final item in entry.items)
          if (ScheduleBackupRules.match(now, item) == ScheduleRestoreMatch.none)
            item.id,
      };

  Future<void> _restore(Set<String> ids) async {
    setState(() => _restoring = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final count = await ref
          .read(scheduleBackupProvider.notifier)
          .restore(widget.entryId, ids);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('일정 $count개를 되살렸어요 · 백업은 그대로 남아요')),
        );
      // 백업 목록과 이 화면을 닫고 일정 화면으로 돌아간다.
      navigator.popUntil((route) => route.isFirst);
    } catch (_) {
      if (!mounted) return;
      setState(() => _restoring = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('되살리지 못했어요. 다시 시도해 주세요')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(
      scheduleBackupProvider.select((s) => s.byId(widget.entryId)),
    );
    final schedule = ref.watch(scheduleProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final note = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final title = entry == null
        ? '기기 백업'
        : '기기 백업 · ${ScheduleLabels.dateTime(entry.backup.savedAt)}';

    if (entry == null || !entry.isReadable) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              entry == null
                  ? '이 백업이 없어요.'
                  : entry.read.status == ScheduleReadStatus.newerVersion
                  ? '새 버전 앱에서 만든 형식이라 이 버전에서는 읽을 수 없어요.\n앱을 업데이트하면 되살릴 수 있어요. 백업은 그대로 보관해요.'
                  : '내용이 손상돼 읽을 수 있는 일정이 없어요.\n필요 없으면 목록에서 삭제할 수 있어요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    final data = schedule.data;
    final selected = _selected ??= _initialSelection(entry, data);
    final items = [...entry.items]..sort(ScheduleItem.compare);
    final duplicates = items
        .where(
          (i) =>
              ScheduleBackupRules.match(data, i) != ScheduleRestoreMatch.none,
        )
        .length;
    final blocked = !schedule.isReady;
    final count = selected.length;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  '되살릴 일정을 고르세요. 고른 일정만 지금 일정에 더하고, 백업은 그대로 남아요.',
                  style: note,
                ),
                if (duplicates > 0)
                  Text('이미 있는 일정 $duplicates개는 처음에 고르지 않았어요.', style: note),
                if (entry.read.unreadable > 0)
                  Text(
                    '읽지 못한 항목 ${entry.read.unreadable}개는 되살릴 수 없어요.',
                    style: note?.copyWith(color: colorScheme.error),
                  ),
              ],
            ),
          ),
          for (final item in items) ...[
            Divider(height: 1, color: colorScheme.outlineVariant),
            _PickRow(
              item: item,
              match: ScheduleBackupRules.match(data, item),
              selected: selected.contains(item.id),
              onChanged: _restoring
                  ? null
                  : (on) => setState(
                      () =>
                          on ? selected.add(item.id) : selected.remove(item.id),
                    ),
            ),
          ],
        ],
      ),
      // 목록과 하단 버튼을 구분선으로 나눈다(목업 .foot).
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const ValueKey('schedule-backup-restore'),
              onPressed: blocked || count == 0 || _restoring
                  ? null
                  : () => _restore({...selected}),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Text(
                blocked
                    ? ScheduleBackupDetailScreen.blockedLabel
                    : _restoring
                    ? '되살리는 중'
                    : count > 0
                    ? '선택한 일정 되살리기 ($count)'
                    : '선택한 일정 되살리기',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.item,
    required this.match,
    required this.selected,
    required this.onChanged,
  });

  final ScheduleItem item;
  final ScheduleRestoreMatch match;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chip = switch (match) {
      ScheduleRestoreMatch.inTimeline => '이미 있음',
      ScheduleRestoreMatch.inArchive => '보관함에 있음',
      ScheduleRestoreMatch.none => null,
    };
    final place = item.place;
    return CheckboxListTile(
      value: selected,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ScheduleLabels.dateTime(item.startsAt),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          Text(item.title, style: theme.textTheme.titleMedium),
          if (place != null)
            Text(
              place.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      secondary: chip == null
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  chip,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
    );
  }
}
