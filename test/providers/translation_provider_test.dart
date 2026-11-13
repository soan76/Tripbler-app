import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/translation_provider.dart';
import 'package:tripbler/services/ocr_service.dart';

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

void main() {
  test('processImage가 끝나기 전에 resetForRetake해도 기존처럼 늦은 OCR 결과를 반영한다', () async {
    // 기존 ChangeNotifier 구현을 먼저 실행해 확인한 동작이다. 동작 변경은 이 작업의 범위가 아니다.
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
    expect(state.recognizedText, 'hello');
    expect(state.status, TranslationStatus.completed);
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
