import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_draft_provider.dart';
import 'package:tripbler/screens/schedule_screen.dart';
import 'package:tripbler/widgets/schedule/schedule_editor_sheet.dart';
import 'package:tripbler/widgets/schedule/schedule_time_wheel.dart';
import 'package:tripbler/widgets/schedule/schedule_timeline.dart';

import '../helpers/memory_schedule_storage.dart';
import '../helpers/schedule_screen_harness.dart';

// 저장한 일정 수정·삭제(docs/mockups/schedule.md 2-4절).

final _sheet = find.byType(ScheduleEditorSheet);
final _update = find.widgetWithText(FilledButton, '수정');
final _delete = find.widgetWithText(OutlinedButton, '삭제');
final _back = find.byTooltip('뒤로 가기');

const _sky = ScheduledPlace(
  name: '도쿄 스카이트리',
  address: '1-1-2 Oshiage',
  latitude: 35.7101,
  longitude: 139.8107,
  placeId: 'p2',
);

List<ScheduleItem> _items() => [
  scheduleItem(
    'a',
    title: '스카이트리 전망대',
    startsAt: DateTime(2026, 11, 28, 18),
    place: _sky,
    alarm: ScheduleAlarm.before10,
    memo: '예약 번호\nTS-2041',
  ),
  scheduleItem('b', title: '공항 이동', startsAt: DateTime(2026, 11, 29, 9)),
];

Finder _inSheet(Finder finder) => find.descendant(of: _sheet, matching: finder);

final _timeRow = find.byKey(const ValueKey('schedule-time'));
final _minuteWheel = find.byKey(const ValueKey('schedule-wheel-minute'));

/// 분 칸에서 지금 가운데(고른 칸)에 보이는 값.
int _centerMinute(WidgetTester tester) {
  final center = tester.getCenter(_minuteWheel).dy;
  final labels = find.descendant(of: _minuteWheel, matching: find.byType(Text));
  var best = -1;
  var bestDistance = double.infinity;
  for (var i = 0; i < labels.evaluate().length; i++) {
    final distance = (tester.getCenter(labels.at(i)).dy - center).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = int.parse(tester.widget<Text>(labels.at(i)).data!);
    }
  }
  return best;
}

/// '공항 이동'(11월 29일 오전 9:00) 수정 화면을 열고 시간 선택기를 펼친다.
Future<ScheduleScreenHarness> _openTimeWheel(WidgetTester tester) async {
  final h = await pumpScheduleScreen(tester, items: _items());
  await tester.tap(find.text('공항 이동'));
  await tester.pumpAndSettle();
  await tester.tap(_timeRow);
  await tester.pumpAndSettle();
  await tester.ensureVisible(_minuteWheel);
  await tester.pumpAndSettle();
  return h;
}

/// 분 칸을 던져 아직 굴러가는 중에 멈추고, 그 순간 가운데 값을 돌려준다.
Future<int> _flingMinute(WidgetTester tester) async {
  await tester.fling(_minuteWheel, const Offset(0, -120), 1000);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final position = tester
      .widget<ListWheelScrollView>(_minuteWheel)
      .controller!
      .position;
  expect(position.isScrollingNotifier.value, isTrue, reason: '아직 굴러가는 중');
  final minute = _centerMinute(tester);
  expect(minute, isNot(0));
  return minute;
}

String _nineOClock(int minute) => '오전 9:${minute.toString().padLeft(2, '0')}';

