import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/network/api_exception.dart';
import '../../models/api_error_response.dart';
import 'auth_api_messages.dart';

/// 인증 API의 HTTP 응답 해석을 담당한다.
///
/// 성공 응답 파싱, 빈 본문 성공 처리,
/// 백엔드 오류 응답의 ApiException 변환을 한 곳에서 처리한다.
class AuthResponseParser {
  const AuthResponseParser({required AuthApiMessages messages})
    : _messages = messages;

  final AuthApiMessages _messages;

  /// 204 또는 200 + 빈 본문 응답을 성공으로 인정한다.
  ///
  /// 현재 백엔드는 204를 사용하지만,
  /// 200과 빈 본문도 호환성을 위해 성공으로 처리한다.
  void ensureNoContentResponse(http.Response response) {
    if (response.statusCode == 204) {
      return;
    }

    if (response.statusCode == 200) {
      final responseBody = _decodeUtf8Body(response);

      if (responseBody.trim().isEmpty) {
        return;
      }

      _throwApiError(response, decodedUtf8Body: responseBody);
    }

    _throwApiError(response);
  }

  /// 성공 JSON 응답을 지정된 모델로 변환한다.
  ///
  /// 기대한 상태 코드가 아니면 공통 오류 응답 처리로 전달한다.
  T parseJsonResponse<T>({
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

  /// HTTP 응답 본문을 UTF-8 문자열로 변환한다.
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
  ///
  /// 빈 본문이나 JSON 객체가 아닌 응답은
  /// 유효하지 않은 서버 응답으로 처리한다.
  Map<String, dynamic> _decodeResponseBody(
    http.Response response, {
    String? decodedUtf8Body,
  }) {
    final responseBody = decodedUtf8Body ?? _decodeUtf8Body(response);

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

  /// 실패 HTTP 응답을 ApiException으로 변환해 전달한다.
  Never _throwApiError(http.Response response, {String? decodedUtf8Body}) {
    final decodedBody = _decodeResponseBody(
      response,
      decodedUtf8Body: decodedUtf8Body,
    );

    throw _createApiExceptionFromErrorResponse(
      response: response,
      decodedBody: decodedBody,
    );
  }

  /// 백엔드 ErrorResponse 구조를 ApiException으로 변환한다.
  ///
  /// 오류 응답 DTO 파싱에 실패해도 상태 코드 기반 메시지를 사용해
  /// 사용자에게 전달 가능한 ApiException을 생성한다.
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

  /// 디버그 빌드에서만 응답 파싱 오류 상세를 출력한다.
  void _debugLog(String message, [StackTrace? stackTrace]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(message);

    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }
  }
}