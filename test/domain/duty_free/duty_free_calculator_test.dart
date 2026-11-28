import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/duty_free/duty_free_calculator.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';
import 'package:tripbler/services/duty_free/duty_free_rules_service.dart';

final _rules = DutyFreeRulesService.example(DateTime(2026, 11, 28));

DutyFreeItem _item(
  DutyFreeCategory category,
  double amount, {
  String currency = 'USD',
  int quantity = 1,
  double volume = 0,
  String id = 'a',
}) => DutyFreeItem(
  id: id,
  category: category,
  name: '물건',
  quantity: quantity,
  volume: volume,
  amount: amount,
  currency: currency,
  place: PurchasePlace.local,
  purchasedAt: DateTime(2026, 11, 28),
);

DutyFreeSummary _sum(List<DutyFreeItem> items, {bool adult = true}) =>
    const DutyFreeCalculator().summarize(
      items: items,
      rules: _rules,
      adult: adult,
    );

void main() {
  test('구매가 없으면 한도가 그대로 남고 별도 기준은 모두 없음', () {
    final s = _sum([]);
    expect(s.general.remainingUsd, 800);
    expect(s.general.over, isFalse);
    expect(s.liquor.status, SeparateLimitStatus.none);
    expect(s.tobacco.status, SeparateLimitStatus.none);
    expect(s.perfume.status, SeparateLimitStatus.none);
    expect(s.anyOver, isFalse);
    expect(s.tax, isNull);
  });

  test('일반 물품만 한도에 더하고, 통화는 예시 환율로 달러로 바꾼다', () {
    final s = _sum([
      _item(DutyFreeCategory.general, 38000, currency: 'JPY'),
      _item(DutyFreeCategory.general, 120),
      _item(DutyFreeCategory.liquor, 300, volume: 0.7),
    ]);
    expect(s.general.spentUsd, closeTo(38000 * 0.0067 + 120, 1e-6));
    expect(s.liquor.status, SeparateLimitStatus.within);
  });

  test('90% 이상이면 근접, 넘으면 초과와 예상 세금(예시)', () {
    expect(_sum([_item(DutyFreeCategory.general, 720)]).general.near, isTrue);
    expect(_sum([_item(DutyFreeCategory.general, 719)]).general.near, isFalse);
    final over = _sum([_item(DutyFreeCategory.general, 900)]);
    expect(over.general.over, isTrue);
    expect(over.general.near, isFalse);
    expect(over.general.overUsd, 100);
    expect(over.overReasons, ['일반 물품 한도 초과']);
    final tax = over.tax!;
    expect(tax.overKrw, 139000);
    expect(tax.taxKrw, closeTo(27800, 1e-6));
    expect(tax.totalKrw, closeTo(27800 * 0.7, 1e-6));
  });

  test('주류는 병 수·용량·금액 중 하나라도 넘으면 초과', () {
    final bottles = _sum([
      _item(DutyFreeCategory.liquor, 100, quantity: 3, volume: 0.5),
    ]);
    expect(bottles.liquor.bottles, 3);
    expect(bottles.liquorOver, isTrue);
    final liters = _sum([
      _item(DutyFreeCategory.liquor, 100, quantity: 2, volume: 1.5),
    ]);
    expect(liters.liquor.liters, 3);
    expect(liters.liquorOver, isTrue);
    final usd = _sum([_item(DutyFreeCategory.liquor, 401, volume: 0.7)]);
    expect(usd.liquorOver, isTrue);
    final ok = _sum([
      _item(DutyFreeCategory.liquor, 200, quantity: 2, volume: 1),
    ]);
    expect(ok.liquor.status, SeparateLimitStatus.within);
    // 주류는 일반 한도에 더하지 않는다.
    expect(ok.general.spentUsd, 0);
  });

  test('만 19세 미만이면 주류·담배는 있으면 초과, 향수는 용량으로만', () {
    final s = _sum([
      _item(DutyFreeCategory.liquor, 10, volume: 0.3),
      _item(DutyFreeCategory.tobacco, 5, id: 'b'),
      _item(DutyFreeCategory.perfume, 50, volume: 50, id: 'c'),
    ], adult: false);
    expect(s.liquorOver, isTrue);
    expect(s.tobaccoOver, isTrue);
    expect(s.perfume.status, SeparateLimitStatus.within);
    expect(s.overReasons, ['주류 기준 초과', '담배 기준 초과']);
    expect(s.tax, isNull);
  });

  test('담배 갑 수와 향수 mL 기준', () {
    final s = _sum([
      _item(DutyFreeCategory.tobacco, 50, quantity: 11),
      _item(DutyFreeCategory.perfume, 89, quantity: 3, volume: 50, id: 'b'),
    ]);
    expect(s.tobaccoOver, isTrue);
    expect(s.perfume.ml, 150);
    expect(s.perfumeOver, isTrue);
  });

  test('환율이 없는 통화의 일반 물품은 합계에서 빼고 개수를 센다', () {
    final s = _sum([_item(DutyFreeCategory.general, 100, currency: 'THB')]);
    expect(s.general.spentUsd, 0);
    expect(s.general.unconvertible, 1);
  });

  test('환율이 없는 주류는 금액에서 빼고 개수를 세며, 병 수·용량 판정은 그대로', () {
    final s = _sum([
      _item(DutyFreeCategory.liquor, 50, volume: 0.7),
      _item(
        DutyFreeCategory.liquor,
        9000,
        currency: 'THB',
        quantity: 2,
        volume: 0.7,
        id: 'b',
      ),
    ]);
    expect(s.liquor.usd, 50);
    expect(s.liquor.unconvertible, 1);
    expect(s.liquor.bottles, 3);
    expect(s.liquorOver, isTrue, reason: '3병은 병 수 기준 초과');
    expect(s.general.unconvertible, 0);
  });
}
