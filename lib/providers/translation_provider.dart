import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../services/ocr_service.dart';
import '../services/translation_service.dart';

enum TranslationStatus {
  checkingPermission,
  permissionRequired,
  permissionDenied,
  permissionPermanentlyDenied,
  initializingCamera,
  cameraReady,
  cameraUnavailable,
  capturing,
  recognizing,
  translating,
  completed,
  failed,
}

class TranslationLanguage {
  final String code;
  final String label;

  const TranslationLanguage({required this.code, required this.label});
}

/// 기기 안에서 글자를 인식하는 서비스.
final ocrServiceProvider = Provider<OcrService>((ref) => OcrService());

/// 서버 번역 API를 호출하는 서비스.
final translationServiceProvider = Provider<TranslationService>((ref) {
  final service = TranslationService();
  ref.onDispose(service.dispose);
  return service;
});

/// 번역 화면이 보여 주는 값.
class TranslationState {
  const TranslationState({
    this.status = TranslationStatus.checkingPermission,
    this.selectedImagePath,
    this.recognizedText = '',
    this.translatedText = '',
    this.errorMessage,
    this.sourceLanguageCode = 'auto',
    this.targetLanguageCode = 'ko',
  });

  static const List<TranslationLanguage> _languages = <TranslationLanguage>[
    TranslationLanguage(code: 'auto', label: '자동 감지'),
    TranslationLanguage(code: 'ko', label: '한국어'),
    TranslationLanguage(code: 'en', label: '영어'),
    TranslationLanguage(code: 'ja', label: '일본어'),
    TranslationLanguage(code: 'zh', label: '중국어'),
  ];

  final TranslationStatus status;
  final String? selectedImagePath;
  final String recognizedText;
  final String translatedText;
  final String? errorMessage;
  final String sourceLanguageCode;
  final String targetLanguageCode;

  bool get hasImage => selectedImagePath != null;
  bool get hasRecognizedText => recognizedText.trim().isNotEmpty;
  bool get hasTranslatedText => translatedText.trim().isNotEmpty;

  bool get isProcessing {
    return status == TranslationStatus.capturing ||
        status == TranslationStatus.recognizing ||
        status == TranslationStatus.translating;
  }

  List<TranslationLanguage> get languages => _languages;

  TranslationState copyWith({
    TranslationStatus? status,
    String? selectedImagePath,
    bool clearSelectedImagePath = false,
    String? recognizedText,
    String? translatedText,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) {
    return TranslationState(
      status: status ?? this.status,
      selectedImagePath: clearSelectedImagePath
          ? null
          : selectedImagePath ?? this.selectedImagePath,
      recognizedText: recognizedText ?? this.recognizedText,
      translatedText: translatedText ?? this.translatedText,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
    );
  }
}

class TranslationNotifier extends Notifier<TranslationState> {
  @override
  TranslationState build() => const TranslationState();

  void setStatus(TranslationStatus status) {
    if (state.status == status) {
      return;
    }

    state = state.copyWith(status: status);
  }

  void setError({
    required String message,
    TranslationStatus status = TranslationStatus.failed,
  }) {
    state = state.copyWith(errorMessage: message, status: status);
  }

  void changeSourceLanguage(String languageCode) {
    if (state.sourceLanguageCode == languageCode) {
      return;
    }

    state = state.copyWith(
      sourceLanguageCode: languageCode,
      translatedText: '',
    );

    if (state.recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  void changeTargetLanguage(String languageCode) {
    if (state.targetLanguageCode == languageCode) {
      return;
    }

    state = state.copyWith(
      targetLanguageCode: languageCode,
      translatedText: '',
    );

    if (state.recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  void swapLanguages() {
    if (state.sourceLanguageCode == 'auto') {
      return;
    }

    state = state.copyWith(
      sourceLanguageCode: state.targetLanguageCode,
      targetLanguageCode: state.sourceLanguageCode,
      translatedText: '',
    );

    if (state.recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  Future<void> processImage(String imagePath) async {
    if (state.status == TranslationStatus.recognizing ||
        state.status == TranslationStatus.translating) {
      return;
    }

    state = state.copyWith(
      selectedImagePath: imagePath,
      recognizedText: '',
      translatedText: '',
      clearErrorMessage: true,
      status: TranslationStatus.recognizing,
    );

    try {
      debugPrint('=== OCR 시작 ===');

      final text = await ref
          .read(ocrServiceProvider)
          .recognizeText(
            imagePath: imagePath,
            sourceLanguageCode: state.sourceLanguageCode,
          );

      if (!ref.mounted) {
        return;
      }

      debugPrint('=== OCR 완료 ===');
      debugPrint('OCR 결과: $text');

      if (text.trim().isEmpty) {
        state = state.copyWith(
          recognizedText: '',
          translatedText: '',
          errorMessage: '이미지에서 번역할 문자를 찾지 못했습니다.\n문자가 선명하게 보이도록 다시 촬영해 주세요.',
          status: TranslationStatus.failed,
        );
        return;
      }

      state = state.copyWith(
        recognizedText: text.trim(),
        status: TranslationStatus.translating,
      );

      debugPrint('=== 번역 시작 ===');

      await translateRecognizedText();
      debugPrint('=== 번역 종료 ===');
    } catch (error, stackTrace) {
      debugPrint('OCR 처리 실패: $error');
      debugPrint('$stackTrace');

      if (!ref.mounted) {
        return;
      }

      state = state.copyWith(
        errorMessage: '문자 인식 중 문제가 발생했습니다.\n이미지를 다시 촬영해 주세요.',
        status: TranslationStatus.failed,
      );
    }
  }

  Future<void> translateRecognizedText() async {
    final text = state.recognizedText.trim();

    if (text.isEmpty) {
      return;
    }

    if (state.sourceLanguageCode == state.targetLanguageCode) {
      state = state.copyWith(
        translatedText: text,
        status: TranslationStatus.completed,
      );
      return;
    }

    state = state.copyWith(
      status: TranslationStatus.translating,
      clearErrorMessage: true,
    );

    try {
      final translatedText = await ref
          .read(translationServiceProvider)
          .translate(
            text: text,
            sourceLanguageCode: state.sourceLanguageCode,
            targetLanguageCode: state.targetLanguageCode,
          );

      if (!ref.mounted) {
        return;
      }

      state = state.copyWith(
        translatedText: translatedText.trim(),
        status: TranslationStatus.completed,
      );
    } catch (error, stackTrace) {
      debugPrint('번역 처리 실패: $error');
      debugPrint('$stackTrace');

      if (!ref.mounted) {
        return;
      }

      state = state.copyWith(
        errorMessage: '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.',
        status: TranslationStatus.failed,
      );
    }
  }

  void resetForRetake() {
    state = state.copyWith(
      clearSelectedImagePath: true,
      recognizedText: '',
      translatedText: '',
      clearErrorMessage: true,
      status: TranslationStatus.cameraReady,
    );
  }
}

final translationProvider =
    NotifierProvider<TranslationNotifier, TranslationState>(
      TranslationNotifier.new,
    );
