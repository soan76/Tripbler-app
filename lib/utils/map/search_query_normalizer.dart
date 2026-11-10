/// 장소 검색어 정리 규칙. 서버(`PlaceController`)와 같은 기준을 쓴다.
///
/// - 앞뒤의 공백류를 지운다: 일반 공백·탭·줄바꿈, 유니코드 구분자(NBSP U+00A0,
///   U+3000 등), 서식 문자(U+200B, U+FEFF 등). 가운데 문자는 그대로 둔다.
/// - 지운 뒤 1~[maxSearchQueryLength]자(코드 포인트 기준)여야 한다.
class SearchQueryNormalizer {
  const SearchQueryNormalizer._();

  static const int maxSearchQueryLength = 100;

  // Java Character.isWhitespace가 포함하는 U+001C~U+001F도 함께 지운다.
  static final RegExp _edgeBlank = RegExp(
    r'^[\s\p{Z}\p{Cf}\u001C-\u001F]$',
    unicode: true,
  );

  /// 정리한 검색어를 돌려준다. 비었거나 너무 길면 null.
  static String? normalize(String query) {
    final codePoints = query.runes.toList();

    var start = 0;
    var end = codePoints.length;

    while (start < end && _isEdgeBlank(codePoints[start])) {
      start++;
    }

    while (end > start && _isEdgeBlank(codePoints[end - 1])) {
      end--;
    }

    final length = end - start;

    if (length < 1 || length > maxSearchQueryLength) {
      return null;
    }

    return String.fromCharCodes(codePoints, start, end);
  }

  /// 앞뒤 공백류를 지운 뒤 [maxSearchQueryLength]자(코드 포인트)를 넘는지.
  /// 빈 검색어와 구분해 "100자까지 입력할 수 있다"는 안내를 띄우는 데 쓴다.
  static bool isTooLong(String query) {
    return _trimmedLength(query) > maxSearchQueryLength;
  }

  static int _trimmedLength(String query) {
    final codePoints = query.runes.toList();

    var start = 0;
    var end = codePoints.length;

    while (start < end && _isEdgeBlank(codePoints[start])) {
      start++;
    }

    while (end > start && _isEdgeBlank(codePoints[end - 1])) {
      end--;
    }

    return end - start;
  }

  static bool _isEdgeBlank(int codePoint) {
    return _edgeBlank.hasMatch(String.fromCharCode(codePoint));
  }
}
