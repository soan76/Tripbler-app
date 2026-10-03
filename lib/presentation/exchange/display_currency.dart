import '../../models/currency_model.dart';
import '../../crypto/models/crypto_coin.dart';

/// 화면 전용 모델. API/환율 도메인에 암호화폐 심볼을 섞지 않는다.
class DisplayCurrency {
  const DisplayCurrency._({
    required this.code,
    required this.countryName,
    required this.currencyName,
    required this.flagEmoji,
    this.fiat,
  });
  factory DisplayCurrency.fromFiat(CurrencyModel currency) => DisplayCurrency._(
    code: currency.code,
    countryName: currency.countryName,
    currencyName: currency.currencyName,
    flagEmoji: currency.flagEmoji,
    fiat: currency,
  );
  factory DisplayCurrency.fromCrypto(CryptoCoin coin) => DisplayCurrency._(
    code: coin.symbol,
    countryName: coin.name,
    currencyName: '암호화폐',
    flagEmoji: '◈',
  );

  final String code;
  final String countryName;
  final String currencyName;
  final String flagEmoji;
  final CurrencyModel? fiat;
  bool get isCrypto => fiat == null;
  String? get iconAssetPath => isCrypto ? _cryptoIconAssets[code] : null;

  // 지원 목록은 서버에서 받고, 로컬 로고 경로만 화면 계층에서 관리한다.
  static const _cryptoIconAssets = <String, String>{
    'BTC': 'assets/images/Bitcoin.png',
    'ETH': 'assets/images/ETH_coin.png',
    'SOL': 'assets/images/SOL_coin.png',
    'XRP': 'assets/images/XRP_coin.png',
    'DOGE': 'assets/images/Dogecoin.png',
    'ADA': 'assets/images/Cardano_coin.png',
    'DASH': 'assets/images/Dash_coin.png',
  };

  String get id => '${isCrypto ? 'crypto' : 'fiat'}:$code';
  bool matches(String query) {
    final value = query.trim().toLowerCase();
    return [
      code,
      countryName,
      currencyName,
    ].any((text) => text.toLowerCase().contains(value));
  }
}
