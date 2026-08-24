class PlaceModel {
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;
  final String address;
  final double? rating;
  final String category;
  final bool? openNow;

  const PlaceModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.rating,
    required this.category,
    required this.openNow,
  });

  /// 좌표가 있는지 여부.
  /// 지도에 마커를 표시하기 전 이 값을 확인해 (0,0) 같은 잘못된
  /// 위치가 찍히는 것을 방지한다.
  bool get hasCoordinates => latitude != null && longitude != null;

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();

    // id는 리스트 렌더링의 key, 중복 제거, 지도 마커 식별 등에
    // 고유값으로 쓰이므로 비어 있으면 조용히 넘어가지 않고 예외로 알린다.
    if (id == null || id.isEmpty) {
      throw const FormatException('장소 응답에 id가 없습니다.');
    }

    return PlaceModel(
      id: id,
      name: json['name']?.toString() ?? '이름 없는 장소',
      // 좌표 파싱에 실패하면 (0, 0)("Null Island")처럼 실존하는 잘못된
      // 좌표로 조용히 대체하지 않고 null을 반환한다. 호출부(지도 위젯)는
      // hasCoordinates로 좌표 유무를 확인한 뒤 마커 표시 여부를 결정한다.
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      address: json['address']?.toString() ?? '주소 정보 없음',
      rating: _parseRating(json['rating']),
      category: json['category']?.toString() ?? 'place',
      openNow: json['openNow'] is bool ? json['openNow'] as bool : null,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  static double? _parseRating(dynamic value) {
    final parsed = _parseDouble(value);

    if (parsed == null) {
      return null;
    }

    // 평점은 0~5 범위를 벗어나지 않도록 방어함.
    // (백엔드/Google Places 응답이 예상 밖의 값을 주더라도
    // 별점 위젯이 깨지지 않게 함)
    return parsed.clamp(0, 5);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PlaceModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PlaceModel(id: $id, name: $name, latitude: $latitude, longitude: $longitude)';
}
