import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/duty_free/receipt_parser.dart';
import 'package:tripbler/screens/duty_free_screen.dart';
import 'package:tripbler/screens/receipt_review_screen.dart';
import 'package:tripbler/services/duty_free/receipt_scan_service.dart';
import 'package:tripbler/services/ocr_service.dart';

import '../helpers/duty_free_screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// 테스트가 끝낼 때까지 읽기를 멈춰 두는 대역.
class _HeldScan extends ReceiptScanService {
  _HeldScan() : super(OcrService());

  final Completer<ParsedReceipt> done = Completer();

  @override
  Future<ParsedReceipt> scan(String imagePath) => done.future;
}

void main() {
  testWidgets('소수 3자리 금액은 고치지 않으면 그대로 저장한다', (tester) async {
    final storage = await pumpDutyFree(
      tester,
      receipt: ParsedReceipt(
        store: 'Shop',
        date: sampleReceipt.date,
        currency: 'USD',
        total: null,
        lines: const [ReceiptLine(name: '가방', amount: 1234.567)],
      ),
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(_key('receipt-amount-0'));
    expect(field.controller!.text, '1234.567');
    await tester.tap(_key('receipt-add'));
    await tester.pumpAndSettle();
    expect(storage.stored.items.single.amount, 1234.567);
  });

  testWidgets('합계 한 줄로 넣을 때 합계가 0이면 이유를 보이고 추가를 막는다', (tester) async {
    final storage = await pumpDutyFree(
      tester,
      receipt: ParsedReceipt(
        store: 'Shop',
        date: sampleReceipt.date,
        currency: 'JPY',
        total: 0,
        lines: const [],
      ),
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(_key('receipt-total-invalid'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('receipt-add')).onPressed, isNull);
    expect(storage.stored.items, isEmpty);
  });

  testWidgets('중첩 Navigator 안에서도 읽는 중 안내만 닫고 화면은 남긴다', (tester) async {
    await pumpDutyFree(
      tester,
      wrap: (screen) => Navigator(
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<void>(builder: (_) => const Text('바닥')),
          MaterialPageRoute<void>(builder: (_) => screen),
        ],
      ),
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(find.text('영수증을 읽는 중이에요'), findsNothing);
    expect(find.text('영수증 확인'), findsOneWidget);

    await tester.tap(find.text('다시 찍기'));
    await tester.pumpAndSettle();
    // 두 번째 촬영도 검토 화면을 연다. 닫으면 면세 화면이 그대로 있다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DutyFreeScreen), findsOneWidget);
    expect(find.text('바닥'), findsNothing);
  });

  testWidgets('읽기가 끝나면 촬영한 사진을 지우고, 다시 찍으면 매 장 지운다', (tester) async {
    final deleted = <String>[];
    final scan = _HeldScan();
    var shots = 0;
    await pumpDutyFree(
      tester,
      scan: scan,
      deleted: deleted,
      picker: () async => ++shots <= 2 ? 'photo$shots.jpg' : null,
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pump();
    expect(find.text('영수증을 읽는 중이에요'), findsOneWidget);
    expect(deleted, isEmpty, reason: '읽는 동안에는 지우지 않는다');

    scan.done.complete(sampleReceipt);
    await tester.pumpAndSettle();
    expect(find.text('영수증 확인'), findsOneWidget);
    expect(deleted, ['photo1.jpg'], reason: '검토 화면이 열려 있어도 이미 지운다');

    await tester.tap(find.text('다시 찍기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 찍기'));
    await tester.pumpAndSettle();
    expect(deleted, ['photo1.jpg', 'photo2.jpg']);
    expect(find.byType(DutyFreeScreen), findsOneWidget);
  });

  testWidgets('읽지 못해도 사진을 지운다', (tester) async {
    final deleted = <String>[];
    await pumpDutyFree(
      tester,
      deleted: deleted,
      receipt: const ParsedReceipt(
        store: '',
        date: null,
        currency: null,
        total: null,
        lines: [],
      ),
    );
    await tester.tap(_key('duty-free-scan'));
    await tester.pumpAndSettle();
    expect(find.text(ReceiptReviewScreen.unreadableMessage), findsOneWidget);
    expect(deleted, ['photo.jpg']);
  });
}
