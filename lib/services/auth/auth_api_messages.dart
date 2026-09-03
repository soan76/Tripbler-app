/// AuthApiService가 사용하는 사용자향 메시지 제공자.
/// 추후 앱의 로컬라이제이션 계층에서 네트워크 서비스와 문자열을 분리한다.
abstract class AuthApiMessages {
  const AuthApiMessages();

  String get requestSerializationFailed;
  String get requestTimeout;
  String get connectionFailed;
  String get invalidServerResponse;

  String get invalidLoginResponse;
  String get invalidSignupResponse;
  String get invalidLoginIdAvailabilityResponse;
  String get invalidFindIdResponse;
  String get invalidPasswordResetVerificationResponse;
  String get invalidTokenRefreshResponse;
  String get invalidCurrentUserResponse;
  String get invalidSocialAccountStatusResponse;

  String forStatusCode({required int statusCode, String? serverMessage});
}

/// Tripbler 인증 API의 기본 한국어 메시지 구현.
/// 추후 Localizations 기반 구현으로 교체해 AuthApiService 생성자에 주입하면 된다.
class KoreanAuthApiMessages extends AuthApiMessages {
  const KoreanAuthApiMessages();

  @override
  String get requestSerializationFailed => '요청 데이터를 처리하지 못했습니다.';

  @override
  String get requestTimeout => '백엔드 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.';

  @override
  String get connectionFailed => '백엔드 서버에 연결하지 못했습니다. 서버가 실행 중인지 확인해 주세요.';

  @override
  String get invalidServerResponse => '서버 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidLoginResponse => '로그인 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidSignupResponse => '회원가입 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidLoginIdAvailabilityResponse => '아이디 중복확인 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidFindIdResponse => '아이디 찾기 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidPasswordResetVerificationResponse =>
      '비밀번호 재설정 인증 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidTokenRefreshResponse => '토큰 재발급 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidCurrentUserResponse => '현재 사용자 응답 형식이 올바르지 않습니다.';

  @override
  String get invalidSocialAccountStatusResponse =>
      '소셜 계정 연동 상태 응답 형식이 올바르지 않습니다.';

  @override
  String forStatusCode({required int statusCode, String? serverMessage}) {
    if (serverMessage != null && serverMessage.trim().isNotEmpty) {
      return serverMessage;
    }

    switch (statusCode) {
      case 400:
        return '인증 요청값이 올바르지 않습니다.';
      case 401:
        return '인증 정보가 올바르지 않거나 만료되었습니다.';
      case 403:
        return '접근 권한이 없습니다.';
      case 404:
        return '요청한 인증 정보를 찾을 수 없습니다.';
      case 409:
        return '이미 사용 중이거나 현재 상태와 충돌하는 요청입니다.';
      case 422:
        return '입력한 인증 정보의 형식이 올바르지 않습니다.';
      case 429:
        return '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
      case 500:
        return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      case 502:
      case 503:
      case 504:
        return '서버를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '인증 요청을 처리하지 못했습니다.';
    }
  }
}