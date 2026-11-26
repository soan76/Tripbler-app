import 'dart:math' as math;
import 'dart:ui' show Rect;

// OCR로 인식한 줄을 번역 단위(문단·항목)로 나누는 순수 계산.
//
// - 본문은 같은 글 덩어리(ML Kit TextBlock) 안에서 이어지는 줄을 문단 하나로 묶는다.
// - 선택지·목록 표시(`(A)`, `A.`, `1.`, `•`)로 시작하는 줄과 가격·숫자가 붙은 짧은 줄은 줄마다 따로 둔다.
//
// 실시간 번역(제거됨)에서 쓰던 코드로, 찍은 사진의 문단별 원문·좌표 추출에 쓰려고 남겨 두었다.
// 아직 앱에서 부르는 곳은 없다.

/// 인식한 줄 하나. [block]은 같은 글 덩어리 번호(같으면 문단으로 묶을 수 있다).
typedef RecognizedTextLine = ({String text, Rect box, int block});

/// 번역 단위 하나(문단 또는 항목). [box]는 줄 상자를 모두 감싼 영역이다.
typedef TextParagraph = ({String text, Rect box, int lineCount});

/// 문단 하나에 묶을 최대 줄 수와 글자 수(번역 지연을 묶어 둔다).
const int maxParagraphLines = 8;
const int maxParagraphLength = 300;

final RegExp _markerPattern = RegExp(
  r'^\s*(?:'
  r'\(\s*[A-Za-z0-9０-９]{1,2}\s*\)|（\s*[A-Za-z0-9０-９]{1,2}\s*）'
  r'|[A-Za-zＡ-Ｚ][.．)）](?=\s|$)'
  r'|[0-9０-９]{1,2}[.．)）](?=\s|$|\D)'
  r'|[①-⑳•・·●○■□▶►◆◇※\-–—*]'
  r')',
);

final RegExp _pricePattern = RegExp(
  r'(?:[¥￥$€£₩]\s*[0-9０-９])|(?:[0-9０-９][0-9０-９,，.]*\s*(?:円|元|원|yen|usd|krw|jpy)?\s*$)',
  caseSensitive: false,
);

final RegExp _cjkPattern = RegExp(r'[぀-ヿ㐀-鿿豈-﫿]');
final RegExp _latinLetterPattern = RegExp(r'[A-Za-z]');

/// [text]가 선택지·목록 항목이나 가격·숫자가 붙은 짧은 줄인지(문단으로 묶지 않는다).
bool isTextItemLine(String text) {
  final trimmed = text.trim();
  if (_markerPattern.hasMatch(trimmed)) {
    return true;
  }
  return trimmed.length <= 24 && _pricePattern.hasMatch(trimmed);
}

bool _isCjk(String text) => _cjkPattern.hasMatch(text);

/// 줄 끝에서 다음 줄로 이어지는지 볼 만큼 긴 줄인지. 짧은 줄(메뉴 이름 등)은 묶지 않는다.
bool _isLongEnough(String text) {
  final length = text.trim().length;
  return _isCjk(text) ? length >= 8 : length >= 16;
}

/// 인식한 줄을 번역 단위로 나눈다. 결과는 위에서 아래 순서다.
///
/// 앞 줄과 다음 줄이 모두 아래를 만족하면 같은 문단으로 묶는다.
/// - 같은 글 덩어리이고, 둘 다 항목 줄이 아니다.
/// - 앞 줄이 덩어리에서 가장 긴 줄 폭의 70% 이상이고(줄이 차서 넘어간 것), 충분히 길다.
/// - 줄 높이가 비슷하고(1.4배 이내), 세로 간격이 줄 높이 이하이며, 가로로 절반 이상 겹친다.
/// - 문단이 [maxParagraphLines]줄·[maxParagraphLength]자를 넘지 않는다.
List<TextParagraph> buildTextParagraphs(List<RecognizedTextLine> lines) {
  final byBlock = <int, List<RecognizedTextLine>>{};
  for (final line in lines) {
    if (line.text.trim().isEmpty) {
      continue;
    }
    byBlock.putIfAbsent(line.block, () => <RecognizedTextLine>[]).add(line);
  }

  final units = <TextParagraph>[];
  for (final blockLines in byBlock.values) {
    blockLines.sort((a, b) => a.box.top.compareTo(b.box.top));
    final maxWidth = blockLines.map((line) => line.box.width).reduce(math.max);

    var texts = <String>[];
    Rect? box;
    RecognizedTextLine? previous;

    void flush() {
      if (box != null && texts.isNotEmpty) {
        units.add((
          text: joinRecognizedLines(texts),
          box: box!,
          lineCount: texts.length,
        ));
      }
      texts = <String>[];
      box = null;
      previous = null;
    }

    for (final line in blockLines) {
      final prev = previous;
      final joined =
          prev != null &&
          _continues(prev, line, maxWidth) &&
          texts.length < maxParagraphLines &&
          texts.fold<int>(0, (sum, text) => sum + text.length) +
                  line.text.length <=
              maxParagraphLength;
      if (!joined) {
        flush();
      }
      texts.add(line.text.trim());
      box = box == null ? line.box : box!.expandToInclude(line.box);
      previous = line;
      if (isTextItemLine(line.text)) {
        flush();
      }
    }
    flush();
  }

  units.sort((a, b) {
    final top = a.box.top.compareTo(b.box.top);
    return top != 0 ? top : a.box.left.compareTo(b.box.left);
  });
  return units;
}

bool _continues(RecognizedTextLine a, RecognizedTextLine b, double maxWidth) {
  if (isTextItemLine(a.text) || isTextItemLine(b.text)) {
    return false;
  }
  if (a.box.width < maxWidth * 0.7 || !_isLongEnough(a.text)) {
    return false;
  }
  final lowHeight = math.min(a.box.height, b.box.height);
  final highHeight = math.max(a.box.height, b.box.height);
  if (lowHeight <= 0 || highHeight / lowHeight > 1.4) {
    return false;
  }
  final gap = b.box.top - a.box.bottom;
  if (gap > lowHeight || gap < -lowHeight * 0.5) {
    return false;
  }
  final overlap =
      math.min(a.box.right, b.box.right) - math.max(a.box.left, b.box.left);
  return overlap >= math.min(a.box.width, b.box.width) * 0.5;
}

/// 줄들을 문단 글자로 잇는다. 로마자 사이는 공백으로, 한자·가나 사이는 붙여 잇는다.
/// 영어 줄 끝의 하이픈(`infor-` + `mation`)은 지우고 붙인다.
String joinRecognizedLines(List<String> lines) {
  final buffer = StringBuffer();
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    if (buffer.isEmpty) {
      buffer.write(line);
      continue;
    }
    final current = buffer.toString();
    final last = current[current.length - 1];
    final first = line[0];
    if (last == '-' &&
        current.length >= 2 &&
        _latinLetterPattern.hasMatch(current[current.length - 2]) &&
        _latinLetterPattern.hasMatch(first)) {
      buffer
        ..clear()
        ..write(current.substring(0, current.length - 1))
        ..write(line);
      continue;
    }
    final glue = _isCjk(last) && _isCjk(first) ? '' : ' ';
    buffer
      ..write(glue)
      ..write(line);
  }
  return buffer.toString();
}
