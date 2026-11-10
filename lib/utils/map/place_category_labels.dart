/// Google 장소 유형(`primaryType`)을 화면에 보여줄 한글 분류로 바꾼다.
///
/// 여행 중 자주 나오는 유형만 옮기고, 목록에 없는 유형은 null을 돌려줘 표시하지 않는다.
class PlaceCategoryLabels {
  const PlaceCategoryLabels._();

  static const Map<String, String> _labels = <String, String>{
    'tourist_attraction': '관광명소',
    'historical_landmark': '역사 명소',
    'museum': '박물관',
    'art_gallery': '미술관',
    'park': '공원',
    'national_park': '국립공원',
    'amusement_park': '놀이공원',
    'zoo': '동물원',
    'aquarium': '수족관',
    'church': '교회',
    'hindu_temple': '사원',
    'buddhist_temple': '사찰',
    'mosque': '모스크',
    'restaurant': '음식점',
    'cafe': '카페',
    'coffee_shop': '카페',
    'bakery': '빵집',
    'bar': '바',
    'fast_food_restaurant': '패스트푸드',
    'lodging': '숙소',
    'hotel': '호텔',
    'hostel': '호스텔',
    'shopping_mall': '쇼핑몰',
    'department_store': '백화점',
    'supermarket': '슈퍼마켓',
    'convenience_store': '편의점',
    'market': '시장',
    'train_station': '기차역',
    'subway_station': '지하철역',
    'bus_station': '버스터미널',
    'airport': '공항',
    'pharmacy': '약국',
    'hospital': '병원',
    'atm': 'ATM',
    'bank': '은행',
  };

  /// 한글 분류. 알 수 없거나 비어 있으면 null.
  static String? labelFor(String? category) {
    if (category == null) {
      return null;
    }

    return _labels[category.trim()];
  }
}
