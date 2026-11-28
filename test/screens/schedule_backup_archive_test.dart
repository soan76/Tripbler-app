import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';
import 'package:tripbler/screens/schedule_archive_screen.dart';
import 'package:tripbler/screens/schedule_backup_detail_screen.dart';
import 'package:tripbler/screens/schedule_backup_screen.dart';
import 'package:tripbler/screens/schedule_screen.dart';
import 'package:tripbler/services/schedule/schedule_backup_store.dart';
import 'package:tripbler/widgets/schedule/schedule_editor_sheet.dart';

import '../helpers/memory_schedule_storage.dart';
import '../helpers/schedule_screen_harness.dart';

// 보관함·기기 백업 화면(schedule.md 4절, 목업 schedule-backup.html)과 길게 눌러 순서 바꾸기(2-2).

final _backupNow = find.byKey(const ValueKey('schedule-backup-now'));
final _deleteAll = find.byKey(const ValueKey('schedule-backup-delete-all'));
final _restore = find.byKey(const ValueKey('schedule-backup-restore'));

List<ScheduleItem> _items() => [
  scheduleItem('a', title: '나리타 공항 도착', startsAt: DateTime(2026, 11, 28, 16)),
  scheduleItem('b', title: '센소지 구경', startsAt: DateTime(2026, 11, 28, 18)),
];

/// 읽지 못해 보관한 백업 하나(예전 형식 항목).
final _autoBackup = {
  ScheduleBackupStore.storageKey: jsonEncode([
    {'savedAt': '2026-11-28T08:00:00.000', 'raw': '{'},
  ]),
};

BuildContext _ctx(WidgetTester tester) =>
    tester.element(find.byType(ScheduleScreen));

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

