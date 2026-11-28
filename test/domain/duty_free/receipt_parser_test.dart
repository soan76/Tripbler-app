import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/duty_free/receipt_parser.dart';
import 'package:tripbler/models/duty_free/duty_free_item.dart';

void main() {
  const parser = ReceiptParser();

  test('가게·날짜·합계·물건 줄을 읽고 소계·세금·거스름돈 줄은 뺀다', () {
    final r = parser.parse([
      '돈키호테 아사쿠사점',
      'TEL 03-1234-5678',
      '2026年11月28日 14:20',
      '과자 선물 세트 ¥1,280',
      '스킨케어 세트 ¥4,500',
      'ウイスキー 700ml ¥6,800',
      '小計 ¥12,580',
      '消費税 ¥1,200',
      '合計 ¥13,780',
      'お預り ¥20,000',
      'お釣り ¥6,220',
    ]);
    expect(r.store, '돈키호테 아사쿠사점');
    expect(r.date, DateTime(2026, 11, 28));
    expect(r.currency, 'JPY');
    expect(r.total, 13780);
    expect(r.lines.map((l) => l.name), ['과자 선물 세트', '스킨케어 세트', 'ウイスキー 700ml']);
    expect(r.lines.map((l) => l.amount), [1280, 4500, 6800]);
    final whisky = r.lines.last;
    expect(whisky.category, DutyFreeCategory.liquor);
    expect(whisky.volume, closeTo(0.7, 1e-9));
    expect(r.lines.any((l) => l.unsure), isFalse);
  });

  test('숫자에 O·l이 섞인 줄은 고쳐 읽고 확인 필요로 둔다', () {
    final r = parser.parse(['SHOP', 'Power bank 1,2O0円']);
    expect(r.lines.single.amount, 1200);
    expect(r.lines.single.unsure, isTrue);
  });

  test('달러 소수점과 향수 분류', () {
    final r = parser.parse([
      'Incheon Duty Free',
      '2026/11/23',
      'Lipstick \$38.00',
      'Eau de Parfum 50ml \$150.00',
      'TOTAL \$188.00',
    ]);
    expect(r.currency, 'USD');
    expect(r.total, 188);
    expect(r.lines[0].amount, 38);
    expect(r.lines[1].category, DutyFreeCategory.perfume);
    expect(r.lines[1].volume, 50);
  });

  test('이름과 금액이 다른 줄에 찍히면 잇는다', () {
    final r = parser.parse(['가게 이름', '보조배터리', '¥3,000']);
    expect(r.lines.single.name, '보조배터리');
    expect(r.lines.single.amount, 3000);
  });

  test('같은 영수증 키는 공백·대소문자와 관계없이 같고 통화가 다르면 다르다', () {
    final a = parser.parse(['Shop A', '2026-11-28', 'Item ¥100', '合計 ¥100']);
    final b = parser.parse(['shop  a', '2026-11-28', 'Item ¥100', '合計 ¥100']);
    expect(a.keyFor('JPY'), b.keyFor('JPY'));
    expect(a.keyFor('JPY'), isNot(a.keyFor('USD')));
  });

  test('합계를 읽지 못하면 줄 금액의 합을 쓴다', () {
    final r = parser.parse(['가게', '가방 ¥1,000', '모자 ¥500']);
    expect(r.total, isNull);
    expect(r.totalOrSum, 1500);
  });

  test('영어 Subtotal·Sub total 줄은 합계로 보지 않고 Total을 합계로 읽는다', () {
    for (final sub in ['Subtotal', 'Sub total', 'SUB-TOTAL']) {
      final r = parser.parse([
        'Seoul Shop',
        'Bag \$100.00',
        '$sub \$100.00',
        'Tax \$10.00',
        'Total \$110.00',
      ]);
      expect(r.total, 110, reason: sub);
      expect(r.lines.map((l) => l.name), ['Bag'], reason: sub);
    }
  });

  test('라틴 낱말은 단어 단위로만 분류·제외한다', () {
    final r = parser.parse([
      'Shop',
      'Original Tote \$20.00',
      'Virgin Olive Oil \$12.00',
      'Face Serum \$30.00',
      'Hotel Shampoo \$5.00',
      'Cardigan \$40.00',
      'Gin Tonic 0.7L \$25.00',
      'Card \$135.00',
      'TEL 03-1234-5678',
    ]);
    expect(r.lines.map((l) => l.name), [
      'Original Tote',
      'Virgin Olive Oil',
      'Face Serum',
      'Hotel Shampoo',
      'Cardigan',
      'Gin Tonic 0.7L',
    ]);
    expect(
      r.lines.map((l) => l.category).take(5),
      everyElement(DutyFreeCategory.general),
    );
    expect(r.lines.last.category, DutyFreeCategory.liquor);
  });

  test('元·RMB·CNY가 있으면 ¥가 있어도 통화를 모름으로 둔다', () {
    for (final marker in [
      '合计 100元',
      '合计 58.00 元',
      '人民币',
      'RMB 100.00',
      'Currency: CNY',
    ]) {
      final r = parser.parse(['某商店', '茶叶 ¥58.00', marker]);
      expect(r.currency, isNull, reason: marker);
    }
    // 라틴 낱말은 단어로만 찾는다.
    expect(parser.parse(['Shop', 'Scnyder ¥1,280']).currency, 'JPY');
    expect(parser.parse(['Shop', 'Bag ¥1,280']).currency, 'JPY');
    // 금액 옆이 아닌 `元`은 일본어 낱말이라 엔으로 읽는다.
    for (final line in ['元祖 たこ焼き ¥800', '地元の味 ¥1,200', '元町店']) {
      expect(
        parser.parse(['Shop', line, '合計 ¥800']).currency,
        'JPY',
        reason: line,
      );
    }
  });
}
