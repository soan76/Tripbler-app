import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 환율 화면에서 사용하는 로컬 데이터를 저장하고 불러오는 서비스.
///
/// 저장 대상:
/// - 기준 통화
/// - 화면에 표시할 통화 목록
/// - 최신 환율 캐시
/// - 마지막 환율 업데이트 시각
/// - 사용자가 입력한 금액
///
/// 저장소의 값은 앱 업데이트, 손상된 데이터 등으로 예상과 다른 형식이 될 수 있으므로
/// 복원 시에는 안전하게 파싱하고 잘못된 캐시는 제거한 뒤 `null`로 처리한다.
class LocalStorageService {
  static const String _baseCurrencyKey = 'exchange_base_currency';
  static const String _visibleCurrenciesKey = 'exchange_visible_currencies';
  static const String _cachedRatesKeyPrefix = 'exchange_cached_rates';
  static const String _lastUpdatedKeyPrefix = 'exchange_last_updated';
  static const String _amountKey = 'exchange_input_amount';

  String _cachedRatesKeyFor(String baseCurrency) {
    return '${_cachedRatesKeyPrefix}_${_normalizeCurrencyCode(baseCurrency)}';
  }

  String _lastUpdatedKeyFor(String baseCurrency) {
    return '${_lastUpdatedKeyPrefix}_${_normalizeCurrencyCode(baseCurrency)}';
  }

  String _normalizeCurrencyCode(String code) {
    final normalized = code.trim().toUpperCase();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        code,
        'baseCurrency',
        '기준 통화 코드는 비어 있을 수 없습니다.',
      );
    }

    return normalized;
  }

  /// SharedPreferences 인스턴스 접근을 한 곳으로 모은다.
  ///
  /// `SharedPreferences.getInstance()` 자체는 내부적으로 인스턴스를 캐싱하므로
  /// 성능 최적화 목적보다는 중복 제거와 접근 방식 통일을 위한 getter다.
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 기준 통화를 저장한다.
  Future<void> saveBaseCurrency(String code) async {
    final prefs = await _prefs;
    await prefs.setString(_baseCurrencyKey, code);
  }

  /// 저장된 기준 통화를 불러온다.
  Future<String?> loadBaseCurrency() async {
    final prefs = await _prefs;
    return prefs.getString(_baseCurrencyKey);
  }

  /// 화면에 표시할 통화 코드 목록을 저장한다.
  Future<void> saveVisibleCurrencies(List<String> codes) async {
    final prefs = await _prefs;
    await prefs.setStringList(_visibleCurrenciesKey, codes);
  }

  /// 저장된 표시 통화 코드 목록을 불러온다.
  Future<List<String>?> loadVisibleCurrencies() async {
    final prefs = await _prefs;
    return prefs.getStringList(_visibleCurrenciesKey);
  }

  /// 최신 환율 데이터를 JSON 문자열로 저장한다.
  ///
  /// NaN, Infinity, 0 이하 값은 정상적인 환율로 사용할 수 없으므로
  /// 저장 전에 검증해 잘못된 캐시가 생성되는 것을 방지한다.
  Future<void> saveCachedRates({
    required String baseCurrency,
    required Map<String, double> rates,
  }) async {
    _validateRatesForCache(rates);

    final prefs = await _prefs;
    final key = _cachedRatesKeyFor(baseCurrency);
    final encoded = jsonEncode(rates);

    await prefs.setString(key, encoded);
  }

  /// 캐시된 최신 환율 데이터를 불러온다.
  ///
  /// 저장 데이터가 손상되었거나 예상과 다른 JSON 구조라면
  /// 해당 캐시를 삭제하고 `null`을 반환하여 "사용 가능한 캐시 없음"으로 처리한다.
  Future<Map<String, double>?> loadCachedRates({
    required String baseCurrency,
  }) async {
    final prefs = await _prefs;
    final key = _cachedRatesKeyFor(baseCurrency);
    final encoded = prefs.getString(key);

    if (encoded == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(encoded);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('환율 캐시가 JSON 객체가 아닙니다.');
      }

      final rates = <String, double>{};

      for (final entry in decoded.entries) {
        final value = entry.value;

        if (value is! num) {
          throw FormatException('환율 캐시 값이 숫자가 아닙니다: ${entry.key}');
        }

        final rate = value.toDouble();

        if (!rate.isFinite || rate <= 0) {
          throw FormatException('환율 캐시 값이 올바르지 않습니다: ${entry.key}');
        }

        rates[entry.key] = rate;
      }

      return rates;
    } catch (error, stackTrace) {
      debugPrint('$baseCurrency 기준 환율 캐시 파싱 실패: $error');
      debugPrint('$stackTrace');

      await prefs.remove(key);

      return null;
    }
  }

  /// 마지막 환율 업데이트 시각을 저장한다.
  Future<void> saveLastUpdated({
    required String baseCurrency,
    required DateTime dateTime,
  }) async {
    final prefs = await _prefs;
    final key = _lastUpdatedKeyFor(baseCurrency);

    await prefs.setString(key, dateTime.toIso8601String());
  }

  /// 저장된 마지막 환율 업데이트 시각을 불러온다.
  ///
  /// 값이 존재하지만 DateTime으로 파싱할 수 없다면 손상된 값으로 판단해
  /// 저장소에서 제거하고 `null`을 반환한다.
  Future<DateTime?> loadLastUpdated({required String baseCurrency}) async {
    final prefs = await _prefs;
    final key = _lastUpdatedKeyFor(baseCurrency);

    final value = prefs.getString(key);

    if (value == null) {
      return null;
    }

    final parsed = DateTime.tryParse(value);

    if (parsed != null) {
      return parsed;
    }

    debugPrint(
      '$baseCurrency 기준 환율 업데이트 시각 형식이 '
      '올바르지 않습니다: $value',
    );

    await prefs.remove(key);

    return null;
  }

  /// 사용자가 입력한 기준 금액을 저장한다.
  Future<void> saveInputAmount(double amount) async {
    final prefs = await _prefs;
    await prefs.setDouble(_amountKey, amount);
  }

  /// 저장된 사용자 입력 금액을 불러온다.
  Future<double?> loadInputAmount() async {
    final prefs = await _prefs;
    return prefs.getDouble(_amountKey);
  }

  /// 환율 캐시에 저장할 값이 모두 유효한지 확인한다.
  ///
  /// 비정상 값을 조용히 제거하면 서버 응답 문제를 숨길 수 있으므로,
  /// 저장 자체를 중단하고 명확한 예외를 발생시킨다.
  void _validateRatesForCache(Map<String, double> rates) {
    for (final entry in rates.entries) {
      final rate = entry.value;

      if (!rate.isFinite || rate <= 0) {
        throw ArgumentError.value(
          rate,
          entry.key,
          '캐시에 저장할 환율은 0보다 큰 유한한 값이어야 합니다.',
        );
      }
    }
  }
}
