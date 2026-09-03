import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import 'auth_api_messages.dart';
import '../../models/api_error_response.dart';
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
  }) : _client = client ?? http.Client(),
       _messages = messages;

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;
  final AuthApiMessages _messages;

  /// 로그인
  Future<UserLoginResponse> login(UserLoginRequest request) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authLoginUri,
      body: request.toJson(),
    );

    return _parseJsonResponse<UserLoginResponse>(
      response: response,
      successStatusCode: 200,
      parser: UserLoginResponse.fromJson,
      parseErrorLog: '로그인 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidLoginResponse,
    );
  }

  /// 회원가입
  Future<UserResponse> signup(UserCreateRequest request) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.usersUri,
      body: request.toJson(),
    );

    return _parseJsonResponse<UserResponse>(
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
    final response = await _sendGetRequest(
      uri: ApiConfig.usersCheckLoginIdUri(loginId: loginId),
    );

    return _parseJsonResponse<LoginIdAvailabilityResponse>(
      response: response,
      successStatusCode: 200,
      parser: LoginIdAvailabilityResponse.fromJson,
      parseErrorLog: '아이디 중복확인 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidLoginIdAvailabilityResponse,
    );
  }

  /// 아이디 찾기 인증코드 발송
  Future<void> sendFindIdVerificationCode({required String email}) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authFindIdSendCodeUri,
      body: {'email': email},
    );

    _ensureNoContentResponse(response);
  }

  /// 아이디 찾기 인증코드 검증
  Future<FindIdVerifyCodeResponse> verifyFindIdVerificationCode({
    required String email,
    required String code,
  }) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authFindIdVerifyCodeUri,
      body: {'email': email, 'code': code},
    );

    return _parseJsonResponse<FindIdVerifyCodeResponse>(
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
    final response = await _sendPostRequest(
      uri: ApiConfig.authPasswordResetSendCodeUri,
      body: {'loginId': loginId, 'email': email},
    );

    _ensureNoContentResponse(response);
  }

  /// 비밀번호 재설정 인증코드를 검증하고 resetToken을 반환한다.
  Future<PasswordResetVerifyCodeResponse> verifyPasswordResetVerificationCode({
    required String loginId,
    required String email,
    required String code,
  }) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authPasswordResetVerifyCodeUri,
      body: {'loginId': loginId, 'email': email, 'code': code},
    );

    return _parseJsonResponse<PasswordResetVerifyCodeResponse>(
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
    final response = await _sendPostRequest(
      uri: ApiConfig.authPasswordResetUri,
      body: {'resetToken': resetToken, 'newPassword': newPassword},
    );

    _ensureNoContentResponse(response);
  }

  /// Refresh Token으로 새로운 Access Token을 발급한다.
  Future<TokenRefreshResponse> refresh(TokenRefreshRequest request) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authRefreshUri,
      body: request.toJson(),
    );

    return _parseJsonResponse<TokenRefreshResponse>(
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
    final response = await _sendGetRequest(
      uri: ApiConfig.usersMeUri,
      authorizationHeader: authorizationHeader,
    );

    return _parseJsonResponse<UserResponse>(
      response: response,
      successStatusCode: 200,
      parser: UserResponse.fromJson,
      parseErrorLog: '현재 사용자 응답 파싱 실패',
      invalidResponseMessage: _messages.invalidCurrentUserResponse,
    );
  }

  /// 현재 사용자의 소셜 계정 연동 상태를 조회한다.
  Future<SocialAccountStatusResponse> getLinkedSocialAccounts({
    required String authorizationHeader,
  }) async {
    final response = await _sendGetRequest(
      uri: ApiConfig.usersMeSocialAccountsUri,
      authorizationHeader: authorizationHeader,
    );

    return _parseJsonResponse<SocialAccountStatusResponse>(
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
    final response = await _sendPostRequest(
      uri: ApiConfig.usersMeGoogleLinkUri,
      authorizationHeader: authorizationHeader,
      body: {'idToken': idToken},
    );

    _ensureNoContentResponse(response);
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<void> unlinkGoogleAccount({
    required String authorizationHeader,
  }) async {
    final response = await _sendDeleteRequest(
      uri: ApiConfig.usersMeGoogleLinkUri,
      authorizationHeader: authorizationHeader,
    );

    _ensureNoContentResponse(response);
  }

  /// 현재 로그인 사용자의 계정을 탈퇴 처리한다.
  Future<void> deleteAccount({required String authorizationHeader}) async {
    final response = await _sendDeleteRequest(
      uri: ApiConfig.usersMeUri,
      authorizationHeader: authorizationHeader,
    );

    _ensureNoContentResponse(response);
  }

  /// 서버에서 로그아웃한다.
  Future<void> logout({required String authorizationHeader}) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authLogoutUri,
      authorizationHeader: authorizationHeader,
    );

    _ensureNoContentResponse(response);
  }

  /// POST 요청을 공통 요청 헬퍼로 전달한다.
  Future<http.Response> _sendPostRequest({
    required Uri uri,
    Map<String, dynamic>? body,
    String? authorizationHeader,
  }) {
    return _sendRequest(
      method: _HttpMethod.post,
      uri: uri,
      authorizationHeader: authorizationHeader,
      body: body,
    );
  }

  /// GET 요청을 공통 요청 헬퍼로 전달한다.
  Future<http.Response> _sendGetRequest({
    required Uri uri,
    String? authorizationHeader,
  }) {
    return _sendRequest(
      method: _HttpMethod.get,
      uri: uri,
      authorizationHeader: authorizationHeader,
    );
  }

  /// DELETE 요청을 공통 요청 헬퍼로 전달한다.
  Future<http.Response> _sendDeleteRequest({
    required Uri uri,
    required String authorizationHeader,
  }) {
    return _sendRequest(
      method: _HttpMethod.delete,
      uri: uri,
      authorizationHeader: authorizationHeader,
    );
  }

  /// 인증 API의 공통 HTTP 요청, 헤더 구성, 타임아웃, 예외 매핑을 담당한다.
  Future<http.Response> _sendRequest({
    required _HttpMethod method,
    required Uri uri,
    Map<String, dynamic>? body,
    String? authorizationHeader,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};

    if (body != null ||
        method == _HttpMethod.post ||
        method == _HttpMethod.delete) {
      headers['Content-Type'] = 'application/json';
    }

    if (authorizationHeader != null && authorizationHeader.trim().isNotEmpty) {
      headers['Authorization'] = authorizationHeader.trim();
    }

    final encodedBody = _encodeRequestBody(body);

    try {
      switch (method) {
        case _HttpMethod.post:
          return await _client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);

        case _HttpMethod.get:
          return await _client.get(uri, headers: headers).timeout(_timeout);

        case _HttpMethod.delete:
          return await _client
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
      }
    } on TimeoutException {
      throw ApiException(message: _messages.requestTimeout);
    } catch (error, stackTrace) {
      _debugLog(
        '인증 API 연결 실패 [${method.name.toUpperCase()} $uri]: $error',
        stackTrace,
      );

      throw ApiException(message: _messages.connectionFailed);
    }
  }

  /// 요청 본문을 JSON 문자열로 직렬화한다.
  ///
  /// 직렬화 실패는 네트워크 연결 실패와 구분해서 처리한다.
  String? _encodeRequestBody(Map<String, dynamic>? body) {
    if (body == null) {
      return null;
    }

    try {
      return jsonEncode(body);
    } catch (error, stackTrace) {
      _debugLog('인증 API 요청 본문 직렬화 실패: $error', stackTrace);
      throw ApiException(message: _messages.requestSerializationFailed);
    }
  }

  /// 204 또는 200 + 빈 본문 응답을 성공으로 인정한다.
  /// 현재 백엔드가 204로 통일되어 있다면 200 허용은 호환성을 위한 방어 처리다.
  void _ensureNoContentResponse(http.Response response) {
    if (response.statusCode == 204) {
      return;
    }

    if (response.statusCode == 200) {
      final responseBody = _decodeUtf8Body(response);

      if (responseBody.trim().isEmpty) {
        return;
      }
    }

    _throwApiError(response);
  }

  /// 성공 JSON 응답을 파싱하고 실패 응답은 공통 오류 처리한다.
  T _parseJsonResponse<T>({
    required http.Response response,
    required int successStatusCode,
    required T Function(Map<String, dynamic> json) parser,
    required String parseErrorLog,
    required String invalidResponseMessage,
  }) {
    if (response.statusCode != successStatusCode) {
      _throwApiError(response);
    }

    final decodedBody = _decodeResponseBody(response);

    try {
      return parser(decodedBody);
    } catch (error, stackTrace) {
      _debugLog('$parseErrorLog: $error', stackTrace);

      throw ApiException(
        statusCode: response.statusCode,
        message: invalidResponseMessage,
      );
    }
  }

  /// HTTP 응답 본문을 UTF-8 문자열로 한 번만 디코딩한다.
  String _decodeUtf8Body(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (error, stackTrace) {
      _debugLog('인증 응답 UTF-8 디코딩 실패: $error', stackTrace);

      throw ApiException(
        statusCode: response.statusCode,
        message: _messages.invalidServerResponse,
      );
    }
  }

  /// HTTP 응답 본문을 JSON 객체로 변환한다.
  Map<String, dynamic> _decodeResponseBody(http.Response response) {
    final responseBody = _decodeUtf8Body(response);

    if (responseBody.trim().isEmpty) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _messages.forStatusCode(statusCode: response.statusCode),
      );
    }

    try {
      final decodedBody = jsonDecode(responseBody);

      if (decodedBody is! Map<String, dynamic>) {
        throw const FormatException('응답 본문이 JSON 객체가 아닙니다.');
      }

      return decodedBody;
    } catch (error, stackTrace) {
      _debugLog('인증 응답 JSON 디코딩 실패: $error', stackTrace);

      throw ApiException(
        statusCode: response.statusCode,
        message: _messages.invalidServerResponse,
      );
    }
  }

  /// 실패 응답을 ApiException으로 변환해 즉시 전달한다.
  Never _throwApiError(http.Response response) {
    final decodedBody = _decodeResponseBody(response);

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 백엔드 ErrorResponse를 ApiException으로 변환한다.
  ApiException _createApiExceptionFromErrorResponse({
    required http.Response response,
    required Map<String, dynamic> decodedBody,
  }) {
    ApiErrorResponse? errorResponse;

    try {
      errorResponse = ApiErrorResponse.fromJson(decodedBody);
    } catch (error, stackTrace) {
      _debugLog('인증 오류 응답 파싱 실패: $error', stackTrace);
      errorResponse = null;
    }

    return ApiException(
      statusCode: response.statusCode,
      code: errorResponse?.code,
      message: _messages.forStatusCode(
        statusCode: response.statusCode,
        serverMessage: errorResponse?.message,
      ),
      path: errorResponse?.path,
      timestamp: errorResponse?.timestamp,
    );
  }

  /// 디버그 빌드에서만 내부 오류 상세를 출력한다.
  void _debugLog(String message, [StackTrace? stackTrace]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(message);

    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }
  }

  void dispose() {
    _client.close();
  }
}

enum _HttpMethod { get, post, delete }