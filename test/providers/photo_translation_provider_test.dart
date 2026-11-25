import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show ocrServiceProvider;
import 'package:tripbler/repositories/auth/auth_exceptions.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_photo_translation.dart';

void main() {
  late FakeNormalizer normalizer;
  late FakeOcr ocr;
  late FakeConsent consent;
  late FakeApi api;
  late ProviderContainer container;
  late Object? runnerError;
  late bool disposed;
  late FakeAuthNotifier auth;

  setUp(() {
    normalizer = FakeNormalizer();
    ocr = FakeOcr()
      ..lines = [fakeLine('醤油ラーメン', 0, 10), fakeLine('980円', 1, 100)];
    consent = FakeConsent();
    api = FakeApi();
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

    api.calls.single.completer.complete(
      fakeResult(api.calls.single.paragraphs),
    );
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

    api.calls.single.completer.complete(
      fakeResult(api.calls.single.paragraphs),
    );
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

    api.calls[1].completer.complete(fakeResult(api.calls[1].paragraphs));
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
        fakeLine('글$i', i, i * 40.0),
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

  test('toggleOriginal_flips', () async {
    expect(state().showOriginal, isFalse);
    notifier().toggleOriginal();
    expect(state().showOriginal, isTrue);
  });
}
