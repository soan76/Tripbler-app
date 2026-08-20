import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/config/map_id_config.dart';
import '../../providers/settings_provider.dart';

/// 구글 맵을 표시하는 위젯 클래스
class TripblerGoogleMap extends StatefulWidget {
  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final void Function(GoogleMapController controller) onMapCreated;
  final void Function(LatLng latLng) onTap;
  final void Function(CameraPosition position) onCameraMove;

  const TripblerGoogleMap({
    super.key,
    required this.initialCameraPosition,
    required this.markers,
    required this.onMapCreated,
    required this.onTap,
    required this.onCameraMove,
  });

  @override
  State<TripblerGoogleMap> createState() => _TripblerGoogleMapState();
}

class _TripblerGoogleMapState extends State<TripblerGoogleMap> {
  GoogleMapController? _controller;
  bool? _lastIsDarkMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final bool isDarkMode = context.watch<SettingsProvider>().isDarkMode;

    if (_lastIsDarkMode == isDarkMode) {
      return;
    }

    _lastIsDarkMode = isDarkMode;

    final GoogleMapController? controller = _controller;

    if (controller != null) {
      controller.setMapColorScheme(isDarkMode);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;

    final bool isDarkMode = context.read<SettingsProvider>().isDarkMode;

    _lastIsDarkMode = isDarkMode;

    controller.setMapColorScheme(isDarkMode);

    widget.onMapCreated(controller);
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      // 플랫폼별 Google Cloud Map ID 적용
      cloudMapId: MapIdConfig.current,

      initialCameraPosition: widget.initialCameraPosition,
      onMapCreated: _onMapCreated,

      // 백엔드에서 받아온 장소 목록 + 현재 위치 방향 마커를 함께 표시함.
      markers: widget.markers,

      // 지도 탭 좌표를 상위 화면으로 전달함.
      onTap: widget.onTap,

      // 지도를 이동/확대/축소할 때마다 카메라 정보를 상위 화면으로 전달함.
      onCameraMove: widget.onCameraMove,

      mapType: MapType.normal,

      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,

      compassEnabled: true,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,

      // 건물 표시 활성화
      buildingsEnabled: true,

      // 낮은 숫자일수록 줌아웃, 높은 숫자일수록 줌인.
      // Scale Bar는 5m ~ 200km 범위의 표시값을 사용함.
      minMaxZoomPreference: const MinMaxZoomPreference(5, 20),

      // 현재 위치는 직접 만든 방향 마커로 표시하므로
      // GoogleMap 기본 현재 위치 파란 점은 꺼둠.
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
    );
  }
}
