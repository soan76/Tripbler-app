import 'package:intl/intl.dart';

import '../../models/duty_free/duty_free_item.dart';

/// 면세 화면의 금액·날짜 글자.
abstract final class DutyFreeFormat {
  static final NumberFormat _whole = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _cents = NumberFormat('#,##0.##', 'en_US');

  static const Map<String, String> _symbols = {
    'JPY': '¥',
    'USD': r'$',
    'EUR': '€',
    'KRW': '₩',
  };

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  static String symbol(String currency) => _symbols[currency] ?? '';

  /// 달러 반올림: `$1,234`.
  static String usd(double value) => '\$${_whole.format(value.round())}';

  /// 원 반올림: `₩12,345`.
  static String krw(double value) => '₩${_whole.format(value.round())}';

  /// 숫자만(소수 두 자리까지): `1,280`, `12.5`.
  static String number(double value) => _cents.format(value);

  /// 입력 칸에 채울 숫자: 반올림·쉼표 없이 `1234.567`, 정수면 `.0` 없이 `12800`.
  static String editable(double value) =>
      value == value.truncateToDouble() && value.abs() < 1e15
      ? value.toInt().toString()
      : value.toString();

  static final RegExp _grouped = RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$');

  /// 입력 칸의 숫자를 읽는다. 쉼표는 3자리씩 끊은 천 단위(`1,280`)만 받고, `1,5`처럼 다른 쉼표나
  /// 숫자가 아닌 글자가 있으면 다른 값으로 바꾸지 않고 null을 돌려준다.
  static double? parseNumber(String text) {
    final t = text.trim();
    if (t.contains(',') && !_grouped.hasMatch(t)) return null;
    final value = double.tryParse(t.replaceAll(',', ''));
    return value != null && value.isFinite ? value : null;
  }

  /// 현지 금액: `¥38,000 JPY`.
  static String money(double amount, String currency) =>
      '${symbol(currency)}${number(amount)} $currency';

  /// `11/28 (토)`.
  static String day(DateTime d) =>
      '${d.month}/${d.day} (${_weekdays[d.weekday - 1]})';

  /// `11월 27일 오전 9:00`.
  static String dateTime(DateTime d) {
    final am = d.hour < 12;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.month}월 ${d.day}일 ${am ? '오전' : '오후'} $h:$m';
  }

  static String isoDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 목록 줄의 수량·용량: ` · 3병 × 0.7L`.
  static String quantity(DutyFreeItem item) => switch (item.category) {
    DutyFreeCategory.liquor => ' · ${item.quantity}병 × ${number(item.volume)}L',
    DutyFreeCategory.perfume =>
      ' · ${item.quantity}개 × ${number(item.volume)}mL',
    DutyFreeCategory.tobacco => ' · ${item.quantity}갑',
    DutyFreeCategory.general => item.quantity > 1 ? ' · ${item.quantity}개' : '',
  };
}
