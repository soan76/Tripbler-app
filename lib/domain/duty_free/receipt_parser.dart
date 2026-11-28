import '../../models/duty_free/duty_free_item.dart';

/// 영수증에서 읽은 물건 한 줄.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.amount,
    this.category = DutyFreeCategory.general,
    this.volume = 0,
    this.unsure = false,
  });

  final String name;
  final double amount;
  final DutyFreeCategory category;

  /// 주류는 병당 L, 향수는 개당 mL. 읽지 못하면 0.
  final double volume;

  /// 글자가 흐리거나 숫자에 다른 글자가 섞여 확인이 필요한 줄.
  final bool unsure;
}

/// 영수증 한 장을 읽은 결과(docs/mockups/duty-free.md 4절).
class ParsedReceipt {
  const ParsedReceipt({
    required this.store,
    required this.date,
    required this.currency,
    required this.total,
    required this.lines,
  });

  /// 가게 이름. 읽지 못하면 빈 글자.
  final String store;
  final DateTime? date;

  /// 읽은 통화 기호로 정한 통화. 모르면 null.
  final String? currency;

  /// 영수증 합계. 읽지 못하면 null.
  final double? total;
  final List<ReceiptLine> lines;

  /// 합계를 읽지 못하면 줄 금액을 더한 값.
  double get totalOrSum =>
      total ?? lines.fold<double>(0, (sum, l) => sum + l.amount);

  /// 같은 영수증인지 알아보는 키(가게·날짜·합계·통화).
  String keyFor(String currency) {
    final d = date;
    final day = d == null ? '' : '${d.year}-${d.month}-${d.day}';
    final store = this.store.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return '$store|$day|${totalOrSum.toStringAsFixed(2)}|$currency';
  }
}

/// 기기에서 읽은 영수증 줄 글자에서 가게·날짜·합계·물건 줄을 뽑는다.
///
/// 줄 끝의 금액을 물건 값으로 보고, 소계·세금·거스름돈 같은 줄은 뺀다. 숫자 자리에 O·l 같은
/// 글자가 섞이면 고쳐 읽고 "확인 필요"로 둔다. 분류는 이름의 낱말로 짐작한다.
class ReceiptParser {
  const ReceiptParser();

  static final RegExp _price = RegExp(
    r'([¥￥$€₩])?\s*([0-9OolI][0-9OolI,.]*)\s*(円|원)?\s*[*※]?\s*$',
  );
  static final RegExp _date = RegExp(
    r'(20\d{2})\s*[./年-]\s*(\d{1,2})\s*[./月-]\s*(\d{1,2})',
  );
  static final RegExp _volume = RegExp(
    r'(\d+(?:\.\d+)?)\s*(ml|l|リットル)(?![a-z])',
    caseSensitive: false,
  );

  static final _Words _totalWords = _Words(const [
    '合計',
    '合 計',
    '総額',
    'お買上',
    'total',
    '합계',
    '결제금액',
    'amount due',
  ]);

  /// 합계 낱말(`total`)이 들어 있어도 합계가 아닌 소계 줄.
  static final _Words _subtotalWords = _Words(const [
    '小計',
    '소계',
    'subtotal',
    'sub total',
    'sub-total',
  ]);

  static final _Words _skipWords = _Words(const [
    '小計',
    'subtotal',
    'sub total',
    'sub-total',
    '소계',
    '税',
    'tax',
    '부가세',
    '預',
    'お釣',
    '釣銭',
    'change',
    'cash',
    '現金',
    'card',
    'カード',
    '카드',
    '거스름',
    'tel',
    '電話',
    '点数',
    'qty',
    '割引',
    'discount',
    '할인',
    'no.',
    'レジ',
  ]);

  /// 중국 위안 영수증 표시. `¥`·`￥`를 함께 쓰므로 이 낱말이 보이면 엔으로 정하지 않는다.
  static final _Words _yuanWords = _Words(const ['人民币', 'rmb', 'cny']);

  /// 금액 바로 뒤의 `元`(예: `100元`, `58.00 元`). 일본어 낱말(元祖·地元)의 `元`은 위안으로 보지 않는다.
  static final RegExp _yuanAmount = RegExp(r'\d\s*元');

  static final Map<DutyFreeCategory, _Words> _categoryWords = {
    DutyFreeCategory.liquor: _Words(const [
      'whisky',
      'whiskey',
      'wine',
      'beer',
      'sake',
      'vodka',
      'gin',
      'rum',
      'cognac',
      'brandy',
      'liquor',
      'ウイスキー',
      'ワイン',
      'ビール',
      '日本酒',
      '焼酎',
      '酒',
      '위스키',
      '와인',
      '맥주',
      '소주',
      '사케',
      '술',
    ]),
    DutyFreeCategory.tobacco: _Words(const [
      'cigarette',
      'tobacco',
      'iqos',
      'marlboro',
      'たばこ',
      'タバコ',
      '煙草',
      '담배',
    ]),
    DutyFreeCategory.perfume: _Words(const [
      'perfume',
      'parfum',
      'eau de',
      'edt',
      'edp',
      'cologne',
      '香水',
      'フレグランス',
      '향수',
    ]),
  };

