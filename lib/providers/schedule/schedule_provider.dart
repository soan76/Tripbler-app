import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/schedule/schedule_order.dart';
import '../../models/schedule/schedule_data.dart';
import '../../models/schedule/schedule_item.dart';
import '../../services/schedule/schedule_backup_store.dart';
import '../../services/schedule/schedule_storage_service.dart';

/// 일정 기기 백업 목록. 테스트에서 바꾼다.
final scheduleBackupStoreProvider = Provider<ScheduleBackupStore>(
  (_) => ScheduleBackupStore(),
);

/// 일정 저장소. 테스트에서 바꾼다. 읽지 못한 값은 [scheduleBackupStoreProvider]에 보관한다.
final scheduleStorageServiceProvider = Provider<ScheduleStorageService>(
  (ref) =>
      ScheduleStorageService(backups: ref.watch(scheduleBackupStoreProvider)),
);

/// 일정 화면이 쓰는 현재 시각. 테스트에서 바꾼다.
final scheduleClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

enum ScheduleLoadStatus {
  /// 저장된 일정을 읽는 중.
  loading,

  /// 읽기를 마쳤다(일정이 없을 수도 있다).
  ready,

  /// 저장소를 열지 못했다. 이때 저장하면 기존 일정을 덮어쓰므로 추가·백업·되살리기를 막는다.
  failed,
}

/// 저장된 일정. [items]는 타임라인 순서(사용자가 정한 순서), [archived]는 보관함이다.
class ScheduleState {
  const ScheduleState({
    this.status = ScheduleLoadStatus.loading,
    this.items = const [],
    this.archived = const [],
  });

  final ScheduleLoadStatus status;
  final List<ScheduleItem> items;
  final List<ArchivedScheduleItem> archived;

  bool get isReady => status == ScheduleLoadStatus.ready;

  ScheduleData get data => ScheduleData(items: items, archived: archived);
}

/// 저장된 일정을 불러오고, 추가·수정·삭제·순서 바꾸기·보관함 이동을 저장한다.
///
/// 바꾸는 일은 하나씩 차례로 저장한다(앞의 저장이 끝난 뒤의 상태에서 다음을 계산한다).
/// 저장에 실패하면 예외를 그대로 던지고 상태는 바꾸지 않는다. 불러오기를 마치기 전이나
/// 실패한 상태에서는 [StateError]를 던진다(기존 일정을 덮어쓰지 않게).
class ScheduleNotifier extends Notifier<ScheduleState> {
  late ScheduleStorageService _storage;
  late DateTime Function() _now;

  /// 가장 최근 불러오기 번호. 앞선 불러오기의 결과는 버린다.
  int _loadId = 0;

  /// 진행 중인 저장. 다음 저장은 이것이 끝난 뒤에 시작한다.
  Future<void> _queue = Future.value();

  @override
  ScheduleState build() {
    _storage = ref.read(scheduleStorageServiceProvider);
    _now = ref.read(scheduleClockProvider);
    _load();
    return const ScheduleState();
  }

  /// 불러오기에 실패했을 때 다시 읽는다.
  Future<void> retry() {
    if (state.status != ScheduleLoadStatus.failed) return Future.value();
    state = const ScheduleState();
    return _load();
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    try {
      final data = await _storage.load();
      if (!ref.mounted || loadId != _loadId) return;
      _apply(data);
    } catch (_) {
      if (!ref.mounted || loadId != _loadId) return;
      state = const ScheduleState(status: ScheduleLoadStatus.failed);
    }
  }

  /// 새 일정을 지금 순서에서 처음으로 더 늦은 일정 앞에 넣는다.
  Future<void> add(ScheduleItem item) => _change(
    (d) => ScheduleData(
      items: ScheduleOrder.insert(d.items, item),
      archived: d.archived,
    ),
  );

