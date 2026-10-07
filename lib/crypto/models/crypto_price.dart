class CryptoPrice {
  const CryptoPrice({
    required this.symbol,
    required this.price,
    required this.fetchedAt,
    this.stale = false,
  });

  final String symbol;
  final double price;
  final DateTime fetchedAt;
  final bool stale;

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'currency': 'KRW',
    'price': price,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'stale': stale,
  };

  factory CryptoPrice.fromJson(Map<String, dynamic> json) {
    final price = json['price'];
    final symbol = json['symbol'];
    final time = DateTime.tryParse(json['fetchedAt']?.toString() ?? '');
    if (symbol is! String ||
        json['currency'] != 'KRW' ||
        price is! num ||
        !price.isFinite ||
        price <= 0 ||
        time == null) {
      throw const FormatException('잘못된 암호화폐 현재가 응답');
    }
    return CryptoPrice(
      symbol: symbol,
      price: price.toDouble(),
      fetchedAt: time.toUtc(),
      stale: json['stale'] == true,
    );
  }
}
