import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/schedule/schedule_time_wheel.dart';

Finder _item(String column, String label) => find.descendant(
  of: find.byKey(ValueKey('schedule-wheel-$column')),
  matching: find.text(label),
);

Finder _column(String column) => find.byKey(ValueKey('schedule-wheel-$column'));

/// 분 칸에서 지금 가운데(고른 칸)에 보이는 값.
int _centerMinute(WidgetTester tester) {
  final center = tester.getCenter(_column('minute')).dy;
  final labels = find.descendant(
    of: _column('minute'),
    matching: find.byType(Text),
  );
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

bool _minuteScrolling(WidgetTester tester) => tester
    .widget<ListWheelScrollView>(_column('minute'))
    .controller!
    .position
    .isScrollingNotifier
    .value;

/// [hour]:[minute]가 세 칸 모두 가운데(고른 칸)에 있는지 확인한다.
void _expectCentered(WidgetTester tester, int hour, int minute) {
  final center = tester.getCenter(_column('minute')).dy;
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  for (final (column, label) in [
    ('meridiem', hour < 12 ? '오전' : '오후'),
    ('hour', '$hour12'),
    ('minute', minute.toString().padLeft(2, '0')),
  ]) {
    expect(
      tester.getCenter(_item(column, label)).dy,
      closeTo(center, 1),
      reason: '$column 가운데 칸이 $label',
    );
  }
}

void main() {
  late List<(int, int)> changes;

  Future<void> pump(
    WidgetTester tester, {
    int hour = 15,
    int minute = 0,
    bool enabled = true,
    bool reduceMotion = false,
    Key? key,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: ScheduleTimeWheel(
                key: key,
                hour: hour,
                minute: minute,
                onChanged: enabled ? (h, m) => changes.add((h, m)) : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => changes = []);

  testWidgets('오전/오후를 바꾸면 같은 시의 24시간 값으로 알린다(12시 경계 포함)', (tester) async {
    await pump(tester, hour: 15);
    await tester.tap(_item('meridiem', '오전'));
    await tester.pumpAndSettle();
    expect(changes, [(3, 0)]);

    changes.clear();
    await pump(tester, hour: 0, minute: 5);
    await tester.tap(_item('meridiem', '오후'));
    await tester.pumpAndSettle();
    expect(changes.last, (12, 5), reason: '오전 12시 → 오후 12시는 정오');
  });

  testWidgets('분 칸을 끌어 굴리면 1분 단위로 멈춘 값을 알린다', (tester) async {
    await pump(tester, hour: 9, minute: 0);
    final minute = find.byKey(const ValueKey('schedule-wheel-minute'));
    await tester.timedDrag(
      minute,
      const Offset(0, -ScheduleTimeWheel.itemExtent * 27),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    // 여러 칸을 지나도 멈춘 뒤 한 번만 알린다.
    expect(changes, hasLength(1));
    // 끌기 시작 여유값 때문에 한 칸 차이가 날 수 있다. 가운데에 멈춘 칸과 알린 값이 같으면 된다.
    final (hour, picked) = changes.single;
    expect(hour, 9);
    expect(picked, inInclusiveRange(26, 28));
    final center = tester.getCenter(minute);
    final label = picked.toString().padLeft(2, '0');
    expect(tester.getCenter(_item('minute', label)).dy, closeTo(center.dy, 1));
  });

  testWidgets('바깥에서 값이 바뀌면 휠도 그 자리로 옮긴다', (tester) async {
    await pump(tester, hour: 9, minute: 0);
    await pump(tester, hour: 21, minute: 45);
    await tester.pumpAndSettle();
    // 가운데(고른) 칸이 새 값이다.
    final center = tester.getCenter(
      find.byKey(const ValueKey('schedule-wheel-minute')),
    );
    expect(tester.getCenter(_item('minute', '45')).dy, closeTo(center.dy, 1));
    expect(tester.getCenter(_item('hour', '9')).dy, closeTo(center.dy, 1));
    expect(tester.getCenter(_item('meridiem', '오후')).dy, closeTo(center.dy, 1));
    expect(changes, isEmpty, reason: '바깥 값을 따라간 것은 다시 알리지 않는다');
  });

  testWidgets('칸을 누르면 사이 칸을 지나 굴러가도 도착한 값 하나만 알린다', (tester) async {
    await pump(tester, hour: 9, minute: 0);
    await tester.tap(_item('minute', '02'));
    await tester.pumpAndSettle();
    expect(changes, [(9, 2)]);
    _expectCentered(tester, 9, 2);
  });

  testWidgets('세 칸을 함께 굴려도 모두 멈춘 뒤 최종 값 하나만 알린다', (tester) async {
    await pump(tester, hour: 15, minute: 0);
    await tester.fling(_column('hour'), const Offset(0, -120), 800);
    await tester.tap(_item('meridiem', '오전'));
    await tester.drag(
      _column('minute'),
      const Offset(0, -ScheduleTimeWheel.itemExtent * 3),
    );
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    final (hour, minute) = changes.single;
    expect(hour, lessThan(12), reason: '오전으로 바꿨다');
    expect(hour, isNot(3), reason: '시 칸도 굴렀다');
    expect(minute, isNot(0), reason: '분 칸도 굴렀다');
    _expectCentered(tester, hour, minute);
  });

  testWidgets('굴러가는 중에 꺼지면(저장 시작) 멈춘 뒤 바깥 값으로 돌아가고, 다시 켜져도 같다', (tester) async {
    var hour = 9;
    var minute = 0;
    var enabled = true;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setOuter = setState;
                  return ScheduleTimeWheel(
                    hour: hour,
                    minute: minute,
                    // 화면처럼 알린 값을 바깥 값(draft)으로 받는다.
                    onChanged: enabled
                        ? (h, m) {
                            changes.add((h, m));
                            setState(() => (hour, minute) = (h, m));
                          }
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(_column('minute'), const Offset(0, -200), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    setOuter(() => enabled = false);
    await tester.pumpAndSettle();
    _expectCentered(tester, hour, minute);

    setOuter(() => enabled = true);
    await tester.pumpAndSettle();
    _expectCentered(tester, hour, minute);
    expect((hour, minute), (9, 0), reason: '멈추기 전에 꺼졌으니 값은 그대로');
    expect(changes, isEmpty);
  });

  testWidgets('굴러가는 중에 flush하면 그 순간 가운데 칸에 멈추고 그 값을 한 번만 알린다', (tester) async {
    final key = GlobalKey<ScheduleTimeWheelState>();
    await pump(tester, hour: 9, minute: 0, key: key);
    await tester.fling(_column('minute'), const Offset(0, -120), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_minuteScrolling(tester), isTrue, reason: '아직 굴러가는 중');
    final minute = _centerMinute(tester);
    expect(minute, isNot(0));

    key.currentState!.flush();
    expect(changes, [(9, minute)], reason: 'flush 안에서 바로 알린다');
    expect(_minuteScrolling(tester), isFalse);
    await tester.pumpAndSettle();
    expect(changes, [(9, minute)], reason: '멈춘 뒤 다시 알리지 않는다');
    _expectCentered(tester, 9, minute);
  });

  testWidgets('멈춰 있고 바깥 값과 같거나, 꺼져 있으면 flush해도 알리지 않는다', (tester) async {
    final key = GlobalKey<ScheduleTimeWheelState>();
    await pump(tester, hour: 9, minute: 30, key: key);
    key.currentState!.flush();
    expect(changes, isEmpty);

    await pump(tester, hour: 9, minute: 30, enabled: false, key: key);
    key.currentState!.flush();
    expect(changes, isEmpty);
  });

  testWidgets('애니메이션 줄이기: 칸 누르기·낭독기 올리기가 바로 옮기고 한 번씩 알린다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, hour: 9, minute: 0, reduceMotion: true);
    await tester.tap(_item('minute', '02'));
    await tester.pump();
    expect(changes, [(9, 2)]);
    _expectCentered(tester, 9, 2);

    final node = tester.getSemantics(_column('minute'));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.increase,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();
    expect(changes, [(9, 2), (9, 3)]);
    await tester.pumpAndSettle();
    expect(changes, [(9, 2), (9, 3)]);
    _expectCentered(tester, 9, 3);
    semantics.dispose();
  });

  testWidgets('저장 중(onChanged 없음)에는 굴리거나 눌러도 바뀌지 않는다', (tester) async {
    await pump(tester, hour: 9, enabled: false);
    await tester.tap(_item('hour', '10'), warnIfMissed: false);
    await tester.drag(
      find.byKey(const ValueKey('schedule-wheel-minute')),
      const Offset(0, -120),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('낭독기: 각 칸이 이름·값과 올리기/내리기를 갖고, 올리면 다음 값을 알린다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, hour: 9, minute: 0);
    final node = tester.getSemantics(
      find.byKey(const ValueKey('schedule-wheel-minute')),
    );
    final data = node.getSemanticsData();
    expect(data.label, '분');
    expect(data.value, '0분');
    expect(data.increasedValue, '1분');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isFalse, reason: '첫 칸');

    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.increase,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pumpAndSettle();
    expect(changes, [(9, 1)]);
    semantics.dispose();
  });

  testWidgets('저장 중에는 흐리게 보이고 낭독기 올리기/내리기도 없다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, hour: 9, minute: 30, enabled: false);
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('schedule-wheel-minute')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity.opacity, lessThan(1));
    final data = tester
        .getSemantics(find.byKey(const ValueKey('schedule-wheel-minute')))
        .getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isFalse);
    expect(data.hasAction(SemanticsAction.decrease), isFalse);
    semantics.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('폭 240·글자 배율 $scale에서 넘치지 않는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
