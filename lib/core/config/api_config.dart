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
  static const String authFindIdSendCodePath = '/api/v1/auth/find-id/send-code';
  static const String authFindIdVerifyCodePath =
      '/api/v1/auth/find-id/verify-code';
  static const String authPasswordResetSendCodePath =
      '/api/v1/auth/password-reset/send-code';

  static const String authPasswordResetVerifyCodePath =
      '/api/v1/auth/password-reset/verify-code';

  static const String authPasswordResetPath = '/api/v1/auth/password-reset';

  static const String usersMePath = '/api/v1/users/me';

  static const String usersMeNicknamePath = '/api/v1/users/me/nickname';

  static const String usersMeProfileImagePath =
      '/api/v1/users/me/profile-image';

  static const String usersMeGoogleLinkPath =
      '/api/v1/users/me/social-accounts/google';
  static const String usersMeSocialAccountsPath =
      '/api/v1/users/me/social-accounts';

  static const String usersCheckLoginIdPath = '/api/v1/users/check-login-id';

  /// 찍기 모드 줄별 번역·한글 발음·가격(로그인 필요).
  static const String translationLinesPath = '/api/v1/translation/lines';

  static Uri get translationLinesUri {
    return Uri.parse(baseUrl).replace(path: translationLinesPath);
  }

  static const String translationPhotoPath = '/api/v1/translation/photo';

  static Uri get translationPhotoUri {
    return Uri.parse(baseUrl).replace(path: translationPhotoPath);
  }

  static const String placesPath = '/api/v1/places';
  static const String placesSearchPath = '$placesPath/search';

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

  static Uri get authFindIdSendCodeUri {
    return Uri.parse(baseUrl).replace(path: authFindIdSendCodePath);
  }

  static Uri get authFindIdVerifyCodeUri {
    return Uri.parse(baseUrl).replace(path: authFindIdVerifyCodePath);
  }

  static Uri get authPasswordResetSendCodeUri {
    return Uri.parse(baseUrl).replace(path: authPasswordResetSendCodePath);
  }

  static Uri get authPasswordResetVerifyCodeUri {
    return Uri.parse(baseUrl).replace(path: authPasswordResetVerifyCodePath);
  }

  static Uri get authPasswordResetUri {
    return Uri.parse(baseUrl).replace(path: authPasswordResetPath);
  }

  static Uri get usersMeUri {
    return Uri.parse(baseUrl).replace(path: usersMePath);
  }

  static Uri get usersMeNicknameUri {
    return Uri.parse(baseUrl).replace(path: usersMeNicknamePath);
  }

  static Uri get usersMeProfileImageUri {
    return Uri.parse(baseUrl).replace(path: usersMeProfileImagePath);
  }

  static Uri get usersMeSocialAccountsUri {
    return Uri.parse(baseUrl).replace(path: usersMeSocialAccountsPath);
  }

  static Uri get usersMeGoogleLinkUri {
    return Uri.parse(baseUrl).replace(path: usersMeGoogleLinkPath);
  }

  static Uri usersCheckLoginIdUri({required String loginId}) {
    return Uri.parse(baseUrl).replace(
      path: usersCheckLoginIdPath,
      queryParameters: <String, String>{'loginId': loginId},
    );
  }

  /// 장소 검색(로그인 필요).
  ///
  /// 좌표는 둘 다 넣거나 둘 다 생략한다. 서버가 하나만 온 요청을 400으로 막는다.
  static Uri placesSearchUri({
    required String query,
    double? latitude,
    double? longitude,
  }) {
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError('위도와 경도는 함께 전달해야 합니다.');
    }

    return Uri.parse(baseUrl).replace(
      path: placesSearchPath,
      queryParameters: <String, String>{
        'query': query,
        if (latitude != null && longitude != null) ...<String, String>{
          'lat': _formatCoordinate(latitude),
          'lng': _formatCoordinate(longitude),
        },
      },
    );
  }

  /// 좌표를 지수 표기 없이 소수 7자리(약 1cm)까지 쓴다. `double.toString()`은 0에 가까운 값을
  /// `1e-7`처럼 쓰는데, 서버가 받는 형식과 맞추려고 고정 소수로 바꾸고 끝의 0은 지운다.
  /// 무한대·NaN은 보낼 수 없어 [ArgumentError]를 던진다.
  static String _formatCoordinate(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'coordinate', '좌표가 올바르지 않습니다.');
    }

    var text = value.toStringAsFixed(7);

    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }

    return text == '-0' ? '0' : text;
  }

  /// 장소 상세. placeId는 경로 조각으로 넣어 `/`, `?` 같은 문자도 인코딩한다.
  ///
  /// 비었거나 공백뿐인 값, `.`·`..`은 경로 조각으로 넣으면 다른 경로(목록 등)를 가리키게 되므로
  /// [ArgumentError]를 던진다.
  static Uri placeDetailsUri({required String placeId}) {
    if (placeId.trim().isEmpty || placeId == '.' || placeId == '..') {
      throw ArgumentError.value(placeId, 'placeId', '장소 ID가 올바르지 않습니다.');
    }

    final baseUri = Uri.parse(baseUrl);

    return baseUri.replace(
      pathSegments: <String>[...Uri.parse(placesPath).pathSegments, placeId],
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