  /// 여러 일정을 차례로 [add]와 같은 규칙으로 넣는다(백업에서 되살리기). 한 번에 저장한다.
  Future<void> addAll(List<ScheduleItem> added) => _change((d) {
    var items = d.items;
    for (final item in added) {
      items = ScheduleOrder.insert(items, item);
    }
    return ScheduleData(items: items, archived: d.archived);
  });

  /// 같은 id의 일정을 [item]으로 바꾼다. 날짜·시간을 바꿨으면 자리를 다시 찾고, 아니면 그대로.
  /// 그 id가 없으면 [StateError].
  Future<void> update(ScheduleItem item) => _change(
    (d) => ScheduleData(
      items:
          ScheduleOrder.replace(d.items, item) ??
          (throw StateError('수정할 일정이 없습니다.')),
      archived: d.archived,
    ),
  );

  /// [id] 일정을 지운다. 그 id가 없으면 [StateError].
  Future<void> remove(String id) => _change((d) {
    final items = d.items.where((i) => i.id != id).toList();
    if (items.length == d.items.length) throw StateError('삭제할 일정이 없습니다.');
    return ScheduleData(items: items, archived: d.archived);
  });

  /// [id] 일정을 [to] 자리로 옮긴다(길게 눌러 끌기). 날짜·시간은 바꾸지 않는다.
  Future<void> move(String id, int to) => _change(
    (d) => ScheduleData(
      items:
          ScheduleOrder.move(d.items, id, to) ??
          (throw StateError('옮길 일정이 없습니다.')),
      archived: d.archived,
    ),
  );

  /// [id] 일정을 타임라인에서 빼 보관함으로 옮긴다.
  Future<void> archive(String id) => _change((d) {
    final index = d.items.indexWhere((i) => i.id == id);
    if (index < 0) throw StateError('보관할 일정이 없습니다.');
    final item = d.items[index];
    return ScheduleData(
      items: [...d.items]..removeAt(index),
      archived: [
        ...d.archived,
        ArchivedScheduleItem(item: item, archivedAt: _now()),
      ],
    );
  });

  /// 보관함의 [id] 일정을 타임라인으로 다시 꺼낸다([add]와 같은 자리 규칙).
  Future<void> unarchive(String id) => _change((d) {
    final entry = d.archived.where((a) => a.item.id == id).firstOrNull;
    if (entry == null) throw StateError('꺼낼 일정이 없습니다.');
    return ScheduleData(
      items: ScheduleOrder.insert(d.items, entry.item),
      archived: d.archived.where((a) => a != entry).toList(),
    );
  });

  /// 보관함의 [id] 일정을 지운다.
  Future<void> deleteArchived(String id) => _change((d) {
    final archived = d.archived.where((a) => a.item.id != id).toList();
    if (archived.length == d.archived.length) {
      throw StateError('삭제할 일정이 없습니다.');
    }
    return ScheduleData(items: d.items, archived: archived);
  });

  /// 앞의 저장이 끝난 뒤 그때 상태에서 [change]로 다음 값을 만들어 저장하고 반영한다.
  Future<void> _change(ScheduleData Function(ScheduleData data) change) {
    final run = _queue.then((_) async {
      if (!ref.mounted) return;
      if (!state.isReady) {
        throw StateError('일정을 불러오기 전에는 바꿀 수 없습니다.');
      }
      final next = change(state.data);
      await _storage.save(next);
      if (!ref.mounted) return;
      _apply(next);
    });
    // 실패해도 다음 저장은 이어서 한다.
    _queue = run.catchError((_) {});
    return run;
  }

  void _apply(ScheduleData data) {
    state = ScheduleState(
      status: ScheduleLoadStatus.ready,
      items: List.unmodifiable(data.items),
      archived: List.unmodifiable(data.archived),
    );
  }
}

final scheduleProvider = NotifierProvider<ScheduleNotifier, ScheduleState>(
  ScheduleNotifier.new,
);
