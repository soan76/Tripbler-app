import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/text_paragraphs.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show ocrServiceProvider;

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

  test('retakeDuringUpload_lateResponseIgnored_photoDeleted', () async {
    consent.valid = true;

    final processing = notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    expect(api.calls, hasLength(1));

    notifier().retake();
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.idle);
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);

    api.calls.single.completer.complete(
      fakeResult(api.calls.single.paragraphs),
    );
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

    held.complete([fakeLine('醤油ラーメン', 0, 10)]);
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

    api.calls.single.completer.complete(
      fakeResult(api.calls.single.paragraphs),
    );
    // 정리된 뒤 도착한 응답은 상태에 쓰지 않고 오류도 내지 않는다.
    await processing;
  });

  test('leaveAfterDispose_doesNothing', () async {
    await notifier().processPhoto('a.jpg');
    final captured = notifier();

    container.dispose();
    disposed = true;
    await pumpEventQueue();
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);

    // 화면 제거 뒤 늦게 부른 leave는 오류 없이 아무것도 하지 않는다.
    captured.leave();
    await pumpEventQueue();
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);
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

    api.calls.single.completer.complete(
      fakeResult(api.calls.single.paragraphs),
    );
    await processing;

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
    expect(state().photo, isNull);
  });
}
