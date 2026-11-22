import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../core/network/api_exception.dart';
import '../models/translation/line_translation_result.dart';
import '../repositories/auth/auth_exceptions.dart';
import '../services/line_translation_api_service.dart';
import '../services/ocr_service.dart';
import '../services/translation_service.dart';
import 'auth/auth_provider.dart';

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

/// 찍기 모드 줄별 번역 API를 호출하는 서비스(로그인 필요).
final lineTranslationApiServiceProvider = Provider<LineTranslationApiService>((
  ref,
) {
  final service = LineTranslationApiService();
  ref.onDispose(service.dispose);
  return service;
});

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

  List<TranslationLanguage> get languages => _languages;

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

class TranslationNotifier extends Notifier<TranslationState> {
  /// 줄별 번역 요청 제한(서버와 같다). 넘는 줄은 보내지 않고 [TranslationState.omittedLineCount]로 알린다.
  static const int maxLines = 50;
  static const int maxLineLength = 200;
  static const int maxTotalCharacters = 5000;

  /// 가장 최근에 시작한 인식·번역 작업 번호.
  ///
  /// 새 사진 처리, 새 번역(언어 변경 포함), 다시 찍기 때마다 올린다. 늦게 끝난 이전 작업은
  /// 번호가 달라 결과·오류를 반영하지 않는다(언어를 바꾼 뒤 이전 언어 번역이 덮어쓰는 문제 등).
  int _requestId = 0;

  @override
  TranslationState build() {
    // 지도와 같은 기준: 로그인 세션 번호가 바뀌면(로그인·로그아웃·계정 전환) 이전 세션의 사진과
    // 결과를 비운다. 구독이 멈춘 동안 로그아웃→재로그인이 하나로 합쳐져 와도 번호가 다르면 알아챈다.
    ref.listen(authProvider, (previous, next) {
      if (previous != null && previous.sessionId != next.sessionId) {
        _onSessionChanged();
      }
    });

    return const TranslationState();
  }

