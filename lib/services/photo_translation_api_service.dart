import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../core/config/api_config.dart';
import '../core/network/api_exception.dart';
import '../core/network/translation_api_errors.dart';
import '../domain/translation/photo_paragraphs.dart';
import '../models/translation/photo_translation_result.dart';
import 'photo_normalizer.dart';

/// 사진 번역 API(`POST /api/v1/translation/photo`, 로그인 필요).
class PhotoTranslationApiService {
  PhotoTranslationApiService({
    http.Client? client,
    Duration timeout = defaultTimeout,
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  // 임시값: 실제 Claude 측정(작업 14) 뒤 확정. 줄별 번역과 같은 기준으로 둔다.
  static const Duration defaultTimeout = Duration(seconds: 120);

  final Duration _timeout;
  final http.Client _client;

  /// [paragraphs]를 사진과 함께 보내 번역한다. 문단 수·길이 한도는 호출부가 맞춘다.
  ///
  /// 실패는 [ApiException]으로 던진다(시간 초과·연결 실패는 statusCode가 null).
  /// 사진과 문단 텍스트는 로그에 남기지 않는다.
  Future<PhotoTranslationResult> translate({
    required NormalizedPhoto photo,
    required List<OcrParagraph> paragraphs,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String authorizationHeader,
  }) async {
    final http.Response response;

    try {
      // 서버는 request 파트가 application/json일 때만 읽는다.
      final request =
          http.MultipartRequest('POST', ApiConfig.translationPhotoUri)
            ..headers['Authorization'] = authorizationHeader
            ..files.add(
              await http.MultipartFile.fromPath(
                'image',
                photo.path,
                filename: 'photo.jpg',
                contentType: MediaType('image', 'jpeg'),
              ),
            )
            ..files.add(
              http.MultipartFile.fromString(
                'request',
                jsonEncode(<String, dynamic>{
                  'sourceLanguageCode': sourceLanguageCode,
                  'targetLanguageCode': targetLanguageCode,
                  'imageWidth': photo.width,
                  'imageHeight': photo.height,
                  'paragraphs': [
                    for (final paragraph in paragraphs)
                      <String, dynamic>{
                        'id': paragraph.id,
                        'text': paragraph.text,
                        'box': <String, dynamic>{
                          'left': paragraph.box.left,
                          'top': paragraph.box.top,
                          'width': paragraph.box.width,
                          'height': paragraph.box.height,
                        },
                      },
                  ],
                }),
                contentType: MediaType('application', 'json'),
              ),
            );

      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        message: '번역 서버 응답 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
      );
    } on Exception {
      // 연결 실패·TLS 오류·사진 파일 읽기 실패를 네트워크 오류로 바꾼다.
      throw const ApiException(
        message: '번역 서버에 연결할 수 없습니다. 인터넷 연결 상태를 확인해 주세요.',
      );
    }

    if (response.statusCode != 200) {
      throw translationApiErrorFrom(response);
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 객체가 아닙니다.');
      }

      return PhotoTranslationResult.fromJson(
        decoded,
        requestedIds: {for (final paragraph in paragraphs) paragraph.id},
      );
    } on FormatException catch (error) {
      debugPrint('사진 번역 응답 해석 실패: ${error.message}');

      throw ApiException(
        statusCode: response.statusCode,
        message: '번역 응답 형식이 올바르지 않습니다.',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
