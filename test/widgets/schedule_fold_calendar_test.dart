import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/schedule/schedule_calendar.dart';
import 'package:tripbler/widgets/schedule/schedule_sheet_parts.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(child: SizedBox(width: 240, child: child)),
      ),
    ),
  ),
);

Widget _fold(bool open) => ScheduleFold(
  open: open,
  child: const SizedBox(key: ValueKey('fold-content'), height: 100),
);

void main() {
  const content = ValueKey('fold-content');

  testWidgets('펼치고 접는 동안 내용이 보이고, 다 접힌 뒤에는 내용을 만들지 않는다', (tester) async {
    await tester.pumpWidget(_app(_fold(false)));
    expect(find.byKey(content), findsNothing);

    await tester.pumpWidget(_app(_fold(true)));
    await tester.pump(ScheduleFold.duration ~/ 2);
    final half = tester.getSize(find.byType(ScheduleFold)).height;
    expect(half, greaterThan(0));
    expect(half, lessThan(112), reason: '움직이는 중');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ScheduleFold)).height, 112);

    await tester.pumpWidget(_app(_fold(false)));
    await tester.pump(ScheduleFold.reverseDuration ~/ 2);
    expect(find.byKey(content), findsOneWidget, reason: '접히는 중에는 그린다');
    await tester.pumpAndSettle();
    expect(find.byKey(content), findsNothing);
  });

  testWidgets('접히기 시작하면 내용은 낭독기에서 빠지고 눌리지 않으며, 다시 펼치면 돌아온다', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    Widget fold(bool open) => ScheduleFold(
      open: open,
      child: TextButton(onPressed: () => taps++, child: const Text('내용 버튼')),
    );
    await tester.pumpWidget(_app(fold(true)));
    expect(find.semantics.byLabel('내용 버튼'), findsOneWidget);

    await tester.pumpWidget(_app(fold(false)));
    await tester.pump(ScheduleFold.reverseDuration ~/ 4);
    expect(find.text('내용 버튼'), findsOneWidget, reason: '접히는 중에는 그린다');
    expect(find.semantics.byLabel('내용 버튼'), findsNothing);
    await tester.tap(find.text('내용 버튼'), warnIfMissed: false);
    expect(taps, 0);

    await tester.pumpWidget(_app(fold(true)));
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('내용 버튼'), findsOneWidget);
    await tester.tap(find.text('내용 버튼'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('애니메이션 줄이기 설정이면 움직임 없이 바로 펼치고 접는다', (tester) async {
    await tester.pumpWidget(_app(_fold(false), reduceMotion: true));
    await tester.pumpWidget(_app(_fold(true), reduceMotion: true));
    expect(tester.getSize(find.byType(ScheduleFold)).height, 112);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_app(_fold(false), reduceMotion: true));
    await tester.pump();
    expect(find.byKey(content), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('폭 240·글자 배율 $scale에서 달력 날짜 칸은 높이 48 이상이고 넘치지 않는다', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: ScheduleCalendar(
              selected: DateTime(2026, 11, 28),
              today: DateTime(2026, 11, 27),
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final cell = tester.getSize(
        find.ancestor(of: find.text('28'), matching: find.byType(InkWell)),
      );
      expect(cell.height, greaterThanOrEqualTo(48));
    });
  }
}
