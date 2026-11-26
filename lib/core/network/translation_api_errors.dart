import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// 번역 API(줄별·사진)의 비정상 응답을 [ApiException]으로 바꾼다.
///
/// 본문이 `{code, message}` JSON이면 코드와 문구를 읽고, 아니면 상태 코드 기준 문구를 쓴다.
ApiException translationApiErrorFrom(http.Response response) {
  String? code;
  String? serverMessage;

  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (decoded is Map<String, dynamic>) {
      final rawCode = decoded['code'];
      final rawMessage = decoded['message'];

      code = rawCode is String ? rawCode : null;
      serverMessage = rawMessage is String && rawMessage.trim().isNotEmpty
          ? rawMessage.trim()
          : null;
    }
  } catch (_) {
    // 본문이 JSON이 아니면 상태 코드 기준 문구를 쓴다.
  }

  return ApiException(
    statusCode: response.statusCode,
    code: code,
    message: _messageFor(response.statusCode, serverMessage),
  );
}

String _messageFor(int statusCode, String? serverMessage) {
  switch (statusCode) {
    case 400:
      return serverMessage ?? '번역 요청값이 올바르지 않습니다.';
    case 401:
      return '로그인이 필요합니다.';
    case 413:
      return '사진이 너무 커서 보낼 수 없습니다.';
    case 429:
      return serverMessage ?? '번역 요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
    case 503:
      return '번역 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
    default:
      return '번역 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
  }
}
