import '../../models/translation/line_translation_result.dart';

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

/// 번역 화면이 보여 주는 값.
class TranslationState {
  const TranslationState({
    this.status = TranslationStatus.checkingPermission,
    this.selectedImagePath,
    this.recognizedText = '',
    this.recognizedLines = const <String>[],
    this.translatedText = '',
    this.lineResult,
    this.omittedLineCount = 0,
    this.frameFallback = false,
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

  /// 줄 단위로 읽은 원문(로그인 상태에서 찍었을 때만). 비어 있으면 통번역을 쓴다.
  final List<String> recognizedLines;

  final String translatedText;

  /// 줄별 번역 결과(찍기 모드). 통번역이면 null.
  final LineTranslationResult? lineResult;

  /// 줄 수·글자 수 제한으로 보내지 못한 줄 수.
  final int omittedLineCount;

  /// 카메라로 찍었지만 가이드 프레임을 맞출 수 없어(가로로 든 사진, 사진·미리보기 크기를 모름) 사진 전체의
  /// 글자를 번역했는지. 결과 화면이 안내 한 줄을 보여 준다.
  final bool frameFallback;
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

  /// 결과(사진·인식·번역·실패)를 보여 주는 상태인지. 권한 확인·카메라 준비처럼 결과가 없는 상태는 false.
  bool get showsResult {
    return hasImage ||
        status == TranslationStatus.recognizing ||
        status == TranslationStatus.translating ||
        status == TranslationStatus.completed ||
        status == TranslationStatus.failed;
  }

  List<TranslationLanguage> get languages => _languages;

  /// 언어 선택은 그대로 두고 인식·번역 결과와 오류만 비운 상태.
  ///
  /// 사진([selectedImagePath])과 [status]는 바꾸지 않는다. 호출부가 다음 값을 정한다.
  TranslationState withoutResult() {
    return copyWith(
      recognizedText: '',
      recognizedLines: const <String>[],
      translatedText: '',
      clearLineResult: true,
      omittedLineCount: 0,
      frameFallback: false,
      clearErrorMessage: true,
    );
  }

  TranslationState copyWith({
    TranslationStatus? status,
    String? selectedImagePath,
    bool clearSelectedImagePath = false,
    String? recognizedText,
    List<String>? recognizedLines,
    String? translatedText,
    LineTranslationResult? lineResult,
    bool clearLineResult = false,
    int? omittedLineCount,
    bool? frameFallback,
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
      recognizedLines: recognizedLines ?? this.recognizedLines,
      translatedText: translatedText ?? this.translatedText,
      lineResult: clearLineResult ? null : lineResult ?? this.lineResult,
      omittedLineCount: omittedLineCount ?? this.omittedLineCount,
      frameFallback: frameFallback ?? this.frameFallback,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
    );
  }
}
