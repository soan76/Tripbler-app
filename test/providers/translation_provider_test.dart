import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/translation/translation_provider.dart';
import 'package:tripbler/services/ocr_service.dart';
import 'package:tripbler/services/translation_service.dart';

class _FakeOcrService extends OcrService {
  final Completer<String> completer = Completer<String>();

  @override
  Future<String> recognizeText({
    required String imagePath,
    required String sourceLanguageCode,
  }) {
    return completer.future;
  }
}

/// 요청마다 Completer를 만들어 테스트가 응답 순서를 정한다.
class _FakeTranslationService extends TranslationService {
  final List<({String target, Completer<String> completer})> calls = [];

  @override
  Future<String> translate({
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    final completer = Completer<String>();
    calls.add((target: targetLanguageCode, completer: completer));
    return completer.future;
  }
}

void main() {
  test('processImage가 끝나기 전에 resetForRetake하면 늦은 OCR 결과는 버린다', () async {
    final ocr = _FakeOcrService();
    final container = ProviderContainer.test(
      overrides: [ocrServiceProvider.overrideWithValue(ocr)],
    );
    final notifier = container.read(translationProvider.notifier);
    // 원본과 번역 언어를 같게 해 번역 서버 호출 없이 끝나게 한다.
    notifier.changeTargetLanguage('auto');

    final future = notifier.processImage('a.jpg');
    notifier.resetForRetake();
    ocr.completer.complete('hello');
    await future;

    final state = container.read(translationProvider);
    expect(state.recognizedText, isEmpty);
    expect(state.selectedImagePath, isNull);
    expect(state.status, TranslationStatus.cameraReady);
  });

  test('resetForRetake 뒤 늦게 실패한 OCR도 오류를 띄우지 않는다', () async {
    final ocr = _FakeOcrService();
    final container = ProviderContainer.test(
      overrides: [ocrServiceProvider.overrideWithValue(ocr)],
    );
    final notifier = container.read(translationProvider.notifier);

    final future = notifier.processImage('a.jpg');
    notifier.resetForRetake();
    ocr.completer.completeError(Exception('ocr'));
    await future;

    final state = container.read(translationProvider);
    expect(state.errorMessage, isNull);
    expect(state.status, TranslationStatus.cameraReady);
  });

  group('번역 중 언어를 바꾸면', () {
    late _FakeTranslationService translator;
    late ProviderContainer container;
    late TranslationNotifier notifier;
    late Future<void> processing;

    // OCR을 끝내고 첫 번역(ko) 요청이 나간 상태로 만든다.
    Future<void> startFirstTranslation() async {
      final ocr = _FakeOcrService();
      translator = _FakeTranslationService();
      container = ProviderContainer.test(
        overrides: [
          ocrServiceProvider.overrideWithValue(ocr),
          translationServiceProvider.overrideWithValue(translator),
        ],
      );
      notifier = container.read(translationProvider.notifier);

      processing = notifier.processImage('a.jpg');
      ocr.completer.complete('hello');
      await pumpEventQueue();
      expect(translator.calls.single.target, 'ko');
    }

    test('늦게 온 이전 언어 응답은 반영하지 않는다', () async {
      await startFirstTranslation();

      notifier.changeTargetLanguage('ja');
      expect(translator.calls.last.target, 'ja');

      translator.calls.last.completer.complete('こんにちは');
      await pumpEventQueue();
      translator.calls.first.completer.complete('안녕하세요');
      await processing;

      final state = container.read(translationProvider);
      expect(state.translatedText, 'こんにちは');
      expect(state.targetLanguageCode, 'ja');
      expect(state.status, TranslationStatus.completed);
    });

    test('이전 언어 요청의 늦은 실패는 새 결과를 덮지 않는다', () async {
      await startFirstTranslation();

      notifier.changeTargetLanguage('ja');
      translator.calls.last.completer.complete('こんにちは');
      await pumpEventQueue();
      translator.calls.first.completer.completeError(Exception('late'));
      await processing;

      final state = container.read(translationProvider);
      expect(state.translatedText, 'こんにちは');
      expect(state.errorMessage, isNull);
      expect(state.status, TranslationStatus.completed);
    });

    test('같은 언어로 바꿔 바로 끝난 뒤에도 늦은 응답은 반영하지 않는다', () async {
      await startFirstTranslation();

      // 원본(auto)과 같게 하면 서버 호출 없이 원문을 결과로 쓴다.
      notifier.changeTargetLanguage('auto');
      expect(container.read(translationProvider).translatedText, 'hello');

      translator.calls.first.completer.complete('안녕하세요');
      await processing;

      final state = container.read(translationProvider);
      expect(state.translatedText, 'hello');
      expect(state.status, TranslationStatus.completed);
    });

    test('다시 찍으면 진행 중이던 번역 응답은 반영하지 않는다', () async {
      await startFirstTranslation();

      notifier.resetForRetake();
      translator.calls.first.completer.complete('안녕하세요');
      await processing;

      final state = container.read(translationProvider);
      expect(state.translatedText, isEmpty);
      expect(state.status, TranslationStatus.cameraReady);
    });
  });

  test('swapLanguages는 auto 원본에서 기존 규칙을 따른다', () {
    final container = ProviderContainer.test();
    final notifier = container.read(translationProvider.notifier);

    notifier.swapLanguages();

    final state = container.read(translationProvider);
    expect(state.sourceLanguageCode, 'auto');
    expect(state.targetLanguageCode, 'ko');

    notifier.changeSourceLanguage('en');
    notifier.swapLanguages();

    final swapped = container.read(translationProvider);
    expect(swapped.sourceLanguageCode, 'ko');
    expect(swapped.targetLanguageCode, 'en');
  });

  test('resetForRetake는 이미지와 오류를 비우고 카메라 준비 상태로 돌린다', () {
    final container = ProviderContainer.test();
    final notifier = container.read(translationProvider.notifier);

    notifier.setError(message: '실패');
    notifier.resetForRetake();

    final state = container.read(translationProvider);
    expect(state.errorMessage, isNull);
    expect(state.selectedImagePath, isNull);
    expect(state.status, TranslationStatus.cameraReady);
  });
}
