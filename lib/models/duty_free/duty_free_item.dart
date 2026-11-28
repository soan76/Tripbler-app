/// 면세 계산의 분류(docs/mockups/duty-free.md 3절). 일반 물품은 금액 한도, 나머지는 별도 기준.
enum DutyFreeCategory {
  general('일반'),
  liquor('주류'),
  tobacco('담배'),
  perfume('향수');

  const DutyFreeCategory(this.label);

  final String label;

  /// 수량 칸 이름.
  String get quantityLabel => switch (this) {
    DutyFreeCategory.general => '수량',
    DutyFreeCategory.liquor => '병 수',
    DutyFreeCategory.tobacco => '갑 수',
    DutyFreeCategory.perfume => '개수',
  };

  /// 용량을 받는 분류인지(주류는 병당 L, 향수는 개당 mL).
  bool get hasVolume =>
      this == DutyFreeCategory.liquor || this == DutyFreeCategory.perfume;

  String get volumeUnit => this == DutyFreeCategory.liquor ? 'L' : 'mL';

  static DutyFreeCategory? byName(Object? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// 산 곳. 출국 면세점·기내에서 산 것도 한도에 들어간다(예시 기준).
enum PurchasePlace {
  local('현지 상점'),
  departureDutyFree('출국 면세점'),
  inflight('기내 면세');

  const PurchasePlace(this.label);

  final String label;

  static PurchasePlace? byName(Object? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// 산 물건 하나. [amount]는 [currency]로 낸 합계 금액이다.
class DutyFreeItem {
  const DutyFreeItem({
    required this.id,
    required this.category,
    required this.name,
    required this.quantity,
    required this.volume,
    required this.amount,
    required this.currency,
    required this.place,
    required this.purchasedAt,
    this.needsCheck = false,
  });

  /// 화면에서 고를 수 있는 통화.
  static const List<String> currencies = ['JPY', 'USD', 'EUR', 'KRW'];

  static const int maxNameLength = 40;

  final String id;
  final DutyFreeCategory category;
  final String name;

  /// 병·갑·개 수(1 이상).
  final int quantity;

  /// 주류는 병당 L, 향수는 개당 mL. 다른 분류는 0.
  final double volume;
  final double amount;
  final String currency;
  final PurchasePlace place;
  final DateTime purchasedAt;

  /// 영수증에서 읽었는데 글자가 불확실한 줄.
  final bool needsCheck;

  /// 분류 전체 용량(주류 L, 향수 mL).
  double get totalVolume => category.hasVolume ? quantity * volume : 0;

  DutyFreeItem copyWith({
    DutyFreeCategory? category,
    String? name,
    int? quantity,
    double? volume,
    double? amount,
    String? currency,
    PurchasePlace? place,
    bool? needsCheck,
  }) {
    return DutyFreeItem(
      id: id,
      category: category ?? this.category,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      volume: volume ?? this.volume,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      place: place ?? this.place,
      purchasedAt: purchasedAt,
      needsCheck: needsCheck ?? this.needsCheck,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category.name,
    'name': name,
    'quantity': quantity,
    'volume': volume,
    'amount': amount,
    'currency': currency,
    'place': place.name,
    'purchasedAt': purchasedAt.toIso8601String(),
    if (needsCheck) 'needsCheck': true,
  };

  /// 형식이 틀리면 null(그 항목만 버린다).
  static DutyFreeItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final category = DutyFreeCategory.byName(json['category']);
    final place = PurchasePlace.byName(json['place']);
    final quantity = json['quantity'];
    final volume = json['volume'];
    final amount = json['amount'];
    final currency = json['currency'];
    final at = json['purchasedAt'];
    final purchasedAt = at is String ? DateTime.tryParse(at) : null;
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        category == null ||
        place == null ||
        quantity is! int ||
        quantity < 1 ||
        volume is! num ||
        volume < 0 ||
        amount is! num ||
        amount < 0 ||
        currency is! String ||
        !currencies.contains(currency) ||
        purchasedAt == null) {
      return null;
    }
    return DutyFreeItem(
      id: id,
      category: category,
      name: name,
      quantity: quantity,
      volume: volume.toDouble(),
      amount: amount.toDouble(),
      currency: currency,
      place: place,
      purchasedAt: purchasedAt,
      needsCheck: json['needsCheck'] == true,
    );
  }
}

/// 기기에 저장하는 면세 기록 한 벌(한 여행).
class DutyFreeTrip {
  const DutyFreeTrip({
    this.adult = true,
    this.items = const [],
    this.receiptKeys = const {},
  });

  static const DutyFreeTrip empty = DutyFreeTrip();

  /// 만 19세 이상인지. 주류·담배 기준에만 쓴다.
  final bool adult;
  final List<DutyFreeItem> items;

  /// 이미 넣은 영수증(가게·날짜·합계·통화). 같은 영수증을 다시 넣을 때 경고한다.
  final Set<String> receiptKeys;

  DutyFreeTrip copyWith({
    bool? adult,
    List<DutyFreeItem>? items,
    Set<String>? receiptKeys,
  }) {
    return DutyFreeTrip(
      adult: adult ?? this.adult,
      items: items ?? this.items,
      receiptKeys: receiptKeys ?? this.receiptKeys,
    );
  }
}
