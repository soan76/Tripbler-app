import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/schedule/schedule_data.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_draft_provider.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';

import '../helpers/memory_schedule_storage.dart';

// 순서 바꾸기(schedule.md 2-2)와 보관함(4절)의 상태 규칙.

void main() {
  late MemoryScheduleStorage storage;
  final now = DateTime(2026, 11, 28, 14, 20);

  ScheduleItem at(String id, int day, int hour) =>
      scheduleItem(id, startsAt: DateTime(2026, 11, day, hour));

  Future<ProviderContainer> ready() async {
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        scheduleStorageServiceProvider.overrideWithValue(storage),
        scheduleClockProvider.overrideWithValue(() => now),
      ],
    );
    container.read(scheduleProvider);
    await pumpEventQueue();
    return container;
  }

  List<String> ids(ProviderContainer c) =>
      c.read(scheduleProvider).items.map((i) => i.id).toList();

  setUp(() {
    storage = MemoryScheduleStorage([
      at('a', 28, 9),
      at('b', 28, 12),
      at('c', 28, 18),
    ]);
  });

  group('순서 바꾸기', () {
    test('옮기면 순서만 바뀌고 날짜·시간은 그대로 저장한다', () async {
      final c = await ready();
      await c.read(scheduleProvider.notifier).move('c', 0);
      expect(ids(c), ['c', 'a', 'b']);
      expect(storage.stored.map((i) => i.id), ['c', 'a', 'b']);
      expect(storage.stored.first.startsAt, DateTime(2026, 11, 28, 18));

      await c.read(scheduleProvider.notifier).move('c', 99);
      expect(ids(c), ['a', 'b', 'c'], reason: '범위를 넘으면 끝으로');
    });

    test('새 일정은 지금 순서에서 처음으로 더 늦은 일정 앞에 넣는다', () async {
      storage.stored = [at('c', 28, 18), at('a', 28, 9)];
      final c = await ready();
      await c.read(scheduleProvider.notifier).add(at('n', 28, 10));
      // 순서가 섞여 있어도 위에서부터 처음으로 더 늦은 일정(c) 앞.
      expect(ids(c), ['n', 'c', 'a']);
      await c.read(scheduleProvider.notifier).add(at('z', 30, 9));
      expect(ids(c), ['n', 'c', 'a', 'z'], reason: '더 늦은 일정이 없으면 끝');
    });

    test('수정에서 날짜·시간을 바꾸면 자리를 다시 찾고, 바꾸지 않으면 그대로 둔다', () async {
      final c = await ready();
      final notifier = c.read(scheduleProvider.notifier);
      await notifier.move('c', 0); // c, a, b
      await notifier.update(
        scheduleItem('c', startsAt: DateTime(2026, 11, 28, 18), title: '새 제목'),
      );
      expect(ids(c), ['c', 'a', 'b'], reason: '시각이 같으면 자리 유지');
      await notifier.update(at('c', 28, 10));
      expect(ids(c), ['a', 'c', 'b']);
    });

    test('수정 화면 저장도 같은 규칙을 따른다', () async {
      final c = await ready();
      await c.read(scheduleProvider.notifier).move('a', 2); // b, c, a
      final draft = c.read(scheduleDraftProvider.notifier)
        ..startEdit(c.read(scheduleProvider).items.last);
      draft.setTitle('제목만 바꿈');
      await draft.save();
      expect(ids(c), ['b', 'c', 'a']);
    });

    test('바꾸는 일이 겹쳐도 앞의 저장이 끝난 뒤 그 상태에서 다음을 계산한다', () async {
      final c = await ready();
      storage.holdSave = Completer<void>();
      final notifier = c.read(scheduleProvider.notifier);
      final first = notifier.move('c', 0);
      final second = notifier.add(at('n', 28, 10));
      storage.holdSave!.complete();
      await Future.wait([first, second]);
      // 옮긴 뒤 순서(c 18시, a, b)에서 10시는 처음으로 더 늦은 c 앞. 처음 순서(a, b, c)로
      // 계산했다면 a, n, b, c가 된다.
      expect(ids(c), ['n', 'c', 'a', 'b']);
      expect(storage.stored.map((i) => i.id), ['n', 'c', 'a', 'b']);
    });

    test('저장에 실패하면 순서를 바꾸지 않고, 다음 바꾸기는 이어서 된다', () async {
      final c = await ready();
      storage.failSave = true;
      await expectLater(
        c.read(scheduleProvider.notifier).move('c', 0),
        throwsA(anything),
      );
      expect(ids(c), ['a', 'b', 'c']);
      storage.failSave = false;
      await c.read(scheduleProvider.notifier).move('b', 0);
      expect(ids(c), ['b', 'a', 'c']);
    });
  });

  group('보관함', () {
    test('보관함으로 옮기면 타임라인에서 빠지고 보관 시각과 함께 저장한다', () async {
      final c = await ready();
      await c.read(scheduleProvider.notifier).archive('b');
      final state = c.read(scheduleProvider);
      expect(ids(c), ['a', 'c']);
      expect(state.archived.single.item.id, 'b');
      expect(state.archived.single.archivedAt, now);
      expect(storage.archived.single.item.id, 'b');
    });

    test('다시 꺼내면 처음으로 더 늦은 일정 앞에 돌아오고, 삭제하면 보관함에서만 지운다', () async {
      final c = await ready();
      final notifier = c.read(scheduleProvider.notifier);
      await notifier.archive('b');
      await notifier.unarchive('b');
      expect(ids(c), ['a', 'b', 'c']);
      expect(c.read(scheduleProvider).archived, isEmpty);

      await notifier.archive('a');
      await notifier.deleteArchived('a');
      expect(ids(c), ['b', 'c']);
      expect(c.read(scheduleProvider).archived, isEmpty);
      expect(storage.archived, isEmpty);
    });

    test('자동으로 지우지 않는다: 오래된 보관 일정도 그대로 읽힌다', () async {
      storage.archived = [
        ArchivedScheduleItem(
          item: at('old', 1, 9),
          archivedAt: DateTime(2025, 1, 1),
        ),
      ];
      final c = await ready();
      expect(c.read(scheduleProvider).archived.single.item.id, 'old');
    });

    test('수정 화면의 보관함 이동은 고치던 값이 아니라 저장된 값을 옮긴다', () async {
      final c = await ready();
      final draft = c.read(scheduleDraftProvider.notifier)
        ..startEdit(c.read(scheduleProvider).items.first);
      draft.setTitle('저장 안 한 제목');
      expect(await draft.archiveEditing(), isTrue);
      expect(c.read(scheduleDraftProvider), isNull);
      expect(c.read(scheduleProvider).archived.single.item.title, '일정 a');
    });

    test('보관함 이동에 실패하면 입력값을 두고 실패를 표시한다', () async {
      final c = await ready();
      final draft = c.read(scheduleDraftProvider.notifier)
        ..startEdit(c.read(scheduleProvider).items.first);
      storage.failSave = true;
      expect(await draft.archiveEditing(), isFalse);
      final state = c.read(scheduleDraftProvider)!;
      expect(state.archiveFailed, isTrue);
      expect(state.isSaving, isFalse);
      expect(ids(c), ['a', 'b', 'c']);
    });
  });
}