  ParsedReceipt parse(List<String> rawLines) {
    var store = '';
    DateTime? date;
    double? total;
    final symbols = <String>[];
    final lines = <ReceiptLine>[];
    String? pendingName;
    var yuan = false;

    for (final raw in rawLines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      yuan = yuan || _yuanWords.matches(lower) || _yuanAmount.hasMatch(line);

      final dateMatch = _date.firstMatch(line);
      if (dateMatch != null) {
        date ??= _toDate(dateMatch);
        pendingName = null;
        continue;
      }

      final price = _readPrice(line);
      if (price == null) {
        if (store.isEmpty && _looksLikeName(line)) {
          store = line;
        } else if (_looksLikeName(line) && !_skipWords.matches(lower)) {
          // 이름과 금액이 다른 줄에 찍힌 영수증: 다음 줄 금액과 잇는다.
          pendingName = line;
        }
        continue;
      }

      if (price.symbol != null) symbols.add(price.symbol!);

      if (_totalWords.matches(lower) && !_subtotalWords.matches(lower)) {
        total ??= price.amount;
        pendingName = null;
        continue;
      }
      if (_skipWords.matches(lower)) {
        pendingName = null;
        continue;
      }

      var name = price.name;
      if (name.isEmpty && pendingName != null) name = pendingName;
      pendingName = null;
      if (name.isEmpty || price.amount <= 0) continue;

      final category = _category(name.toLowerCase());
      lines.add(
        ReceiptLine(
          name: name,
          amount: price.amount,
          category: category,
          volume: _volumeFor(name, category),
          unsure: price.unsure || !_looksLikeName(name),
        ),
      );
    }

    return ParsedReceipt(
      store: store,
      date: date,
      // 위안 영수증일 수 있으면 통화를 모름으로 두고 검토 화면에서 고르게 한다.
      currency: yuan ? null : _currency(symbols),
      total: total,
      lines: lines,
    );
  }

  /// 글자(한글·가나·한자·라틴)가 두 개 이상이면 이름으로 본다.
  static bool _looksLikeName(String text) {
    final letters = RegExp(r'[A-Za-z぀-ヿ㐀-鿿가-힣]').allMatches(text).length;
    return letters >= 2 && !text.contains('?');
  }

  static DateTime? _toDate(RegExpMatch m) {
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }

  static _Price? _readPrice(String line) {
    final m = _price.firstMatch(line);
    if (m == null) return null;
    var digits = m.group(2)!;
    if (!RegExp(r'\d').hasMatch(digits)) return null;
    // 금액 앞에 글자가 붙어 있으면(예: "A4") 금액으로 보지 않는다.
    final before = line.substring(0, m.start);
    if (m.group(1) == null &&
        !m.group(0)!.startsWith(RegExp(r'\s')) &&
        before.isNotEmpty &&
        RegExp(r'[A-Za-z0-9]$').hasMatch(before)) {
      return null;
    }
    final unsure = RegExp(r'[OolI]').hasMatch(digits);
    digits = digits
        .replaceAll(RegExp('[Oo]'), '0')
        .replaceAll(RegExp('[lI]'), '1');
    // 마지막 점 뒤가 1~2자리면 소수점, 아니면 천 단위 구분.
    final dot = digits.lastIndexOf('.');
    if (dot >= 0 && digits.length - dot - 1 <= 2 && digits.length - dot > 1) {
      digits =
          digits.substring(0, dot).replaceAll(RegExp('[.,]'), '') +
          digits.substring(dot);
    } else {
      digits = digits.replaceAll(RegExp('[.,]'), '');
    }
    final amount = double.tryParse(digits);
    if (amount == null) return null;
    final symbol = m.group(1) ?? m.group(3);
    final name = before.trim().replaceAll(RegExp(r'[\s:：]+$'), '');
    return _Price(name: name, amount: amount, symbol: symbol, unsure: unsure);
  }

  static String? _currency(List<String> symbols) {
    for (final s in symbols) {
      switch (s) {
        case '¥' || '￥' || '円':
          return 'JPY';
        case r'$':
          return 'USD';
        case '€':
          return 'EUR';
        case '₩' || '원':
          return 'KRW';
      }
    }
    return null;
  }

  static DutyFreeCategory _category(String lower) {
    for (final entry in _categoryWords.entries) {
      if (entry.value.matches(lower)) return entry.key;
    }
    return DutyFreeCategory.general;
  }

  static double _volumeFor(String name, DutyFreeCategory category) {
    if (!category.hasVolume) return 0;
    final m = _volume.firstMatch(name);
    if (m == null) return 0;
    final value = double.parse(m.group(1)!);
    final isMl = m.group(2)!.toLowerCase() == 'ml';
    if (category == DutyFreeCategory.liquor) return isMl ? value / 1000 : value;
    return isMl ? value : value * 1000;
  }
}

/// 소문자 줄에서 찾을 낱말 묶음.
///
/// 라틴 낱말은 앞뒤에 다른 라틴 글자가 붙지 않은 단어로만 찾는다(`gin`이 `original`에, `tel`이
/// `hotel`에 걸리지 않게). 한글·가나·한자 낱말은 띄어 쓰지 않으므로 글자 안에서 포함 여부로 찾는다.
class _Words {
  factory _Words(List<String> words) {
    final latin = words.where(_latinOnly.hasMatch).map(RegExp.escape).toList();
    return _Words._(
      words.where((w) => !_latinOnly.hasMatch(w)).toList(),
      latin.isEmpty
          ? null
          : RegExp('(?<![a-z])(?:${latin.join('|')})(?![a-z])'),
    );
  }

  _Words._(this._cjk, this._latin);

  static final RegExp _latinOnly = RegExp(r'^[a-z0-9 .\-]+$');

  final List<String> _cjk;
  final RegExp? _latin;

  bool matches(String lower) =>
      _cjk.any(lower.contains) || (_latin?.hasMatch(lower) ?? false);
}

class _Price {
  const _Price({
    required this.name,
    required this.amount,
    required this.symbol,
    required this.unsure,
  });

  final String name;
  final double amount;
  final String? symbol;
  final bool unsure;
}
