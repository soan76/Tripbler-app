import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/schedule/schedule_data.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_backup_provider.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';
import 'package:tripbler/services/schedule/schedule_backup_store.dart';
import 'package:tripbler/services/schedule/schedule_payload.dart';
import 'package:tripbler/services/schedule/schedule_storage_service.dart';

import '../helpers/memory_schedule_storage.dart';

// 기기 백업(schedule.md 4절): 지금 백업·최근 3개·선택 되살리기·삭제 영향·읽지 못한 일정 알림.

void main() {
  const key = ScheduleStorageService.storageKey;
  var clock = DateTime(2026, 11, 28, 9);

  ScheduleItem at(String id, int hour, {String? title}) =>
      scheduleItem(id, startsAt: DateTime(2026, 11, 28, hour), title: title);

  String raw(List<ScheduleItem> items) =>
      SchedulePayload.encode(ScheduleData(items: items));

  /// 실제 저장소(가짜 shared_preferences)로 일정과 백업 목록을 다 읽은 컨테이너.
  Future<ProviderContainer> ready({
    Map<String, Object> prefs = const {},
    ScheduleStorageService? storage,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = ScheduleBackupStore(now: () => clock);
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        scheduleBackupStoreProvider.overrideWithValue(store),
        scheduleStorageServiceProvider.overrideWithValue(
          storage ?? ScheduleStorageService(backups: store),
        ),
        scheduleClockProvider.overrideWithValue(() => clock),
      ],
    );
    container.listen(scheduleBackupProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  ScheduleBackupNotifier backups(ProviderContainer c) =>
      c.read(scheduleBackupProvider.notifier);
  List<ScheduleBackupEntry> entries(ProviderContainer c) =>
      c.read(scheduleBackupProvider).entries;

  setUp(() => clock = DateTime(2026, 11, 28, 9));

  test('지금 백업은 지금 일정의 복사본이고, 같은 내용이면 같다고 알린다', () async {
    final c = await ready(
      prefs: {
        key: raw([at('a', 9)]),
      },
    );
    expect(entries(c), isEmpty);
    expect(backups(c).isSameAsLastManual(c.read(scheduleProvider)), isFalse);

    await backups(c).backupNow();
    final entry = entries(c).single;
    expect(entry.isAuto, isFalse);
    expect(entry.items.single.id, 'a');
    expect(backups(c).isSameAsLastManual(c.read(scheduleProvider)), isTrue);

    await c.read(scheduleProvider.notifier).add(at('b', 12));
    expect(backups(c).isSameAsLastManual(c.read(scheduleProvider)), isFalse);
  });

  test('직접 백업이 3개면 가장 오래된 직접 백업만 지우고 읽지 못해 보관한 백업은 남긴다', () async {
    final c = await ready(
      prefs: {
        key: '{"version":2,"items":[${jsonEncode(at('a', 9).toJson())}, 1]}',
      },
    );
    expect(entries(c).single.isAuto, isTrue);
    for (var i = 0; i < 3; i++) {
      clock = clock.add(const Duration(minutes: 1));
      await c.read(scheduleProvider.notifier).add(at('n$i', 10 + i));
      await backups(c).backupNow();
    }
    final oldest = entries(c).where((e) => !e.isAuto).last;
    expect(backups(c).rotatedOut?.id, oldest.id);

    clock = clock.add(const Duration(minutes: 1));
    await c.read(scheduleProvider.notifier).add(at('n3', 15));
    await backups(c).backupNow();
    final list = entries(c);
    expect(list.where((e) => !e.isAuto), hasLength(3));
    expect(list.any((e) => e.id == oldest.id), isFalse);
    expect(list.where((e) => e.isAuto), hasLength(1));
  });

  test('되살리기는 고른 일정만 시간 규칙대로 더하고, 겹치는 id는 새 id로, 백업은 남긴다', () async {
    final c = await ready(
      prefs: {
        key: raw([at('a', 9), at('c', 18)]),
      },
    );
    await backups(c).backupNow();
    // 백업 뒤 b를 지우고 a 제목을 바꾼다 → 백업의 a는 id가 겹친다.
    final notifier = c.read(scheduleProvider.notifier);
    await notifier.update(at('a', 9, title: '바뀐 a'));
    await notifier.add(at('b', 12));
    final entryId = entries(c).single.id;
    final count = await backups(c).restore(entryId, {'a', 'c'});
    expect(count, 2);
    final items = c.read(scheduleProvider).items;
    expect(items.map((i) => i.title), ['바뀐 a', '일정 a', '일정 b', '일정 c', '일정 c']);
    expect(items.map((i) => i.id).toSet(), hasLength(5), reason: 'id가 겹치지 않는다');
    expect(entries(c).single.id, entryId, reason: '백업은 남는다');
  });

  test('일정을 불러오지 못했으면 백업 만들기와 되살리기를 막는다', () async {
    final failing = MemoryScheduleStorage()..failLoad = true;
    final c = await ready(storage: failing);
    expect(c.read(scheduleProvider).status, ScheduleLoadStatus.failed);
    await expectLater(backups(c).backupNow(), throwsStateError);
    await expectLater(backups(c).restore('x', {'a'}), throwsStateError);
    expect(failing.saveCount, 0);
  });

  test('삭제 영향: 이 백업에만 있는 일정만 잃는 일정으로 센다', () async {
    final c = await ready(
      prefs: {
        key: raw([at('a', 9), at('only', 10)]),
      },
    );
    await backups(c).backupNow();
    clock = clock.add(const Duration(minutes: 1));
    await c.read(scheduleProvider.notifier).remove('only');
    await c.read(scheduleProvider.notifier).archive('a');
    await backups(c).backupNow();
    final [newer, older] = entries(c);

    // 'only'는 오래된 백업에만 있다. 'a'는 보관함에 있다.
    expect(backups(c).lostIfDeleted({older.id}).map((i) => i.id), ['only']);
    expect(backups(c).lostIfDeleted({newer.id}), isEmpty);
    expect(backups(c).lostIfDeleted({newer.id, older.id}).map((i) => i.id), [
      'only',
    ]);
    await backups(c).delete({older.id});
    expect(entries(c).single.id, newer.id);
  });

  test('읽지 못해 보관한 백업은 확인 전까지 알리고, 확인을 기억해 다시 켜도 알리지 않는다', () async {
    final c = await ready(prefs: {key: '{'});
    expect(c.read(scheduleBackupProvider).hasUnseenAuto, isTrue);
    await backups(c).markAutoSeen();
    expect(c.read(scheduleBackupProvider).hasUnseenAuto, isFalse);

    // 앱을 다시 켠 것처럼 같은 저장값으로 새 컨테이너를 만든다.
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final k in prefs.getKeys()) k: prefs.getString(k)!};
    final again = await ready(prefs: saved);
    expect(again.read(scheduleBackupProvider).hasUnseenAuto, isFalse);
  });

  test('읽지 못해 보관한 백업에서 되살리면 확인한 것으로 기억한다', () async {
    final c = await ready(
      prefs: {
        key: '{"version":2,"items":[${jsonEncode(at('a', 9).toJson())}, 1]}',
      },
    );
    await c.read(scheduleProvider.notifier).remove('a');
    final entry = entries(c).single;
    expect(entry.read.unreadable, 1);
    await backups(c).restore(entry.id, {'a'});
    expect(c.read(scheduleBackupProvider).hasUnseenAuto, isFalse);
    expect(c.read(scheduleProvider).items.single.id, 'a');
  });
}