void main() {
  testWidgets('제목을 누르면 저장한 값이 채워진 수정 화면이 열린다', (tester) async {
    await pumpScheduleScreen(tester, items: _items());
    await tester.tap(find.text('스카이트리 전망대'));
    await tester.pumpAndSettle();

    expect(_sheet, findsOneWidget);
    expect(_inSheet(find.text('일정 수정')), findsOneWidget);
    expect(_back, findsOneWidget);
    expect(tester.getSize(_back), const Size(48, 48));
    expect(_update, findsOneWidget);
    expect(_delete, findsOneWidget);
    expect(find.widgetWithText(TextField, '스카이트리 전망대'), findsOneWidget);
    expect(find.widgetWithText(TextField, '도쿄 스카이트리'), findsOneWidget);
    expect(find.widgetWithText(TextField, '예약 번호\nTS-2041'), findsOneWidget);
    expect(_inSheet(find.text('11월 28일 (토) · 오늘')), findsOneWidget);
    expect(_inSheet(find.text('오후 6:00')), findsOneWidget);
    expect(_inSheet(find.text('10분 전 알림')), findsOneWidget);
    expect(
      _inSheet(find.text('1-1-2 Oshiage · 35.7101, 139.8107')),
      findsOneWidget,
    );
    // 수정은 키보드를 바로 띄우지 않는다.
    expect(
      tester.widget<TextField>(scheduleTitleField).focusNode!.hasFocus,
      isFalse,
    );
  });

  testWidgets('오른쪽 점을 눌러도 수정 화면이 열린다', (tester) async {
    await pumpScheduleScreen(tester, items: _items());
    final row = tester.getRect(find.bySemanticsLabel(RegExp('공항 이동')));
    await tester.tapAt(
      Offset(row.right - ScheduleTimeline.nodeColumnWidth / 2, row.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '공항 이동'), findsOneWidget);
    expect(_inSheet(find.text('알림 없음')), findsOneWidget);
  });

  testWidgets('바꾼 게 없으면 뒤로 가기·바깥 누르기·시스템 뒤로 가기로 바로 닫힌다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    Future<void> open() async {
      await tester.tap(find.text('공항 이동'));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
    }

    await open();
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);

    await open();
    await tester.tapAt(const Offset(200, 10));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);

    await open();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);

    expect(h.storage.saveCount, 0);
    expect(h.container.read(scheduleDraftProvider), isNull);
  });

  testWidgets('바꾼 게 있으면 뒤로 갈 때 버릴지 묻고, 버리면 저장한 값이 그대로다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    await tester.tap(find.text('공항 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(scheduleTitleField, '나리타 공항 이동');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.discardEditQuestion), findsOneWidget);
    await tester.tap(find.text('계속 수정'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '나리타 공항 이동'), findsOneWidget);

    await tester.tap(_back);
    await tester.pumpAndSettle();
    await tester.tap(find.text('버리기'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.text('공항 이동'), findsOneWidget);
    expect(h.storage.saveCount, 0);
  });

  testWidgets('수정하면 저장하고 시간순 자리로 옮긴다(id·만든 시각 유지)', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    await tester.tap(find.text('공항 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(scheduleTitleField, '아침 공항 이동');
    await tester.tap(find.byKey(const ValueKey('schedule-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('11월 28일 (토) · 오늘'));
    await tester.pumpAndSettle();
    await tester.tap(_update);
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    final stored = h.storage.stored;
    expect(stored.map((i) => i.id), ['b', 'a']);
    expect(stored.first.title, '아침 공항 이동');
    expect(stored.first.startsAt, DateTime(2026, 11, 28, 9));
    expect(stored.first.createdAt, DateTime(2026, 11, 1));
    // 타임라인도 새 순서다.
    final top = tester.getTopLeft(find.text('아침 공항 이동')).dy;
    expect(top, lessThan(tester.getTopLeft(find.text('스카이트리 전망대')).dy));
    expect(find.text('11월 28일 (토) · 오전 9:00'), findsOneWidget);
  });

  testWidgets('수정할 때 제목을 비우면 안내하고, 저장에 실패하면 화면과 입력값을 유지한다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    await tester.tap(find.text('공항 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(scheduleTitleField, '  ');
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.titleRequiredMessage), findsOneWidget);

    await tester.enterText(scheduleTitleField, '공항 버스');
    h.storage.failSave = true;
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(find.text(ScheduleEditorSheet.saveFailedMessage), findsOneWidget);
    expect(find.widgetWithText(TextField, '공항 버스'), findsOneWidget);
    expect(h.storage.stored.last.title, '공항 이동');
  });

  testWidgets('삭제는 한 번 확인한 뒤 지우고, 마지막 일정을 지우면 빈 상태로 돌아간다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: [_items().last]);
    await tester.tap(find.text('공항 이동'));
    await tester.pumpAndSettle();

    await tester.tap(_delete);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.deleteQuestion), findsOneWidget);
    expect(find.text('삭제한 일정은 되돌릴 수 없어요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(h.storage.saveCount, 0);

    await tester.tap(_delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(h.storage.stored, isEmpty);
    expect(find.text(ScheduleScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('삭제에 실패하면 화면을 닫지 않고 안내하며 일정은 남는다', (tester) async {
    final h = await pumpScheduleScreen(tester, items: _items());
    await tester.tap(find.text('공항 이동'));
    await tester.pumpAndSettle();
    h.storage.failSave = true;
    await tester.tap(_delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(_sheet, findsOneWidget);
    expect(find.text(ScheduleEditorSheet.deleteFailedMessage), findsOneWidget);
    expect(h.storage.stored, hasLength(2));
  });

  testWidgets('분 칸이 굴러가는 중에 수정을 누르면 누른 순간 가운데 값으로 저장한다', (tester) async {
    final h = await _openTimeWheel(tester);
    // 저장 실패로 카드를 남겨, 누른 뒤의 휠·줄 표시도 확인한다.
    h.storage.failSave = true;
    final minute = await _flingMinute(tester);
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.saveFailedMessage), findsOneWidget);
    expect(_inSheet(find.text(_nineOClock(minute))), findsOneWidget);
    expect(_centerMinute(tester), minute);
    expect(
      tester.widget<ScheduleTimeWheel>(find.byType(ScheduleTimeWheel)).minute,
      minute,
    );

    h.storage.failSave = false;
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    final saved = h.storage.stored.singleWhere((i) => i.id == 'b');
    expect(saved.startsAt, DateTime(2026, 11, 29, 9, minute));
  });

  testWidgets('굴러가는 중에 시간 줄을 눌러 접으면 그 순간 가운데 값이 남고, 다시 펼쳐도 같다', (tester) async {
    await _openTimeWheel(tester);
    final minute = await _flingMinute(tester);
    // 줄이 보이게 판만 옮긴다(시간을 흘리지 않아 휠은 계속 굴러가는 중이다).
    await tester.ensureVisible(_timeRow);
    await tester.pump();
    await tester.tap(_timeRow);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleTimeWheel), findsNothing);
    expect(_inSheet(find.text(_nineOClock(minute))), findsOneWidget);

    await tester.tap(_timeRow);
    await tester.pumpAndSettle();
    expect(_centerMinute(tester), minute);
    expect(
      tester.widget<ScheduleTimeWheel>(find.byType(ScheduleTimeWheel)).minute,
      minute,
    );
  });

  testWidgets('시간만 굴리는 중에 뒤로 가도 버릴지 묻는다', (tester) async {
    final h = await _openTimeWheel(tester);
    await _flingMinute(tester);
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.discardEditQuestion), findsOneWidget);
    await tester.tap(find.text('버리기'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(h.storage.saveCount, 0);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('폭 320·글자 배율 $scale에서 수정 화면이 넘치지 않는다', (tester) async {
      await pumpScheduleScreen(
        tester,
        items: _items(),
        size: const Size(320, 640),
        textScale: scale,
      );
      await tester.tap(find.text('스카이트리 전망대'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_update, findsOneWidget);
      expect(tester.getSize(_sheet).height, lessThanOrEqualTo(640 * 0.9 + 0.5));
    });
  }
}
