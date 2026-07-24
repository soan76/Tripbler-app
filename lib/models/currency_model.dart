import 'package:flutter/material.dart';

class CurrencyModel {
  final String code;
  final String countryName;
  final String currencyName;
  final String flagEmoji;
  final Color accentColor;

  const CurrencyModel({
    required this.code,
    required this.countryName,
    required this.currencyName,
    required this.flagEmoji,
    this.accentColor = Colors.blue,
  });

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'countryName': countryName,
      'currencyName': currencyName,
      'flagEmoji': flagEmoji,
    };
  }

  factory CurrencyModel.fromJson(Map<String, dynamic> json) {
    return CurrencyModel(
      code: json['code'] as String,
      countryName: json['countryName'] as String,
      currencyName: json['currencyName'] as String,
      flagEmoji: json['flagEmoji'] as String,
    );
  }
}

const List<CurrencyModel> supportedCurrencies = [
  CurrencyModel(
    code: 'KRW',
    countryName: '대한민국',
    currencyName: '원',
    flagEmoji: '🇰🇷',
  ),
  CurrencyModel(
    code: 'USD',
    countryName: '미국',
    currencyName: '달러',
    flagEmoji: '🇺🇸',
  ),
  CurrencyModel(
    code: 'JPY',
    countryName: '일본',
    currencyName: '엔',
    flagEmoji: '🇯🇵',
  ),
  CurrencyModel(
    code: 'EUR',
    countryName: '유럽연합',
    currencyName: '유로',
    flagEmoji: '🇪🇺',
  ),
  CurrencyModel(
    code: 'GBP',
    countryName: '영국',
    currencyName: '파운드',
    flagEmoji: '🇬🇧',
  ),
  CurrencyModel(
    code: 'CNY',
    countryName: '중국',
    currencyName: '위안',
    flagEmoji: '🇨🇳',
  ),
  CurrencyModel(
    code: 'THB',
    countryName: '태국',
    currencyName: '바트',
    flagEmoji: '🇹🇭',
  ),
  CurrencyModel(
    code: 'VND',
    countryName: '베트남',
    currencyName: '동',
    flagEmoji: '🇻🇳',
  ),
  CurrencyModel(
    code: 'AUD',
    countryName: '호주',
    currencyName: '달러',
    flagEmoji: '🇦🇺',
  ),
  CurrencyModel(
    code: 'CAD',
    countryName: '캐나다',
    currencyName: '달러',
    flagEmoji: '🇨🇦',
  ),
];

CurrencyModel findCurrencyByCode(String code) {
  return supportedCurrencies.firstWhere(
    (currency) => currency.code == code,
    orElse: () => supportedCurrencies.first,
  );
}
