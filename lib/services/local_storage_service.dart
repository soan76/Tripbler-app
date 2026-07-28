import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// 로컬 스토리지에 데이터를 저장하고 불러오는 서비스를 제공하는 클래스
class LocalStorageService {
  static const String _baseCurrencyKey = 'exchange_base_currency';
  static const String _visibleCurrenciesKey = 'exchange_visible_currencies';
  static const String _cachedRatesKey = 'exchange_cached_rates';
  static const String _lastUpdatedKey = 'exchange_last_updated';
  static const String _amountKey = 'exchange_input_amount';

  // 기준 통화를 저장하는 메서드
  Future<void> saveBaseCurrency(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseCurrencyKey, code);
  }

  // 기준 통화를 불러오는 메서드
  Future<String?> loadBaseCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseCurrencyKey);
  }

  // 표시할 통화 목록을 저장하는 메서드
  Future<void> saveVisibleCurrencies(List<String> codes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_visibleCurrenciesKey, codes);
  }

  // 표시할 통화 목록을 불러오는 메서드
  Future<List<String>?> loadVisibleCurrencies() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_visibleCurrenciesKey);
  }

  // 캐시된 환율 데이터를 저장하는 메서드
  Future<void> saveCachedRates(Map<String, double> rates) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(rates);
    await prefs.setString(_cachedRatesKey, encoded);
  }

  // 캐시된 환율 데이터를 불러오는 메서드
  Future<Map<String, double>?> loadCachedRates() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_cachedRatesKey);

    if (encoded == null) {
      return null;
    }

    final Map<String, dynamic> decoded = jsonDecode(encoded);

    return decoded.map((key, value) {
      return MapEntry(key, (value as num).toDouble());
    });
  }

  // 마지막 업데이트 시간을 저장하는 메서드
  Future<void> saveLastUpdated(DateTime dateTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUpdatedKey, dateTime.toIso8601String());
  }

  // 마지막 업데이트 시간을 불러오는 메서드
  Future<DateTime?> loadLastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastUpdatedKey);

    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  // 사용자가 입력한 금액을 저장하는 메서드
  Future<void> saveInputAmount(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_amountKey, amount);
  }

  // 사용자가 입력한 금액을 불러오는 메서드
  Future<double?> loadInputAmount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_amountKey);
  }
}
