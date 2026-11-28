import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/duty_free/receipt_parser.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';
import 'package:tripbler/models/duty_free/duty_free_rules.dart';
import 'package:tripbler/screens/duty_free_screen.dart';
import 'package:tripbler/screens/receipt_review_screen.dart';
import 'package:tripbler/services/duty_free/duty_free_rules_service.dart';

import '../helpers/duty_free_screen_harness.dart';

class _FailingRules extends DutyFreeRulesService {
  const _FailingRules();

  @override
  Future<DutyFreeRules> fetch() async => throw Exception('offline');
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('구매가 없으면 빈 상태와 남은 한도 전체, 예시 표시', (tester) async {
    await pumpDutyFree(tester);
    expect(find.text(DutyFreeScreen.emptyMessage), findsOneWidget);
    expect(find.text('남은 한도 \$800'), findsOneWidget);
    expect(find.text('예시 기준'), findsOneWidget);
    expect(find.textContaining('한국 입국 기준'), findsOneWidget);
    expect(find.textContaining('세관 신고'), findsNothing);
    expect(_key('duty-free-new-trip'), findsNothing);
  });

  testWidgets('직접 입력으로 추가하면 목록과 한도가 바뀌고, 넘으면 신고 안내와 예상 세금', (tester) async {
    final storage = await pumpDutyFree(tester);
    await tester.tap(_key('duty-free-add'));
    await tester.pumpAndSettle();

    await tester.tap(_key('duty-free-save'));
    await tester.pumpAndSettle();
    expect(find.text('상품명을 입력해 주세요'), findsOneWidget);

    await tester.enterText(_key('duty-free-name'), '손목시계');
    await tester.enterText(_key('duty-free-amount'), '900');
    await tester.tap(_key('duty-free-currency'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    expect(find.text('≈ \$900 (예시 환율)'), findsOneWidget);
    await tester.tap(_key('duty-free-save'));
    await tester.pumpAndSettle();

    expect(storage.stored.items.single.name, '손목시계');
    expect(find.text('한도 초과 \$100'), findsOneWidget);
    expect(find.text('입국할 때 세관 신고가 필요할 수 있어요'), findsOneWidget);
    expect(find.textContaining('일반 물품 한도 초과'), findsOneWidget);

    await tester.ensureVisible(_key('duty-free-tax-toggle'));
    await tester.tap(_key('duty-free-tax-toggle'));
    await tester.pumpAndSettle();
    expect(find.text('예상 세금'), findsOneWidget);
    expect(find.text('₩19,460'), findsOneWidget);
  });

  testWidgets('수정 카드에서 삭제하면 확인 뒤 지운다', (tester) async {
    final storage = await pumpDutyFree(
      tester,
      items: [dutyFreeItem('a', name: '가방')],
    );
    await tester.tap(find.text('가방'));
    await tester.pumpAndSettle();
    expect(find.text('물건 수정'), findsOneWidget);

    await tester.tap(_key('duty-free-delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('일반 물품 한도 계산에서 빠져요'), findsOneWidget);
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();
    expect(storage.stored.items, isEmpty);
    expect(find.text(DutyFreeScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('새 여행 시작은 확인 뒤 목록을 비운다', (tester) async {
    final storage = await pumpDutyFree(
      tester,
      items: [dutyFreeItem('a'), dutyFreeItem('b')],
    );
    await tester.tap(_key('duty-free-new-trip'));
    await tester.pumpAndSettle();
    expect(find.textContaining('산 물건 2개가 모두 지워지고'), findsOneWidget);
    await tester.tap(find.text('모두 지우기'));
    await tester.pumpAndSettle();
    expect(storage.stored.items, isEmpty);
  });

  testWidgets('만 19세 미만으로 바꾸면 주류·담배는 면세 안 됨', (tester) async {
    await pumpDutyFree(
      tester,
      items: [dutyFreeItem('a', category: DutyFreeCategory.tobacco)],
    );
    await tester.tap(_key('duty-free-basis-change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('만 19세 미만').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('만 19세 미만은 면세 안 됨'), findsNWidgets(2));
    expect(find.textContaining('담배 기준 초과'), findsOneWidget);
  });

  testWidgets('영수증: 불확실한 줄은 처음에 빼고, 같은 영수증을 다시 넣으면 경고', (tester) async {
    final storage = await pumpDutyFree(tester);
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(find.text('영수증 확인'), findsOneWidget);
    expect(find.text('목록에 추가 (2)'), findsOneWidget);
    expect(_key('receipt-duplicate'), findsNothing);

    // 합계 한 줄로 바꾸면 한 줄만 넣는다.
    await tester.tap(find.text('합계 한 줄로 넣기'));
    await tester.pumpAndSettle();
    expect(find.text('목록에 추가 (1)'), findsOneWidget);
    await tester.tap(find.text('항목별로 넣기'));
    await tester.pumpAndSettle();

    await tester.tap(_key('receipt-add'));
    await tester.pumpAndSettle();
    expect(storage.stored.items.map((i) => i.name), ['과자 선물 세트', '위스키 700mL']);
    expect(storage.stored.items.last.category, DutyFreeCategory.liquor);
    expect(find.text('영수증에서 2개를 추가했어요'), findsOneWidget);

    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(_key('receipt-duplicate'), findsOneWidget);
    expect(find.text('그래도 추가 (2)'), findsOneWidget);

    // 불확실한 줄을 골라 넣으면 목록에 확인 필요로 남는다.
    await tester.tap(_key('receipt-line-2'));
    await tester.pumpAndSettle();
    await tester.tap(_key('receipt-add'));
    await tester.pumpAndSettle();
    expect(storage.stored.items.length, 5);
    expect(storage.stored.items.last.needsCheck, isTrue);
    await tester.scrollUntilVisible(
      find.text('확인 필요'),
      200,
      scrollable: find.descendant(
        of: _key('duty-free-list'),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('확인 필요'), findsOneWidget);
  });

  testWidgets('기준을 받지 못하면 계산 대신 다시 시도, 목록은 현지 금액만', (tester) async {
    await pumpDutyFree(
      tester,
      items: [dutyFreeItem('a')],
      rules: const _FailingRules(),
    );
    expect(find.text(DutyFreeScreen.rulesFailedMessage), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.textContaining('남은 한도'), findsNothing);
    expect(find.text('환산 불가'), findsOneWidget);
  });

  testWidgets('작은 화면에서도 넘치지 않는다', (tester) async {
    await pumpDutyFree(
      tester,
      size: const Size(320, 640),
      items: [
        dutyFreeItem('a', name: '아주 긴 상품 이름이 들어간 한정판 가죽 가방 세트', amount: 900),
        dutyFreeItem(
          'b',
          category: DutyFreeCategory.liquor,
          quantity: 3,
          volume: 0.7,
        ),
      ],
    );
    expect(tester.takeException(), isNull);
    await tester.tap(_key('duty-free-add'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: _key('duty-free-category'),
        matching: find.text('주류'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('직접 입력: 금액·주류 용량이 0 이하거나 잘못된 값이면 오류를 보이고 저장하지 않는다', (
    tester,
  ) async {
    final storage = await pumpDutyFree(tester);
    await tester.tap(_key('duty-free-add'));
    await tester.pumpAndSettle();
    await tester.enterText(_key('duty-free-name'), '가방');

    for (final bad in ['', '0', 'abc', '1,5', '-3']) {
      await tester.enterText(_key('duty-free-amount'), bad);
      await tester.tap(_key('duty-free-save'));
      await tester.pumpAndSettle();
      expect(find.text('금액을 0보다 큰 숫자로 입력해 주세요'), findsOneWidget, reason: bad);
      expect(storage.stored.items, isEmpty, reason: bad);
    }

    // 주류로 바꾸고 용량을 0으로 두면 용량 오류.
    await tester.enterText(_key('duty-free-amount'), '1,280');
    await tester.tap(
      find.descendant(
        of: _key('duty-free-category'),
        matching: find.text('주류'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_key('duty-free-volume'), '0');
    await tester.tap(_key('duty-free-save'));
    await tester.pumpAndSettle();
    expect(find.text('용량을 0보다 큰 숫자로 입력해 주세요'), findsOneWidget);
    expect(storage.stored.items, isEmpty);

    await tester.enterText(_key('duty-free-volume'), '0.7');
    await tester.tap(_key('duty-free-save'));
    await tester.pumpAndSettle();
    final saved = storage.stored.items.single;
    expect(saved.amount, 1280);
    expect(saved.volume, closeTo(0.7, 1e-9));
  });

  testWidgets('영수증 통화를 읽지 못하면 통화를 고르기 전까지 추가를 막는다', (tester) async {
    final storage = await pumpDutyFree(
      tester,
      receipt: ParsedReceipt(
        store: 'Shop',
        date: sampleReceipt.date,
        currency: null,
        total: null,
        lines: const [ReceiptLine(name: '가방', amount: 1000)],
      ),
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(
      find.text(ReceiptReviewScreen.currencyNeededMessage),
      findsOneWidget,
    );
    final add = tester.widget<FilledButton>(_key('receipt-add'));
    expect(add.onPressed, isNull);

    await tester.tap(_key('receipt-currency'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KRW').last);
    await tester.pumpAndSettle();
    expect(find.text(ReceiptReviewScreen.currencyNeededMessage), findsNothing);
    await tester.tap(_key('receipt-add'));
    await tester.pumpAndSettle();
    expect(storage.stored.items.single.currency, 'KRW');
  });

  testWidgets('영수증 통화를 읽었으면 안내 없이 바로 추가할 수 있다', (tester) async {
    await pumpDutyFree(tester);
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(find.text(ReceiptReviewScreen.currencyNeededMessage), findsNothing);
    expect(
      tester.widget<FilledButton>(_key('receipt-add')).onPressed,
      isNotNull,
    );
  });

  testWidgets('다시 찍기는 촬영을 다시 열고, 취소하면 면세 화면으로 돌아온다', (tester) async {
    var shots = 0;
    final storage = await pumpDutyFree(
      tester,
      picker: () async => ++shots == 1 ? 'photo.jpg' : null,
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(find.text('영수증 확인'), findsOneWidget);

    await tester.tap(find.text('다시 찍기'));
    await tester.pumpAndSettle();
    expect(shots, 2);
    expect(find.text('영수증 확인'), findsNothing);
    expect(find.byType(DutyFreeScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(storage.stored.items, isEmpty);

    // 다시 찍으면 검토 화면이 다시 열린다.
    shots = 0;
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 찍기'));
    await tester.pumpAndSettle();
    expect(shots, 2);
  });

  testWidgets('영수증 금액을 0·잘못된 값으로 고치면 칸 오류를 보이고 추가를 막는다', (tester) async {
    final storage = await pumpDutyFree(tester);
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    FilledButton add() => tester.widget<FilledButton>(_key('receipt-add'));

    for (final bad in ['1,5', 'abc', '', '0']) {
      await tester.enterText(_key('receipt-amount-0'), bad);
      await tester.pump();
      expect(find.text('금액 확인'), findsOneWidget, reason: bad);
      expect(add().onPressed, isNull, reason: bad);
    }

    // 고르지 않은 줄의 금액은 막지 않는다.
    await tester.tap(_key('receipt-line-0'));
    await tester.pump();
    expect(find.text('금액 확인'), findsNothing);
    expect(add().onPressed, isNotNull);

    await tester.tap(_key('receipt-line-0'));
    await tester.enterText(_key('receipt-amount-0'), '1,280');
    await tester.pump();
    expect(find.text('금액 확인'), findsNothing);
    await tester.tap(_key('receipt-add'));
    await tester.pumpAndSettle();
    expect(storage.stored.items.first.amount, 1280);
  });

  testWidgets('환율이 없는 주류는 주류 줄에 금액에서 뺐다고 알린다', (tester) async {
    await pumpDutyFree(
      tester,
      items: [
        dutyFreeItem(
          'a',
          category: DutyFreeCategory.liquor,
          currency: 'THB',
          volume: 0.7,
        ),
      ],
    );
    expect(find.textContaining('환율이 없는 주류 1개는 금액에서 뺐어요'), findsOneWidget);
  });
}
