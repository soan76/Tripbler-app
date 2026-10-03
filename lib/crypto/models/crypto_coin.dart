class CryptoCoin {
  const CryptoCoin({required this.symbol, required this.name});

  final String symbol;
  final String name;

  factory CryptoCoin.fromJson(Map<String, dynamic> json) {
    final symbol = json['symbol'];
    final name = json['name'];
    if (symbol is! String ||
        symbol.isEmpty ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('잘못된 암호화폐 목록 응답');
    }
    return CryptoCoin(symbol: symbol.toUpperCase(), name: name);
  }

  Map<String, dynamic> toJson() => {'symbol': symbol, 'name': name};
}
