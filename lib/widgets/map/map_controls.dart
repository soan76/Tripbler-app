import 'package:flutter/material.dart';

import '../../utils/map/scale_bar_calculator.dart';
import 'current_location_button.dart';
import 'map_scale_bar.dart';

/// 하단 패널 위에 놓이는 지도 버튼 묶음(축척 표시와 현재 위치 버튼).
///
/// `MapOverlayLayout`의 `mapControlsHeight`에도 [height]를 넘긴다.
class MapControls extends StatelessWidget {
  /// 축척 표시·현재 위치 버튼 영역 높이(버튼 56 + 아래 여백 24)
  static const double height = 80;

  const MapControls({
    super.key,
    required this.latitude,
    required this.zoom,
    required this.isLoading,
    required this.onCurrentLocationPressed,
  });

  /// 축척 계산 기준인 지도 카메라 중심의 위도
  final double latitude;

  /// 현재 지도 줌 레벨
  final double zoom;

  /// 현재 위치를 가져오는 중인지(버튼에 진행 표시)
  final bool isLoading;

  final VoidCallback? onCurrentLocationPressed;

  @override
  Widget build(BuildContext context) {
    // 현재 지도 줌 상태에 따른 Scale Bar 계산
    final scaleBarData = ScaleBarCalculator.calculate(
      currentLatitude: latitude,
      currentZoom: zoom,
    );

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 지도 축척 표시
          Positioned(
            right: 88,
            bottom: 38,
            child: MapScaleBar(
              data: scaleBarData,
              label: ScaleBarCalculator.formatDistance(
                scaleBarData.distanceMeters,
              ),
            ),
          ),

          // 현재 위치 버튼
          CurrentLocationButton(
            isLoading: isLoading,
            bottom: 24,
            onPressed: onCurrentLocationPressed,
          ),
        ],
      ),
    );
  }
}
