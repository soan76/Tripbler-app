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

  static const String usersPath = '/api/v1/users';

  static const String authLoginPath = '/api/v1/auth/login';
  static const String authRefreshPath = '/api/v1/auth/refresh';
  static const String authLogoutPath = '/api/v1/auth/logout';
  static const String usersMePath = '/api/v1/users/me';
  static const String usersCheckLoginIdPath = '/api/v1/users/check-login-id';

  static Uri get usersUri {
    return Uri.parse(baseUrl).replace(path: usersPath);
  }

  static Uri get authLoginUri {
    return Uri.parse(baseUrl).replace(path: authLoginPath);
  }

  static Uri get authRefreshUri {
    return Uri.parse(baseUrl).replace(path: authRefreshPath);
  }

  static Uri get authLogoutUri {
    return Uri.parse(baseUrl).replace(path: authLogoutPath);
  }

  static Uri get usersMeUri {
    return Uri.parse(baseUrl).replace(path: usersMePath);
  }

  static Uri usersCheckLoginIdUri({required String loginId}) {
    return Uri.parse(baseUrl).replace(
      path: usersCheckLoginIdPath,
      queryParameters: <String, String>{'loginId': loginId},
    );
  }

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
