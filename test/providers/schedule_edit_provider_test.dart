import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_draft_provider.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';

import '../helpers/memory_schedule_storage.dart';

// 저장한 일정 수정·삭제의 상태 처리(docs/mockups/schedule.md 2-4절).

void main() {
  late MemoryScheduleStorage storage;
  final now = DateTime(2026, 11, 28, 14, 20);
  const picked = ScheduledPlace(
    name: '센소지',
    address: '2-3-1 Asakusa',
    latitude: 35.7148,
    longitude: 139.7967,
    placeId: 'p1',
  );

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

  setUp(() {
    storage = MemoryScheduleStorage([
      scheduleItem(
        'a',
        title: '센소지 구경',
        startsAt: DateTime(2026, 11, 28, 15),
        place: picked,
        alarm: ScheduleAlarm.before30,
        memo: '입장 무료',
        createdAt: DateTime(2026, 11, 2),
      ),
      scheduleItem(
        'b',
        title: '긴자 쇼핑',
        startsAt: DateTime(2026, 11, 28, 18),
        place: const ScheduledPlace(name: '긴자 거리'),
      ),
    ]);
  });

  group('ScheduleNotifier 수정·삭제', () {
    test('수정하면 같은 id를 바꾸고 시간순으로 다시 정렬해 저장한다', () async {
      final container = await ready();
      await container
          .read(scheduleProvider.notifier)
          .update(scheduleItem('b', startsAt: DateTime(2026, 11, 28, 9)));
      expect(container.read(scheduleProvider).items.map((i) => i.id), [
        'b',
        'a',
      ]);
      expect(storage.stored.map((i) => i.id), ['b', 'a']);
    });

    test('삭제하면 목록과 저장소에서 지운다', () async {
      final container = await ready();
      await container.read(scheduleProvider.notifier).remove('a');
      expect(container.read(scheduleProvider).items.single.id, 'b');
      expect(storage.stored.single.id, 'b');
    });

    test('없는 id는 StateError, 저장에 실패하면 목록을 바꾸지 않는다', () async {
      final container = await ready();
      final notifier = container.read(scheduleProvider.notifier);
      await expectLater(notifier.remove('x'), throwsStateError);
      await expectLater(
        notifier.update(scheduleItem('x', startsAt: now)),
        throwsStateError,
      );
      storage.failSave = true;
      await expectLater(notifier.remove('a'), throwsA(anything));
      expect(container.read(scheduleProvider).items, hasLength(2));
    });
  });

  group('ScheduleDraftNotifier 수정', () {
    test('저장한 값으로 시작하고, 바꾸기 전에는 버릴 내용이 없다', () async {
      final container = await ready();
      final item = container.read(scheduleProvider).items.first;
      container.read(scheduleDraftProvider.notifier).startEdit(item);

      final draft = container.read(scheduleDraftProvider)!;
      expect(draft.isEditing, isTrue);
      expect(draft.title, '센소지 구경');
      expect(draft.startsAt, DateTime(2026, 11, 28, 15));
      expect(draft.placeText, '센소지');
      expect(draft.pickedPlace, same(picked));
      expect(draft.alarm, ScheduleAlarm.before30);
      expect(draft.memo, '입장 무료');
      expect(draft.isDirty, isFalse);
    });

    test('값을 바꾸면 버릴 내용이 생기고, 되돌리면(앞뒤 공백만 달라도) 없어진다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.first);
      bool dirty() => container.read(scheduleDraftProvider)!.isDirty;

      notifier.setTime(16, 0);
      expect(dirty(), isTrue);
      notifier.setTime(15, 0);
      expect(dirty(), isFalse);

      notifier.setTitle(' 센소지 구경 ');
      expect(dirty(), isFalse);
      notifier.setAlarm(ScheduleAlarm.none);
      expect(dirty(), isTrue);
      notifier.setAlarm(ScheduleAlarm.before30);

      // 같은 이름을 직접 다시 쳐도 지도에서 고른 장소는 남는다.
      notifier.setPlaceText('센소지');
      expect(dirty(), isFalse);
      notifier.setPlaceText('센소지 앞');
      expect(dirty(), isTrue);
    });

    test('분이 있는 저장값은 열기만 하면 버릴 내용이 없고, 분을 바꿨다 되돌리면 다시 없어진다', () async {
      storage = MemoryScheduleStorage([
        scheduleItem('c', startsAt: DateTime(2026, 11, 28, 15, 59)),
      ]);
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.single);
      ScheduleDraft draft() => container.read(scheduleDraftProvider)!;

      expect((draft().hour, draft().minute), (15, 59));
      expect(draft().isDirty, isFalse);
      notifier.setTime(15, 59);
      expect(draft().isDirty, isFalse, reason: '같은 값을 다시 골라도 그대로');
      notifier.setTime(15, 58);
      expect(draft().isDirty, isTrue);
      notifier.setTime(15, 59);
      expect(draft().isDirty, isFalse);

      // 분을 바꿔 저장하면 그 분으로 남고, 다시 열면 버릴 내용이 없다.
      notifier
        ..setTitle('분 단위 수정')
        ..setTime(16, 7);
      final saved = await notifier.save();
      expect(saved!.startsAt, DateTime(2026, 11, 28, 16, 7));
      notifier.startEdit(container.read(scheduleProvider).items.single);
      expect(draft().minute, 7);
      expect(draft().isDirty, isFalse);
    });

    test('좌표만 있는 장소(장소 id·주소 없음)는 수정해 저장해도 좌표를 잃지 않는다', () async {
      storage = MemoryScheduleStorage([
        scheduleItem(
          'c',
          startsAt: DateTime(2026, 11, 28, 20),
          place: const ScheduledPlace(
            name: '호텔',
            latitude: 35.68,
            longitude: 139.76,
          ),
        ),
      ]);
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.single);
      expect(container.read(scheduleDraftProvider)!.isDirty, isFalse);
      notifier.setTitle('호텔 체크인');

      final saved = await notifier.save();
      expect(saved!.place!.latitude, 35.68);
      expect(saved.place!.longitude, 139.76);
      expect(storage.stored.single.place!.latitude, 35.68);
    });

    test('장소 id가 없는 지도 장소를 이름이 같은 다른 장소로 바꾸면 바뀐 것으로 본다', () async {
      storage = MemoryScheduleStorage([
        scheduleItem(
          'c',
          startsAt: DateTime(2026, 11, 28, 20),
          place: const ScheduledPlace(name: '스타벅스', address: '긴자 1-1'),
        ),
      ]);
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.single);
      notifier.pickPlace(
        const ScheduledPlace(
          name: '스타벅스',
          address: '신주쿠 3-3',
          latitude: 35.69,
          longitude: 139.70,
        ),
      );
      expect(container.read(scheduleDraftProvider)!.isDirty, isTrue);

      notifier.pickPlace(const ScheduledPlace(name: '스타벅스', address: '긴자 1-1'));
      expect(container.read(scheduleDraftProvider)!.isDirty, isFalse);
    });

    test('수정 저장은 id·만든 시각을 유지하고 작성을 끝낸다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.first);
      notifier
        ..setTitle('센소지·나카미세')
        ..setDate(DateTime(2026, 11, 29));

      final saved = await notifier.save();
      expect(saved!.id, 'a');
      expect(saved.createdAt, DateTime(2026, 11, 2));
      expect(saved.startsAt, DateTime(2026, 11, 29, 15));
      expect(saved.place, same(picked));
      expect(container.read(scheduleDraftProvider), isNull);
      expect(storage.stored.map((i) => i.id), ['b', 'a']);
      expect(storage.stored.last.title, '센소지·나카미세');
    });

    test('삭제에 성공하면 작성을 끝내고 true, 새 일정에서는 아무것도 하지 않는다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.start();
      expect(await notifier.delete(), isFalse);
      expect(storage.saveCount, 0);

      notifier.startEdit(container.read(scheduleProvider).items.last);
      expect(await notifier.delete(), isTrue);
      expect(container.read(scheduleDraftProvider), isNull);
      expect(storage.stored.single.id, 'a');
    });

    test('삭제에 실패하면 입력값을 두고 실패를 표시한다, 다시 하면 성공한다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.first);
      notifier.setMemo('바꾼 메모');
      storage.failSave = true;

      expect(await notifier.delete(), isFalse);
      final failed = container.read(scheduleDraftProvider)!;
      expect(failed.deleteFailed, isTrue);
      expect(failed.saveFailed, isFalse);
      expect(failed.isSaving, isFalse);
      expect(failed.memo, '바꾼 메모');
      expect(container.read(scheduleProvider).items, hasLength(2));

      storage.failSave = false;
      expect(await notifier.delete(), isTrue);
      expect(storage.stored.single.id, 'b');
    });

    test('삭제하는 동안에는 저장·입력·다시 삭제를 받지 않는다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.startEdit(container.read(scheduleProvider).items.first);
      storage.holdSave = Completer<void>();

      final deleting = notifier.delete();
      expect(container.read(scheduleDraftProvider)!.isSaving, isTrue);
      expect(await notifier.delete(), isFalse);
      expect(await notifier.save(), isNull);
      notifier.setTitle('바뀐 제목');
      expect(container.read(scheduleDraftProvider)!.title, '센소지 구경');

      storage.holdSave!.complete();
      expect(await deleting, isTrue);
      expect(storage.saveCount, 1);
    });
  });
}
