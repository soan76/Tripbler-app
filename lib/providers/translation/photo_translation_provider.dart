import 'dart:async';
import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;

import '../../core/network/api_exception.dart';
import '../../domain/translation/photo_paragraphs.dart';
import '../../models/translation/photo_translation_result.dart';
import '../../repositories/auth/auth_exceptions.dart';
import '../../services/photo_consent_store.dart';
import '../../services/photo_normalizer.dart';
import '../../services/photo_translation_api_service.dart';
import '../auth/auth_provider.dart';
import 'photo_translation_state.dart';
import 'translation_provider.dart' show ocrServiceProvider;

export 'photo_translation_state.dart';

/// 선택한 사진을 기준 사진으로 정리한다.
final photoNormalizerProvider = Provider<PhotoNormalizer>(
  (ref) => PhotoNormalizer(),
);

/// 기준 사진을 임시로 저장할 폴더. 사진은 번역이 끝나거나 화면을 떠나면 지운다.
final photoOutputDirectoryProvider = Provider<String>(
  (ref) => Directory.systemTemp.path,
);

/// 사진 전송 동의 저장소.
final photoConsentStoreProvider = Provider<PhotoConsentStore>(
  (ref) => PhotoConsentStore(),
);

/// 사진 번역 API를 호출하는 서비스(로그인 필요).
final photoTranslationApiServiceProvider = Provider<PhotoTranslationApiService>(
  (ref) {
    final service = PhotoTranslationApiService();
    ref.onDispose(service.dispose);
    return service;
  },
);

// 사진 번역 화면 안내 문구.
const String _noTextMessage =
    '사진에서 번역할 글자를 찾지 못했습니다.\n글자가 선명하게 보이도록 다시 찍어 주세요.';
const String _unsupportedPhotoMessage = '이 사진은 읽을 수 없습니다.\n다른 사진을 골라 주세요.';
const String _prepareFailedMessage = '사진을 준비하는 중 문제가 발생했습니다.\n다시 찍어 주세요.';
const String _translateFailedMessage = '번역 중 문제가 발생했습니다.\n잠시 후 다시 시도해 주세요.';
const String _sessionChangedMessage = '로그인 상태가 바뀌었습니다.\n다시 찍어 주세요.';
const String _sessionExpiredMessage = '로그인이 만료되었습니다.\n다시 로그인한 뒤 찍어 주세요.';

/// 사진 번역 흐름: 사진 정리 → 글자 인식 → 문단 나누기 → (동의) → 업로드 → 결과.
///
/// 기준 사진은 이 Notifier가 소유한다. 다시 찍기·취소·화면 이탈·새 사진·정리 때 지운다.
class PhotoTranslationNotifier extends Notifier<PhotoTranslationState> {
  /// 가장 최근에 시작한 작업 번호. 늦게 끝난 이전 작업은 번호가 달라 결과를 반영하지 않는다.
  int _requestId = 0;

  /// 지금 소유한 기준 사진. 상태와 따로 두어 정리 뒤에도 지울 수 있게 한다.
  NormalizedPhoto? _photo;

  /// 정리 뒤(`ref`를 쓸 수 없을 때)에도 사진을 지울 수 있게 미리 받아 둔다.
  late PhotoNormalizer _normalizer;

  @override
  PhotoTranslationState build() {
    _normalizer = ref.read(photoNormalizerProvider);
    // 로그인 세션이 바뀌면(로그인·로그아웃·계정 전환) 이전 세션의 사진·문단·결과를 비운다.
    ref.listen(authProvider, (previous, next) {
      if (previous != null && previous.sessionId != next.sessionId) {
        _requestId++;
        _releasePhoto();
        state = state.reset();
      }
    });
    ref.onDispose(() {
      _requestId++;
      _releasePhoto();
    });
    return const PhotoTranslationState();
  }

  /// [requestId]가 아직 가장 최근 작업이고 상태 객체가 살아 있는지.
  bool _isCurrent(int requestId) => ref.mounted && requestId == _requestId;

  /// 소유한 기준 사진을 지운다. 없으면 아무것도 하지 않는다.
  void _releasePhoto() {
    final photo = _photo;
    _photo = null;
    if (photo != null) {
      unawaited(_normalizer.delete(photo));
    }
  }

