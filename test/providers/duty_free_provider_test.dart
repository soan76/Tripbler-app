import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';
import 'package:tripbler/providers/duty_free/duty_free_provider.dart';

import '../helpers/memory_duty_free_storage.dart';

Future<ProviderContainer> _ready(MemoryDutyFreeStorage storage) async {
  final container = ProviderContainer.test(
    overrides: [dutyFreeStorageServiceProvider.overrideWithValue(storage)],
  );
  container.read(dutyFreeProvider);
  await Future<void>.delayed(Duration.zero);
  return container;
}

void main() {
  test('추가·수정·삭제·나이·새 여행을 저장한다', () async {
    final storage = MemoryDutyFreeStorage();
    final c = await _ready(storage);
    final n = c.read(dutyFreeProvider.notifier);
    expect(c.read(dutyFreeProvider).isReady, isTrue);

    await n.add(dutyFreeItem('a'));
    await n.update(dutyFreeItem('a', amount: 200));
    await n.setAdult(false);
    expect(storage.stored.items.single.amount, 200);
    expect(storage.stored.adult, isFalse);

    await n.addReceipt([dutyFreeItem('b'), dutyFreeItem('c')], 'key');
    expect(c.read(dutyFreeProvider).items.length, 3);
    expect(c.read(dutyFreeProvider).trip.receiptKeys, {'key'});

    await n.remove('a');
    expect(storage.stored.items.map((i) => i.id), ['b', 'c']);

    await n.startNewTrip();
    expect(storage.stored.items, isEmpty);
    expect(storage.stored.receiptKeys, isEmpty);
    expect(storage.stored.adult, isFalse, reason: '나이는 그대로 둔다');
  });

  test('저장에 실패하면 예외를 던지고 상태는 그대로', () async {
    final storage = MemoryDutyFreeStorage(
      DutyFreeTrip(items: [dutyFreeItem('a')]),
    );
    final c = await _ready(storage);
    storage.failSave = true;
    await expectLater(
      c.read(dutyFreeProvider.notifier).remove('a'),
      throwsA(anything),
    );
    expect(c.read(dutyFreeProvider).items.single.id, 'a');
  });

  test('불러오기에 실패하면 바꾸지 못하고 다시 시도로 읽는다', () async {
    final storage = MemoryDutyFreeStorage()..failLoad = true;
    final c = await _ready(storage);
    expect(c.read(dutyFreeProvider).status, DutyFreeLoadStatus.failed);
    await expectLater(
      c.read(dutyFreeProvider.notifier).add(dutyFreeItem('a')),
      throwsStateError,
    );
    expect(storage.saveCount, 0);

    storage.failLoad = false;
    await c.read(dutyFreeProvider.notifier).retry();
    expect(c.read(dutyFreeProvider).isReady, isTrue);
  });

  test('요약은 규칙과 기록이 모두 있을 때 계산한다', () async {
    final storage = MemoryDutyFreeStorage(
      DutyFreeTrip(
        items: [
          dutyFreeItem('a', amount: 900),
          dutyFreeItem('b', category: DutyFreeCategory.tobacco, quantity: 3),
        ],
      ),
    );
    final c = await _ready(storage);
    await c.read(dutyFreeRulesProvider.future);
    final s = c.read(dutyFreeSummaryProvider)!;
    expect(s.general.over, isTrue);
    expect(s.tobacco.packs, 3);
  });
}
