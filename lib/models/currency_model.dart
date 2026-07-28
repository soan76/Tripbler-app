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

  // CurrencyModel 객체를 JSON 형태의 Map으로 변환
  // 로컬 저장소나 서버에 데이터를 저장할 때 사용.
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'countryName': countryName,
      'currencyName': currencyName,
      'flagEmoji': flagEmoji,
    };
  }

  // JSON 형태의 Map을 CurrencyModel 객체로 변환
  //저장된 통화 정보를 다시 불러올 때 사용
  factory CurrencyModel.fromJson(Map<String, dynamic> json) {
    return CurrencyModel(
      code: json['code'] as String,
      countryName: json['countryName'] as String,
      currencyName: json['currencyName'] as String,
      flagEmoji: json['flagEmoji'] as String,
    );
  }
}

// 지원하는 통화 목록 - 수정 예정
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

// 통화 코드를 이용해 supportedCurrencies 목록에서 통화 정보를 검색
CurrencyModel findCurrencyByCode(String code) {
  return supportedCurrencies.firstWhere(
    // 전달받은 코드와 일치하는 통화 객체를 반환
    (currency) => currency.code == code,
    // 일치하는 통화가 없을 경우, 기본값으로 첫 번째 통화 객체를 반환
    orElse: () => supportedCurrencies.first,
  );
}
