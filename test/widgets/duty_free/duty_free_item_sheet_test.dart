import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';

import '../../helpers/duty_free_screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('수량이 비었거나 1 미만이면 칸 오류를 보이고 저장하지 않는다', (tester) async {
    final storage = await pumpDutyFree(tester);
    await tester.tap(_key('duty-free-add'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('duty-free-name'), '가방');
    await tester.enterText(_key('duty-free-amount'), '100');

    for (final bad in ['', '0']) {
      await tester.enterText(_key('duty-free-quantity'), bad);
      await tester.tap(_key('duty-free-save'));
      await tester.pumpAndSettle();
      expect(find.text('수량을 1 이상의 정수로 입력해 주세요'), findsOneWidget, reason: bad);
      expect(storage.stored.items, isEmpty, reason: bad);
    }

    await tester.enterText(_key('duty-free-quantity'), '3');
    await tester.pump();
    expect(find.text('수량을 1 이상의 정수로 입력해 주세요'), findsNothing);
    await tester.tap(_key('duty-free-save'));
    await tester.pumpAndSettle();
    expect(storage.stored.items.single.quantity, 3);
  });

  testWidgets('수정 카드는 금액·용량을 반올림하지 않고 채워, 고치지 않으면 값이 그대로다', (tester) async {
    final storage = await pumpDutyFree(
      tester,
      items: [
        dutyFreeItem(
          'a',
          name: '와인',
          category: DutyFreeCategory.liquor,
          amount: 1234.567,
          volume: 0.375,
        ),
      ],
    );
    await tester.tap(find.text('와인'));
    await tester.pumpAndSettle();
    String text(String key) =>
        tester.widget<TextField>(_key(key)).controller!.text;
    expect(text('duty-free-amount'), '1234.567');
    expect(text('duty-free-volume'), '0.375');
    expect(text('duty-free-quantity'), '1');

    await tester.tap(_key('duty-free-save'));
    await tester.pumpAndSettle();
    final saved = storage.stored.items.single;
    expect(saved.amount, 1234.567);
    expect(saved.volume, 0.375);
  });

  testWidgets('수정 카드는 정수 금액을 .0 없이 채운다', (tester) async {
    await pumpDutyFree(
      tester,
      items: [dutyFreeItem('a', name: '가방', amount: 12800, currency: 'JPY')],
    );
    await tester.tap(find.text('가방'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_key('duty-free-amount')).controller!.text,
      '12800',
    );
  });
}
