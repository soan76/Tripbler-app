import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
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
  AuthApiService({http.Client? client}) : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;

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
      invalidResponseMessage: '로그인 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '회원가입 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '아이디 중복확인 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '아이디 찾기 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '비밀번호 재설정 인증 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '토큰 재발급 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '현재 사용자 응답 형식이 올바르지 않습니다.',
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
      invalidResponseMessage: '소셜 계정 연동 상태 응답 형식이 올바르지 않습니다.',
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

  /// 서버에서 로그아웃한다.
  Future<void> logout({required String authorizationHeader}) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authLogoutUri,
      authorizationHeader: authorizationHeader,
    );

    _ensureNoContentResponse(response);
  }

  /// POST 요청의 공통 네트워크 처리를 담당한다.
  Future<http.Response> _sendPostRequest({
    required Uri uri,
    Map<String, dynamic>? body,
    String? authorizationHeader,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (authorizationHeader != null && authorizationHeader.trim().isNotEmpty) {
      headers['Authorization'] = authorizationHeader;
    }

    try {
      return await _client
          .post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        message: '백엔드 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on ApiException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('인증 API 연결 실패: $error');
      debugPrint('$stackTrace');

      throw const ApiException(
        message: '백엔드 서버에 연결하지 못했습니다. 서버가 실행 중인지 확인해 주세요.',
      );
    }
  }

  /// GET 요청의 공통 네트워크 처리를 담당한다.
  Future<http.Response> _sendGetRequest({
    required Uri uri,
    String? authorizationHeader,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};

    if (authorizationHeader != null && authorizationHeader.trim().isNotEmpty) {
      headers['Authorization'] = authorizationHeader;
    }

    try {
      return await _client.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(message: '서버 응답 시간이 초과되었습니다.');
    } on http.ClientException catch (error) {
      debugPrint('인증 API 네트워크 오류: $error');

      throw const ApiException(message: '서버에 연결할 수 없습니다.');
    }
  }

  /// DELETE 요청의 공통 네트워크 처리를 담당한다.
  Future<http.Response> _sendDeleteRequest({
    required Uri uri,
    required String authorizationHeader,
  }) {
    return _client
        .delete(
          uri,
          headers: {
            'Authorization': authorizationHeader,
            'Content-Type': 'application/json',
          },
        )
        .timeout(_timeout);
  }

  /// 204 응답을 확인하고 실패 응답은 공통 오류 처리로 전달한다.
  void _ensureNoContentResponse(http.Response response) {
    if (response.statusCode == 204) {
      return;
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
    } on FormatException catch (error) {
      debugPrint('$parseErrorLog: $error');

      throw ApiException(
        statusCode: response.statusCode,
        message: invalidResponseMessage,
      );
    }
  }

  /// HTTP 응답 본문을 JSON 객체로 변환한다.
  Map<String, dynamic> _decodeResponseBody(http.Response response) {
    if (response.body.trim().isEmpty) {
      throw ApiException(
        statusCode: response.statusCode,
        message: _messageForStatusCode(statusCode: response.statusCode),
      );
    }

    try {
      final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      if (decodedBody is! Map<String, dynamic>) {
        throw const FormatException('응답 본문이 JSON 객체가 아닙니다.');
      }

      return decodedBody;
    } on ApiException {
      rethrow;
    } catch (error) {
      debugPrint('인증 응답 JSON 디코딩 실패: $error');

      throw ApiException(
        statusCode: response.statusCode,
        message: '서버 응답 형식이 올바르지 않습니다.',
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
    } catch (_) {
      errorResponse = null;
    }

    return ApiException(
      statusCode: response.statusCode,
      code: errorResponse?.code,
      message: _messageForStatusCode(
        statusCode: response.statusCode,
        serverMessage: errorResponse?.message,
      ),
      path: errorResponse?.path,
      timestamp: errorResponse?.timestamp,
    );
  }

  /// 서버 메시지가 없을 때 HTTP 상태코드에 맞는 기본 메시지를 반환한다.
  String _messageForStatusCode({
    required int statusCode,
    String? serverMessage,
  }) {
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

      case 500:
        return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';

      default:
        return '인증 요청을 처리하지 못했습니다.';
    }
  }

  void dispose() {
    _client.close();
  }
}