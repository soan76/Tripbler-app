import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/tab_item.dart';
import 'package:tripbler/widgets/bottom_tab_bar.dart';

import '../helpers/bottom_menu_background.dart';

// 번역 화면(alwaysShowIcon)에서는 하단 메뉴가 점으로 접히지 않고 늘 현재 화면 버튼 상태를 보인다.
// 다른 화면은 지금처럼 점으로 접힌다.

const _tabs = [
  TabItem(label: '환율', icon: Icons.attach_money),
  TabItem(label: '지도', icon: Icons.map),
  TabItem(label: '번역', icon: Icons.translate),
];
const _translation = 2;
final _current = find.byKey(const ValueKey('bottom-menu-current'));
final _background = find.byKey(const ValueKey('bottom-menu-background'));

double _width(WidgetTester tester) => tester.getSize(_background).width;

/// 메인 화면처럼 탭을 고르면 선택이 바뀌고, 번역 탭일 때만 alwaysShowIcon을 켠다.
Future<void> _mount(WidgetTester tester, {required int initialTab}) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var selected = initialTab;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: double.infinity,
              child: BottomTabBar(
                tabs: _tabs,
                selectedIndex: selected,
                isHomeSelected: false,
                onTabTap: (index) => setState(() => selected = index),
                onHomeTap: () {},
                alwaysShowIcon: selected == _translation,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openFan(WidgetTester tester) async {
  if (_width(tester) < 74) {
    await tester.tap(_current);
    await tester.pumpAndSettle();
  }
  await tester.drag(_current, const Offset(0, -150));
  await tester.pumpAndSettle();
  expectBottomMenuBackgroundCoversArea(tester);
}

Future<void> _choose(WidgetTester tester, int index) async {
  await tester.tap(find.byKey(ValueKey('bottom-menu-tab-$index')));
}

void main() {
  testWidgets('번역 화면에서 시작하면 처음부터 현재 화면 버튼 상태다', (tester) async {
    await _mount(tester, initialTab: _translation);
    await tester.pump();
    expect(_width(tester), 74);
    await tester.pumpWidget(const SizedBox());
  });

  // 버그 수정: 다른 화면에서 번역 버튼을 고르면 고르는 순간 점으로 접혔다가(한 번) 번역 화면이 됐다.
  testWidgets('다른 화면에서 번역 화면으로 가면 점이 되지 않고 현재 화면 버튼 상태로 들어간다', (tester) async {
    await _mount(tester, initialTab: 0);
    await _openFan(tester);

    await _choose(tester, _translation);
    // 접히는 동안 매 프레임 폭을 재어 점(10)까지 줄어든 적이 없는지 본다.
    var smallest = _width(tester);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_width(tester) < smallest) smallest = _width(tester);
    }
    await tester.pumpAndSettle();
    expect(smallest, greaterThanOrEqualTo(74));
    expect(_width(tester), 74);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('번역 화면에서는 바깥 누르기·4초 무입력에도 접히지 않고, 부채꼴은 현재 화면 버튼으로 돌아온다', (
    tester,
  ) async {
    await _mount(tester, initialTab: _translation);
    await tester.pump();

    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(_width(tester), 74);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_width(tester), 74);

    await _openFan(tester);
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(_width(tester), 74);

    // 부채꼴에서 번역(현재 화면)을 다시 골라도 현재 화면 버튼 상태로 돌아온다.
    await _openFan(tester);
    await _choose(tester, _translation);
    await tester.pumpAndSettle();
    expect(_width(tester), 74);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('번역 화면에서 다른 화면으로 가면 지금처럼 점으로 접힌다', (tester) async {
    await _mount(tester, initialTab: _translation);
    await tester.pump();
    await _openFan(tester);

    await _choose(tester, 0);
    await tester.pumpAndSettle();
    expect(_width(tester), 10);

    // 다른 화면에서는 바깥 누르기로 점으로 접힌다.
    await tester.tap(_current);
    await tester.pumpAndSettle();
    expect(_width(tester), 74);
    await tester.tapAt(const Offset(20, 200));
    await tester.pumpAndSettle();
    expect(_width(tester), 10);
    await tester.pumpWidget(const SizedBox());
  });
}
