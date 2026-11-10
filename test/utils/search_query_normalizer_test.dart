import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/utils/map/search_query_normalizer.dart';

void main() {
  group('SearchQueryNormalizer', () {
    test('앞뒤 공백을 지운다', () {
      expect(SearchQueryNormalizer.normalize('  경복궁 \t\n'), '경복궁');
    });

    test('유니코드 공백류(NBSP, U+3000, U+200B, U+FEFF)도 앞뒤에서 지운다', () {
      expect(
        SearchQueryNormalizer.normalize('\u00A0\u3000경복궁\u200B\uFEFF'),
        '경복궁',
      );
    });

    test('가운데 공백과 ZWJ 이모지 시퀀스는 그대로 둔다', () {
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';

      expect(SearchQueryNormalizer.normalize(' 서울 $family '), '서울 $family');
    });

    test('비었거나 공백류뿐이면 null', () {
      expect(SearchQueryNormalizer.normalize(''), isNull);
      expect(SearchQueryNormalizer.normalize('   '), isNull);
      expect(SearchQueryNormalizer.normalize('\u00A0\u200B\u3000'), isNull);
    });

    test('코드 포인트 기준 100자는 허용하고 101자는 null', () {
      expect(SearchQueryNormalizer.normalize('가' * 100), '가' * 100);
      expect(SearchQueryNormalizer.normalize('가' * 101), isNull);
      // 이모지 100개는 UTF-16으로 200자지만 코드 포인트로 100자다.
      expect(SearchQueryNormalizer.normalize('\u{1F600}' * 100), isNotNull);
    });
  });
}
