import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _definedBaseUrl = String.fromEnvironment(
    'TRIPBLER_API_BASE_URL',
  );
  
  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) {
      return _definedBaseUrl;
    }

    if (kIsWeb) {
      return 'http://localhost:8080';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8080';

      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return 'http://localhost:8080';

      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return 'http://localhost:8080';
    }
  }

  static const String exchangeRatesPath = '/api/v1/exchange/rates';
  static const String exchangeHistoryPath = '/api/v1/exchange/history';

  static Uri exchangeRatesUri({
    required String baseCurrency,
    required List<String> targetCurrencies,
  }) {
    return Uri.parse(baseUrl).replace(
      path: exchangeRatesPath,
      queryParameters: <String, String>{
        'base': baseCurrency,
        'targets': targetCurrencies.join(','),
      },
    );
  }

  static Uri exchangeHistoryUri({
    required String baseCurrency,
    required String targetCurrency,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return Uri.parse(baseUrl).replace(
      path: exchangeHistoryPath,
      queryParameters: <String, String>{
        'base': baseCurrency,
        'target': targetCurrency,
        'startDate': _formatDate(startDate),
        'endDate': _formatDate(endDate),
      },
    );
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
