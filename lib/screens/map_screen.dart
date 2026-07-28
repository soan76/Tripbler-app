import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// 구글 맵 화면을 구성하는 State 클래스
class _MapScreenState extends State<MapScreen> {
  static const LatLng _seoulCityHall = LatLng(37.5665, 126.9780);

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: _seoulCityHall,
    zoom: 13,
  );

  GoogleMapController? _mapController;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }
  // 구글 맵 화면의 상태를 관리하는 State 클래스
  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
  // 구글 맵 화면을 구성하는 위젯 트리를 반환하는 build 메서드
  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: _initialCameraPosition,
      onMapCreated: _onMapCreated,

      mapType: MapType.normal,

      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,

      compassEnabled: true,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,

      myLocationEnabled: false,
      myLocationButtonEnabled: false,
    );
  }
}
