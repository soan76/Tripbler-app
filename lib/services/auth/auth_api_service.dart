import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../models/api_error_response.dart';
import '../../models/auth/token_refresh_response.dart';
import '../../models/auth/user_login_request.dart';
import '../../models/auth/user_login_response.dart';
import '../../models/auth/token_refresh_request.dart';
import '../../models/auth/social_account_status_response.dart';
import '../../models/auth/find_id_verify_code_response.dart';
import '../../models/user/user_response.dart';
import '../../models/user/user_create_request.dart';
import '../../models/user/login_id_availability_response.dart';

/// Tripbler 백엔드 인증 API와 통신하는 서비스.
///
/// 담당 기능:
/// - 로그인
/// - Access Token 재발급
/// - 로그아웃
///
/// 토큰 저장/삭제는 TokenStorageService 또는 AuthRepository에서 담당한다.
class AuthApiService {
  AuthApiService({http.Client? client}) : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;

  /// 로그인
  ///
  /// POST /api/v1/auth/login
  Future<UserLoginResponse> login(UserLoginRequest request) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authLoginUri,
      body: request.toJson(),
    );

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return UserLoginResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('로그인 응답 파싱 실패: $error');

        throw const ApiException(message: '로그인 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 회원가입
  ///
  /// POST /api/v1/users
  Future<UserResponse> signup(UserCreateRequest request) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.usersUri,
      body: request.toJson(),
    );

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 201) {
      try {
        return UserResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('회원가입 응답 파싱 실패: $error');

        throw const ApiException(message: '회원가입 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 아이디 사용 가능 여부 확인
  ///
  /// GET /api/v1/users/check-login-id?loginId=...
  Future<LoginIdAvailabilityResponse> checkLoginIdAvailability(
    String loginId,
  ) async {
    final response = await _sendGetRequest(
      uri: ApiConfig.usersCheckLoginIdUri(loginId: loginId),
    );

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return LoginIdAvailabilityResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('아이디 중복확인 응답 파싱 실패: $error');

        throw const ApiException(message: '아이디 중복확인 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 아이디 찾기 인증코드 발송
  ///
  /// POST /api/v1/auth/find-id/send-code
  Future<void> sendFindIdVerificationCode({required String email}) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authFindIdSendCodeUri,
      body: {'email': email},
    );

    if (response.statusCode == 204) {
      return;
    }

    final decodedBody = _decodeResponseBody(response);

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 아이디 찾기 인증코드 검증
  ///
  /// POST /api/v1/auth/find-id/verify-code
  Future<FindIdVerifyCodeResponse> verifyFindIdVerificationCode({
    required String email,
    required String code,
  }) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authFindIdVerifyCodeUri,
      body: {'email': email, 'code': code},
    );

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return FindIdVerifyCodeResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('아이디 찾기 인증 응답 파싱 실패: $error');

        throw const ApiException(message: '아이디 찾기 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// Refresh Token을 사용해 새로운 Access Token 발급
  /// POST /api/v1/auth/refresh
  Future<TokenRefreshResponse> refresh(TokenRefreshRequest request) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authRefreshUri,
      body: request.toJson(),
    );

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return TokenRefreshResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('토큰 재발급 응답 파싱 실패: $error');

        throw const ApiException(message: '토큰 재발급 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 현재 로그인 사용자 조회
  ///
  /// GET /api/v1/users/me
  Future<UserResponse> getCurrentUser({
    required String authorizationHeader,
  }) async {
    final response = await _sendGetRequest(
      uri: ApiConfig.usersMeUri,
      authorizationHeader: authorizationHeader,
    );

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return UserResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('현재 사용자 응답 파싱 실패: $error');

        throw const ApiException(message: '현재 사용자 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
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

    final decodedBody = _decodeResponseBody(response);

    if (response.statusCode == 200) {
      try {
        return SocialAccountStatusResponse.fromJson(decodedBody);
      } on FormatException catch (error) {
        debugPrint('소셜 계정 연동 상태 응답 파싱 실패: $error');

        throw const ApiException(message: '소셜 계정 연동 상태 응답 형식이 올바르지 않습니다.');
      }
    }

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 현재 로그인한 Tripbler 사용자에게 Google 계정을 연동한다.
  Future<void> linkGoogleAccount({
    required String authorizationHeader,
    required String idToken,
  }) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.usersMeGoogleLinkUri,
      authorizationHeader: authorizationHeader,
      body: {'idToken': idToken},
    );

    if (response.statusCode == 204) {
      return;
    }

    final decodedBody = _decodeResponseBody(response);

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 현재 사용자에게 연동된 Google 계정을 해제한다.
  Future<void> unlinkGoogleAccount({
    required String authorizationHeader,
  }) async {
    final response = await _sendDeleteRequest(
      uri: ApiConfig.usersMeGoogleLinkUri,
      authorizationHeader: authorizationHeader,
    );

    if (response.statusCode == 204) {
      return;
    }

    final decodedBody = _decodeResponseBody(response);

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 로그아웃
  /// POST /api/v1/auth/logout
  ///
  /// 백엔드에서 Access Token 인증이 필요하므로
  /// Authorization 헤더 값을 전달받는다.
  Future<void> logout({required String authorizationHeader}) async {
    final response = await _sendPostRequest(
      uri: ApiConfig.authLogoutUri,
      authorizationHeader: authorizationHeader,
    );

    if (response.statusCode == 204) {
      return;
    }

    final decodedBody = _decodeResponseBody(response);

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// POST 요청 공통 처리
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

  /// HTTP 응답 JSON 파싱
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

  /// 백엔드 ErrorResponse를 ApiException으로 변환
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

  /// 응답 본문이 없거나 파싱할 수 없을 때 사용하는 기본 메시지
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
