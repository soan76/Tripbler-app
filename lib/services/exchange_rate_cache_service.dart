import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/exchange_rate_history_model.dart';

class ExchangeRateCacheService {
  static const String _latestRatePrefix = 'chart_latest_rate';
  static const String _historyPrefix = 'chart_history';
  static const String _lastUpdatedPrefix = 'chart_last_updated';

  Future<void> saveLatestRate({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required double rate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _latestRateKey(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
    );

    await prefs.setDouble(key, rate);
  }

  Future<double?> loadLatestRate({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _latestRateKey(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
    );

    return prefs.getDouble(key);
  }

  Future<void> saveHistory({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required ChartPeriod period,
    required List<ExchangeRateHistoryModel> history,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final key = _historyKey(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
      period: period,
    );

    final encoded = jsonEncode(history.map((item) => item.toJson()).toList());

    await prefs.setString(key, encoded);
  }

  Future<List<ExchangeRateHistoryModel>?> loadHistory({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required ChartPeriod period,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final key = _historyKey(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
      period: period,
    );

    final encoded = prefs.getString(key);

    if (encoded == null) {
      return null;
    }

    final List<dynamic> decoded = jsonDecode(encoded);

    return decoded
        .map(
          (item) =>
              ExchangeRateHistoryModel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> saveLastUpdated({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required DateTime lastUpdated,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final key = _lastUpdatedKey(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
    );

    await prefs.setString(key, lastUpdated.toIso8601String());
  }

  Future<DateTime?> loadLastUpdated({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final key = _lastUpdatedKey(
      baseCurrencyCode: baseCurrencyCode,
      targetCurrencyCode: targetCurrencyCode,
    );

    final value = prefs.getString(key);

    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  String _latestRateKey({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) {
    return '$_latestRatePrefix-$baseCurrencyCode-$targetCurrencyCode';
  }

  String _historyKey({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
    required ChartPeriod period,
  }) {
    return '$_historyPrefix-$baseCurrencyCode-$targetCurrencyCode-${period.name}';
  }

  String _lastUpdatedKey({
    required String baseCurrencyCode,
    required String targetCurrencyCode,
  }) {
    return '$_lastUpdatedPrefix-$baseCurrencyCode-$targetCurrencyCode';
  }
}
