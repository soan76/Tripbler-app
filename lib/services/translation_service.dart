import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  TranslationService({http.Client? client}) : _client = client ?? http.Client();

  static const String _definedBaseUrl = String.fromEnvironment(
    'TRIPBLER_API_BASE_URL',
  );

  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _client;

  // 실행 환경에 따라 백엔드 기본 주소를 결정함.
  String get _baseUrl {
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

  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final trimmedText = text.trim();

    if (trimmedText.isEmpty) {
      return '';
    }

    final uri = Uri.parse('$_baseUrl/api/v1/translation');

    // Google API 형식이 아니라 Spring Boot 백엔드 DTO 형식으로 요청함.
    final requestBody = <String, dynamic>{
      'text': trimmedText,
      'sourceLanguageCode': sourceLanguageCode,
      'targetLanguageCode': targetLanguageCode,
    };

    final response = await _sendPostRequest(uri: uri, body: requestBody);

    if (response.statusCode != 200) {
      throw TranslationApiException(
        message: _parseErrorMessage(
          response,
          fallbackMessage: _messageForStatusCode(response.statusCode),
        ),
      );
    }

    try {
      final Map<String, dynamic> jsonBody = _decodeJsonObject(response);

      final translatedText = jsonBody['translatedText'];

      if (translatedText is! String || translatedText.trim().isEmpty) {
        throw const FormatException('translatedText 값이 비어 있습니다.');
      }

      return translatedText.trim();
    } catch (error, stackTrace) {
      debugPrint('번역 응답 파싱 실패: $error');
      debugPrint('$stackTrace');

      throw const TranslationApiException(message: '번역 응답 형식이 올바르지 않습니다.');
    }
  }

  // POST 요청을 보내고 서버 접속 실패와 타임아웃을 사용자용 오류로 변환함.
  Future<http.Response> _sendPostRequest({
    required Uri uri,
    required Map<String, dynamic> body,
  }) async {
    try {
      return await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const TranslationApiException(
        message: '번역 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on http.ClientException {
      throw const TranslationApiException(
        message: '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    } catch (_) {
      throw const TranslationApiException(
        message: '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }
  }

  // 응답 본문을 JSON 객체로 변환함.
  Map<String, dynamic> _decodeJsonObject(http.Response response) {
    final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

    if (decodedBody is! Map<String, dynamic>) {
      throw const FormatException('JSON 객체 형식이 아닙니다.');
    }

    return decodedBody;
  }

  // 백엔드 공통 오류 응답에서 message를 우선 사용함.
  String _parseErrorMessage(
    http.Response response, {
    required String fallbackMessage,
  }) {
    try {
      final Map<String, dynamic> jsonBody = _decodeJsonObject(response);

      final status = jsonBody['status'];
      final code = jsonBody['code'];
      final message = jsonBody['message'];

      final parsedCode = code is String ? code : null;

      final parsedMessage = message is String && message.trim().isNotEmpty
          ? message.trim()
          : fallbackMessage;

      if (status == 503 || parsedCode == 'TRANSLATION_PROVIDER_UNAVAILABLE') {
        return '번역 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      }

      if (status == 500 || parsedCode == 'INTERNAL_SERVER_ERROR') {
        return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
      }

      return parsedMessage;
    } catch (_) {
      return fallbackMessage;
    }
  }

  // 백엔드 오류 응답 파싱에 실패했을 때 사용할 기본 메시지.
  String _messageForStatusCode(int statusCode) {
    if (statusCode == 400) {
      return '번역 요청값이 올바르지 않습니다.';
    }

    if (statusCode == 404) {
      return '번역 API 주소를 찾을 수 없습니다.';
    }

    if (statusCode == 500) {
      return '서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    if (statusCode == 503) {
      return '번역 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    }

    return '번역 중 문제가 발생했습니다. 다시 시도해 주세요.';
  }

  void dispose() {
    _client.close();
  }
}

// 번역 API 오류를 사용자에게 보여줄 메시지와 함께 전달하기 위한 예외 클래스.
class TranslationApiException implements Exception {
  final String message;

  const TranslationApiException({required this.message});

  @override
  String toString() {
    return message;
  }
}
