import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/schedule/schedule_backup_rules.dart';
import '../../models/schedule/schedule_data.dart';
import '../../models/schedule/schedule_item.dart';
import '../../services/schedule/schedule_backup_store.dart';
import '../../services/schedule/schedule_payload.dart';
import 'schedule_provider.dart';

/// 백업 하나와 그 원문을 읽은 결과.
class ScheduleBackupEntry {
  const ScheduleBackupEntry({required this.backup, required this.read});

  final ScheduleBackup backup;
  final ScheduleReadResult read;

  String get id => backup.id;
  bool get isAuto => backup.kind == ScheduleBackupKind.auto;
  bool get isReadable => read.status == ScheduleReadStatus.ok;

  /// 되살릴 수 있는 타임라인 일정.
  List<ScheduleItem> get items => read.data.items;
}

enum ScheduleBackupLoadStatus { loading, ready, failed }

/// 기기 백업 목록(새 것부터).
class ScheduleBackupState {
  const ScheduleBackupState({
    this.status = ScheduleBackupLoadStatus.loading,
    this.entries = const [],
  });

  final ScheduleBackupLoadStatus status;
  final List<ScheduleBackupEntry> entries;

  /// 아직 확인하지 않은 "읽지 못해 보관" 백업이 있는지(일정 화면 위 알림).
  bool get hasUnseenAuto => entries.any((e) => e.isAuto && !e.backup.seen);

  /// 가장 최근 직접 백업.
  ScheduleBackupEntry? get lastManual =>
      entries.where((e) => !e.isAuto).firstOrNull;

  ScheduleBackupEntry? byId(String id) =>
      entries.where((e) => e.id == id).firstOrNull;
}

/// 기기 백업: 지금 백업, 선택 되살리기, 삭제, 읽지 못한 일정 알림 확인
/// (docs/mockups/schedule.md 4절, 목업 schedule-backup.html). 서버 백업은 다음 단계다.
///
/// 일정을 다 불러온 뒤(읽지 못한 값을 보관한 뒤) 목록을 읽는다. 일정을 불러오지 못한 상태에서는
/// 백업 만들기와 되살리기를 [StateError]로 막는다.
class ScheduleBackupNotifier extends Notifier<ScheduleBackupState> {
  late ScheduleBackupStore _store;
  int _loadId = 0;

  @override
  ScheduleBackupState build() {
    _store = ref.read(scheduleBackupStoreProvider);
    final status = ref.watch(scheduleProvider.select((s) => s.status));
    if (status != ScheduleLoadStatus.loading) reload();
    return const ScheduleBackupState();
  }

  /// 목록을 다시 읽는다.
  Future<void> reload() async {
    final loadId = ++_loadId;
    try {
      final backups = await _store.list();
      if (!ref.mounted || loadId != _loadId) return;
      state = ScheduleBackupState(
        status: ScheduleBackupLoadStatus.ready,
        entries: List.unmodifiable([
          for (final b in backups)
            ScheduleBackupEntry(backup: b, read: SchedulePayload.decode(b.raw)),
        ]),
      );
    } catch (_) {
      if (!ref.mounted || loadId != _loadId) return;
      state = const ScheduleBackupState(
        status: ScheduleBackupLoadStatus.failed,
      );
    }
  }

  ScheduleState get _schedule => ref.read(scheduleProvider);

  /// 지금 일정이 마지막 직접 백업과 같은지(그러면 `지금 백업`을 끈다).
  bool isSameAsLastManual(ScheduleState schedule) {
    final last = state.lastManual;
    return last != null &&
        last.backup.raw == SchedulePayload.encode(schedule.data);
  }

  /// 지금 백업을 만들면 지워질 가장 오래된 직접 백업. 직접 백업이 아직 3개가 안 되면 null.
  ScheduleBackupEntry? get rotatedOut {
    final manual = state.entries.where((e) => !e.isAuto).toList();
    return manual.length >= ScheduleBackupStore.maxManual ? manual.last : null;
  }

  /// 지금 일정의 복사본을 만든다. 일정을 불러오지 못했거나 일정이 없으면 [StateError].
  Future<void> backupNow() async {
    final schedule = _schedule;
    if (!schedule.isReady) throw StateError('일정을 불러오기 전에는 백업할 수 없습니다.');
    if (schedule.items.isEmpty && schedule.archived.isEmpty) {
      throw StateError('백업할 일정이 없습니다.');
    }
    await _store.addManual(SchedulePayload.encode(schedule.data));
    await reload();
  }

  Future<void> delete(Set<String> ids) async {
    await _store.delete(ids);
    await reload();
  }

  /// 읽지 못해 보관한 백업을 모두 확인한 것으로 기억한다(알림 `확인`·닫기).
  Future<void> markAutoSeen() async {
    final ids = {
      for (final e in state.entries)
        if (e.isAuto && !e.backup.seen) e.id,
    };
    if (ids.isEmpty) return;
    await _store.markSeen(ids);
    await reload();
  }

  /// [removedIds] 백업을 지우면 더는 되살릴 수 없게 되는 일정.
  List<ScheduleItem> lostIfDeleted(Set<String> removedIds) {
    final readable = state.entries.where((e) => e.isReadable);
    return ScheduleBackupRules.lostIfDeleted(
      current: _schedule.data,
      removed: [
        for (final e in readable)
          if (removedIds.contains(e.id)) e.read.data,
      ],
      kept: [
        for (final e in readable)
          if (!removedIds.contains(e.id)) e.read.data,
      ],
    );
  }

  /// [entryId] 백업에서 [itemIds] 일정을 지금 타임라인에 더한다. 백업은 그대로 남는다.
  /// 읽지 못해 보관한 백업이면 확인한 것으로 기억한다. 더한 일정 수를 돌려준다.
  Future<int> restore(String entryId, Set<String> itemIds) async {
    final schedule = _schedule;
    if (!schedule.isReady) throw StateError('일정을 불러오기 전에는 되살릴 수 없습니다.');
    final entry = state.byId(entryId);
    if (entry == null || !entry.isReadable) throw StateError('되살릴 백업이 없습니다.');
    final picked = entry.items.where((i) => itemIds.contains(i.id)).toList();
    if (picked.isEmpty) return 0;
    final added = ScheduleBackupRules.prepareRestore(
      schedule.data,
      picked,
      now: ref.read(scheduleClockProvider)(),
    );
    await ref.read(scheduleProvider.notifier).addAll(added);
    if (entry.isAuto && !entry.backup.seen) {
      // 되살리기는 이미 끝났다. 확인 기록만 못 남겨도 되살린 일정은 그대로 둔다.
      try {
        await _store.markSeen({entry.id});
        await reload();
      } catch (_) {}
    }
    return added.length;
  }
}

final scheduleBackupProvider =
    NotifierProvider<ScheduleBackupNotifier, ScheduleBackupState>(
      ScheduleBackupNotifier.new,
    );
