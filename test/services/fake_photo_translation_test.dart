import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/services/fake_photo_translation.dart';

// 개발용 가짜 번역: 실제 OCR 문단 ID마다 가짜 결과를 붙이고, 모든 번역에 가짜 표시를 단다.
void main() {
  OcrParagraph paragraph(String id, String text) => OcrParagraph(
    id: id,
    text: text,
    box: const Rect.fromLTWH(10, 10, 100, 20),
    lineCount: 1,
  );

  final paragraphs = [
    paragraph('p1', '醤油ラーメン 980円'),
    paragraph('p2', '味噌ラーメン 1,050円'),
    paragraph('p3', '営業時間'),
    paragraph('p4', '定休日'),
    paragraph('p5', '餃子 450円'),
  ];

  PhotoTranslationResult build() => buildFakePhotoTranslation(
    paragraphs: paragraphs,
    sourceLanguageCode: 'ja',
    targetLanguageCode: 'ko',
    now: DateTime(2026, 11, 26, 12),
  );

  test('fakeResult_coversEveryOcrIdInOrder_andIsMarkedSimulated', () {
    final result = build();

    expect(result.simulated, isTrue);
    expect(result.paragraphs.map((p) => p.id), ['p1', 'p2', 'p3', 'p4', 'p5']);
    expect(result.sourceLanguageCode, 'ja');
    expect(result.targetLanguageCode, 'ko');
    for (final translated in result.paragraphs) {
      expect(translated.translated, startsWith(fakeTranslationPrefix));
      expect(translated.translated, contains(translated.id));
    }
    // 원문은 기기에서 읽은 글자 그대로다.
    expect(result.paragraphs.first.original, '醤油ラーメン 980円');
  });

  test('fakeResult_variesShapes_forLayoutChecks', () {
    final result = build().paragraphs;

    // 두 번째는 상자보다 긴 번역이다.
    expect(result[1].translated.length, greaterThan(40));
    // 네 번째는 읽을 수 없음 표시와 불확실.
    expect(result[3].uncertain, isTrue);
    expect(result[3].translated, contains(unreadableMarker));
    // 다섯 번째는 대체 번역이고 발음이 없다.
    expect(result[4].source, PhotoTranslationSource.ocrText);
    expect(result[4].pronunciation, isNull);
    expect(result[0].source, PhotoTranslationSource.ai);
    expect(result[0].pronunciation, startsWith(fakeTranslationPrefix));
  });

  test('fakePrices_confirmedOnEven_unconfirmedOnOdd_noneWithoutDigits', () {
    final result = build().paragraphs;

    final confirmed = result[0].prices.single;
    expect(confirmed.confirmed, isTrue);
    expect(confirmed.amount, 980);
    expect(confirmed.krwAmount, closeTo(9310, 0.001));

    final unconfirmed = result[1].prices.single;
    expect(unconfirmed.confirmed, isFalse);
    expect(unconfirmed.amount, 1050);
    expect(unconfirmed.krwAmount, isNull);

    expect(result[2].prices, isEmpty);
  });

  test('serverResult_isNeverSimulated', () {
    final result = PhotoTranslationResult.fromJson({
      'sourceLanguageCode': 'ja',
      'targetLanguageCode': 'ko',
      'paragraphs': <Object>[],
    }, requestedIds: const {});

    expect(result.simulated, isFalse);
  });
}
