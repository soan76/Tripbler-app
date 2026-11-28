import 'package:tripbler/models/duty_free/duty_free_item.dart';
import 'package:tripbler/services/duty_free/duty_free_storage_service.dart';

/// 메모리에 두는 면세 저장소 대역. 실패를 테스트가 정한다.
class MemoryDutyFreeStorage extends DutyFreeStorageService {
  MemoryDutyFreeStorage([this.stored = DutyFreeTrip.empty]);

  DutyFreeTrip stored;
  bool failLoad = false;
  bool failSave = false;
  int saveCount = 0;

  @override
  Future<DutyFreeTrip> load() async {
    if (failLoad) throw const DutyFreeStorageException('load');
    return stored;
  }

  @override
  Future<void> save(DutyFreeTrip trip) async {
    saveCount++;
    if (failSave) throw const DutyFreeStorageException('save');
    stored = trip;
  }
}

DutyFreeItem dutyFreeItem(
  String id, {
  DutyFreeCategory category = DutyFreeCategory.general,
  String? name,
  double amount = 100,
  String currency = 'USD',
  int quantity = 1,
  double volume = 0,
  DateTime? purchasedAt,
}) => DutyFreeItem(
  id: id,
  category: category,
  name: name ?? '물건 $id',
  quantity: quantity,
  volume: volume,
  amount: amount,
  currency: currency,
  place: PurchasePlace.local,
  purchasedAt: purchasedAt ?? DateTime(2026, 11, 27),
);
