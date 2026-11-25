import 'package:flutter/foundation.dart' show immutable;

import '../../domain/translation/photo_paragraphs.dart';
import '../../models/translation/photo_translation_result.dart';
import '../../services/photo_normalizer.dart';

/// 사진 번역 진행 단계.
enum PhotoTranslationStatus {
  /// 사진을 고르기 전(또는 다시 찍기·취소 뒤).
  idle,

  /// 사진 정리와 글자 인식 중.
  preparing,

  /// 사진 전송 동의를 기다린다. 아직 아무것도 보내지 않았다.
  awaitingConsent,

  /// 사진과 문단을 서버로 보내 번역 중.
  uploading,
  completed,

  /// 사진에서 글자를 찾지 못했다.
  noText,

  /// 읽을 수 없는 사진(지원하지 않는 형식, 손상된 파일).
  unsupportedPhoto,
  failed,
}

@immutable
class PhotoTranslationState {
  const PhotoTranslationState({
    this.status = PhotoTranslationStatus.idle,
    this.photo,
    this.paragraphs = const <OcrParagraph>[],
    this.omittedCount = 0,
    this.result,
    this.showOriginal = false,
    this.errorMessage,
    this.canRetry = false,
    this.sourceLanguageCode = 'auto',
    this.targetLanguageCode = 'ko',
  });

  final PhotoTranslationStatus status;

  /// 정리한 기준 사진. 화면 표시·업로드·다시 시도가 모두 이 사진을 쓴다.
  final NormalizedPhoto? photo;

  /// 서버에 보낼(보낸) 문단.
  final List<OcrParagraph> paragraphs;

  /// 한도 때문에 요청에서 뺀 문단 수.
  final int omittedCount;
  final PhotoTranslationResult? result;

  /// 번역 대신 원문을 보여 줄지.
  final bool showOriginal;
  final String? errorMessage;

  /// 실패한 업로드를 같은 사진으로 다시 보내 볼 만한지. 연결 실패·429·5xx처럼 잠시 뒤 나아질 수 있는
  /// 실패일 때만 true다. 잘못된 요청(400·413)이나 로그인 문제는 다시 보내도 같으므로 false다.
  final bool canRetry;
  final String sourceLanguageCode;
  final String targetLanguageCode;

  /// 언어 선택만 남기고 사진·문단·결과·오류를 비운 상태.
  PhotoTranslationState reset({
    PhotoTranslationStatus status = PhotoTranslationStatus.idle,
    String? errorMessage,
  }) {
    return PhotoTranslationState(
      status: status,
      errorMessage: errorMessage,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );
  }

  PhotoTranslationState copyWith({
    PhotoTranslationStatus? status,
    NormalizedPhoto? photo,
    bool clearPhoto = false,
    List<OcrParagraph>? paragraphs,
    int? omittedCount,
    PhotoTranslationResult? result,
    bool clearResult = false,
    bool? showOriginal,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? canRetry,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) {
    return PhotoTranslationState(
      status: status ?? this.status,
      photo: clearPhoto ? null : photo ?? this.photo,
      paragraphs: paragraphs ?? this.paragraphs,
      omittedCount: omittedCount ?? this.omittedCount,
      result: clearResult ? null : result ?? this.result,
      showOriginal: showOriginal ?? this.showOriginal,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      canRetry: canRetry ?? this.canRetry,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
    );
  }
}
