import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_draft_provider.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';
import 'package:tripbler/services/schedule/schedule_backup_store.dart';
import 'package:tripbler/services/schedule/schedule_storage_service.dart';

import '../helpers/memory_schedule_storage.dart';

void main() {
  late MemoryScheduleStorage storage;
  late DateTime now;

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        scheduleStorageServiceProvider.overrideWithValue(storage),
        scheduleClockProvider.overrideWithValue(() => now),
      ],
    );
    return container;
  }

  /// 불러오기를 마칠 때까지 기다린다.
  Future<ProviderContainer> ready() async {
    final container = makeContainer();
    container.read(scheduleProvider);
    await pumpEventQueue();
    return container;
  }

  setUp(() {
    storage = MemoryScheduleStorage();
    now = DateTime(2026, 11, 28, 14, 20);
  });

  group('ScheduleNotifier', () {
    test('저장된 일정을 저장한 순서(타임라인 순서) 그대로 불러온다', () async {
      storage.stored = [
        scheduleItem('late', startsAt: DateTime(2026, 11, 29, 9)),
        scheduleItem(
          'same-2',
          startsAt: DateTime(2026, 11, 28, 15),
          createdAt: DateTime(2026, 11, 2),
        ),
        scheduleItem(
          'same-1',
          startsAt: DateTime(2026, 11, 28, 15),
          createdAt: DateTime(2026, 11, 1),
        ),
      ];
      final container = makeContainer();
      expect(
        container.read(scheduleProvider).status,
        ScheduleLoadStatus.loading,
      );
      await pumpEventQueue();

      final state = container.read(scheduleProvider);
      expect(state.status, ScheduleLoadStatus.ready);
      // 날짜·시간 순으로 다시 정렬하지 않는다(사용자가 끌어 바꾼 순서를 지킨다).
      expect(state.items.map((i) => i.id), ['late', 'same-2', 'same-1']);
    });

    test('새 일정은 처음으로 더 늦은 일정 앞에 넣고 저장한다', () async {
      storage.stored = [
        scheduleItem('a', startsAt: DateTime(2026, 11, 28, 9)),
        scheduleItem('c', startsAt: DateTime(2026, 11, 28, 18)),
      ];
      final container = await ready();

      await container
          .read(scheduleProvider.notifier)
          .add(scheduleItem('b', startsAt: DateTime(2026, 11, 28, 12)));

      expect(container.read(scheduleProvider).items.map((i) => i.id), [
        'a',
        'b',
        'c',
      ]);
      expect(storage.stored.map((i) => i.id), ['a', 'b', 'c']);
    });

    test('저장에 실패하면 예외를 던지고 목록은 그대로 둔다', () async {
      final container = await ready();
      storage.failSave = true;

      await expectLater(
        container
            .read(scheduleProvider.notifier)
            .add(scheduleItem('x', startsAt: DateTime(2026, 11, 28, 15))),
        throwsA(anything),
      );
      expect(container.read(scheduleProvider).items, isEmpty);
    });

    test('불러오기에 실패하면 추가를 막고(덮어쓰기 방지) 다시 시도로 회복한다', () async {
      storage.failLoad = true;
      final container = await ready();
      expect(
        container.read(scheduleProvider).status,
        ScheduleLoadStatus.failed,
      );

      await expectLater(
        container
            .read(scheduleProvider.notifier)
            .add(scheduleItem('x', startsAt: DateTime(2026, 11, 28, 15))),
        throwsStateError,
      );
      expect(storage.saveCount, 0);

      storage
        ..failLoad = false
        ..stored = [scheduleItem('kept', startsAt: DateTime(2026, 11, 28, 9))];
      await container.read(scheduleProvider.notifier).retry();
      final state = container.read(scheduleProvider);
      expect(state.status, ScheduleLoadStatus.ready);
      expect(state.items.single.id, 'kept');
    });

    test('일부 손상을 백업하지 못하면 실패로 두어 추가를 막고, 다시 시도해 백업하면 살린 일정을 보인다', () async {
      final good = scheduleItem('ok', startsAt: DateTime(2026, 11, 28, 9));
      final raw = jsonEncode({
        'version': 1,
        'items': [
          good.toJson(),
          {...good.toJson(), 'id': 'bad', 'startsAt': 'yesterday'},
        ],
      });
      SharedPreferences.setMockInitialValues({
        ScheduleStorageService.storageKey: raw,
      });
      final prefs = _BackupSwitchPrefs(await SharedPreferences.getInstance());
      final container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          scheduleStorageServiceProvider.overrideWithValue(
            ScheduleStorageService(prefs: () async => prefs),
          ),
          scheduleClockProvider.overrideWithValue(() => now),
        ],
      );
      container.read(scheduleProvider);
      await pumpEventQueue();
      expect(
        container.read(scheduleProvider).status,
        ScheduleLoadStatus.failed,
      );
      await expectLater(
        container
            .read(scheduleProvider.notifier)
            .add(scheduleItem('x', startsAt: DateTime(2026, 11, 28, 15))),
        throwsStateError,
      );
      expect(prefs.getString(ScheduleStorageService.storageKey), raw);

      prefs.failBackup = false;
      await container.read(scheduleProvider.notifier).retry();
      final state = container.read(scheduleProvider);
      expect(state.status, ScheduleLoadStatus.ready);
      expect(state.items.single.id, 'ok');
      expect(prefs.getString(ScheduleBackupStore.storageKey), contains('bad'));
    });
  });

  group('ScheduleDraftNotifier 기본값', () {
    test('일정이 없으면 오늘 지금 다음 정시', () async {
      final container = await ready();
      container.read(scheduleDraftProvider.notifier).start();
      final draft = container.read(scheduleDraftProvider)!;
      expect(draft.date, DateTime(2026, 11, 28));
      expect(draft.hour, 15);
      expect(draft.alarm, ScheduleAlarm.none);
      expect(draft.isDirty, isFalse);
    });

    test('23시가 넘으면 내일 9시', () async {
      now = DateTime(2026, 11, 28, 23, 10);
      final container = await ready();
      container.read(scheduleDraftProvider.notifier).start();
      final draft = container.read(scheduleDraftProvider)!;
      expect(draft.startsAt, DateTime(2026, 11, 29, 9));
    });

    test('마지막 일정이 아직 지나지 않았으면 그 날짜의 다음 시, 지났으면 다음 정시', () async {
      storage.stored = [
        scheduleItem('next', startsAt: DateTime(2026, 11, 30, 10)),
      ];
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier);
      notifier.start();
      expect(
        container.read(scheduleDraftProvider)!.startsAt,
        DateTime(2026, 11, 30, 11),
      );

      now = DateTime(2026, 11, 30, 12, 5);
      notifier.start();
      expect(
        container.read(scheduleDraftProvider)!.startsAt,
        DateTime(2026, 11, 30, 13),
      );
    });

    test('마지막 일정의 분은 다음 일정 기본값에 그대로 이어진다', () async {
      storage.stored = [
        scheduleItem('next', startsAt: DateTime(2026, 11, 30, 10, 45)),
      ];
      final container = await ready();
      container.read(scheduleDraftProvider.notifier).start();
      expect(
        container.read(scheduleDraftProvider)!.startsAt,
        DateTime(2026, 11, 30, 11, 45),
      );
    });

    test('시각은 1분 단위로 바꾸고, 범위를 벗어난 값은 무시한다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier.setTime(15, 59);
      expect(
        container.read(scheduleDraftProvider)!.startsAt,
        DateTime(2026, 11, 28, 15, 59),
      );
      for (final (h, m) in [(24, 0), (-1, 0), (10, 60), (10, -1)]) {
        notifier.setTime(h, m);
      }
      expect(container.read(scheduleDraftProvider)!.minute, 59);
      notifier.setTitle('분 저장');
      expect((await notifier.save())!.startsAt, DateTime(2026, 11, 28, 15, 59));
    });
  });

  group('ScheduleDraftNotifier 저장', () {
    test('제목이 비었거나 공백만 있으면 저장하지 않고 표시한다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier.setTitle('   ');

      expect(await notifier.save(), isNull);
      expect(container.read(scheduleDraftProvider)!.titleError, isTrue);
      expect(storage.saveCount, 0);

      notifier.setTitle('센소지');
      expect(container.read(scheduleDraftProvider)!.titleError, isFalse);
    });

    test('저장에 실패하면 입력값을 그대로 두고 실패를 표시한다, 다시 저장하면 성공한다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier
        ..setTitle('  센소지 구경 ')
        ..setTime(16, 0)
        ..setPlaceText('아사쿠사')
        ..setAlarm(ScheduleAlarm.before10)
        ..setMemo('줄 1\n줄 2\n');
      storage.failSave = true;

      expect(await notifier.save(), isNull);
      final failed = container.read(scheduleDraftProvider)!;
      expect(failed.saveFailed, isTrue);
      expect(failed.isSaving, isFalse);
      expect(failed.title, '  센소지 구경 ');
      expect(failed.placeText, '아사쿠사');
      expect(failed.memo, '줄 1\n줄 2\n');
      expect(failed.alarm, ScheduleAlarm.before10);

      storage.failSave = false;
      final saved = await notifier.save();
      expect(saved, isNotNull);
      expect(saved!.title, '센소지 구경');
      expect(saved.startsAt, DateTime(2026, 11, 28, 16));
      expect(saved.place!.name, '아사쿠사');
      expect(saved.place!.isFromMap, isFalse);
      expect(saved.memo, '줄 1\n줄 2');
      expect(container.read(scheduleDraftProvider), isNull);
      expect(container.read(scheduleProvider).items.single.id, saved.id);
    });

    test('한도를 넘은 제목·메모는 글자(이모지 포함) 기준으로 잘라 저장한다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier
        ..setTitle('😀' * 60)
        ..setMemo('👍🏽' * 501);

      final saved = await notifier.save();
      expect(saved!.title, '😀' * ScheduleItem.titleMaxLength);
      expect(saved.memo, '👍🏽' * ScheduleItem.memoMaxLength);
      expect(storage.stored.single.title, saved.title);
    });

    test('저장하는 동안에는 다시 저장하거나 입력을 바꾸지 않는다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier.setTitle('공항 이동');
      storage.holdSave = Completer<void>();

      final first = notifier.save();
      expect(container.read(scheduleDraftProvider)!.isSaving, isTrue);
      expect(await notifier.save(), isNull);
      notifier.setTitle('바뀐 제목');
      expect(container.read(scheduleDraftProvider)!.title, '공항 이동');

      storage.holdSave!.complete();
      expect((await first)!.title, '공항 이동');
      expect(storage.saveCount, 1);
    });

    test('지도에서 고른 장소는 주소·좌표와 함께 저장하고, 장소 칸을 고치면 직접 입력으로 바뀐다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      const picked = ScheduledPlace(
        name: '도쿄 스카이트리',
        address: '1-1-2 Oshiage',
        latitude: 35.7101,
        longitude: 139.8107,
        placeId: 'p2',
      );
      notifier.pickPlace(picked);
      expect(container.read(scheduleDraftProvider)!.placeText, '도쿄 스카이트리');
      expect(container.read(scheduleDraftProvider)!.place, same(picked));

      notifier.setPlaceText('도쿄 스카이트리');
      expect(container.read(scheduleDraftProvider)!.pickedPlace, same(picked));

      notifier.setPlaceText('스카이트리 앞');
      final draft = container.read(scheduleDraftProvider)!;
      expect(draft.pickedPlace, isNull);
      expect(draft.place!.isFromMap, isFalse);
    });

    test('알림 시각이 지났는지 알려 준다(저장은 막지 않는다)', () async {
      now = DateTime(2026, 11, 28, 14, 50);
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier
        ..setTitle('곧 시작')
        ..setAlarm(ScheduleAlarm.before30);
      expect(container.read(scheduleDraftProvider)!.isAlarmPassed(now), isTrue);
      notifier.setAlarm(ScheduleAlarm.before5);
      expect(
        container.read(scheduleDraftProvider)!.isAlarmPassed(now),
        isFalse,
      );
      notifier.setAlarm(ScheduleAlarm.before30);
      expect(await notifier.save(), isNotNull);
    });

    test('버리면 작성이 사라지고, 다시 열면 새 기본값으로 시작한다', () async {
      final container = await ready();
      final notifier = container.read(scheduleDraftProvider.notifier)..start();
      notifier.setTitle('버릴 일정');
      expect(container.read(scheduleDraftProvider)!.isDirty, isTrue);
      notifier.discard();
      expect(container.read(scheduleDraftProvider), isNull);
      notifier.start();
      expect(container.read(scheduleDraftProvider)!.title, '');
    });
  });
}

/// [failBackup]인 동안 백업 키 쓰기만 실패하는 저장소.
class _BackupSwitchPrefs implements SharedPreferences {
  _BackupSwitchPrefs(this._inner);

  final SharedPreferences _inner;
  bool failBackup = true;

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> setString(String key, String value) async =>
      failBackup && key == ScheduleBackupStore.storageKey
      ? false
      : _inner.setString(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
