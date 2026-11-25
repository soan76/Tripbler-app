import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/domain/translation/text_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show ocrServiceProvider;
import 'package:tripbler/repositories/auth/auth_exceptions.dart';
import 'package:tripbler/services/ocr_service.dart';
import 'package:tripbler/services/photo_consent_store.dart';
import 'package:tripbler/services/photo_normalizer.dart';
import 'package:tripbler/services/photo_translation_api_service.dart';

import '../helpers/fake_auth_notifier.dart';

/// 파일을 만들지 않고 정리 결과를 돌려준다. [hold]이면 테스트가 완료 시점을 정한다.
class _FakeNormalizer extends PhotoNormalizer {
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

class _FakeOcr extends OcrService {
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

class _FakeConsent extends PhotoConsentStore {
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

class _FakeApi extends PhotoTranslationApiService {
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

RecognizedTextLine _line(String text, int block, double top) =>
    (text: text, box: Rect.fromLTWH(10, top, 200, 20), block: block);

PhotoTranslationResult _result(List<OcrParagraph> paragraphs) {
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

void main() {
  late _FakeNormalizer normalizer;
  late _FakeOcr ocr;
  late _FakeConsent consent;
  late _FakeApi api;
  late ProviderContainer container;
  late Object? runnerError;
  late bool disposed;
  late FakeAuthNotifier auth;

  setUp(() {
    normalizer = _FakeNormalizer();
    ocr = _FakeOcr()..lines = [_line('醤油ラーメン', 0, 10), _line('980円', 1, 100)];
    consent = _FakeConsent();
    api = _FakeApi();
    runnerError = null;
    disposed = false;
    auth = FakeAuthNotifier();
    container = ProviderContainer(
      overrides: [
        photoNormalizerProvider.overrideWithValue(normalizer),
        photoOutputDirectoryProvider.overrideWithValue('tmp'),
        ocrServiceProvider.overrideWithValue(ocr),
        photoConsentStoreProvider.overrideWithValue(consent),
        photoTranslationApiServiceProvider.overrideWithValue(api),
        authProvider.overrideWith(() => auth),
        authorizedRequestRunnerProvider.overrideWithValue(<T>(
          Future<T> Function(String) request,
        ) async {
          final error = runnerError;
          if (error != null) {
            throw error;
          }
          return request('Bearer test');
        }),
      ],
    );
    // 상태를 계속 구독해 자동 정리되지 않게 한다.
    container.listen(photoTranslationProvider, (_, _) {});
  });

  tearDown(() {
    if (!disposed) {
      container.dispose();
    }
  });

  PhotoTranslationNotifier notifier() =>
      container.read(photoTranslationProvider.notifier);
  PhotoTranslationState state() => container.read(photoTranslationProvider);

  test('firstTime_waitsForConsent_andSendsNothing', () async {
    await notifier().processPhoto('a.jpg');

    expect(state().status, PhotoTranslationStatus.awaitingConsent);
    expect(state().photo?.path, 'tmp/photo_1.jpg');
    expect(state().paragraphs.map((p) => p.id), ['p1', 'p2']);
    expect(api.calls, isEmpty);
    expect(consent.acceptCalls, 0);
  });

  test('cancelConsent_deletesPhoto_returnsIdle_noUpload', () async {
    await notifier().processPhoto('a.jpg');
    notifier().cancelConsent();
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().photo, isNull);
    expect(state().paragraphs, isEmpty);
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);
    expect(api.calls, isEmpty);
    expect(consent.acceptCalls, 0);
  });

  test('acceptTwice_uploadsOnce', () async {
    await notifier().processPhoto('a.jpg');

    final first = notifier().acceptConsentAndTranslate();
    final second = notifier().acceptConsentAndTranslate();
    expect(state().status, PhotoTranslationStatus.uploading);
    await pumpEventQueue();

    expect(consent.acceptCalls, 1);
    expect(api.calls, hasLength(1));

    api.calls.single.completer.complete(_result(api.calls.single.paragraphs));
    await Future.wait([first, second]);

    expect(state().status, PhotoTranslationStatus.completed);
    expect(state().result!.paragraphs.first.translated, '번역:醤油ラーメン');
    expect(normalizer.deleted, isEmpty);
  });

  test('validConsent_uploadsWithoutAsking', () async {
    consent.valid = true;

    final processing = notifier().processPhoto('a.jpg');
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.uploading);
    expect(api.calls, hasLength(1));
    expect(api.calls.single.photo.path, 'tmp/photo_1.jpg');
    expect(api.calls.single.source, 'auto');
    expect(api.calls.single.target, 'ko');
    expect(consent.acceptCalls, 0);

    api.calls.single.completer.complete(_result(api.calls.single.paragraphs));
    await processing;
    expect(state().status, PhotoTranslationStatus.completed);
  });

  test('noText_statusNoText_noUpload', () async {
    consent.valid = true;
    ocr.lines = const [];

    await notifier().processPhoto('a.jpg');

    expect(state().status, PhotoTranslationStatus.noText);
    expect(state().photo, isNull);
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);
    expect(api.calls, isEmpty);
  });

  test('unsupportedPhoto_statusUnsupported_noUpload', () async {
    consent.valid = true;
    normalizer.unsupported = true;

    await notifier().processPhoto('a.heic');

    expect(state().status, PhotoTranslationStatus.unsupportedPhoto);
    expect(state().photo, isNull);
    expect(ocr.calls, 0);
    expect(api.calls, isEmpty);
  });

