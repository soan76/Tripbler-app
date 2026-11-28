import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/schedule/schedule_item.dart';
import 'package:tripbler/providers/schedule/schedule_draft_provider.dart';
import 'package:tripbler/providers/schedule/schedule_provider.dart';
import 'package:tripbler/screens/place_picker_screen.dart';
import 'package:tripbler/screens/schedule_screen.dart';
import 'package:tripbler/widgets/schedule/schedule_calendar.dart';
import 'package:tripbler/widgets/schedule/schedule_editor_sheet.dart';
import 'package:tripbler/widgets/schedule/schedule_time_wheel.dart';
import 'package:tripbler/widgets/schedule/schedule_timeline.dart';

import '../helpers/fake_place_api.dart';
import '../helpers/memory_schedule_storage.dart';
import '../helpers/schedule_screen_harness.dart';

final _titleField = scheduleTitleField;
final _placeField = schedulePlaceField;
final _memoField = scheduleMemoField;
final _addFirst = scheduleAddFirst;
final _addNext = scheduleAddNext;
final _save = find.widgetWithText(FilledButton, '저장');
final _cancel = find.widgetWithText(OutlinedButton, '취소');

/// 휠 [column]('meridiem'·'hour'·'minute') 안의 [label] 칸.
Finder _wheelItem(String column, String label) => find.descendant(
  of: find.byKey(ValueKey('schedule-wheel-$column')),
  matching: find.text(label),
);

