import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
import '../services/map/location_service.dart';
import '../services/map/map_marker_icon_service.dart';
import '../utils/map/scale_bar_calculator.dart';
import '../widgets/map/current_location_button.dart';
import '../widgets/map/map_scale_bar.dart';
import '../widgets/map/place_detail_card.dart';
import '../widgets/map/tripbler_google_map.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

// 구글 맵 화면을 구성하는 State 클래스
class _MapScreenState extends State<MapScreen> {
  // 위치 권한이 없거나 현재 위치를 가져오지 못했을 때 사용할 기본 위치
  static const LatLng _seoulCityHall = LatLng(37.5665, 126.9780);

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: _seoulCityHall,
    zoom: 13,
  );

  // 현재 위치 방향 아이콘 경로
  static const String _currentLocationIconPath =
      'assets/images/current_location_arrow.png';

  // 현재 위치 방향 아이콘 크기
  static const int _currentLocationIconSize = 72;

  final LocationService _locationService = const LocationService();
  final MapMarkerIconService _markerIconService = const MapMarkerIconService();

  GoogleMapController? _mapController;

  // 현재 지도 카메라 중심 좌표
  LatLng _currentCameraTarget = _seoulCityHall;

  // 현재 지도 줌 레벨
  double _currentZoom = 13;

  // 직접 만든 현재 위치 방향 아이콘
  BitmapDescriptor? _currentLocationIcon;

  // 사용자의 현재 위치 좌표
  LatLng? _currentUserPosition;

  // 사용자가 바라보는 방향값
  // 0도: 북쪽, 90도: 동쪽, 180도: 남쪽, 270도: 서쪽
  double _currentHeading = 0;

  // 위치 업데이트를 계속 감지하기 위한 구독 객체
  StreamSubscription<Position>? _positionSubscription;

  // 위치 권한 허용 여부
  bool _isLocationPermissionGranted = false;

  // 현재 위치를 가져오는 중인지 여부
  bool _isLoadingCurrentLocation = false;

  @override
  void initState() {
    super.initState();

    // 지도에 사용할 현재 위치 방향 아이콘을 미리 불러옴.
    _loadCurrentLocationIcon();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    // 지도가 생성된 뒤 현재 위치를 가져와 현재 위치 마커를 표시함.
    _initializeCurrentLocation();
  }

  // 구글 맵 화면의 상태를 정리하는 메서드
  @override
  void dispose() {
    // 위치 스트림 구독 해제
    _positionSubscription?.cancel();

    _mapController?.dispose();
    super.dispose();
  }

  // assets에 등록한 현재 위치 방향 아이콘을 GoogleMap Marker 아이콘으로 변환함.
  Future<void> _loadCurrentLocationIcon() async {
    try {
      final icon = await _markerIconService.createResizedBitmapDescriptor(
        assetPath: _currentLocationIconPath,
        targetWidth: _currentLocationIconSize,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentLocationIcon = icon;
      });
    } catch (error, stackTrace) {
      debugPrint('현재 위치 아이콘 로딩 실패: $error');
      debugPrint('$stackTrace');
    }
  }

  // 지도 생성 후 현재 위치를 가져오고, 현재 위치 방향 마커를 표시하도록 초기화함.
  Future<void> _initializeCurrentLocation() async {
    if (_isLoadingCurrentLocation) {
      return;
    }

    setState(() {
      _isLoadingCurrentLocation = true;
    });

    try {
      final position = await _locationService.getCurrentPosition();

      if (!mounted) {
        return;
      }

      final currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _isLocationPermissionGranted = true;
        _currentUserPosition = currentLatLng;
        _currentHeading = _normalizeHeading(position.heading);
        _isLoadingCurrentLocation = false;
      });

      // 앱을 처음 켰을 때 현재 위치로 카메라 이동
      await _moveCameraToCurrentLocation(currentLatLng);

      // 사용자가 움직일 때 위치와 방향을 계속 업데이트
      _startLocationUpdates();
    } on LocationServiceException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLocationPermissionGranted = false;
        _isLoadingCurrentLocation = false;
      });

      _showMapSnackBar(error.message);
    } on TimeoutException {
      debugPrint('현재 위치 가져오기 시간 초과');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCurrentLocation = false;
      });

      _showMapSnackBar('현재 위치를 가져오는 데 시간이 오래 걸립니다. 다시 시도해 주세요.');
    } catch (error, stackTrace) {
      debugPrint('현재 위치 초기화 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCurrentLocation = false;
      });

      _showMapSnackBar('현재 위치를 가져오지 못했습니다.');
    }
  }

  // 사용자의 위치와 바라보는 방향을 계속 감지함.
  void _startLocationUpdates() {
    _positionSubscription?.cancel();

    _positionSubscription = _locationService.getPositionStream().listen(
      (position) {
        final currentLatLng = LatLng(position.latitude, position.longitude);

        if (!mounted) {
          return;
        }

        setState(() {
          // 사용자의 현재 위치 마커 좌표 갱신
          _currentUserPosition = currentLatLng;

          // 사용자가 바라보는 방향값 갱신
          _currentHeading = _normalizeHeading(position.heading);
        });

        // 여기서 매번 카메라를 현재 위치로 이동시키면
        // 사용자가 지도를 둘러보는 중에도 화면이 계속 현재 위치로 끌려감.
        // 그래서 위치 마커만 움직이고, 카메라는 현재 위치 버튼을 눌렀을 때만 이동시킴.
      },
      onError: (error) {
        debugPrint('현재 위치 업데이트 실패: $error');
      },
    );
  }

  // heading 값 보정.
  // Geolocator에서 방향을 알 수 없을 때 -1이 들어올 수 있으므로 기존 방향값을 유지함.
  double _normalizeHeading(double heading) {
    if (heading < 0) {
      return _currentHeading;
    }

    return heading % 360;
  }

  // 현재 위치로 지도 카메라 이동
  Future<void> _moveCameraToCurrentLocation(LatLng position) async {
    final controller = _mapController;

    if (controller == null) {
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: 17),
      ),
    );
  }

  // 현재 위치 버튼 클릭 시 현재 위치로 카메라 이동
  Future<void> _onCurrentLocationPressed() async {
    if (_isLoadingCurrentLocation) {
      return;
    }

    setState(() {
      _isLoadingCurrentLocation = true;
    });

    try {
      final position = await _locationService.getCurrentPosition();

      if (!mounted) {
        return;
      }

      final currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _isLocationPermissionGranted = true;
        _currentUserPosition = currentLatLng;
        _currentHeading = _normalizeHeading(position.heading);
        _isLoadingCurrentLocation = false;
      });

      await _moveCameraToCurrentLocation(currentLatLng);

      // 혹시 위치 스트림이 멈춰 있었을 수 있으므로 다시 시작
      _startLocationUpdates();
    } on LocationServiceException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLocationPermissionGranted = false;
        _isLoadingCurrentLocation = false;
      });

      _showMapSnackBar(error.message);
    } on TimeoutException {
      debugPrint('현재 위치 버튼 시간 초과');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCurrentLocation = false;
      });

      _showMapSnackBar('현재 위치를 가져오는 데 시간이 오래 걸립니다. 다시 눌러 주세요.');
    } catch (error, stackTrace) {
      debugPrint('현재 위치 이동 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingCurrentLocation = false;
      });

      _showMapSnackBar('현재 위치로 이동하지 못했습니다.');
    }
  }

  // 현재 위치 방향 마커를 생성함.
  Marker? _buildCurrentLocationMarker() {
    final currentUserPosition = _currentUserPosition;

    if (currentUserPosition == null) {
      return null;
    }

    return Marker(
      markerId: const MarkerId('current_user_location'),

      // 사용자의 현재 위치 좌표
      position: currentUserPosition,

      // 사용자가 바라보는 방향에 맞춰 아이콘 회전
      rotation: _currentHeading,

      // 아이콘 중심을 현재 위치 좌표에 맞춤
      anchor: const Offset(0.5, 0.5),

      // true로 해야 마커가 지도 위에 평평하게 붙고 회전이 자연스럽게 보임
      flat: true,

      // 아이콘 로딩 전에는 기본 파란 마커를 임시로 표시
      icon:
          _currentLocationIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),

      // 장소 마커보다 현재 위치 마커가 위에 보이도록 설정
      zIndex: 9999,
    );
  }

  // 지도 관련 안내 메시지를 화면 하단에 표시함.
  void _showMapSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // 구글 맵 화면을 구성하는 build 메서드
  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();

    // 현재 선택된 장소.
    // 마커를 누르면 MapProvider의 selectedPlace 값이 바뀌고,
    // 이 값이 null이 아니면 화면 하단에 장소 상세 카드가 표시됨.
    final selectedPlace = mapProvider.selectedPlace;

    final currentLocationMarker = _buildCurrentLocationMarker();

    final scaleBarData = ScaleBarCalculator.calculate(
      currentLatitude: _currentCameraTarget.latitude,
      currentZoom: _currentZoom,
    );

    return Stack(
      children: [
        TripblerGoogleMap(
          initialCameraPosition: _initialCameraPosition,
          onMapCreated: _onMapCreated,
          markers: {
            ...mapProvider.markers,
            if (currentLocationMarker != null) currentLocationMarker,
          },

          // 지도 위 기본 POI 아이콘을 직접 클릭하는 기능은 google_maps_flutter에서 바로 제공되지 않음.
          // 대신 사용자가 탭한 좌표를 백엔드에 보내서,
          // 그 좌표 주변의 가장 가까운 장소를 Places API로 찾는 방식으로 구현함.
          onTap: (latLng) {
            context.read<MapProvider>().selectNearestPlaceByLatLng(
              latitude: latLng.latitude,
              longitude: latLng.longitude,
            );
          },

          // 지도를 이동/확대/축소할 때마다 Scale Bar 계산 기준을 갱신함.
          onCameraMove: (CameraPosition position) {
            setState(() {
              _currentCameraTarget = position.target;
              _currentZoom = position.zoom;
            });
          },
        ),

        // 현재 지도 확대/축소 상태에 맞는 Scale Bar.
        // 오른쪽 하단 현재 위치 버튼의 왼쪽에 배치함.
        Positioned(
          right: 88,
          bottom: selectedPlace == null ? 38 : 234,
          child: MapScaleBar(
            data: scaleBarData,
            label: ScaleBarCalculator.formatDistance(
              scaleBarData.distanceMeters,
            ),
          ),
        ),

        // 현재 위치로 이동 버튼
        CurrentLocationButton(
          isLoading: _isLoadingCurrentLocation,
          bottom: selectedPlace == null ? 24 : 220,
          onPressed: _onCurrentLocationPressed,
        ),

        // 마커를 클릭했을 때만 하단에 장소 상세 카드를 보여줌.
        if (selectedPlace != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PlaceDetailCard(
              place: selectedPlace,

              // 닫기 버튼을 누르면 선택된 장소를 해제해서 카드를 숨김.
              onClose: context.read<MapProvider>().clearSelectedPlace,

              // 상세 보기 버튼을 누르면 placeId 기준으로 백엔드 Place Details API를 호출함.
              onDetailPressed: () {
                context.read<MapProvider>().loadSelectedPlaceDetails();
              },
            ),
          ),
      ],
    );
  }
}
