import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:tripbler/models/translation/line_translation_result.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show
        lineTranslationApiServiceProvider,
        ocrServiceProvider,
        translationServiceProvider;
import 'package:tripbler/services/line_translation_api_service.dart';
import 'package:tripbler/services/translation_service.dart';

import 'fake_auth_notifier.dart';
import 'fake_photo_translation.dart';

/// 줄별 번역 API 가짜. 기본은 줄마다 `ko:<원문>`으로 바로 답한다.
/// [error]가 있으면 그 예외를 던지고, [hold]이면 테스트가 [pending]으로 완료 시점을 정한다.
class FakeLineApi extends LineTranslationApiService {
  final List<({List<String> lines, String header})> calls = [];
  final List<Completer<LineTranslationResult>> pending = [];
  Object? error;
  bool hold = false;

  static LineTranslationResult resultFor(List<String> lines) =>
      LineTranslationResult(
        sourceLanguageCode: 'ja',
        targetLanguageCode: 'ko',
        lines: [
          for (final line in lines)
            TranslatedLine(original: line, translated: 'ko:$line'),
        ],
      );

  @override
  Future<LineTranslationResult> translateLines({
    required List<String> lines,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String authorizationHeader,
  }) async {
    calls.add((lines: lines, header: authorizationHeader));
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    if (hold) {
      final completer = Completer<LineTranslationResult>();
      pending.add(completer);
      return completer.future;
    }
    return resultFor(lines);
  }
}

/// 통번역 서비스 가짜. 기본은 `통:<원문>`으로 바로 답한다.
/// [errors]에 있는 글자는 그 예외를 던지고, [hold]이면 테스트가 [pending]으로 완료 시점을 정한다.
class FakeTextService extends TranslationService {
  final List<String> calls = [];
  final Map<String, Object> errors = {};
  final Map<String, Completer<String>> pending = {};
  bool hold = false;

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    calls.add(text);
    if (hold) {
      final completer = Completer<String>();
      pending[text] = completer;
      return completer.future;
    }
    final failure = errors[text];
    if (failure != null) {
      throw failure;
    }
    return '통:$text';
  }
}

/// 기본 방식(사진 AI 번역·가짜가 아님)으로 사진 번역을 돌리는 컨테이너.
ProviderContainer buildDeviceTranslationContainer({
  required bool signedIn,
  required FakeNormalizer normalizer,
  required FakeOcr ocr,
  required FakeConsent consent,
  required FakeApi api,
  required FakeLineApi lineApi,
  required FakeTextService textService,
}) {
  final created = ProviderContainer(
    overrides: [
      photoFakeTranslationProvider.overrideWithValue(false),
      photoAiTranslationProvider.overrideWithValue(false),
      photoNormalizerProvider.overrideWithValue(normalizer),
      photoOutputDirectoryProvider.overrideWithValue('tmp'),
      ocrServiceProvider.overrideWithValue(ocr),
      photoConsentStoreProvider.overrideWithValue(consent),
      photoTranslationApiServiceProvider.overrideWithValue(api),
      lineTranslationApiServiceProvider.overrideWithValue(lineApi),
      translationServiceProvider.overrideWithValue(textService),
      authProvider.overrideWith(
        () => FakeAuthNotifier(initiallySignedIn: signedIn),
      ),
      authorizedRequestRunnerProvider.overrideWithValue(
        <T>(Future<T> Function(String) request) => request('Bearer t'),
      ),
    ],
  );
  created.listen(photoTranslationProvider, (_, _) {});
  return created;
}