void main() {
  late MemoryScheduleStorage storage;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    List<ScheduleItem> items = const [],
    Size size = const Size(400, 800),
    double textScale = 1,
  }) async {
    final harness = await pumpScheduleScreen(
      tester,
      items: items,
      size: size,
      textScale: textScale,
    );
    storage = harness.storage;
    container = harness.container;
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(_addFirst.evaluate().isNotEmpty ? _addFirst : _addNext);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorSheet), findsOneWidget);
  }

  testWidgets('일정이 없으면 가운데 +와 안내를 보이고, +를 누르면 입력 카드가 열린다', (tester) async {
    await pump(tester);
    expect(find.text(ScheduleScreen.emptyMessage), findsOneWidget);
    expect(tester.getSize(_addFirst), const Size(72, 72));

    await openEditor(tester);
    expect(find.text('일정 추가'), findsOneWidget);
    // 기본값: 오늘, 지금 다음 정시, 알림 없음.
    expect(find.text('11월 28일 (토) · 오늘'), findsOneWidget);
    expect(find.text('오후 3:00'), findsOneWidget);
    expect(find.text('알림 없음'), findsOneWidget);
  });

  testWidgets('제목 없이 저장하면 안내를 보이고 제목에 초점을 둔다', (tester) async {
    await pump(tester);
    await openEditor(tester);
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(find.text(ScheduleEditorSheet.titleRequiredMessage), findsOneWidget);
    expect(tester.widget<TextField>(_titleField).focusNode!.hasFocus, isTrue);
    expect(storage.saveCount, 0);
    expect(find.byType(ScheduleEditorSheet), findsOneWidget);
  });

  testWidgets('저장하면 카드가 닫히고 타임라인·끝의 점선과 +가 보인다, 앱을 다시 켜도 남는다', (tester) async {
    await pump(tester);
    await openEditor(tester);
    await tester.enterText(_titleField, '센소지 구경');
    await tester.enterText(_placeField, '아사쿠사');
    await tester.enterText(_memoField, '예약 TS-2041');
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(find.byType(ScheduleEditorSheet), findsNothing);
    expect(find.byType(ScheduleTimeline), findsOneWidget);
    expect(find.text('센소지 구경'), findsOneWidget);
    expect(find.text('11월 28일 (토) · 오후 3:00'), findsOneWidget);
    expect(find.text('아사쿠사'), findsOneWidget);
    expect(find.text(ScheduleTimeline.addHint), findsOneWidget);
    expect(_addNext, findsOneWidget);
    expect(storage.stored.single.title, '센소지 구경');

    // 같은 저장소로 새로 시작해도(앱 재실행) 일정이 남는다.
    final saved = [...storage.stored];
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await pump(tester, items: saved);
    expect(find.text('센소지 구경'), findsOneWidget);
  });

  testWidgets('저장에 실패하면 카드를 닫지 않고 입력값을 그대로 두며 안내한다', (tester) async {
    await pump(tester);
    await openEditor(tester);
    await tester.enterText(_titleField, '공항 이동');
    await tester.enterText(_memoField, '여권');
    storage.failSave = true;
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(find.byType(ScheduleEditorSheet), findsOneWidget);
    expect(find.text(ScheduleEditorSheet.saveFailedMessage), findsOneWidget);
    expect(find.widgetWithText(TextField, '공항 이동'), findsOneWidget);
    expect(find.widgetWithText(TextField, '여권'), findsOneWidget);

    storage.failSave = false;
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorSheet), findsNothing);
    expect(find.text('공항 이동'), findsOneWidget);
  });

  testWidgets('입력 없이 취소하면 바로 닫히고, 입력이 있으면 버릴지 묻는다', (tester) async {
    await pump(
      tester,
      items: [scheduleItem('a', startsAt: DateTime(2026, 11, 28, 18))],
    );
    await openEditor(tester);
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorSheet), findsNothing);

    await openEditor(tester);
    await tester.enterText(_titleField, '긴자 쇼핑');
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.discardQuestion), findsOneWidget);

    await tester.tap(find.text('계속 쓰기'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '긴자 쇼핑'), findsOneWidget);

    // 바깥(어두운 배경)을 눌러도 같은 확인을 거친다.
    await tester.tapAt(const Offset(200, 10));
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditorSheet.discardQuestion), findsOneWidget);
    await tester.tap(find.text('버리기'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditorSheet), findsNothing);
    expect(container.read(scheduleDraftProvider), isNull);
    expect(storage.saveCount, 0);
    expect(find.text('일정 a'), findsOneWidget);
  });

  testWidgets('시간·날짜·알림을 고르면 값이 바뀌고, 지난 알림 시각을 알린다', (tester) async {
    await pump(tester);
    await openEditor(tester);

    // 선택기는 처음에 접혀 있다.
    expect(find.byType(ScheduleTimeWheel), findsNothing);
    expect(find.byType(ScheduleCalendar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('schedule-time')));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleTimeWheel), findsOneWidget);
    await tester.tap(_wheelItem('hour', '2'));
    await tester.pumpAndSettle();
    await tester.tap(_wheelItem('minute', '02'));
    await tester.pumpAndSettle();
    // 고른 값은 바로 보이고 선택기는 열려 있다.
    expect(find.text('오후 2:02'), findsOneWidget);
    expect(find.byType(ScheduleTimeWheel), findsOneWidget);

    // 휠이 펼쳐지면 아래 항목이 밀리므로 알림 줄이 보이게 스크롤한다.
    await tester.ensureVisible(find.text('알림 없음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('알림 없음'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30분 전'));
    await tester.pumpAndSettle();
    expect(find.text('30분 전 알림'), findsOneWidget);
    expect(find.text(ScheduleEditorSheet.alarmPassedMessage), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('schedule-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-date')));
    await tester.pumpAndSettle();
    expect(find.text('2026년 11월'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('11월 30일 (월)'));
    await tester.pumpAndSettle();
    expect(find.text('11월 30일 (월)'), findsOneWidget);
    expect(find.byType(ScheduleCalendar), findsOneWidget);
    expect(find.text(ScheduleEditorSheet.alarmPassedMessage), findsNothing);
    expect(find.text(ScheduleEditorSheet.alarmNotSentMessage), findsOneWidget);

    // 다시 누르면 접히고, 다시 펼쳐도 고른 값이 그대로다.
    await tester.ensureVisible(find.byKey(const ValueKey('schedule-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-time')));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleTimeWheel), findsNothing);
    await tester.tap(find.byKey(const ValueKey('schedule-time')));
    await tester.pumpAndSettle();
    final wheel = tester.widget<ScheduleTimeWheel>(
      find.byType(ScheduleTimeWheel),
    );
    expect((wheel.hour, wheel.minute), (14, 2));

    await tester.enterText(_titleField, '분 단위 일정');
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(storage.stored.single.startsAt, DateTime(2026, 11, 30, 14, 2));
    expect(find.text('11월 30일 (월) · 오후 2:02'), findsOneWidget);
  });

  testWidgets('장소 고르기 화면을 닫고 돌아와도 작성 내용과 장소가 그대로다', (tester) async {
    await pump(tester);
    await openEditor(tester);
    await tester.enterText(_titleField, '츠키지 아침 식사');
    await tester.enterText(_placeField, '츠키지');

    await tester.tap(find.byTooltip('지도에서 장소 고르기'));
    await tester.pumpAndSettle();
    expect(find.byType(PlacePickerScreen), findsOneWidget);
    expect(find.text(PlacePickerScreen.title), findsOneWidget);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(PlacePickerScreen), findsNothing);
    expect(find.widgetWithText(TextField, '츠키지 아침 식사'), findsOneWidget);
    expect(find.widgetWithText(TextField, '츠키지'), findsOneWidget);
    expect(container.read(scheduleDraftProvider)!.title, '츠키지 아침 식사');
  });

  testWidgets('장소 고르기에서 고른 장소가 장소 칸과 주소·좌표 줄을 채운다', (tester) async {
    await pump(tester);
    await openEditor(tester);
    await tester.tap(find.byTooltip('지도에서 장소 고르기'));
    await tester.pumpAndSettle();

    final place = testPlace('p1');
    Navigator.of(
      tester.element(find.byType(PlacePickerScreen)),
    ).pop(PlacePickerScreen.toScheduledPlace(place));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '장소 p1'), findsOneWidget);
    expect(find.text('주소 p1 · 37.5000, 126.9000'), findsOneWidget);
    expect(container.read(scheduleDraftProvider)!.pickedPlace!.placeId, 'p1');
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('폭 320·높이 640·글자 배율 $scale에서 넘치지 않고 카드는 화면의 90% 안이다', (
      tester,
    ) async {
      await pump(
        tester,
        size: const Size(320, 640),
        textScale: scale,
        items: [
          for (var h = 8; h < 20; h += 2)
            scheduleItem(
              'i$h',
              title: '아주 긴 일정 제목이 줄을 넘어가도 잘리지 않는지 보는 일정 $h',
              startsAt: DateTime(2026, 11, 28, h),
              place: const ScheduledPlace(name: '이름이 꽤 긴 장소 이름'),
            ),
        ],
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(_addNext, 200);
      // 목록은 보이는 줄만 만들므로 찾은 뒤에도 화면 안으로 끌어온다.
      await tester.ensureVisible(_addNext);
      await tester.pumpAndSettle();
      await openEditor(tester);
      expect(tester.takeException(), isNull);
      final sheetHeight = tester
          .getSize(find.byType(ScheduleEditorSheet))
          .height;
      expect(sheetHeight, lessThanOrEqualTo(640 * 0.9 + 0.5));
      // 날짜·시간 칸은 두 줄로 놓인다.
      final date = tester.getRect(find.byKey(const ValueKey('schedule-date')));
      final time = tester.getRect(find.byKey(const ValueKey('schedule-time')));
      expect(time.top, greaterThanOrEqualTo(date.bottom));
      // 두 선택기를 펼쳐도 넘치지 않는다.
      await tester.tap(find.byKey(const ValueKey('schedule-date')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('schedule-time')));
      await tester.tap(find.byKey(const ValueKey('schedule-time')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final wheel = tester.getRect(find.byType(ScheduleTimeWheel));
      expect(wheel.right, lessThanOrEqualTo(320));
    });
  }

  testWidgets('키보드가 열리면 하단 버튼이 키보드 위에 남는다', (tester) async {
    await pump(tester, size: const Size(360, 740));
    await openEditor(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(tester.getRect(_save).bottom, lessThanOrEqualTo(740 - 300));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('폭 320·높이 640·글자 배율 $scale에서 두 선택기를 펼친 채 키보드가 열려도 넘치지 않는다', (
      tester,
    ) async {
      await pump(tester, size: const Size(320, 640), textScale: scale);
      await openEditor(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-date')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('schedule-time')));
      await tester.tap(find.byKey(const ValueKey('schedule-time')));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleCalendar), findsOneWidget);
      expect(find.byType(ScheduleTimeWheel), findsOneWidget);

      await tester.showKeyboard(_titleField);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_save).bottom, lessThanOrEqualTo(640 - 300));
      // 펼친 선택기는 그대로이고 값도 그대로다.
      expect(find.byType(ScheduleTimeWheel), findsOneWidget);
      expect(container.read(scheduleDraftProvider)!.startsAt, isNotNull);
    });
  }

  testWidgets('불러오기에 실패하면 안내와 다시 시도를 보인다', (tester) async {
    final failing = MemoryScheduleStorage()..failLoad = true;
    await pump(tester);
    container.dispose();
    container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [scheduleStorageServiceProvider.overrideWithValue(failing)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ScheduleScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(ScheduleScreen.loadFailedMessage), findsOneWidget);

    failing.failLoad = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text(ScheduleScreen.emptyMessage), findsOneWidget);
  });
}
