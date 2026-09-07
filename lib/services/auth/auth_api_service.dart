import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import 'auth_api_messages.dart';
import 'auth_http_client.dart';
import 'auth_response_parser.dart';
import '../../models/auth/find_id_verify_code_response.dart';
import '../../models/auth/password_reset_verify_code_response.dart';
import '../../models/auth/social_account_status_response.dart';
import '../../models/auth/token_refresh_request.dart';
import '../../models/auth/token_refresh_response.dart';
import '../../models/auth/user_login_request.dart';
import '../../models/auth/user_login_response.dart';
import '../../models/user/login_id_availability_response.dart';
import '../../models/user/user_create_request.dart';
import '../../models/user/user_response.dart';

/// Tripbler 인증 관련 백엔드 API 통신을 담당한다.
/// 토큰 저장과 인증 상태 관리는 Repository / Provider에서 처리한다.
class AuthApiService {
  AuthApiService({
    http.Client? client,
    AuthApiMessages messages = const KoreanAuthApiMessages(),
  }) : _httpClient = AuthHttpClient(client: client, messages: messages),
       _responseParser = AuthResponseParser(messages: messages),
       _messages = messages;

  final AuthHttpClient _httpClient;
  final AuthResponseParser _responseParser;
  final AuthApiMessages _messages;

