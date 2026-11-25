import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/text_paragraphs.dart';

// 인식한 줄을 번역 단위(문단·항목)로 나누기(순수 계산).
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

  group('buildTextParagraphs', () {
    test('같은 덩어리에서 줄이 차서 넘어간 본문 줄은 문단 하나로 묶는다', () {
      final units = buildTextParagraphs([
        line('Please keep your ticket until', 100),
        line('you leave the station.', 124, width: 150),
      ]);

      expect(units, hasLength(1));
      expect(
        units.single.text,
        'Please keep your ticket until you leave the station.',
      );
      expect(units.single.lineCount, 2);
      expect(units.single.box, const Rect.fromLTRB(10, 100, 210, 144));
    });

    test('일본어·중국어 줄은 공백 없이 잇는다', () {
      final units = buildTextParagraphs([
        line('ご来店ありがとうございます。また', 100),
        line('のお越しをお待ちしております。', 124),
      ]);
      expect(units.single.text, 'ご来店ありがとうございます。またのお越しをお待ちしております。');
    });

    test('선택지·목록 표시와 가격이 붙은 짧은 줄은 따로 둔다', () {
      final units = buildTextParagraphs([
        line('Which of the following is true about', 100),
        line('(A) The store opens at nine', 124),
        line('B. It is closed on Sundays', 148),
        line('1. Coffee', 172),
        line('Ramen ¥980', 196),
      ]);
      expect(units.map((unit) => unit.text), [
        'Which of the following is true about',
        '(A) The store opens at nine',
        'B. It is closed on Sundays',
        '1. Coffee',
        'Ramen ¥980',
      ]);
    });

    test('짧은 메뉴 이름, 다른 덩어리, 크게 떨어진 줄은 묶지 않는다', () {
      final units = buildTextParagraphs([
        line('Coffee', 100, width: 60),
        line('Tea', 124, width: 40),
        line('Please keep your ticket until', 200, block: 1),
        line('you leave the station.', 224, block: 2),
        line('This line is long enough to join', 300, block: 3),
        line('but it is far below.', 400, block: 3),
      ]);
      expect(units, hasLength(6));
    });

    test('영어 줄 끝의 하이픈은 지우고 붙인다', () {
      expect(
        joinRecognizedLines(['This is infor-', 'mation.']),
        'This is information.',
      );
    });
  });
}
