import 'dart:io' show Directory;

import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../../domain/translation/photo_text_translation.dart'
    show translateParagraphText;
import '../../services/fake_photo_translation.dart';
import '../../services/photo_consent_store.dart';
import '../../services/photo_normalizer.dart';
import '../../services/photo_translation_api_service.dart';

/// 사진 번역 흐름이 쓰는 서비스·설정. 테스트에서 override한다.

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

/// 개발용 가짜 번역을 쓸지. 릴리스 빌드에서는 항상 false다([photoFakeTranslationEnabled]).
final photoFakeTranslationProvider = Provider<bool>(
  (ref) => photoFakeTranslationEnabled,
);

/// 사진을 서버 AI로 보내 번역할지(`--dart-define=TRIPBLER_PHOTO_TRANSLATION=true`).
///
/// false(기본)면 사진은 보내지 않고 기기에서 읽은 글자만 번역해 흰 상자에 붙인다
/// ([translateParagraphText]). 나중에 Gemini 사진 번역을 붙이면 기본을 바꾼다.
/// 설계: docs/superpowers/specs/2026-11-27-device-photo-translation-design.md
final photoAiTranslationProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('TRIPBLER_PHOTO_TRANSLATION'),
);

/// 가짜 번역이 끝나기까지 기다리는 시간. 전송 중 화면을 잠깐 보여 주려고 둔다.
final photoFakeTranslationDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 700),
);
