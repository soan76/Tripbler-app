import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/providers/translation/translation_provider.dart'
    show ocrServiceProvider;
import 'package:tripbler/services/fake_photo_translation.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_photo_translation.dart';

// 개발용 가짜 번역 모드: 서버·로그인 없이 실제 OCR 문단에 가짜 결과를 붙이고, 아무것도 보내지 않는다.
void main() {
  late FakeNormalizer normalizer;
  late FakeOcr ocr;
  late FakeConsent consent;
  late FakeApi api;
  late ProviderContainer container;
  late int runnerCalls;

  setUp(() {
    normalizer = FakeNormalizer();
    ocr = FakeOcr()
      ..lines = [fakeLine('醤油ラーメン', 0, 10), fakeLine('980円', 1, 100)];
    consent = FakeConsent();
    api = FakeApi();
    runnerCalls = 0;
    container = ProviderContainer(
      overrides: [
        photoFakeTranslationProvider.overrideWithValue(true),
        photoFakeTranslationDelayProvider.overrideWithValue(Duration.zero),
        photoNormalizerProvider.overrideWithValue(normalizer),
        photoOutputDirectoryProvider.overrideWithValue('tmp'),
        ocrServiceProvider.overrideWithValue(ocr),
        photoConsentStoreProvider.overrideWithValue(consent),
        photoTranslationApiServiceProvider.overrideWithValue(api),
        authProvider.overrideWith(FakeAuthNotifier.new),
        authorizedRequestRunnerProvider.overrideWithValue(<T>(
          Future<T> Function(String) request,
        ) {
          runnerCalls++;
          throw StateError('가짜 모드에서는 로그인 요청을 쓰지 않아야 한다');
        }),
      ],
    );
    container.listen(photoTranslationProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  PhotoTranslationNotifier notifier() =>
      container.read(photoTranslationProvider.notifier);
  PhotoTranslationState state() => container.read(photoTranslationProvider);

  test(
    'fakeMode_attachesFakeResultToRealOcrIds_withoutServerOrLogin',
    () async {
      consent.valid = true;

      await notifier().processPhoto('a.jpg');
      await pumpEventQueue();

      expect(state().status, PhotoTranslationStatus.completed);
      final result = state().result!;
      expect(result.simulated, isTrue);
      expect(
        result.paragraphs.map((p) => p.id),
        state().paragraphs.map((p) => p.id),
      );
      expect(
        result.paragraphs.first.translated,
        startsWith(fakeTranslationPrefix),
      );
      expect(api.calls, isEmpty);
      expect(runnerCalls, 0);
    },
  );

  test('fakeMode_keepsConsentFlow_soItCanBeCheckedWithoutServer', () async {
    await notifier().processPhoto('a.jpg');

    expect(state().status, PhotoTranslationStatus.awaitingConsent);

    await notifier().acceptConsentAndTranslate();
    await pumpEventQueue();

    expect(consent.acceptCalls, 1);
    expect(state().status, PhotoTranslationStatus.completed);
    expect(state().result!.simulated, isTrue);
    expect(api.calls, isEmpty);
  });

  test('fakeMode_sameLanguage_keepsOriginal_notSimulated_noConsent', () async {
    notifier()
      ..changeSourceLanguage('ja')
      ..changeTargetLanguage('ja');

    await notifier().processPhoto('a.jpg');
    await pumpEventQueue();

    // 원문 언어와 번역 언어가 같으면 가짜 번역도 만들지 않고 원문을 그대로 보인다.
    expect(state().status, PhotoTranslationStatus.completed);
    final result = state().result!;
    expect(result.simulated, isFalse);
    expect(
      result.paragraphs.map((p) => p.translated),
      state().paragraphs.map((p) => p.text),
    );
    expect(
      result.paragraphs.every(
        (p) => !p.translated.startsWith(fakeTranslationPrefix),
      ),
      isTrue,
    );
    expect(consent.acceptCalls, 0);
    expect(api.calls, isEmpty);
    expect(runnerCalls, 0);
  });

  test('fakeMode_retakeBeforeFakeResult_dropsLateResult', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        photoFakeTranslationProvider.overrideWithValue(true),
        photoFakeTranslationDelayProvider.overrideWithValue(
          const Duration(milliseconds: 50),
        ),
        photoNormalizerProvider.overrideWithValue(normalizer),
        photoOutputDirectoryProvider.overrideWithValue('tmp'),
        ocrServiceProvider.overrideWithValue(ocr),
        photoConsentStoreProvider.overrideWithValue(consent..valid = true),
        photoTranslationApiServiceProvider.overrideWithValue(api),
        authProvider.overrideWith(FakeAuthNotifier.new),
      ],
    );
    container.listen(photoTranslationProvider, (_, _) {});

    final pending = notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.uploading);

    notifier().retake();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
  });
}