  test('retakeDuringUpload_lateResponseIgnored_photoDeleted', () async {
    consent.valid = true;

    final processing = notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    expect(api.calls, hasLength(1));

    notifier().retake();
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.idle);
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);

    api.calls.single.completer.complete(_result(api.calls.single.paragraphs));
    await processing;

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
    expect(state().photo, isNull);
  });

  test('retakeDuringNormalize_lateNormalizedPhotoDeleted', () async {
    normalizer.hold = true;

    final processing = notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    notifier().retake();
    normalizer.completePending();
    await processing;

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().photo, isNull);
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);
    expect(ocr.calls, 0);
  });

  test('leaveDuringOcr_lateOcrIgnored', () async {
    final held = Completer<List<RecognizedTextLine>>();
    ocr.held = held;

    final processing = notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.preparing);

    notifier().leave();
    await pumpEventQueue();
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);

    held.complete([_line('醤油ラーメン', 0, 10)]);
    await processing;

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().paragraphs, isEmpty);
    expect(state().photo, isNull);
    expect(api.calls, isEmpty);
  });

  test('disposeDuringUpload_noStateWrite', () async {
    consent.valid = true;

    final processing = notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    expect(api.calls, hasLength(1));

    container.dispose();
    disposed = true;
    await pumpEventQueue();
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);

    api.calls.single.completer.complete(_result(api.calls.single.paragraphs));
    // 정리된 뒤 도착한 응답은 상태에 쓰지 않고 오류도 내지 않는다.
    await processing;
  });

  test('retryAfterFailure_resendsSamePhoto_noConsentPrompt', () async {
    await notifier().processPhoto('a.jpg');
    final accepting = notifier().acceptConsentAndTranslate();
    await pumpEventQueue();
    api.calls.single.completer.completeError(
      const ApiException(message: '번역 서버에 연결할 수 없습니다.'),
    );
    await accepting;

    expect(state().status, PhotoTranslationStatus.failed);
    expect(state().errorMessage, '번역 서버에 연결할 수 없습니다.');
    expect(state().photo, isNotNull);

    final retrying = notifier().retry();
    expect(state().status, PhotoTranslationStatus.uploading);
    await pumpEventQueue();

    expect(api.calls, hasLength(2));
    expect(api.calls[1].photo.path, api.calls[0].photo.path);
    expect(api.calls[1].paragraphs, api.calls[0].paragraphs);
    expect(consent.acceptCalls, 1);
    expect(normalizer.deleted, isEmpty);

    api.calls[1].completer.complete(_result(api.calls[1].paragraphs));
    await retrying;
    expect(state().status, PhotoTranslationStatus.completed);
    expect(state().errorMessage, isNull);
  });

  test('sameSourceAndTarget_noUpload_showsOriginal', () async {
    notifier()
      ..changeSourceLanguage('ja')
      ..changeTargetLanguage('ja');

    await notifier().processPhoto('a.jpg');

    expect(state().status, PhotoTranslationStatus.completed);
    expect(api.calls, isEmpty);
    expect(consent.acceptCalls, 0);
    final paragraphs = state().result!.paragraphs;
    expect(paragraphs.map((p) => p.translated), ['醤油ラーメン', '980円']);
    expect(
      paragraphs.every((p) => p.source == PhotoTranslationSource.original),
      isTrue,
    );
    expect(state().photo, isNotNull);
  });

  test('omittedParagraphs_countKept', () async {
    ocr.lines = [
      for (var i = 0; i < PhotoParagraphLimits.maxParagraphs + 3; i++)
        _line('글$i', i, i * 40.0),
    ];

    await notifier().processPhoto('a.jpg');

    expect(state().status, PhotoTranslationStatus.awaitingConsent);
    expect(state().paragraphs, hasLength(PhotoParagraphLimits.maxParagraphs));
    expect(state().omittedCount, 3);
  });

  test('sessionExpired_failedWithLoginMessage', () async {
    consent.valid = true;
    runnerError = const SessionExpiredException(1);

    await notifier().processPhoto('a.jpg');

    expect(state().status, PhotoTranslationStatus.failed);
    expect(state().errorMessage, contains('로그인이 만료'));
  });

  test('sessionChange_clearsStateAndDeletesPhoto', () async {
    // 결과를 보고 있던 중 로그아웃하면 사진·문단·결과를 비운다.
    notifier()
      ..changeSourceLanguage('ja')
      ..changeTargetLanguage('ja');
    await notifier().processPhoto('a.jpg');
    expect(state().status, PhotoTranslationStatus.completed);

    auth.signOut();
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().photo, isNull);
    expect(state().paragraphs, isEmpty);
    expect(state().result, isNull);
    expect(state().targetLanguageCode, 'ja');
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);

    // 업로드 중 계정이 바뀌면 늦게 온 응답을 버린다.
    notifier().changeTargetLanguage('ko');
    consent.valid = true;
    final processing = notifier().processPhoto('b.jpg');
    await pumpEventQueue();
    expect(api.calls, hasLength(1));

    auth.signIn();
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.idle);
    expect(normalizer.deleted, ['tmp/photo_1.jpg', 'tmp/photo_2.jpg']);

    api.calls.single.completer.complete(_result(api.calls.single.paragraphs));
    await processing;

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
    expect(state().photo, isNull);
  });

  test('toggleOriginal_flips', () async {
    expect(state().showOriginal, isFalse);
    notifier().toggleOriginal();
    expect(state().showOriginal, isTrue);
  });
}
