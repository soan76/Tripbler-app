import 'dart:math' as math;

import '../../models/map/scale_bar_data.dart';

class ScaleBarCalculator {
  const ScaleBarCalculator._();

  // 현재 카메라 중심 위도와 줌 레벨을 기준으로 Scale Bar 정보를 계산함.
  //
  // currentLatitude:
  // 현재 지도 카메라 중심의 위도.
  //
  // currentZoom:
  // 현재 지도 줌 레벨.
  //
  // 반환값:
  // distanceMeters: 화면에 표시할 실제 거리
  // widthPx: 그 거리를 화면에서 몇 px 길이의 선으로 보여줄지
  static ScaleBarData calculate({
    required double currentLatitude,
    required double currentZoom,
  }) {
    // Scale Bar의 최대 화면 너비.
    // 최대 줌인 상태에서 5m 단위가 나오도록 64px 기준으로 계산함.
    const double maxBarWidthPx = 64;

    // Web Mercator 기준 1px당 실제 거리 계산.
    // 위도가 높아질수록 같은 줌 레벨에서도 1px당 실제 거리가 달라짐.
    final double latitudeRadians = currentLatitude * math.pi / 180;

    final double metersPerPixel =
        156543.03392 * math.cos(latitudeRadians) / math.pow(2, currentZoom);

    final double rawDistanceMeters = metersPerPixel * maxBarWidthPx;

    final double niceDistanceMeters = _pickNiceDistance(rawDistanceMeters);

    final double widthPx = niceDistanceMeters / metersPerPixel;

    return ScaleBarData(
      distanceMeters: niceDistanceMeters,
      widthPx: widthPx.clamp(28, maxBarWidthPx).toDouble(),
    );
  }

  // Scale Bar에 표시할 거리를 보기 좋은 값으로 정리.
  //
  // 7m   -> 5m
  // 23m  -> 20m
  // 64m  -> 50m
  // 130m -> 100m
  static double _pickNiceDistance(double rawMeters) {
    const List<double> niceDistances = [
      5,
      10,
      20,
      50,
      100,
      200,
      500,
      1000,
      2000,
      5000,
      10000,
      20000,
      50000,
      100000,
      200000,
    ];

    for (final distance in niceDistances.reversed) {
      if (distance <= rawMeters) {
        return distance;
      }
    }

    return 5;
  }

  // Scale Bar에 표시할 거리 텍스트 생성.
  //
  // 50    -> 50m
  // 1000  -> 1km
  // 200000 -> 200km
  static String formatDistance(double meters) {
    if (meters >= 1000) {
      final double km = meters / 1000;

      if (km == km.roundToDouble()) {
        return '${km.toInt()}km';
      }

      return '${km.toStringAsFixed(1)}km';
    }

    return '${meters.toInt()}m';
  }
}