  /// 로그인
  Future<UserLoginResponse> login(UserLoginRequest request) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authLoginUri,
      body: request.toJson(),
    );

    return _responseParser.parseJsonResponse<UserLoginResponse>(
      response: response,
      successStatusCode: 200,
      parser: UserLoginResponse.fromJson,
      parseErrorLog: '로그인 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidLoginResponse,
    );
  }

  /// 회원가입
  Future<UserResponse> signup(UserCreateRequest request) async {
    final response = await _httpClient.post(
      uri: ApiConfig.usersUri,
      body: request.toJson(),
    );

    return _responseParser.parseJsonResponse<UserResponse>(
      response: response,
      successStatusCode: 201,
      parser: UserResponse.fromJson,
      parseErrorLog: '회원가입 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidSignupResponse,
    );
  }

  /// 아이디 사용 가능 여부 확인
  Future<LoginIdAvailabilityResponse> checkLoginIdAvailability(
    String loginId,
  ) async {
    final response = await _httpClient.get(
      uri: ApiConfig.usersCheckLoginIdUri(loginId: loginId),
    );

    return _responseParser.parseJsonResponse<LoginIdAvailabilityResponse>(
      response: response,
      successStatusCode: 200,
      parser: LoginIdAvailabilityResponse.fromJson,
      parseErrorLog: '아이디 중복확인 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidLoginIdAvailabilityResponse,
    );
  }

  /// 아이디 찾기 인증코드 발송
  Future<void> sendFindIdVerificationCode({required String email}) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authFindIdSendCodeUri,
      body: {'email': email},
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// 아이디 찾기 인증코드 검증
  Future<FindIdVerifyCodeResponse> verifyFindIdVerificationCode({
    required String email,
    required String code,
  }) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authFindIdVerifyCodeUri,
      body: {'email': email, 'code': code},
    );

    return _responseParser.parseJsonResponse<FindIdVerifyCodeResponse>(
      response: response,
      successStatusCode: 200,
      parser: FindIdVerifyCodeResponse.fromJson,
      parseErrorLog: '아이디 찾기 인증 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidFindIdResponse,
    );
  }

  /// 비밀번호 재설정 인증코드 발송
  Future<void> sendPasswordResetVerificationCode({
    required String loginId,
    required String email,
  }) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authPasswordResetSendCodeUri,
      body: {'loginId': loginId, 'email': email},
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// 비밀번호 재설정 인증코드를 검증하고 resetToken을 반환한다.
  Future<PasswordResetVerifyCodeResponse> verifyPasswordResetVerificationCode({
    required String loginId,
    required String email,
    required String code,
  }) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authPasswordResetVerifyCodeUri,
      body: {'loginId': loginId, 'email': email, 'code': code},
    );

    return _responseParser.parseJsonResponse<PasswordResetVerifyCodeResponse>(
      response: response,
      successStatusCode: 200,
      parser: PasswordResetVerifyCodeResponse.fromJson,
      parseErrorLog: '비밀번호 재설정 인증 응답 파싱 실패',
      invalidResponseMessage:
          _messages.invalidPasswordResetVerificationResponse,
    );
  }

  /// resetToken을 사용해 새 비밀번호로 변경한다.
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authPasswordResetUri,
      body: {'resetToken': resetToken, 'newPassword': newPassword},
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// Refresh Token으로 새로운 Access Token을 발급한다.
  Future<TokenRefreshResponse> refresh(TokenRefreshRequest request) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authRefreshUri,
      body: request.toJson(),
    );

    return _responseParser.parseJsonResponse<TokenRefreshResponse>(
      response: response,
      successStatusCode: 200,
      parser: TokenRefreshResponse.fromJson,
      parseErrorLog: '토큰 재발급 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidTokenRefreshResponse,
    );
  }

  /// 현재 로그인 사용자 정보를 조회한다.
  Future<UserResponse> getCurrentUser({
    required String authorizationHeader,
  }) async {
    final response = await _httpClient.get(
      uri: ApiConfig.usersMeUri,
      authorizationHeader: authorizationHeader,
    );

    return _responseParser.parseJsonResponse<UserResponse>(
      response: response,
      successStatusCode: 200,
      parser: UserResponse.fromJson,
      parseErrorLog: '현재 사용자 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidCurrentUserResponse,
    );
  }

  /// 현재 로그인 사용자의 닉네임을 변경한다.
  Future<UserResponse> updateNickname({
    required String authorizationHeader,
    required String nickname,
  }) async {
    final response = await _httpClient.patch(
      uri: ApiConfig.usersMeNicknameUri,
      authorizationHeader: authorizationHeader,
      body: {'nickname': nickname},
    );

    return _responseParser.parseJsonResponse<UserResponse>(
      response: response,
      successStatusCode: 200,
      parser: UserResponse.fromJson,
      parseErrorLog: '닉네임 변경 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidUpdateNicknameResponse,
    );
  }

  /// 현재 사용자의 소셜 계정 연동 상태를 조회한다.
  Future<SocialAccountStatusResponse> getLinkedSocialAccounts({
    required String authorizationHeader,
  }) async {
    final response = await _httpClient.get(
      uri: ApiConfig.usersMeSocialAccountsUri,
      authorizationHeader: authorizationHeader,
    );

    return _responseParser.parseJsonResponse<SocialAccountStatusResponse>(
      response: response,
      successStatusCode: 200,
      parser: SocialAccountStatusResponse.fromJson,
      parseErrorLog: '소셜 계정 연동 상태 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidSocialAccountStatusResponse,
    );
  }

  /// 현재 로그인한 사용자에게 Google 계정을 연동한다.
  Future<void> linkGoogleAccount({
    required String authorizationHeader,
    required String idToken,
  }) async {
    final response = await _httpClient.post(
      uri: ApiConfig.usersMeGoogleLinkUri,
      authorizationHeader: authorizationHeader,
      body: {'idToken': idToken},
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<void> unlinkGoogleAccount({
    required String authorizationHeader,
  }) async {
    final response = await _httpClient.delete(
      uri: ApiConfig.usersMeGoogleLinkUri,
      authorizationHeader: authorizationHeader,
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// 현재 로그인 사용자의 계정을 탈퇴 처리한다.
  Future<void> deleteAccount({required String authorizationHeader}) async {
    final response = await _httpClient.delete(
      uri: ApiConfig.usersMeUri,
      authorizationHeader: authorizationHeader,
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// 서버에서 로그아웃한다.
  Future<void> logout({required String authorizationHeader}) async {
    final response = await _httpClient.post(
      uri: ApiConfig.authLogoutUri,
      authorizationHeader: authorizationHeader,
    );

    _responseParser.ensureNoContentResponse(response);
  }

  /// 내부 HTTP 클라이언트를 정리한다.
  void dispose() {
    _httpClient.dispose();
  }
}