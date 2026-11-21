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
  /// 가장 최근에 시작한 인식·번역 작업 번호.
  ///
  /// 새 사진 처리, 새 번역(언어 변경 포함), 다시 찍기 때마다 올린다. 늦게 끝난 이전 작업은
  /// 번호가 달라 결과·오류를 반영하지 않는다(언어를 바꾼 뒤 이전 언어 번역이 덮어쓰는 문제 등).
  int _requestId = 0;

  @override
  TranslationState build() => const TranslationState();

  /// [requestId]가 아직 가장 최근 작업이고 상태 객체가 살아 있는지.
  bool _isCurrent(int requestId) => ref.mounted && requestId == _requestId;

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

    final requestId = ++_requestId;

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

      if (!_isCurrent(requestId)) {
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

      if (!_isCurrent(requestId)) {
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

    // 원문을 그대로 쓰는 경우에도 진행 중이던 이전 번역 응답이 덮어쓰지 않게 번호를 올린다.
    final requestId = ++_requestId;

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

      if (!_isCurrent(requestId)) {
        return;
      }

      state = state.copyWith(
        translatedText: translatedText.trim(),
        status: TranslationStatus.completed,
      );
    } catch (error, stackTrace) {
      debugPrint('번역 처리 실패: $error');
      debugPrint('$stackTrace');

      if (!_isCurrent(requestId)) {
        return;
      }

      state = state.copyWith(
        errorMessage: '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.',
        status: TranslationStatus.failed,
      );
    }
  }

  void resetForRetake() {
    // 진행 중이던 인식·번역 결과가 다시 찍는 화면에 들어오지 않게 한다.
    _requestId++;

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
