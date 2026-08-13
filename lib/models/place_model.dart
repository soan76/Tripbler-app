class PlaceModel {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
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

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    return PlaceModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '이름 없는 장소',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      address: json['address']?.toString() ?? '주소 정보 없음',
      rating: json['rating'] == null ? null : _toDouble(json['rating']),
      category: json['category']?.toString() ?? 'place',
      openNow: json['openNow'] is bool ? json['openNow'] as bool : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }
}