  /// 진행 중이던 인식·번역 응답을 버리고, 결과 화면이면 카메라 화면으로 돌아간다.
  /// 권한 확인·카메라 준비처럼 결과가 없는 상태는 그대로 둔다.
  void _onSessionChanged() {
    _requestId++;

    final showsResult =
        state.hasImage ||
        state.status == TranslationStatus.recognizing ||
        state.status == TranslationStatus.translating ||
        state.status == TranslationStatus.completed ||
        state.status == TranslationStatus.failed;

    if (!showsResult) {
      return;
    }

    _clearResult();
  }

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
      clearLineResult: true,
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
      clearLineResult: true,
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
      clearLineResult: true,
    );

    if (state.recognizedText.trim().isNotEmpty) {
      translateRecognizedText();
    }
  }

  /// 사진의 글자를 읽어 번역한다.
  ///
  /// [fromCamera]이면 카메라 가이드 프레임 안의 글자만 쓴다(갤러리 사진은 프레임이 없어 전체).
  /// [cameraPreviewAspect]는 촬영 순간 미리보기의 세로 기준 비율(짧은 변/긴 변)이다. 모르면 카드가
  /// 미리보기를 제대로 그리지 못한 상태라 프레임을 쓰지 않고 사진 전체를 읽는다.
  Future<void> processImage(
    String imagePath, {
    bool fromCamera = false,
    double? cameraPreviewAspect,
  }) async {
    if (state.status == TranslationStatus.recognizing ||
        state.status == TranslationStatus.translating) {
      return;
    }

    final requestId = ++_requestId;

    state = state.copyWith(
      selectedImagePath: imagePath,
      recognizedText: '',
      recognizedLines: const <String>[],
      translatedText: '',
      clearLineResult: true,
      omittedLineCount: 0,
      frameFallback: false,
      clearErrorMessage: true,
      status: TranslationStatus.recognizing,
    );

    try {
      debugPrint('=== OCR 시작 ===');

      // 로그인했으면 줄 단위로 읽어 줄별 번역(발음·가격)을 쓰고, 아니면 통번역을 쓴다.
      // 줄별 번역 API는 로그인이 필요하다.
      final ocr = ref.read(ocrServiceProvider);
      final useFrame = fromCamera && cameraPreviewAspect != null;
      var lines = const <String>[];
      var frameApplied = false;
      final String text;

      if (_isSignedIn || useFrame) {
        final result = await ocr.recognizeLines(
          imagePath: imagePath,
          sourceLanguageCode: state.sourceLanguageCode,
          onlyInCaptureFrame: useFrame,
          cameraPreviewAspect: cameraPreviewAspect,
        );
        frameApplied = result.frameApplied;
        // 로그인하지 않았으면(통번역) 줄을 `\n`으로 이어 쓴다. ML Kit의 전체 글자(`recognizeText`)도
        // 덩어리 안 줄과 덩어리 사이를 모두 `\n`으로 잇기 때문에 통번역에 보내는 형식이 같다.
        if (_isSignedIn) {
          lines = result.lines;
        }
        text = result.lines.join('\n');
      } else {
        text = await ocr.recognizeText(
          imagePath: imagePath,
          sourceLanguageCode: state.sourceLanguageCode,
        );
      }

      if (!_isCurrent(requestId)) {
        return;
      }

      debugPrint('=== OCR 완료 ===');

      if (text.trim().isEmpty) {
        state = state.copyWith(
          recognizedText: '',
          translatedText: '',
          errorMessage: frameApplied
              ? '프레임 안에서 번역할 문자를 찾지 못했습니다.\n번역할 글자를 프레임 안에 맞춰 다시 촬영해 주세요.'
              : '이미지에서 번역할 문자를 찾지 못했습니다.\n문자가 선명하게 보이도록 다시 촬영해 주세요.',
          status: TranslationStatus.failed,
        );
        return;
      }

      state = state.copyWith(
        recognizedText: text.trim(),
        recognizedLines: lines,
        frameFallback: fromCamera && !frameApplied,
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

    if (state.recognizedLines.isNotEmpty && _isSignedIn) {
      await _translateLines(requestId);
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

  /// 줄별 번역(찍기 모드). [requestId]는 [translateRecognizedText]가 올린 번호.
  Future<void> _translateLines(int requestId) async {
    final (lines, omitted) = linesForRequest(state.recognizedLines);
    final source = state.sourceLanguageCode;
    final target = state.targetLanguageCode;

    if (source == target) {
      // 원문 언어와 번역 언어가 같으면 서버에 보내지 않고 원문을 그대로 보여 준다.
      state = state.copyWith(
        lineResult: LineTranslationResult(
          sourceLanguageCode: source,
          targetLanguageCode: target,
          lines: List<TranslatedLine>.unmodifiable(
            lines.map(
              (line) => TranslatedLine(original: line, translated: line),
            ),
          ),
        ),
        translatedText: lines.join('\n'),
        omittedLineCount: omitted,
        status: TranslationStatus.completed,
      );
      return;
    }

    state = state.copyWith(
      status: TranslationStatus.translating,
      clearErrorMessage: true,
    );

    try {
      final service = ref.read(lineTranslationApiServiceProvider);
      final result = await ref.read(authorizedRequestRunnerProvider)(
        (authorizationHeader) => service.translateLines(
          lines: lines,
          sourceLanguageCode: source,
          targetLanguageCode: target,
          authorizationHeader: authorizationHeader,
        ),
      );

      if (!_isCurrent(requestId)) {
        return;
      }

      state = state.copyWith(
        lineResult: result,
        translatedText: result.lines.map((line) => line.translated).join('\n'),
        omittedLineCount: omitted,
        status: TranslationStatus.completed,
      );
    } on SessionChangedException {
      // 요청 중 로그아웃·재로그인됐다. 이 결과는 버린다.
      if (_isCurrent(requestId)) {
        state = state.copyWith(
          errorMessage: '로그인 상태가 바뀌었습니다.\n다시 찍어 주세요.',
          status: TranslationStatus.failed,
        );
      }
    } catch (error) {
      debugPrint('줄별 번역 실패: $error');

      if (!_isCurrent(requestId)) {
        return;
      }

      state = state.copyWith(
        errorMessage: _lineErrorMessage(error),
        status: TranslationStatus.failed,
      );
    }
  }

  static String _lineErrorMessage(Object error) {
    if (error is SessionExpiredException) {
      return '로그인이 만료되었습니다.\n다시 로그인한 뒤 찍어 주세요.';
    }

    if (error is ApiException) {
      return error.message;
    }

    return '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
  }

  /// 서버 제한(줄 수·줄 길이·합계)에 맞게 줄을 고른다. 긴 줄은 자르고, 제한을 넘으면 그 뒤 줄은 뺀다.
  /// 두 번째 값은 보내지 못한 줄 수(빈 줄은 세지 않음).
  @visibleForTesting
  static (List<String>, int) linesForRequest(List<String> lines) {
    final selected = <String>[];
    var total = 0;
    var nonEmpty = 0;

    for (final raw in lines) {
      var line = raw.trim();

      if (line.isEmpty) {
        continue;
      }

      nonEmpty++;

      if (line.length > maxLineLength) {
        var end = maxLineLength;
        // 이모지처럼 두 단위로 된 문자를 반으로 자르지 않는다.
        final last = line.codeUnitAt(end - 1);
        if (last >= 0xD800 && last <= 0xDBFF) {
          end -= 1;
        }
        line = line.substring(0, end);
      }

      if (selected.length < maxLines &&
          total + line.length <= maxTotalCharacters &&
          selected.length == nonEmpty - 1) {
        selected.add(line);
        total += line.length;
      }
    }

    return (List<String>.unmodifiable(selected), nonEmpty - selected.length);
  }

  /// 지금 로그인돼 있는지(줄별 번역은 로그인이 필요하다).
  bool get _isSignedIn => ref.read(authProvider).isAuthenticated;

  void resetForRetake() {
    // 진행 중이던 인식·번역 결과가 다시 찍는 화면에 들어오지 않게 한다.
    _requestId++;
    _clearResult();
  }

  void _clearResult() {
    state = state.copyWith(
      clearSelectedImagePath: true,
      recognizedText: '',
      recognizedLines: const <String>[],
      translatedText: '',
      clearLineResult: true,
      omittedLineCount: 0,
      frameFallback: false,
      clearErrorMessage: true,
      status: TranslationStatus.cameraReady,
    );
  }
}

final translationProvider =
    NotifierProvider<TranslationNotifier, TranslationState>(
      TranslationNotifier.new,
    );
