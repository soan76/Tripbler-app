import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _baseCurrencyKey = 'exchange_base_currency';
  static const String _visibleCurrenciesKey = 'exchange_visible_currencies';
  static const String _cachedRatesKey = 'exchange_cached_rates';
  static const String _lastUpdatedKey = 'exchange_last_updated';
  static const String _amountKey = 'exchange_input_amount';

  Future<void> saveBaseCurrency(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseCurrencyKey, code);
  }

  Future<String?> loadBaseCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseCurrencyKey);
  }

  Future<void> saveVisibleCurrencies(List<String> codes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_visibleCurrenciesKey, codes);
  }

  Future<List<String>?> loadVisibleCurrencies() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_visibleCurrenciesKey);
  }

  Future<void> saveCachedRates(Map<String, double> rates) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(rates);
    await prefs.setString(_cachedRatesKey, encoded);
  }

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

  Future<void> saveLastUpdated(DateTime dateTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUpdatedKey, dateTime.toIso8601String());
  }

  Future<DateTime?> loadLastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_lastUpdatedKey);

    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  Future<void> saveInputAmount(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_amountKey, amount);
  }

  Future<double?> loadInputAmount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_amountKey);
  }
}
