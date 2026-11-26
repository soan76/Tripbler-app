import 'package:flutter/foundation.dart' show kReleaseMode;

import '../domain/translation/photo_paragraphs.dart';
import '../models/translation/photo_translation_result.dart';

/// 개발용 가짜 사진 번역을 켤지.
///
/// `--dart-define=TRIPBLER_PHOTO_FAKE_TRANSLATION=true`로 빌드한 디버그·프로필 빌드에서만 켜진다.
/// 릴리스 빌드에서는 값과 상관없이 꺼진다(`kReleaseMode`가 상수라 가짜 경로가 빌드에서 빠진다).
/// 켜지면 사진과 글자를 어디에도 보내지 않고, 기기에서 읽은 문단 ID에 가짜 번역을 붙인다.
/// 결과 상자·좌표·확대·이동·상세 화면을 서버 없이 실기기에서 확인하기 위한 것이다.
const bool photoFakeTranslationEnabled =
    !kReleaseMode && bool.fromEnvironment('TRIPBLER_PHOTO_FAKE_TRANSLATION');

/// 가짜 번역 결과의 앞머리. 상자를 확대해 잘라 봐도 가짜임을 알 수 있게 모든 번역에 붙인다.
const String fakeTranslationPrefix = '[가짜]';

/// 가짜 원화 환율(1 단위당 원). 실제 환율이 아니다.
const double _fakeKrwRate = 9.5;

final RegExp _number = RegExp(r'\d[\d,]*(?:\.\d+)?');

/// [paragraphs]의 ID마다 가짜 번역을 만든다. 실제 번역이 아니며 외부 호출이 없다.
///
/// 화면 확인을 위해 문단 순서에 따라 모양을 바꾼다.
/// - 짧은 번역, 상자보다 긴 번역(줄바꿈·말줄임), 원문 길이를 적은 번역을 돌아가며 쓴다.
/// - 네 번째 문단마다 [unreadableMarker]를 넣고 불확실로 표시한다.
/// - 다섯 번째 문단마다 대체 번역(OCR 글자만으로 번역)으로 표시하고 발음을 뺀다.
/// - 원문에 숫자가 있으면 가짜 가격을 붙인다. 짝수 번째는 확정·원화 환산, 홀수 번째는 미확정이다.
PhotoTranslationResult buildFakePhotoTranslation({
  required List<OcrParagraph> paragraphs,
  required String sourceLanguageCode,
  required String targetLanguageCode,
  DateTime? now,
}) {
  final fetchedAt = now ?? DateTime.now();

  return PhotoTranslationResult(
    sourceLanguageCode: sourceLanguageCode,
    targetLanguageCode: targetLanguageCode,
    simulated: true,
    paragraphs: List<TranslatedParagraph>.unmodifiable([
      for (var index = 0; index < paragraphs.length; index++)
        _fakeParagraph(paragraphs[index], index, fetchedAt),
    ]),
  );
}

TranslatedParagraph _fakeParagraph(
  OcrParagraph paragraph,
  int index,
  DateTime fetchedAt,
) {
  final id = paragraph.id;
  final uncertain = index % 4 == 3;
  final fallback = index % 5 == 4;

  final translated = switch (index % 4) {
    0 => '$fakeTranslationPrefix $id 번역',
    1 =>
      '$fakeTranslationPrefix $id 긴 번역 문장입니다. 상자 안 줄바꿈과 말줄임, '
          '확대했을 때 글자 위치를 확인하려고 일부러 길게 만들었습니다.',
    2 => '$fakeTranslationPrefix $id 원문 ${paragraph.text.length}자',
    _ => '$fakeTranslationPrefix $id $unreadableMarker 표시 확인',
  };

  return TranslatedParagraph(
    id: id,
    original: paragraph.text,
    translated: translated,
    uncertain: uncertain,
    source: fallback
        ? PhotoTranslationSource.ocrText
        : PhotoTranslationSource.ai,
    pronunciation: fallback ? null : '$fakeTranslationPrefix 발음 $id',
    prices: _fakePrices(paragraph.text, index, fetchedAt),
  );
}

List<PhotoPrice> _fakePrices(String text, int index, DateTime fetchedAt) {
  final match = _number.firstMatch(text);

  if (match == null) {
    return const <PhotoPrice>[];
  }

  final amount = double.tryParse(match.group(0)!.replaceAll(',', ''));

  if (amount == null) {
    return const <PhotoPrice>[];
  }

  if (index.isOdd) {
    return [
      PhotoPrice(
        text: match.group(0)!,
        amount: amount,
        currency: null,
        confirmed: false,
      ),
    ];
  }

  return [
    PhotoPrice(
      text: match.group(0)!,
      amount: amount,
      currency: 'JPY',
      confirmed: true,
      krwAmount: amount * _fakeKrwRate,
      krwRate: _fakeKrwRate,
      rateFetchedAt: fetchedAt,
    ),
  ];
}
