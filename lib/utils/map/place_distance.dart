import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/place_model.dart';

/// 기기 위치와 장소 사이의 거리 계산과 표시 문구.
class PlaceDistance {
  const PlaceDistance._();

  static const double _earthRadiusMeters = 6371008.8;

  /// 두 좌표 사이의 대원 거리(m, 하버사인 공식).
  static double metersBetween(LatLng from, LatLng to) {
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final deltaLat = lat2 - lat1;
    final deltaLng = _toRadians(to.longitude - from.longitude);

    final a =
        math.pow(math.sin(deltaLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLng / 2), 2);

    return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
  }

  /// [origin]에서 [place]까지의 거리(m). 둘 중 하나라도 좌표가 없으면 null.
  static double? metersTo(LatLng? origin, PlaceModel place) {
    if (origin == null || !place.hasCoordinates) {
      return null;
    }

    return metersBetween(origin, LatLng(place.latitude!, place.longitude!));
  }

  /// [origin]에서 가까운 순으로 정렬한 새 목록.
  ///
  /// 거리가 같으면 원래 순서를 유지한다. 좌표가 없는 장소는 원래 순서대로 맨 뒤에 둔다.
  /// [origin]이 없으면 원래 순서 그대로 돌려준다.
  static List<PlaceModel> sortByDistance(
    List<PlaceModel> places,
    LatLng? origin,
  ) {
    if (origin == null) {
      return List.of(places);
    }

    final indexed = [
      for (var i = 0; i < places.length; i++)
        (index: i, place: places[i], meters: metersTo(origin, places[i])),
    ];

    indexed.sort((a, b) {
      final aMeters = a.meters;
      final bMeters = b.meters;

      if (aMeters == null || bMeters == null) {
        if (aMeters != null) return -1;
        if (bMeters != null) return 1;
        return a.index.compareTo(b.index);
      }

      final byDistance = aMeters.compareTo(bMeters);
      return byDistance != 0 ? byDistance : a.index.compareTo(b.index);
    });

    return [for (final entry in indexed) entry.place];
  }

  /// 거리 표시 문구. 1km 미만은 10m 단위, 10km 미만은 소수 한 자리 km, 그 이상은 km 정수.
  static String format(double meters) {
    if (meters < 1000) {
      final rounded = (meters / 10).round() * 10;
      // 990m 이상은 반올림하면 1000m가 되므로 km로 넘긴다.
      if (rounded < 1000) {
        return '${rounded}m';
      }
    }

    final km = meters / 1000;

    if (km < 9.95) {
      return '${km.toStringAsFixed(1)}km';
    }

    return '${km.round()}km';
  }

  /// [origin](검색하거나 장소를 고른 순간의 기기 위치)에서 [place]까지의 거리 문구.
  /// 계산할 수 없으면 null.
  static String? labelTo(LatLng? origin, PlaceModel place) {
    final meters = metersTo(origin, place);
    return meters == null ? null : format(meters);
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
