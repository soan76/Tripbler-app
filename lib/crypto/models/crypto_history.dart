class CryptoHistoryPoint {
  const CryptoHistoryPoint({required this.timestamp, required this.price});
  final DateTime timestamp;
  final double price;

  factory CryptoHistoryPoint.fromJson(Map<String, dynamic> json) {
    final timestamp = json['timestamp'];
    final price = json['price'];
    if (timestamp is! int || price is! num || !price.isFinite || price <= 0) {
      throw const FormatException('잘못된 암호화폐 과거 시세 포인트');
    }
    return CryptoHistoryPoint(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      price: price.toDouble(),
    );
  }
}

class CryptoHistory {
  CryptoHistory({
    required this.symbol,
    required this.currency,
    required this.period,
    required this.days,
    required List<CryptoHistoryPoint> prices,
    required this.fetchedAt,
    this.stale = false,
  }) : prices = List.unmodifiable(prices);
  final String symbol;
  final String currency;
  final String period;
  final int days;
  final List<CryptoHistoryPoint> prices;
  final DateTime fetchedAt;
  final bool stale;

  static const supportedPeriods = {
    '7D': 7,
    '1M': 30,
    '3M': 90,
    '6M': 180,
    '1Y': 365,
  };

  factory CryptoHistory.fromJson(Map<String, dynamic> json) {
    final symbol = json['symbol'];
    final period = json['period'];
    final days = json['days'];
    final prices = json['prices'];
    final fetchedAt = DateTime.tryParse(json['fetchedAt']?.toString() ?? '');
    if (symbol is! String ||
        symbol.isEmpty ||
        json['currency'] != 'KRW' ||
        period is! String ||
        days is! int ||
        supportedPeriods[period] != days ||
        prices is! List ||
        fetchedAt == null) {
      throw const FormatException('잘못된 암호화폐 과거 시세 응답');
    }
    final points = prices
        .map(
          (point) => CryptoHistoryPoint.fromJson(point as Map<String, dynamic>),
        )
        .toList();
    for (var i = 1; i < points.length; i++) {
      if (!points[i].timestamp.isAfter(points[i - 1].timestamp)) {
        throw const FormatException('과거 시세의 시각이 중복되거나 정렬되지 않았습니다.');
      }
    }
    return CryptoHistory(
      symbol: symbol,
      currency: 'KRW',
      period: period,
      days: days,
      prices: points,
      fetchedAt: fetchedAt.toUtc(),
      stale: json['stale'] == true,
    );
  }
}
