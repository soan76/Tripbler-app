/// 줄별 번역 요청 제한(서버와 같다). 넘는 줄은 보내지 않고 보내지 못한 줄 수로 알린다.
abstract final class LineRequestLimits {
  static const int maxLines = 50;
  static const int maxLineLength = 200;
  static const int maxTotalCharacters = 5000;
}

/// 서버 제한(줄 수·줄 길이·합계)에 맞게 줄을 고른다. 긴 줄은 자르고, 제한을 넘으면 그 뒤 줄은 뺀다.
/// 두 번째 값은 보내지 못한 줄 수(빈 줄은 세지 않음).
(List<String>, int) linesForRequest(List<String> lines) {
  final selected = <String>[];
  var total = 0;
  var nonEmpty = 0;

  for (final raw in lines) {
    var line = raw.trim();

    if (line.isEmpty) {
      continue;
    }

    nonEmpty++;

    if (line.length > LineRequestLimits.maxLineLength) {
      var end = LineRequestLimits.maxLineLength;
      // 이모지처럼 두 단위로 된 문자를 반으로 자르지 않는다.
      final last = line.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        end -= 1;
      }
      line = line.substring(0, end);
    }

    // 앞에서 한 줄이라도 빠졌으면(selected.length가 nonEmpty - 1보다 작음) 이 줄도 뺀다.
    if (selected.length < LineRequestLimits.maxLines &&
        total + line.length <= LineRequestLimits.maxTotalCharacters &&
        selected.length == nonEmpty - 1) {
      selected.add(line);
      total += line.length;
    }
  }

  return (List<String>.unmodifiable(selected), nonEmpty - selected.length);
}
