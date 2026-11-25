import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/domain/translation/text_paragraphs.dart';

// 사진 번역용 문단 ID 부여와 한도(순수 계산).
void main() {
  RecognizedTextLine line(
    String text,
    double top, {
    double left = 10,
    double width = 200,
    double height = 20,
    int block = 0,
  }) =>
      (text: text, box: Rect.fromLTWH(left, top, width, height), block: block);

  group('toOcrParagraphs', () {
    test('assignsIdsInReadingOrder', () {
      final result = toOcrParagraphs([
        line('아래 문단', 300, block: 2),
        line('위 문단', 10, block: 1),
      ]);

      expect(result.omitted, 0);
      expect(result.paragraphs.map((p) => p.id), ['p1', 'p2']);
      expect(result.paragraphs[0].text, '위 문단');
      expect(result.paragraphs[1].text, '아래 문단');
    });

    test('emptyLines_returnsEmpty', () {
      final result = toOcrParagraphs(const []);

      expect(result.paragraphs, isEmpty);
      expect(result.omitted, 0);
    });

    test('over50Paragraphs_keeps50AndCountsOmitted', () {
      final lines = [
        for (var i = 0; i < 55; i++) line('문단 $i', i * 100.0, block: i),
      ];

      final result = toOcrParagraphs(lines);

      expect(result.paragraphs, hasLength(50));
      expect(result.omitted, 5);
      expect(result.paragraphs.first.id, 'p1');
      expect(result.paragraphs.last.id, 'p50');
    });

    test('totalOver4000_stopsBeforeLimit', () {
      // 300자 문단 14개 = 4200자. 앞에서 13개(3900자)까지만 담는다.
      final body = 'a' * 300;
      final lines = [
        for (var i = 0; i < 14; i++) line(body, i * 100.0, block: i),
      ];

      final result = toOcrParagraphs(lines);

      expect(result.paragraphs, hasLength(13));
      expect(result.omitted, 1);
      final total = result.paragraphs.fold<int>(
        0,
        (sum, p) => sum + p.text.length,
      );
      expect(total, lessThanOrEqualTo(PhotoParagraphLimits.maxTotalCharacters));
    });

    test('longParagraph_truncatedTo300', () {
      final result = toOcrParagraphs([line('가' * 350, 0)]);

      expect(result.paragraphs, hasLength(1));
      expect(result.paragraphs.single.text.length, 300);
      expect(result.omitted, 0);
    });

    test('keepsBoxOfParagraph', () {
      final result = toOcrParagraphs([line('짧은 문단', 40, left: 15)]);

      expect(result.paragraphs.single.box, Rect.fromLTWH(15, 40, 200, 20));
    });

    test('ocrParagraph_equalityUsesAllFields', () {
      final a = OcrParagraph(
        id: 'p1',
        text: '문단',
        box: Rect.fromLTWH(0, 0, 10, 10),
      );
      final same = OcrParagraph(
        id: 'p1',
        text: '문단',
        box: Rect.fromLTWH(0, 0, 10, 10),
      );
      final other = OcrParagraph(
        id: 'p2',
        text: '문단',
        box: Rect.fromLTWH(0, 0, 10, 10),
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(other));
    });

    test('unreadableMarkerMatchesServer', () {
      expect(unreadableMarker, '[읽을 수 없음]');
    });
  });
}
