import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';
import 'package:tripbler/services/duty_free/duty_free_storage_service.dart';

DutyFreeItem _item(String id) => DutyFreeItem(
  id: id,
  category: DutyFreeCategory.liquor,
  name: '위스키',
  quantity: 2,
  volume: 0.7,
  amount: 6800,
  currency: 'JPY',
  place: PurchasePlace.inflight,
  purchasedAt: DateTime(2026, 11, 27, 9),
  needsCheck: true,
);

void main() {
  test('저장한 여행을 그대로 다시 읽는다', () async {
    SharedPreferences.setMockInitialValues({});
    final service = DutyFreeStorageService();
    expect((await service.load()).items, isEmpty);

    await service.save(
      DutyFreeTrip(adult: false, items: [_item('a')], receiptKeys: {'k'}),
    );
    final trip = await service.load();
    expect(trip.adult, isFalse);
    expect(trip.receiptKeys, {'k'});
    final item = trip.items.single;
    expect(item.id, 'a');
    expect(item.category, DutyFreeCategory.liquor);
    expect(item.quantity, 2);
    expect(item.volume, 0.7);
    expect(item.place, PurchasePlace.inflight);
    expect(item.purchasedAt, DateTime(2026, 11, 27, 9));
    expect(item.needsCheck, isTrue);
  });

  test('형식이 틀린 항목과 같은 id는 버리고 나머지는 살린다', () async {
    final good = _item('a').toJson();
    SharedPreferences.setMockInitialValues({
      DutyFreeStorageService.storageKey: jsonEncode({
        'adult': true,
        'items': [
          good,
          {...good, 'id': 'b', 'currency': 'XXX'},
          {...good, 'id': 'c', 'quantity': 0},
          good,
          'oops',
        ],
        'receiptKeys': ['k', 3],
      }),
    });
    final trip = await DutyFreeStorageService().load();
    expect(trip.items.map((i) => i.id), ['a']);
    expect(trip.receiptKeys, {'k'});
  });

  test('읽을 수 없는 저장값은 빈 여행', () {
    expect(DutyFreeStorageService.decode('{').items, isEmpty);
    expect(DutyFreeStorageService.decode('[]').adult, isTrue);
  });

  test('저장소를 열지 못하면 예외', () async {
    final service = DutyFreeStorageService(prefs: () => throw Exception());
    expect(service.load(), throwsA(isA<DutyFreeStorageException>()));
  });
}