void main() {
  testWidgets('읽지 못한 일정 알림: 확인하면 기기 백업 목록으로 가고, 돌아오면 다시 뜨지 않는다', (
    tester,
  ) async {
    await pumpScheduleScreen(tester, items: _items(), prefs: _autoBackup);
    expect(find.text(ScheduleScreen.unreadNotice), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schedule-unread-open')));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleBackupScreen), findsOneWidget);
    expect(find.text('읽지 못해 보관'), findsOneWidget);
    expect(find.text('내용이 손상돼 읽을 수 없어요'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(ScheduleScreen.unreadNotice), findsNothing);
  });

  testWidgets('읽지 못한 일정 알림을 닫아도 다시 뜨지 않고, 타임라인 스크롤 위치는 그대로다', (tester) async {
    await pumpScheduleScreen(
      tester,
      prefs: _autoBackup,
      items: [
        for (var h = 6; h < 22; h++)
          scheduleItem('i$h', startsAt: DateTime(2026, 11, 28, h)),
      ],
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pumpAndSettle();
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('schedule-unread-close')));
    await tester.pumpAndSettle();
    expect(find.text(ScheduleScreen.unreadNotice), findsNothing);
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, before, reason: '타임라인을 새로 만들지 않는다');
  });

  testWidgets('지금 백업 → 같은 내용이면 꺼짐 → 삭제 확인창이 대상과 영향을 알린다', (tester) async {
    await pumpScheduleScreen(tester, items: _items());
    ScheduleBackupScreen.open(_ctx(tester));
    await tester.pumpAndSettle();
    expect(find.text('기기 백업이 없어요.'), findsOneWidget);
    expect(_enabled(tester, _deleteAll), isFalse);

    await tester.tap(_backupNow);
    await tester.pumpAndSettle();
    expect(find.text('직접 백업'), findsOneWidget);
    expect(find.text('되살릴 수 있는 일정 2개'), findsOneWidget);
    expect(_enabled(tester, _backupNow), isFalse);
    expect(find.text('지금 일정이 마지막 직접 백업과 같아요.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('백업 삭제\$')));
    await tester.pumpAndSettle();
    expect(find.textContaining('을(를) 삭제할까요?'), findsOneWidget);
    expect(find.text('지금 일정과 보관함은 바뀌지 않아요.'), findsOneWidget);
    expect(find.textContaining('잃는 일정은 없어요'), findsOneWidget);
    expect(find.text('삭제한 백업은 되돌릴 수 없어요.'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, '삭제'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기기 백업이 없어요.'), findsOneWidget);
  });

  testWidgets('되살리기: 이미 있는 일정은 고르지 않고, 고른 일정만 더한 뒤 일정 화면으로 돌아간다', (
    tester,
  ) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    ScheduleBackupScreen.open(_ctx(tester));
    await tester.pumpAndSettle();
    await tester.tap(_backupNow);
    await tester.pumpAndSettle();
    await h.container.read(scheduleProvider.notifier).remove('a');

    await tester.tap(find.text('직접 백업'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleBackupDetailScreen), findsOneWidget);
    expect(find.text('이미 있음'), findsOneWidget);
    expect(find.text('이미 있는 일정 1개는 처음에 고르지 않았어요.'), findsOneWidget);
    final boxes = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(boxes.map((b) => b.value), [true, false], reason: 'a 고름, b 안 고름');

    await tester.tap(_restore);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleBackupScreen), findsNothing);
    expect(find.text('나리타 공항 도착'), findsOneWidget);
    expect(h.storage.stored.map((i) => i.id), ['a', 'b']);
  });

  testWidgets('되살리기는 일정을 불러오지 못한 상태에서 막는다', (tester) async {
    final h = await pumpScheduleScreen(
      tester,
      prefs: {
        ScheduleBackupStore.storageKey: jsonEncode([
          {
            'id': 'm1',
            'kind': 'manual',
            'savedAt': '2026-11-28T08:00:00.000',
            'raw': jsonEncode({
              'version': 2,
              'items': [_items().first.toJson()],
              'archived': [],
            }),
          },
        ]),
      },
    );
    h.storage.failLoad = true;
    h.container.invalidate(scheduleProvider);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleScreen.loadFailedMessage), findsOneWidget);

    ScheduleBackupDetailScreen.open(_ctx(tester), 'm1');
    await tester.pumpAndSettle();
    expect(find.text(ScheduleBackupDetailScreen.blockedLabel), findsOneWidget);
    expect(_enabled(tester, _restore), isFalse);
  });

  testWidgets('수정 화면의 보관함으로 이동 → 보관함에서 다시 꺼내기·삭제', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    await tester.tap(find.text('센소지 구경'));
    await tester.pumpAndSettle();
    final move = find.byKey(const ValueKey('schedule-move-to-archive'));
    await tester.ensureVisible(move);
    await tester.pumpAndSettle();
    await tester.tap(move);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorSheet), findsNothing);
    expect(find.text('센소지 구경'), findsNothing);
    expect(h.storage.archived.single.item.id, 'b');

    ScheduleArchiveScreen.open(_ctx(tester));
    await tester.pumpAndSettle();
    expect(find.text('센소지 구경'), findsOneWidget);
    await tester.tap(find.text('센소지 구경'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '다시 꺼내기'));
    await tester.pumpAndSettle();
    expect(find.text(ScheduleArchiveScreen.emptyMessage), findsOneWidget);
    expect(h.storage.stored.map((i) => i.id), ['a', 'b']);

    // 다시 보관한 뒤 보관함에서 삭제(확인창에 대상과 영향).
    await h.container.read(scheduleProvider.notifier).archive('a');
    await tester.pumpAndSettle();
    await tester.tap(find.text('나리타 공항 도착'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '삭제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('보관함에서만 지워져요'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();
    expect(h.storage.archived, isEmpty);
    expect(h.storage.stored.map((i) => i.id), ['b']);
  });

  testWidgets('길게 눌러 끌면 순서만 바뀌고, 짧게 누르면 수정 화면이 열린다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    final first = tester.getCenter(find.text('나리타 공항 도착'));
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      find.byType(ScheduleEditorSheet),
      findsNothing,
      reason: '끈 뒤에는 안 열림',
    );
    expect(h.storage.stored.map((i) => i.id), ['b', 'a']);
    expect(h.storage.stored.last.startsAt, DateTime(2026, 11, 28, 16));
    final top = tester.getTopLeft(find.text('센소지 구경')).dy;
    expect(top, lessThan(tester.getTopLeft(find.text('나리타 공항 도착')).dy));

    await tester.tap(find.text('센소지 구경'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorSheet), findsOneWidget);
  });

  testWidgets('낭독기의 아래로 옮기기 동작으로도 순서를 바꾼다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    final semantics = tester.ensureSemantics();
    final row = tester.getSemantics(find.bySemanticsLabel(RegExp('나리타 공항 도착')));
    final action = row.getSemanticsData().customSemanticsActionIds!.single;
    row.owner!.performAction(row.id, SemanticsAction.customAction, action);
    await tester.pumpAndSettle();
    expect(h.storage.stored.map((i) => i.id), ['b', 'a']);
    semantics.dispose();
  });
}