  /// 사진을 정리하고 글자를 읽어 문단으로 나눈다. 동의가 유효하면 바로 보내고, 아니면 동의를 기다린다.
  Future<void> processPhoto(String sourcePath) async {
    final requestId = ++_requestId;
    _releasePhoto();
    state = state.reset(status: PhotoTranslationStatus.preparing);

    final NormalizedPhoto photo;
    try {
      photo = await _normalizer.normalize(
        sourcePath: sourcePath,
        outputDirectory: ref.read(photoOutputDirectoryProvider),
      );
    } on UnsupportedPhotoException {
      if (_isCurrent(requestId)) {
        state = state.reset(
          status: PhotoTranslationStatus.unsupportedPhoto,
          errorMessage: _unsupportedPhotoMessage,
        );
      }
      return;
    } catch (error) {
      debugPrint('사진 정리 실패: ${error.runtimeType}');
      if (_isCurrent(requestId)) {
        state = state.reset(
          status: PhotoTranslationStatus.failed,
          errorMessage: _prepareFailedMessage,
        );
      }
      return;
    }

    if (!_isCurrent(requestId)) {
      // 버려진 작업이 만든 사진은 아무도 소유하지 않으므로 여기서 지운다.
      unawaited(_normalizer.delete(photo));
      return;
    }
    _photo = photo;
    state = state.copyWith(photo: photo);

    final ({List<OcrParagraph> paragraphs, int omitted}) ocr;
    try {
      final lines = await ref
          .read(ocrServiceProvider)
          .recognizeTextLines(
            imagePath: photo.path,
            sourceLanguageCode: state.sourceLanguageCode,
          );
      if (!_isCurrent(requestId)) {
        return;
      }
      ocr = toOcrParagraphs(lines);
    } catch (error) {
      debugPrint('사진 글자 인식 실패: ${error.runtimeType}');
      if (_isCurrent(requestId)) {
        _releasePhoto();
        state = state.reset(
          status: PhotoTranslationStatus.failed,
          errorMessage: _prepareFailedMessage,
        );
      }
      return;
    }

    if (ocr.paragraphs.isEmpty) {
      _releasePhoto();
      state = state.reset(
        status: PhotoTranslationStatus.noText,
        errorMessage: _noTextMessage,
      );
      return;
    }

    state = state.copyWith(
      paragraphs: List<OcrParagraph>.unmodifiable(ocr.paragraphs),
      omittedCount: ocr.omitted,
    );

    if (_keepsOriginal) {
      // 원문 언어와 번역 언어가 같으면 서버에 보내지 않고 동의도 묻지 않는다.
      state = state.copyWith(
        result: _originalResult(),
        status: PhotoTranslationStatus.completed,
      );
      return;
    }

    final bool consented;
    try {
      consented = await ref.read(photoConsentStoreProvider).hasValidConsent();
    } catch (_) {
      if (_isCurrent(requestId)) {
        state = state.copyWith(status: PhotoTranslationStatus.awaitingConsent);
      }
      return;
    }
    if (!_isCurrent(requestId)) {
      return;
    }

    if (!consented) {
      state = state.copyWith(status: PhotoTranslationStatus.awaitingConsent);
      return;
    }

    await _upload(requestId);
  }

  /// 동의를 기록하고 업로드한다. 동의를 기다릴 때만 동작하며, 겹친 두 번째 호출은 무시한다.
  Future<void> acceptConsentAndTranslate() async {
    if (state.status != PhotoTranslationStatus.awaitingConsent) {
      return;
    }
    final requestId = _requestId;
    // 첫 await 전에 상태를 바꿔 두 번째 호출이 위 확인에서 걸러지게 한다.
    state = state.copyWith(
      status: PhotoTranslationStatus.uploading,
      clearErrorMessage: true,
    );

    try {
      await ref.read(photoConsentStoreProvider).accept();
    } catch (error) {
      // 사용자는 이번에 동의했다. 저장에 실패하면 다음에 다시 물을 뿐이므로 이번 전송은 진행한다.
      debugPrint('사진 전송 동의 저장 실패: ${error.runtimeType}');
    }
    if (!_isCurrent(requestId)) {
      return;
    }

    await _upload(requestId);
  }

