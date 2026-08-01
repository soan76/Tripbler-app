import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  TranslationService({http.Client? client}) : _client = client ?? http.Client();

  static const String _endpoint =
      'https://translation.googleapis.com/language/translate/v2';

  final http.Client _client;

  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final trimmedText = text.trim();

    if (trimmedText.isEmpty) {
      return '';
    }

    if (sourceLanguageCode == targetLanguageCode) {
      return trimmedText;
    }

    final apiKey = _googleCloudTranslationApiKey;

    if (apiKey.isEmpty) {
      throw Exception('Google Cloud Translation API 키가 설정되지 않았습니다.');
    }

    final uri = Uri.parse('$_endpoint?key=$apiKey');

    final requestBody = <String, dynamic>{
      'q': trimmedText,
      'target': targetLanguageCode,
      'format': 'text',
    };

    if (sourceLanguageCode != 'auto') {
      requestBody['source'] = sourceLanguageCode;
    }

    try {
      final response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('Google Translation API 실패');
        debugPrint('statusCode: ${response.statusCode}');
        debugPrint('body: ${response.body}');

        throw Exception('번역 API 요청에 실패했습니다.');
      }

      final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;

      final data = jsonBody['data'] as Map<String, dynamic>?;
      final translations = data?['translations'] as List<dynamic>?;

      if (translations == null || translations.isEmpty) {
        throw Exception('번역 결과가 비어 있습니다.');
      }

      final firstTranslation = translations.first as Map<String, dynamic>;

      final translatedText = firstTranslation['translatedText'] as String?;

      if (translatedText == null || translatedText.trim().isEmpty) {
        throw Exception('번역된 텍스트가 없습니다.');
      }

      return _decodeHtmlEntities(translatedText.trim());
    } catch (error, stackTrace) {
      debugPrint('번역 처리 실패: $error');
      debugPrint('$stackTrace');

      throw Exception('번역 중 문제가 발생했습니다.');
    }
  }

  String get _googleCloudTranslationApiKey {
    return const String.fromEnvironment('GOOGLE_CLOUD_TRANSLATION_API_KEY');
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  void dispose() {
    _client.close();
  }
}
