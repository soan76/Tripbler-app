import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/duty_free/receipt_parser.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';
import 'package:tripbler/providers/duty_free/duty_free_provider.dart';
import 'package:tripbler/screens/duty_free_screen.dart';
import 'package:tripbler/services/duty_free/duty_free_rules_service.dart';
import 'package:tripbler/services/duty_free/receipt_scan_service.dart';
import 'package:tripbler/services/ocr_service.dart';

import 'memory_duty_free_storage.dart';

export 'memory_duty_free_storage.dart';

/// 면세 화면 테스트의 현재 시각.
final dutyFreeTestNow = DateTime(2026, 11, 28, 14, 20);

/// 정해 둔 영수증을 돌려주는 글자 읽기 대역.
class FakeReceiptScan extends ReceiptScanService {
  FakeReceiptScan(this.receipt) : super(OcrService());

  final ParsedReceipt receipt;

  @override
  Future<ParsedReceipt> scan(String imagePath) async => receipt;
}

/// 면세 화면 테스트의 기본 영수증: 확실한 줄 2개와 불확실한 줄 1개.
final sampleReceipt = ParsedReceipt(
  store: '돈키호테 아사쿠사점',
  date: DateTime(2026, 11, 28),
  currency: 'JPY',
  total: 13780,
  lines: const [
    ReceiptLine(name: '과자 선물 세트', amount: 1280),
    ReceiptLine(
      name: '위스키 700mL',
      amount: 6800,
      category: DutyFreeCategory.liquor,
      volume: 0.7,
    ),
    ReceiptLine(name: '보조배터리', amount: 1200, unsure: true),
  ],
);

/// 면세 화면을 띄운다. 사진 지우기는 실제 파일 대신 [deleted]에 경로를 남긴다.
///
/// [wrap]으로 화면을 다른 위젯(예: 중첩 Navigator) 안에 넣을 수 있다.
Future<MemoryDutyFreeStorage> pumpDutyFree(
  WidgetTester tester, {
  List<DutyFreeItem> items = const [],
  DutyFreeRulesService rules = const DutyFreeRulesService(),
  Size size = const Size(400, 900),
  ParsedReceipt? receipt,
  ReceiptScanService? scan,
  Future<String?> Function()? picker,
  List<String>? deleted,
  Widget Function(Widget screen)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = MemoryDutyFreeStorage(DutyFreeTrip(items: items));
  const screen = Scaffold(body: DutyFreeScreen());
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        dutyFreeStorageServiceProvider.overrideWithValue(storage),
        dutyFreeClockProvider.overrideWithValue(() => dutyFreeTestNow),
        dutyFreeRulesServiceProvider.overrideWithValue(rules),
        receiptPhotoPickerProvider.overrideWithValue(
          picker ?? () async => 'photo.jpg',
        ),
        receiptPhotoDeleterProvider.overrideWithValue((path) async {
          deleted?.add(path);
        }),
        receiptScanServiceProvider.overrideWithValue(
          scan ?? FakeReceiptScan(receipt ?? sampleReceipt),
        ),
        customsGuideLauncherProvider.overrideWithValue(() async => true),
      ],
      child: MaterialApp(home: wrap == null ? screen : wrap(screen)),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}