  /// 동의를 거절했다. 임시 사진을 지우고 처음으로 돌아간다. 아무것도 보내지 않는다.
  void cancelConsent() {
    _requestId++;
    _releasePhoto();
    state = state.reset();
  }

  /// 실패한 업로드를 같은 기준 사진·같은 문단으로 다시 보낸다. 동의는 다시 묻지 않는다.
  Future<void> retry() async {
    if (state.status != PhotoTranslationStatus.failed ||
        state.photo == null ||
        state.paragraphs.isEmpty) {
      return;
    }
    final requestId = ++_requestId;
    await _upload(requestId);
  }

  /// 진행 중인 작업을 버리고 임시 사진을 지운 뒤 처음으로 돌아간다.
  void retake() {
    _requestId++;
    _releasePhoto();
    state = state.reset();
  }

  /// 화면을 떠난다. 진행 중인 작업을 버리고 임시 사진을 지운다.
  void leave() => retake();

  void toggleOriginal() {
    state = state.copyWith(showOriginal: !state.showOriginal);
  }

  /// 다음 사진부터 적용한다.
  void changeSourceLanguage(String languageCode) {
    if (state.sourceLanguageCode != languageCode) {
      state = state.copyWith(sourceLanguageCode: languageCode);
    }
  }

  /// 다음 사진부터 적용한다.
  void changeTargetLanguage(String languageCode) {
    if (state.targetLanguageCode != languageCode) {
      state = state.copyWith(targetLanguageCode: languageCode);
    }
  }

  bool get _keepsOriginal =>
      state.sourceLanguageCode != 'auto' &&
      state.sourceLanguageCode == state.targetLanguageCode;

  PhotoTranslationResult _originalResult() {
    return PhotoTranslationResult(
      sourceLanguageCode: state.sourceLanguageCode,
      targetLanguageCode: state.targetLanguageCode,
      paragraphs: List<TranslatedParagraph>.unmodifiable(
        state.paragraphs.map(
          (paragraph) => TranslatedParagraph(
            id: paragraph.id,
            original: paragraph.text,
            translated: paragraph.text,
            uncertain: false,
            source: PhotoTranslationSource.original,
          ),
        ),
      ),
    );
  }

  /// 상태의 기준 사진과 문단을 보낸다. [requestId]는 호출부가 정한 작업 번호.
  Future<void> _upload(int requestId) async {
    final photo = state.photo!;
    final paragraphs = state.paragraphs;
    final source = state.sourceLanguageCode;
    final target = state.targetLanguageCode;

    state = state.copyWith(
      status: PhotoTranslationStatus.uploading,
      clearResult: true,
      clearErrorMessage: true,
    );

    try {
      final service = ref.read(photoTranslationApiServiceProvider);
      final result = await ref.read(authorizedRequestRunnerProvider)(
        (authorizationHeader) => service.translate(
          photo: photo,
          paragraphs: paragraphs,
          sourceLanguageCode: source,
          targetLanguageCode: target,
          authorizationHeader: authorizationHeader,
        ),
      );

      if (!_isCurrent(requestId)) {
        return;
      }

      state = state.copyWith(
        result: result,
        showOriginal: false,
        status: PhotoTranslationStatus.completed,
      );
    } catch (error) {
      debugPrint('사진 번역 실패: ${error.runtimeType}');

      if (!_isCurrent(requestId)) {
        return;
      }

      state = state.copyWith(
        errorMessage: _errorMessage(error),
        status: PhotoTranslationStatus.failed,
      );
    }
  }

  static String _errorMessage(Object error) {
    if (error is SessionChangedException) {
      return _sessionChangedMessage;
    }
    if (error is SessionExpiredException) {
      return _sessionExpiredMessage;
    }
    if (error is ApiException) {
      return error.message;
    }
    return _translateFailedMessage;
  }
}

final photoTranslationProvider =
    NotifierProvider<PhotoTranslationNotifier, PhotoTranslationState>(
      PhotoTranslationNotifier.new,
    );
