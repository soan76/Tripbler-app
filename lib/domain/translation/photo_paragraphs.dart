import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show immutable;

import 'text_paragraphs.dart';

// 사진 번역 요청에 실을 문단 목록을 만든다(순수 계산).
//
// - 문단마다 `p1`, `p2`… 형식의 ID를 붙인다. 서버는 `^p[0-9]{1,3}$`만 받는다.
// - 서버가 읽을 수 없는 문단에 돌려주는 표시 문구는 [unreadableMarker]와 같아야 한다.

/// 번역할 수 없는 문단에 서버가 넣는 표시 문구. 서버 계약과 같아야 한다.
const String unreadableMarker = '[읽을 수 없음]';

/// 사진 번역 요청 한도. 실제 Claude 측정(작업 14) 뒤 확정한다.
abstract final class PhotoParagraphLimits {
  // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
  static const int maxParagraphs = 50;

  // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
  static const int maxParagraphLength = 300;

  // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
  static const int maxTotalCharacters = 4000;
}

/// ID가 붙은 번역 단위 하나. [box]는 화면에 원문 위치를 그릴 때 쓴다.
@immutable
class OcrParagraph {
  const OcrParagraph({required this.id, required this.text, required this.box});

  final String id;
  final String text;
  final Rect box;

  @override
  bool operator ==(Object other) =>
      other is OcrParagraph &&
      other.id == id &&
      other.text == text &&
      other.box == box;

  @override
  int get hashCode => Object.hash(id, text, box);

  @override
  String toString() => 'OcrParagraph(id: $id, text: $text, box: $box)';
}

/// 줄 목록을 문단으로 나누고 ID를 붙인다. [omitted]는 한도 때문에 뺀 문단 수다.
///
/// - 결과는 위에서 아래, 왼쪽에서 오른쪽 순서다.
/// - 문단은 [PhotoParagraphLimits.maxParagraphLength]자에서 자른다.
/// - 문단 수나 전체 글자 수가 한도를 넘으면 앞에서부터 한도까지만 담는다.
({List<OcrParagraph> paragraphs, int omitted}) toOcrParagraphs(
  List<RecognizedTextLine> lines,
) {
  final units = buildTextParagraphs(lines);
  final paragraphs = <OcrParagraph>[];
  var totalCharacters = 0;

  for (final unit in units) {
    if (paragraphs.length >= PhotoParagraphLimits.maxParagraphs) {
      break;
    }
    final text = _truncate(unit.text, PhotoParagraphLimits.maxParagraphLength);
    if (totalCharacters + text.length >
        PhotoParagraphLimits.maxTotalCharacters) {
      break;
    }
    totalCharacters += text.length;
    paragraphs.add(
      OcrParagraph(id: 'p${paragraphs.length + 1}', text: text, box: unit.box),
    );
  }

  return (paragraphs: paragraphs, omitted: units.length - paragraphs.length);
}

String _truncate(String text, int maxLength) =>
    text.length <= maxLength ? text : text.substring(0, maxLength);
