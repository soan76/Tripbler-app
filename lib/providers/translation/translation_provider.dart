import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../../core/network/api_exception.dart';
import '../../domain/translation/line_request_limits.dart';
import '../../models/translation/line_translation_result.dart';
import '../../repositories/auth/auth_exceptions.dart';
import '../../services/line_translation_api_service.dart';
import '../../services/translation_service.dart';
import '../auth/auth_provider.dart';
import '../ocr_provider.dart';
import 'translation_state.dart';

// 기존 사용처·테스트가 이 파일에서 가져가므로 같은 이름으로 다시 내보낸다.
export '../ocr_provider.dart' show ocrServiceProvider;
export 'translation_state.dart';

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

// 번역 화면 안내 문구.
const String _emptyInFrameMessage =
    '프레임 안에서 번역할 문자를 찾지 못했습니다.\n번역할 글자를 프레임 안에 맞춰 다시 촬영해 주세요.';
const String _emptyInImageMessage =
    '이미지에서 번역할 문자를 찾지 못했습니다.\n문자가 선명하게 보이도록 다시 촬영해 주세요.';
const String _ocrFailedMessage = '문자 인식 중 문제가 발생했습니다.\n이미지를 다시 촬영해 주세요.';
const String _translateFailedMessage = '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
const String _sessionChangedMessage = '로그인 상태가 바뀌었습니다.\n다시 찍어 주세요.';
const String _sessionExpiredMessage = '로그인이 만료되었습니다.\n다시 로그인한 뒤 찍어 주세요.';
const String _lineTranslateFailedMessage = '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';

class TranslationNotifier extends Notifier<TranslationState> {
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

    if (!state.showsResult) {
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

    _applyLanguages(languageCode, state.targetLanguageCode);
  }

  void changeTargetLanguage(String languageCode) {
    if (state.targetLanguageCode == languageCode) {
      return;
    }

    _applyLanguages(state.sourceLanguageCode, languageCode);
  }

  /// 원문이 자동 감지면 바꾸지 않는다. 두 언어가 같아도 바꾸고 다시 번역한다.
  void swapLanguages() {
    if (state.sourceLanguageCode == 'auto') {
      return;
    }

    _applyLanguages(state.targetLanguageCode, state.sourceLanguageCode);
  }

  /// 두 언어를 반영하고 번역 결과만 비운 뒤, 읽은 원문이 있으면 다시 번역한다.
  ///
  /// 원문·줄 목록·생략 줄 수·프레임 안내·오류는 그대로 둔다(원문을 지우면 다시 번역할 수 없다).
  void _applyLanguages(String sourceLanguageCode, String targetLanguageCode) {
    state = state.copyWith(
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
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

    state = state.withoutResult().copyWith(
      selectedImagePath: imagePath,
      status: TranslationStatus.recognizing,
    );

    try {
      debugPrint('=== OCR 시작 ===');

      final recognized = await _recognize(
        imagePath,
        fromCamera: fromCamera,
        cameraPreviewAspect: cameraPreviewAspect,
      );

      if (!_isCurrent(requestId)) {
        return;
      }

      debugPrint('=== OCR 완료 ===');

      final text = recognized.text;

      if (text.trim().isEmpty) {
        state = state.copyWith(
          recognizedText: '',
          translatedText: '',
          errorMessage: recognized.frameApplied
              ? _emptyInFrameMessage
              : _emptyInImageMessage,
          status: TranslationStatus.failed,
        );
        return;
      }

      state = state.copyWith(
        recognizedText: text.trim(),
        recognizedLines: recognized.lines,
        frameFallback: fromCamera && !recognized.frameApplied,
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
        errorMessage: _ocrFailedMessage,
        status: TranslationStatus.failed,
      );
    }
  }

  /// 사진의 글자를 읽는다. 상태는 바꾸지 않는다.
  ///
  /// 로그인했으면 줄 단위로 읽어 줄별 번역(발음·가격)을 쓰고, 아니면 통번역을 쓴다.
  /// 줄별 번역 API는 로그인이 필요하다. `lines`는 줄별 번역에 쓸 줄이고 통번역이면 비어 있다.
  Future<({String text, List<String> lines, bool frameApplied})> _recognize(
    String imagePath, {
    required bool fromCamera,
    double? cameraPreviewAspect,
  }) async {
    final ocr = ref.read(ocrServiceProvider);
    final useFrame = fromCamera && cameraPreviewAspect != null;

    if (_isSignedIn || useFrame) {
      final result = await ocr.recognizeLines(
        imagePath: imagePath,
        sourceLanguageCode: state.sourceLanguageCode,
        onlyInCaptureFrame: useFrame,
        cameraPreviewAspect: cameraPreviewAspect,
      );
      var lines = const <String>[];
      // 로그인하지 않았으면(통번역) 줄을 `\n`으로 이어 쓴다. ML Kit의 전체 글자(`recognizeText`)도
      // 덩어리 안 줄과 덩어리 사이를 모두 `\n`으로 잇기 때문에 통번역에 보내는 형식이 같다.
      // 줄 목록을 남길지는 인식이 끝난 뒤의 로그인 상태로 정한다.
      if (_isSignedIn) {
        lines = result.lines;
      }
      return (
        text: result.lines.join('\n'),
        lines: lines,
        frameApplied: result.frameApplied,
      );
    }

    final text = await ocr.recognizeText(
      imagePath: imagePath,
      sourceLanguageCode: state.sourceLanguageCode,
    );
    return (text: text, lines: const <String>[], frameApplied: false);
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

    await _translateWhole(requestId);
  }

  /// 통번역. [requestId]는 [translateRecognizedText]가 올린 번호.
  Future<void> _translateWhole(int requestId) async {
    final text = state.recognizedText.trim();

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
        errorMessage: _translateFailedMessage,
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
          errorMessage: _sessionChangedMessage,
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
      return _sessionExpiredMessage;
    }

    if (error is ApiException) {
      return error.message;
    }

    return _lineTranslateFailedMessage;
  }

  /// 지금 로그인돼 있는지(줄별 번역은 로그인이 필요하다).
  bool get _isSignedIn => ref.read(authProvider).isAuthenticated;

  void resetForRetake() {
    // 진행 중이던 인식·번역 결과가 다시 찍는 화면에 들어오지 않게 한다.
    _requestId++;
    _clearResult();
  }

  void _clearResult() {
    state = state.withoutResult().copyWith(
      clearSelectedImagePath: true,
      status: TranslationStatus.cameraReady,
    );
  }
}

final translationProvider =
    NotifierProvider<TranslationNotifier, TranslationState>(
      TranslationNotifier.new,
    );
