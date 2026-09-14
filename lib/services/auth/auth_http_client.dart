import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/network/api_exception.dart';
import 'auth_api_messages.dart';

/// 인증 관련 HTTP 전송 계층을 담당한다.
/// 직렬화, 타임아웃, 연결 예외만 공통 처리한다.
class AuthHttpClient {
  AuthHttpClient({http.Client? client, required AuthApiMessages messages})
    : _client = client ?? http.Client(),
      _messages = messages;

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;
  final AuthApiMessages _messages;

  /// JSON POST 요청을 전송한다.
  Future<http.Response> post({
    required Uri uri,
    Map<String, dynamic>? body,
    String? authorizationHeader,
  }) {
    return _sendRequest(
      method: _HttpMethod.post,
      uri: uri,
      body: body,
      authorizationHeader: authorizationHeader,
    );
  }

  /// GET 요청을 전송한다.
  Future<http.Response> get({required Uri uri, String? authorizationHeader}) {
    return _sendRequest(
      method: _HttpMethod.get,
      uri: uri,
      authorizationHeader: authorizationHeader,
    );
  }

  /// 인증된 JSON PATCH 요청을 전송한다.
  Future<http.Response> patch({
    required Uri uri,
    required String authorizationHeader,
    Map<String, dynamic>? body,
  }) {
    return _sendRequest(
      method: _HttpMethod.patch,
      uri: uri,
      body: body,
      authorizationHeader: authorizationHeader,
    );
  }

  /// 인증된 DELETE 요청을 전송한다.
  Future<http.Response> delete({
    required Uri uri,
    required String authorizationHeader,
  }) {
    return _sendRequest(
      method: _HttpMethod.delete,
      uri: uri,
      authorizationHeader: authorizationHeader,
    );
  }

  /// 인증된 multipart PUT 요청으로 파일을 전송한다.
  Future<http.Response> putMultipart({
    required Uri uri,
    required String authorizationHeader,
    required String fieldName,
    required String filePath,
  }) async {
    final contentType = _resolveImageMediaType(filePath);

    try {
      final request = http.MultipartRequest('PUT', uri);

      request.headers['Accept'] = 'application/json';

      final trimmedAuthorizationHeader = authorizationHeader.trim();

      if (trimmedAuthorizationHeader.isNotEmpty) {
        request.headers['Authorization'] = trimmedAuthorizationHeader;
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          fieldName,
          filePath,
          contentType: contentType,
        ),
      );

      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_timeout);

      return response;
    } on TimeoutException {
      throw ApiException(message: _messages.requestTimeout);
    } catch (error, stackTrace) {
      _debugLog(
        'multipart API 연결 실패 '
        '[PUT $uri]: $error',
        stackTrace,
      );

      throw ApiException(message: _messages.connectionFailed);
    }
  }

  /// 이미지 파일 확장자에 맞는 MIME 타입을 반환한다.
  MediaType _resolveImageMediaType(String filePath) {
    final normalizedPath = filePath.toLowerCase();

    if (normalizedPath.endsWith('.jpg') || normalizedPath.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }

    if (normalizedPath.endsWith('.png')) {
      return MediaType('image', 'png');
    }

    if (normalizedPath.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }

    if (normalizedPath.endsWith('.gif')) {
      return MediaType('image', 'gif');
    }

    throw const ApiException(message: '지원하지 않는 이미지 파일 형식입니다.');
  }

  /// 공통 HTTP 요청을 실행한다.
  Future<http.Response> _sendRequest({
    required _HttpMethod method,
    required Uri uri,
    Map<String, dynamic>? body,
    String? authorizationHeader,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (authorizationHeader != null && authorizationHeader.trim().isNotEmpty) {
      headers['Authorization'] = authorizationHeader.trim();
    }

    final encodedBody = _encodeRequestBody(body);

    try {
      switch (method) {
        case _HttpMethod.get:
          return await _client.get(uri, headers: headers).timeout(_timeout);

        case _HttpMethod.post:
          return await _client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);

        case _HttpMethod.patch:
          return await _client
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);

        case _HttpMethod.delete:
          return await _client
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
      }
    } on TimeoutException {
      throw ApiException(message: _messages.requestTimeout);
    } catch (error, stackTrace) {
      _debugLog(
        '인증 API 연결 실패 '
        '[${method.name.toUpperCase()} $uri]: $error',
        stackTrace,
      );

      throw ApiException(message: _messages.connectionFailed);
    }
  }

  /// 요청 본문을 JSON 문자열로 직렬화한다.
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

  /// 디버그 빌드에서만 HTTP 계층 오류 상세를 출력한다.
  void _debugLog(String message, [StackTrace? stackTrace]) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(message);

    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }
  }

  /// 내부 HTTP 클라이언트를 종료한다.
  void dispose() {
    _client.close();
  }
}

/// AuthHttpClient 내부에서만 사용하는 HTTP 메서드 구분값
enum _HttpMethod { get, post, patch, delete }
