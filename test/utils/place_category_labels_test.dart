import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/utils/map/place_category_labels.dart';
import 'package:tripbler/utils/map/search_query_normalizer.dart';

void main() {
  group('PlaceCategoryLabels', () {
    test('자주 나오는 유형은 한글로 바꾼다', () {
      expect(PlaceCategoryLabels.labelFor('tourist_attraction'), '관광명소');
      expect(PlaceCategoryLabels.labelFor('restaurant'), '음식점');
      expect(PlaceCategoryLabels.labelFor('cafe'), '카페');
    });

    test('알 수 없거나 없는 유형은 null', () {
      expect(PlaceCategoryLabels.labelFor('unknown_type'), isNull);
      expect(PlaceCategoryLabels.labelFor(null), isNull);
      expect(PlaceCategoryLabels.labelFor(''), isNull);
    });
  });

  group('SearchQueryNormalizer.isTooLong', () {
    test('앞뒤 공백류를 지운 뒤 100자를 넘을 때만 true', () {
      expect(SearchQueryNormalizer.isTooLong('가' * 100), isFalse);
      expect(SearchQueryNormalizer.isTooLong('가' * 101), isTrue);
      expect(SearchQueryNormalizer.isTooLong('  ${'가' * 100}  '), isFalse);
      expect(SearchQueryNormalizer.isTooLong(''), isFalse);
      expect(SearchQueryNormalizer.isTooLong('   '), isFalse);
    });
  });
}
