import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/network/api_exception.dart';
import '../models/translation/line_translation_result.dart';

/// 찍기 모드 줄별 번역 API(`POST /api/v1/translation/lines`, 로그인 필요).
class LineTranslationApiService {
  LineTranslationApiService({
    http.Client? client,
    Duration timeout = defaultTimeout,
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  /// 서버 최악 처리 시간보다 길게 둔다. 서버(`LineTranslationService`)는 Claude 최대 90초 +
  /// Google 대체 연결 3초·읽기 5초 + 환율 조회 대기 최대 5초 = 약 103초다. 여기에 업로드·응답 전송과
  /// 서버 호출 제한 확인 몫으로 17초를 더한다. 계약 문서: `backend/docs/translation-lines-api.md`.
  static const Duration defaultTimeout = Duration(seconds: 120);

  final Duration _timeout;
  final http.Client _client;

  /// [lines]를 줄마다 번역한다. 줄 수·길이 제한(1~50줄, 줄 200자, 합계 5000자)은 호출부가 맞춘다.
  ///
  /// 실패는 [ApiException]으로 던진다.
  /// - 서버 오류 응답: statusCode와 code(예: TOO_MANY_REQUESTS, TRANSLATION_PROVIDER_UNAVAILABLE)
  /// - 시간 초과·연결 실패: statusCode가 null([ApiException.isNetworkError])
  /// 401이면 호출부(AuthRepository.authorizedRequest)가 토큰을 재발급해 다시 시도한다.
  Future<LineTranslationResult> translateLines({
    required List<String> lines,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String authorizationHeader,
  }) async {
    final http.Response response;

    try {
      response = await _client
          .post(
            ApiConfig.translationLinesUri,
            headers: <String, String>{
              'Authorization': authorizationHeader,
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, dynamic>{
              'lines': lines,
              'sourceLanguageCode': sourceLanguageCode,
              'targetLanguageCode': targetLanguageCode,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        message: '번역 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on Exception {
      // 연결 실패·TLS 오류 같은 통신 예외만 네트워크 오류로 바꾼다.
      throw const ApiException(
        message: '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }

    if (response.statusCode != 200) {
      throw _errorFrom(response);
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 객체가 아닙니다.');
      }

      final result = LineTranslationResult.fromJson(decoded);

      if (result.lines.length != lines.length) {
        throw const FormatException('번역 줄 수가 요청과 다릅니다.');
      }

      return result;
    } on FormatException catch (error) {
      debugPrint('줄별 번역 응답 해석 실패: ${error.message}');

      throw ApiException(
        statusCode: response.statusCode,
        message: '번역 응답 형식이 올바르지 않습니다.',
      );
    }
  }

  ApiException _errorFrom(http.Response response) {
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

  static String _messageFor(int statusCode, String? serverMessage) {
    switch (statusCode) {
      case 400:
        return serverMessage ?? '번역 요청값이 올바르지 않습니다.';
      case 401:
        return '로그인이 필요합니다.';
      case 429:
        return serverMessage ?? '번역 요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
      case 503:
        return '번역 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.';
      default:
        return '번역 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }

  void dispose() {
    _client.close();
  }
}
