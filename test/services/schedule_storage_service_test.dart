import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/schedule/schedule_data.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/services/schedule/schedule_backup_store.dart';
import 'package:tripbler/services/schedule/schedule_payload.dart';
import 'package:tripbler/services/schedule/schedule_storage_service.dart';

import '../helpers/memory_schedule_storage.dart';

void main() {
  const key = ScheduleStorageService.storageKey;
  const backupKey = ScheduleBackupStore.storageKey;
  final good = scheduleItem('ok', startsAt: DateTime(2026, 11, 28, 9));
  var clock = DateTime(2026, 11, 28, 9);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 28, 9);
  });

  ScheduleBackupStore store() => ScheduleBackupStore(now: () => clock);
  ScheduleStorageService service() => ScheduleStorageService(backups: store());
  String v1(List<Object?> items) => jsonEncode({'version': 1, 'items': items});
  String v2(List<Object?> items, [List<Object?> archived = const []]) =>
      jsonEncode({'version': 2, 'items': items, 'archived': archived});
  Future<List<ScheduleBackup>> backups() => store().list();

  group('저장·읽기', () {
    test('타임라인 순서와 보관함을 그대로 다시 읽는다(장소·알림·메모·줄바꿈·이모지 포함)', () async {
      final items = [
        scheduleItem('late', startsAt: DateTime(2026, 11, 29, 9)),
        scheduleItem(
          'a',
          startsAt: DateTime(2026, 11, 28, 14, 30),
          title: '😀' * ScheduleItem.titleMaxLength,
          place: const ScheduledPlace(
            name: '센소지',
            address: '2-3-1 Asakusa',
            latitude: 35.7148,
            longitude: 139.7967,
            placeId: 'p1',
          ),
          alarm: ScheduleAlarm.before30,
          memo: '줄 1\n${'👍🏽' * 10}',
        ),
      ];
      final archived = [
        ArchivedScheduleItem(
          item: scheduleItem('z', startsAt: DateTime(2026, 11, 30, 9)),
          archivedAt: DateTime(2026, 11, 28, 8),
        ),
      ];
      await service().save(ScheduleData(items: items, archived: archived));

      final loaded = await service().load();
      expect(loaded.items.map((i) => i.id), ['late', 'a'], reason: '순서 유지');
      final a = loaded.items.last;
      expect(a.startsAt, DateTime(2026, 11, 28, 14, 30));
      expect(a.title, items.last.title);
      expect(a.place!.placeId, 'p1');
      expect(a.alarm, ScheduleAlarm.before30);
      expect(a.memo, items.last.memo);
      expect(loaded.archived.single.item.id, 'z');
      expect(loaded.archived.single.archivedAt, DateTime(2026, 11, 28, 8));
      expect(await backups(), isEmpty, reason: '정상 저장값은 보관하지 않는다');
    });

    test('예전 버전 1 저장값은 시간순으로 읽고 보관하지 않는다(다음 저장에서 버전 2로)', () async {
      final late = scheduleItem('late', startsAt: DateTime(2026, 11, 29, 9));
      SharedPreferences.setMockInitialValues({
        key: v1([late.toJson(), good.toJson()]),
      });
      final loaded = await service().load();
      expect(loaded.items.map((i) => i.id), ['ok', 'late']);
      expect(loaded.archived, isEmpty);
      expect(await backups(), isEmpty);

      await service().save(loaded);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(key)!)['version'], 2);
    });

    test('정수 좌표·키 순서·null 필드·생략한 기본값·다른 날짜 표기는 바뀐 값으로 보지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        key: v2([
          {
            'createdAt': '2026-11-01',
            'title': '센소지',
            'place': {
              'longitude': 139,
              'name': '센소지',
              'latitude': 35,
              'address': null,
            },
            'startsAt': '2026-11-28T09:00:00Z',
            'id': 'int',
          },
          {...good.toJson(), 'place': null},
        ]),
      });
      final loaded = await service().load();
      expect(loaded.items.map((i) => i.id), ['int', 'ok']);
      expect(await backups(), isEmpty);
    });

    test('저장값이 없으면 빈 값이고 보관하지 않는다', () async {
      final loaded = await service().load();
      expect(loaded.items, isEmpty);
      expect(await backups(), isEmpty);
    });

    test('해석할 수 없는 값·새 버전 값은 원래 값을 보관하고 빈 값으로 시작한다', () async {
      for (final (raw, status) in [
        ('{', ScheduleReadStatus.corrupt),
        ('[]', ScheduleReadStatus.corrupt),
        ('{"version":1}', ScheduleReadStatus.corrupt),
        ('{"version":2,"items":{}}', ScheduleReadStatus.corrupt),
        ('{"version":9,"items":[]}', ScheduleReadStatus.newerVersion),
      ]) {
        SharedPreferences.setMockInitialValues({key: raw});
        final loaded = await service().load();
        expect(loaded.items, isEmpty, reason: raw);
        final saved = await backups();
        expect(saved.single.raw, raw, reason: raw);
        expect(saved.single.kind, ScheduleBackupKind.auto);
        expect(SchedulePayload.decode(raw).status, status, reason: raw);
      }
    });

    test('일부 항목을 버렸거나 살린 값이 바뀌면 원래 값을 보관하고 살린 값을 돌려준다', () async {
      for (final bad in [
        {...good.toJson(), 'id': 'bad', 'startsAt': 'yesterday'},
        {...good.toJson(), 'id': 'long', 'title': '😀' * 60},
        {...good.toJson(), 'id': 'unknown', 'color': 'red'},
        {...good.toJson()}, // 같은 id
      ]) {
        final raw = v2([good.toJson(), bad]);
        SharedPreferences.setMockInitialValues({key: raw});
        final loaded = await service().load();
        expect(loaded.items.first.id, 'ok', reason: '$bad');
        expect((await backups()).single.raw, raw, reason: '$bad');
      }
    });

    test('같은 원래 값은 다시 보관하지 않는다', () async {
      SharedPreferences.setMockInitialValues({key: '{'});
      await service().load();
      await service().load();
      expect(await backups(), hasLength(1));
    });

    test('저장소를 열지 못하거나 보관하지 못하면 예외로 알린다(덮어쓰기 방지)', () async {
      final broken = ScheduleStorageService(
        prefs: () => Future.error(StateError('no prefs')),
      );
      await expectLater(
        broken.load(),
        throwsA(isA<ScheduleStorageException>()),
      );
      await expectLater(
        broken.save(ScheduleData.empty),
        throwsA(isA<ScheduleStorageException>()),
      );

      SharedPreferences.setMockInitialValues({key: '{'});
      final prefs = await SharedPreferences.getInstance();
      final failing = ScheduleStorageService(
        prefs: () async => prefs,
        backups: ScheduleBackupStore(prefs: () async => _NoBackupPrefs(prefs)),
      );
      await expectLater(
        failing.load(),
        throwsA(isA<ScheduleStorageException>()),
      );
      expect(prefs.getString(key), '{');
    });
  });

  group('기기 백업 목록', () {
    test('직접 백업은 최근 3개만 남기고, 읽지 못해 보관한 백업은 지우지 않는다', () async {
      final s = store();
      await s.addAuto('broken-1');
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(minutes: 1));
        await s.addManual('manual-$i');
        await s.addAuto('broken-${i + 2}');
      }
      final list = await s.list();
      final manual = list.where((b) => b.kind == ScheduleBackupKind.manual);
      final auto = list.where((b) => b.kind == ScheduleBackupKind.auto);
      expect(manual.map((b) => b.raw), ['manual-4', 'manual-3', 'manual-2']);
      expect(auto, hasLength(6), reason: '개수에 세지 않고 남는다');
      expect(list.first.raw, 'broken-6', reason: '새 것부터');
    });

    test('지우기와 확인 기록은 고른 백업에만 적용된다', () async {
      final s = store();
      await s.addAuto('a');
      await s.addAuto('b');
      final [b, a] = await s.list();
      await s.markSeen({a.id});
      expect((await s.list()).map((x) => x.seen), [false, true]);
      await s.delete({b.id});
      expect((await s.list()).single.raw, 'a');
    });

    test('목록 저장값이 깨졌으면 쓰기 전에 원래 문자열을 따로 남긴다(전체·일부 항목)', () async {
      const damagedKey = ScheduleBackupStore.damagedKey;
      final partial = jsonEncode([
        {'savedAt': '2026-11-27T09:00:00.000', 'raw': 'old'},
        {'savedAt': 'bad'},
      ]);
      for (final value in ['{', '{"a":1}', partial]) {
        SharedPreferences.setMockInitialValues({backupKey: value});
        final s = store();
        await s.addAuto('new');
        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString(damagedKey)!), [
          value,
        ], reason: value);
        final raws = (await s.list()).map((b) => b.raw);
        expect(raws, contains('new'), reason: value);
        if (value == partial) expect(raws, contains('old'));

        // 같은 깨진 값은 한 번만 남기고, 다음 쓰기에서는 이미 정상 목록이다.
        await s.addManual('m');
        expect(jsonDecode(prefs.getString(damagedKey)!), [value]);
      }
    });

    test('깨진 원래 문자열을 남기지 못하면 목록을 쓰지 않는다', () async {
      SharedPreferences.setMockInitialValues({backupKey: '{'});
      final prefs = await SharedPreferences.getInstance();
      final s = ScheduleBackupStore(
        prefs: () async => _FailKeyPrefs(prefs, ScheduleBackupStore.damagedKey),
      );
      await expectLater(
        s.addManual('m'),
        throwsA(isA<ScheduleStorageException>()),
      );
      expect(prefs.getString(backupKey), '{');
    });

    test('예전 형식 항목(savedAt·raw만)은 읽지 못해 보관한 백업으로 읽는다', () async {
      SharedPreferences.setMockInitialValues({
        backupKey: jsonEncode([
          {'savedAt': '2026-11-27T09:00:00.000', 'raw': '{'},
          'not a map',
        ]),
      });
      final single = (await store().list()).single;
      expect(single.kind, ScheduleBackupKind.auto);
      expect(single.seen, isFalse);
      expect(single.id, isNotEmpty);
    });
  });
}

/// 백업 키 쓰기만 실패하는 저장소.
class _NoBackupPrefs implements SharedPreferences {
  _NoBackupPrefs(this._inner);

  final SharedPreferences _inner;

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> setString(String key, String value) async =>
      key == ScheduleBackupStore.storageKey
      ? false
      : _inner.setString(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [failKey] 쓰기만 실패하는 저장소.
class _FailKeyPrefs implements SharedPreferences {
  _FailKeyPrefs(this._inner, this.failKey);

  final SharedPreferences _inner;
  final String failKey;

  @override
  String? getString(String key) => _inner.getString(key);

  @override
  Future<bool> setString(String key, String value) async =>
      key == failKey ? false : _inner.setString(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
