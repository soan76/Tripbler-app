import 'package:flutter/material.dart';

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

class TranslationProvider extends ChangeNotifier {
  TranslationProvider({
    OcrService? ocrService,
    TranslationService? translationService,
  }) : _ocrService = ocrService ?? OcrService(),
       _translationService = translationService ?? TranslationService();

  final OcrService _ocrService;
  final TranslationService _translationService;

  TranslationStatus _status = TranslationStatus.checkingPermission;

  String? _selectedImagePath;
  String _recognizedText = '';
  String _translatedText = '';
  String? _errorMessage;

  String _sourceLanguageCode = 'ja';
  String _targetLanguageCode = 'ko';

  TranslationStatus get status => _status;
  String? get selectedImagePath => _selectedImagePath;
  String get recognizedText => _recognizedText;
  String get translatedText => _translatedText;
  String? get errorMessage => _errorMessage;
  String get sourceLanguageCode => _sourceLanguageCode;
  String get targetLanguageCode => _targetLanguageCode;

  bool get hasImage => _selectedImagePath != null;
  bool get hasRecognizedText => _recognizedText.trim().isNotEmpty;
  bool get hasTranslatedText => _translatedText.trim().isNotEmpty;

  bool get isProcessing {
    return _status == TranslationStatus.capturing ||
        _status == TranslationStatus.recognizing ||
        _status == TranslationStatus.translating;
  }

  List<TranslationLanguage> get languages {
    return const <TranslationLanguage>[
      TranslationLanguage(code: 'auto', label: '자동 감지'),
      TranslationLanguage(code: 'ko', label: '한국어'),
      TranslationLanguage(code: 'en', label: '영어'),
      TranslationLanguage(code: 'ja', label: '일본어'),
      TranslationLanguage(code: 'zh', label: '중국어'),
    ];
  }

  void setStatus(TranslationStatus status) {
    if (_status == status) {
      return;
    }

    _status = status;
    notifyListeners();
  }

  void setError({
    required String message,
    TranslationStatus status = TranslationStatus.failed,
  }) {
    _errorMessage = message;
    _status = status;
    notifyListeners();
  }

  void changeSourceLanguage(String languageCode) {
    if (_sourceLanguageCode == languageCode) {
      return;
    }

    _sourceLanguageCode = languageCode;
    _translatedText = '';
    notifyListeners();

    if (_recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  void changeTargetLanguage(String languageCode) {
    if (_targetLanguageCode == languageCode) {
      return;
    }

    _targetLanguageCode = languageCode;
    _translatedText = '';
    notifyListeners();

    if (_recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  void swapLanguages() {
    if (_sourceLanguageCode == 'auto') {
      return;
    }

    final oldSource = _sourceLanguageCode;
    _sourceLanguageCode = _targetLanguageCode;
    _targetLanguageCode = oldSource;
    _translatedText = '';

    notifyListeners();

    if (_recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  Future<void> processImage(String imagePath) async {
    if (_status == TranslationStatus.recognizing ||
        _status == TranslationStatus.translating) {
      return;
    }

    _selectedImagePath = imagePath;
    _recognizedText = '';
    _translatedText = '';
    _errorMessage = null;
    _status = TranslationStatus.recognizing;
    notifyListeners();

    try {
      debugPrint('=== OCR 시작 ===');

      final text = await _ocrService.recognizeText(
        imagePath: imagePath,
        sourceLanguageCode: _sourceLanguageCode,
      );

      debugPrint('=== OCR 완료 ===');
      debugPrint('OCR 결과: $text');

      if (text.trim().isEmpty) {
        _recognizedText = '';
        _translatedText = '';
        _errorMessage = '이미지에서 번역할 문자를 찾지 못했습니다.\n문자가 선명하게 보이도록 다시 촬영해 주세요.';
        _status = TranslationStatus.failed;
        notifyListeners();
        return;
      }

      _recognizedText = text.trim();
      _status = TranslationStatus.translating;
      notifyListeners();

      debugPrint('=== 번역 시작 ===');

      await translateRecognizedText();
      debugPrint('=== 번역 종료 ===');
    } catch (error, stackTrace) {
      debugPrint('OCR 처리 실패: $error');
      debugPrint('$stackTrace');

      _errorMessage = '문자 인식 중 문제가 발생했습니다.\n이미지를 다시 촬영해 주세요.';
      _status = TranslationStatus.failed;
      notifyListeners();
    }
  }

  Future<void> translateRecognizedText() async {
    final text = _recognizedText.trim();

    if (text.isEmpty) {
      return;
    }

    if (_sourceLanguageCode == _targetLanguageCode) {
      _translatedText = text;
      _status = TranslationStatus.completed;
      notifyListeners();
      return;
    }

    _status = TranslationStatus.translating;
    _errorMessage = null;
    notifyListeners();

    try {
      final translatedText = await _translationService.translate(
        text: text,
        sourceLanguageCode: _sourceLanguageCode,
        targetLanguageCode: _targetLanguageCode,
      );

      _translatedText = translatedText.trim();
      _status = TranslationStatus.completed;
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('번역 처리 실패: $error');
      debugPrint('$stackTrace');

      _errorMessage = '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
      _status = TranslationStatus.failed;
      notifyListeners();
    }
  }

  void resetForRetake() {
    _selectedImagePath = null;
    _recognizedText = '';
    _translatedText = '';
    _errorMessage = null;
    _status = TranslationStatus.cameraReady;
    notifyListeners();
  }
}
