import 'dart:async';
import 'dart:ui' show Rect;

import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/domain/translation/text_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/services/ocr_service.dart';
import 'package:tripbler/services/photo_consent_store.dart';
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/services/photo_translation_api_service.dart';

/// 파일을 만들지 않고 정리 결과를 돌려준다. [hold]이면 테스트가 완료 시점을 정한다.
class FakeNormalizer extends PhotoNormalizer {
  bool unsupported = false;
  bool hold = false;
  int _count = 0;
  final List<Completer<NormalizedPhoto>> pending = [];
  final List<String> deleted = [];

  NormalizedPhoto _next() {
    _count++;
    return NormalizedPhoto(
      path: 'tmp/photo_$_count.jpg',
      width: 800,
      height: 600,
    );
  }

  @override
  Future<NormalizedPhoto> normalize({
    required String sourcePath,
    required String outputDirectory,
  }) async {
    if (unsupported) {
      throw const UnsupportedPhotoException();
    }
    if (hold) {
      final completer = Completer<NormalizedPhoto>();
      pending.add(completer);
      return completer.future;
    }
    return _next();
  }

  void completePending() => pending.removeAt(0).complete(_next());

  @override
  Future<void> delete(NormalizedPhoto photo) async {
    deleted.add(photo.path);
  }
}

class FakeOcr extends OcrService {
  List<RecognizedTextLine> lines = const [];
  Completer<List<RecognizedTextLine>>? held;
  int calls = 0;

  @override
  Future<List<RecognizedTextLine>> recognizeTextLines({
    required String imagePath,
    required String sourceLanguageCode,
  }) {
    calls++;
    final completer = held;
    if (completer != null) {
      return completer.future;
    }
    return Future.value(lines);
  }
}

class FakeConsent extends PhotoConsentStore {
  bool valid = false;
  int acceptCalls = 0;

  @override
  Future<bool> hasValidConsent() async => valid;

  @override
  Future<void> accept() async {
    acceptCalls++;
    valid = true;
  }
}

class FakeApi extends PhotoTranslationApiService {
  final List<
    ({
      NormalizedPhoto photo,
      List<OcrParagraph> paragraphs,
      String source,
      String target,
      Completer<PhotoTranslationResult> completer,
    })
  >
  calls = [];

  @override
  Future<PhotoTranslationResult> translate({
    required NormalizedPhoto photo,
    required List<OcrParagraph> paragraphs,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    required String authorizationHeader,
  }) {
    final completer = Completer<PhotoTranslationResult>();
    calls.add((
      photo: photo,
      paragraphs: paragraphs,
      source: sourceLanguageCode,
      target: targetLanguageCode,
      completer: completer,
    ));
    return completer.future;
  }
}

RecognizedTextLine fakeLine(String text, int block, double top) =>
    (text: text, box: Rect.fromLTWH(10, top, 200, 20), block: block);

PhotoTranslationResult fakeResult(List<OcrParagraph> paragraphs) {
  return PhotoTranslationResult(
    sourceLanguageCode: 'ja',
    targetLanguageCode: 'ko',
    paragraphs: [
      for (final paragraph in paragraphs)
        TranslatedParagraph(
          id: paragraph.id,
          original: paragraph.text,
          translated: '번역:${paragraph.text}',
          uncertain: false,
          source: PhotoTranslationSource.ai,
        ),
    ],
  );
}
