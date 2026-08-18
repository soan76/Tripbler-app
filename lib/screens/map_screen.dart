import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
import '../services/map/location_service.dart';
import '../services/map/map_location_controller.dart';
import '../services/map/map_marker_icon_service.dart';
import '../utils/map/scale_bar_calculator.dart';
import '../widgets/map/current_location_button.dart';
import '../widgets/map/map_scale_bar.dart';
import '../widgets/map/place_detail_card.dart';
import '../widgets/map/tripbler_google_map.dart';

/// 구글 맵 화면을 구성하는 StatefulWidget 클래스
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// 구글 맵 화면을 구성하는 State 클래스
class _MapScreenState extends State<MapScreen> {
  // 위치를 가져오지 못했을 때 사용할 기본 위치
  static const LatLng _seoulCityHall = LatLng(37.5665, 126.9780);

  // 지도 최초 카메라 위치
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: _seoulCityHall,
    zoom: 13,
  );

  // 현재 위치 방향 아이콘 경로
  static const String _currentLocationIconPath =
      'assets/images/current_location_arrow.png';

  // 현재 위치 방향 아이콘 크기
  static const int _currentLocationIconSize = 72;

  // 현재 위치와 방향 상태를 관리하는 Controller
  final MapLocationController _locationController = MapLocationController();

  // 현재 위치 마커 아이콘 생성 Service
  final MapMarkerIconService _markerIconService = const MapMarkerIconService();

  // Google Map Controller
  GoogleMapController? _mapController;

  // 현재 지도 카메라 중심 좌표
  LatLng _currentCameraTarget = _seoulCityHall;

  // 현재 지도 줌 레벨
  double _currentZoom = 13;

  // 현재 위치 방향 아이콘
  BitmapDescriptor? _currentLocationIcon;

  @override
  void initState() {
    super.initState();

    // 현재 위치 마커용 이미지 로딩
    _loadCurrentLocationIcon();

    // 현재 위치/방향 Controller 초기화
    _locationController.initialize();

    // 위치 또는 방향 상태 변경 시 화면 갱신
    _locationController.addListener(_onLocationStateChanged);
  }

  @override
  void dispose() {
    // Controller Listener 해제
    _locationController.removeListener(_onLocationStateChanged);

    // 위치 Stream, Compass Stream, Timer 등을
    // MapLocationController 내부에서 정리함.
    _locationController.dispose();

    // Google Map Controller 종료
    _mapController?.dispose();

    super.dispose();
  }

  /// 현재 위치 또는 방향 상태가 변경됐을 때
  /// 현재 위치 마커를 다시 그림.
  void _onLocationStateChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  /// Google Map 생성 완료 처리
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    // 지도 생성 후 최초 현재 위치 요청
    _initializeCurrentLocation();
  }

  /// assets에 등록된 현재 위치 방향 아이콘을
  /// Google Map Marker용 BitmapDescriptor로 변환함.
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

  /// 지도 생성 후 최초 현재 위치를 요청함.
  Future<void> _initializeCurrentLocation() async {
    try {
      final position = await _locationController.requestCurrentLocation();

      if (!mounted) {
        return;
      }

      // 최근 위치 또는 최신 위치를 얻었다면
      // 해당 위치로 지도 이동
      if (position != null) {
        await _moveCameraToCurrentLocation(position);

        return;
      }

      // 위치를 전혀 확보하지 못하고
      // 실제 최신 위치 요청까지 timeout 된 경우
      if (_locationController.hasShownTimeoutMessage) {
        _showMapSnackBar('현재 위치를 확인하고 있습니다.');
      }
    } on LocationServiceException catch (error) {
      if (!mounted) {
        return;
      }

      /*
       * 최초 권한 요청을 거부한 경우 여기서 끝남.
       *
       * 자동 재시도하지 않기 때문에
       * timeout 요청이 반복되지 않음.
       */
      _showMapSnackBar(error.message);
    } catch (error, stackTrace) {
      debugPrint('현재 위치 초기화 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      _showMapSnackBar('현재 위치를 가져오지 못했습니다.');
    }
  }

  /// 현재 위치 버튼 클릭 처리
  Future<void> _onCurrentLocationPressed() async {
    try {
      /*
       * requestCurrentLocation 내부에서
       *
       * 1. 위치 권한 확인/재요청
       * 2. 기존 위치 확인
       * 3. 최근 위치 확인
       * 4. 실제 최신 위치 요청
       * 5. 위치 Stream 시작
       *
       * 을 처리함.
       */
      final position = await _locationController.requestCurrentLocation();

      if (!mounted) {
        return;
      }

      // 위치를 확보했다면 해당 위치로 이동
      if (position != null) {
        await _moveCameraToCurrentLocation(position);

        return;
      }

      // 위치가 전혀 없는 상태에서 timeout 된 경우에만
      // 안내 메시지를 표시함.
      if (_locationController.hasShownTimeoutMessage) {
        _showMapSnackBar(
          '현재 위치를 아직 확인하지 못했습니다. '
          '잠시 후 다시 시도해 주세요.',
        );
      }
    } on LocationServiceException catch (error) {
      if (!mounted) {
        return;
      }

      /*
       * 사용자가 최초 권한 요청에서 거부했더라도,
       * 현재 위치 버튼을 누르면 LocationService가
       * 다시 권한 상태를 확인함.
       */
      _showMapSnackBar(error.message);
    } catch (error, stackTrace) {
      debugPrint('현재 위치 이동 실패: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      _showMapSnackBar('현재 위치로 이동하지 못했습니다.');
    }
  }

  /// 현재 위치로 지도 카메라 이동
  Future<void> _moveCameraToCurrentLocation(LatLng position) async {
    final controller = _mapController;

    if (controller == null) {
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: position, zoom: 17),
        ),
      );
    } catch (error) {
      debugPrint('현재 위치 카메라 이동 실패: $error');
    }
  }

  /// 현재 위치 방향 마커를 생성함.
  Marker? _buildCurrentLocationMarker() {
    final currentUserPosition = _locationController.currentPosition;

    // 아직 현재 위치를 알 수 없다면
    // 현재 위치 마커를 표시하지 않음.
    if (currentUserPosition == null) {
      return null;
    }

    return Marker(
      markerId: const MarkerId('current_user_location'),

      // 사용자의 현재 위치
      position: currentUserPosition,

      // Compass 방향에 따라 마커 회전
      rotation: _locationController.currentHeading,

      // 아이콘 중심을 실제 위치와 맞춤
      anchor: const Offset(0.5, 0.5),

      // 지도 위에 평평하게 배치하여
      // 방향 회전을 자연스럽게 표시함.
      flat: true,

      // 커스텀 아이콘 로딩 전에는
      // 기본 파란 마커를 임시 표시함.
      icon:
          _currentLocationIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),

      // 장소 마커보다 위에 표시
      zIndex: 9999,
    );
  }

  /// 지도 관련 안내 메시지 표시
  void _showMapSnackBar(String message) {
    if (!mounted) {
      return;
    }

    /*
     * 기존 SnackBar가 남아있으면 제거하고
     * 새로운 메시지만 표시함.
     *
     * 같은 위치 오류 메시지가 화면에
     * 여러 개 쌓이는 것을 방지함.
     */
    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = context.watch<MapProvider>();

    // 현재 선택된 장소
    final selectedPlace = mapProvider.selectedPlace;

    // 현재 위치 마커
    final currentLocationMarker = _buildCurrentLocationMarker();

    // 현재 지도 줌 상태에 따른 Scale Bar 계산
    final scaleBarData = ScaleBarCalculator.calculate(
      currentLatitude: _currentCameraTarget.latitude,
      currentZoom: _currentZoom,
    );

    return Stack(
      children: [
        // Google Map
        TripblerGoogleMap(
          initialCameraPosition: _initialCameraPosition,

          onMapCreated: _onMapCreated,

          markers: {
            ...mapProvider.markers,

            if (currentLocationMarker != null) currentLocationMarker,
          },

          // 지도 위치 클릭 처리
          onTap: (latLng) {
            context.read<MapProvider>().selectNearestPlaceByLatLng(
              latitude: latLng.latitude,
              longitude: latLng.longitude,
            );
          },

          // 지도 이동/확대/축소 시
          // Scale Bar 계산 기준 갱신
          onCameraMove: (CameraPosition position) {
            setState(() {
              _currentCameraTarget = position.target;

              _currentZoom = position.zoom;
            });
          },
        ),

        // 지도 축척 표시
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

        // 현재 위치 버튼
        CurrentLocationButton(
          isLoading: _locationController.isLoading,
          bottom: selectedPlace == null ? 24 : 220,
          onPressed: _onCurrentLocationPressed,
        ),

        // 장소 선택 시 하단 상세 카드 표시
        if (selectedPlace != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PlaceDetailCard(
              place: selectedPlace,

              // 장소 선택 해제
              onClose: context.read<MapProvider>().clearSelectedPlace,

              // Place Details API 요청
              onDetailPressed: () {
                context.read<MapProvider>().loadSelectedPlaceDetails();
              },
            ),
          ),
      ],
    );
  }
}
