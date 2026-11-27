import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/translation/photo_translation_provider.dart';
import 'package:tripbler/services/translation_service.dart';

import '../helpers/fake_auth_notifier.dart';
import '../helpers/fake_device_translation.dart';
import '../helpers/fake_photo_translation.dart';

// 기본 방식(기기 읽기 + 글자 번역) 진행 중 retake·화면 이탈·세션 변경·일부 실패.
// 늦게 끝난 번역 요청은 상태를 바꾸지 않아야 한다.
void main() {
  late FakeNormalizer normalizer;
  late FakeOcr ocr;
  late FakeLineApi lineApi;
  late FakeTextService textService;
  late ProviderContainer container;

  ProviderContainer build({required bool signedIn}) =>
      buildDeviceTranslationContainer(
        signedIn: signedIn,
        normalizer: normalizer,
        ocr: ocr,
        consent: FakeConsent(),
        api: FakeApi(),
        lineApi: lineApi,
        textService: textService,
      );

  setUp(() {
    normalizer = FakeNormalizer();
    ocr = FakeOcr()
      ..lines = [fakeLine('醤油ラーメン', 0, 10), fakeLine('980円', 1, 100)];
    lineApi = FakeLineApi()..hold = true;
    textService = FakeTextService()..hold = true;
  });

  tearDown(() => container.dispose());

  PhotoTranslationState state() => container.read(photoTranslationProvider);
  PhotoTranslationNotifier notifier() =>
      container.read(photoTranslationProvider.notifier);

  /// 사진을 찍고 번역 요청이 나간 상태(응답 대기)까지 진행한다.
  Future<void> startUpload() async {
    notifier().processPhoto('a.jpg');
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.uploading);
  }

  void completeTexts() {
    for (final entry in textService.pending.entries.toList()) {
      if (!entry.value.isCompleted) {
        entry.value.complete('늦음:${entry.key}');
      }
    }
  }

  test('retake_whileTextTranslating_ignoresLateResponses', () async {
    container = build(signedIn: false);
    await startUpload();

    notifier().retake();
    completeTexts();
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
    expect(state().photo, isNull);
    expect(normalizer.deleted, ['tmp/photo_1.jpg']);
  });

  test('leave_whileLineTranslating_ignoresLateResponse', () async {
    container = build(signedIn: true);
    await startUpload();

    notifier().leave();
    lineApi.pending.single.complete(
      FakeLineApi.resultFor(lineApi.calls.single.lines),
    );
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
  });

  test('sessionChange_whileLineTranslating_ignoresLateResponse', () async {
    container = build(signedIn: true);
    await startUpload();

    (container.read(authProvider.notifier) as FakeAuthNotifier).signOut();
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.idle);

    lineApi.pending.single.complete(
      FakeLineApi.resultFor(lineApi.calls.single.lines),
    );
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.idle);
    expect(state().result, isNull);
    expect(state().paragraphs, isEmpty);
  });

  test(
    'oneParagraphFails_failsAtOnce_andLaterSuccessDoesNotOverwrite',
    () async {
      container = build(signedIn: false);
      await startUpload();

      textService.pending['醤油ラーメン']!.completeError(
        const TranslationApiException(message: '번역 서버에 연결할 수 없습니다.'),
      );
      await pumpEventQueue();

      // 다른 문단 응답을 기다리지 않고 바로 실패를 보인다.
      expect(state().status, PhotoTranslationStatus.failed);
      expect(state().errorMessage, '번역 서버에 연결할 수 없습니다.');
      expect(state().canRetry, isTrue);

      completeTexts();
      await pumpEventQueue();

      expect(state().status, PhotoTranslationStatus.failed);
      expect(state().result, isNull);
    },
  );

  test('oneParagraphFails_stopsSendingRemainingParagraphs', () async {
    ocr.lines = [for (var i = 0; i < 6; i++) fakeLine('t$i', i, i * 100.0)];
    container = build(signedIn: false);
    await startUpload();
    expect(textService.calls, ['t0', 't1', 't2', 't3']);

    textService.pending['t0']!.completeError(
      const TranslationApiException(message: '실패'),
    );
    await pumpEventQueue();
    completeTexts();
    await pumpEventQueue();

    expect(textService.calls, ['t0', 't1', 't2', 't3']);
    expect(state().status, PhotoTranslationStatus.failed);
  });

  test('retryAfterFailure_isNotOverwrittenByPreviousLateResponse', () async {
    container = build(signedIn: false);
    await startUpload();
    final stale = textService.pending['980円']!;
    textService.pending['醤油ラーメン']!.completeError(
      const TranslationApiException(message: '실패'),
    );
    await pumpEventQueue();
    expect(state().status, PhotoTranslationStatus.failed);

    textService.hold = false;
    await notifier().retry();
    await pumpEventQueue();
    stale.complete('늦음:980円');
    await pumpEventQueue();

    expect(state().status, PhotoTranslationStatus.completed);
    expect(state().result!.paragraphs.map((p) => p.translated), [
      '통:醤油ラーメン',
      '통:980円',
    ]);
  });
}
