import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
import '../widgets/map/place_detail_card.dart';

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

  // 마커 아이콘 크기.
  // 기존 문제가 아이콘이 너무 크게 나오는 것이므로 PNG 원본 크기와 상관없이 72px로 줄여서 사용함.
  static const int _currentLocationIconSize = 72;

  GoogleMapController? _mapController;

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

    // 지도에 사용할 현재 위치 방향 아이콘을 미리 불러옴
    _loadCurrentLocationIcon();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    // 지도가 생성된 뒤 현재 위치를 가져와 현재 위치 마커를 표시함
    _initializeCurrentLocation();
  }

  // 구글 맵 화면의 상태를 관리하는 State 클래스
  @override
  void dispose() {
    // 위치 스트림 구독 해제
    _positionSubscription?.cancel();

    _mapController?.dispose();
    super.dispose();
  }

  // assets에 등록한 현재 위치 방향 아이콘을 GoogleMap Marker 아이콘으로 변환
  Future<void> _loadCurrentLocationIcon() async {
    try {
      final icon = await _createResizedBitmapDescriptor(
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

  // PNG 원본 크기가 커도 지도 마커에서는 지정한 크기로 보이도록 리사이즈함.
  // BitmapDescriptor.fromAssetImage의 ImageConfiguration(size)만으로는
  // 실제 기기에서 원하는 크기로 줄어들지 않는 경우가 있어서 바이트 단위로 직접 줄임.
  Future<BitmapDescriptor> _createResizedBitmapDescriptor({
    required String assetPath,
    required int targetWidth,
  }) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();

    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
    );

    final ui.FrameInfo frameInfo = await codec.getNextFrame();

    final ByteData? resizedData = await frameInfo.image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (resizedData == null) {
      throw Exception('현재 위치 아이콘 변환에 실패했습니다.');
    }

    return BitmapDescriptor.fromBytes(resizedData.buffer.asUint8List());
  }

  // 위치 서비스와 권한 상태를 확인하고, 필요하면 사용자에게 위치 권한을 요청함
  Future<bool> _checkAndRequestLocationPermission() async {
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isServiceEnabled) {
      _showMapSnackBar('기기의 위치 서비스가 꺼져 있습니다. 위치 서비스를 켜 주세요.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _showMapSnackBar('현재 위치를 사용하려면 위치 권한을 허용해야 합니다.');
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _showMapSnackBar('위치 권한이 차단되어 있습니다. 앱 설정에서 위치 권한을 허용해 주세요.');
      return false;
    }

    return true;
  }

  // 지도 생성 후 현재 위치를 가져오고, 현재 위치 방향 마커를 표시하도록 초기화
  Future<void> _initializeCurrentLocation() async {
    if (_isLoadingCurrentLocation) {
      return;
    }

    setState(() {
      _isLoadingCurrentLocation = true;
    });

    final hasPermission = await _checkAndRequestLocationPermission();

    if (!mounted) {
      return;
    }

    if (!hasPermission) {
      setState(() {
        _isLocationPermissionGranted = false;
        _isLoadingCurrentLocation = false;
      });
      return;
    }

    setState(() {
      _isLocationPermissionGranted = true;
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) {
        return;
      }

      final currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentUserPosition = currentLatLng;
        _currentHeading = _normalizeHeading(position.heading);
        _isLoadingCurrentLocation = false;
      });

      // 앱을 처음 켰을 때 현재 위치로 카메라 이동
      await _moveCameraToCurrentLocation(currentLatLng);

      // 현재 위치 주변 장소를 Nearby Search로 불러옴
      await context.read<MapProvider>().loadNearbyPlaces(
        latitude: currentLatLng.latitude,
        longitude: currentLatLng.longitude,
      );

      // 사용자가 움직일 때 위치와 방향을 계속 업데이트
      _startLocationUpdates();
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

  // 사용자의 위치와 바라보는 방향을 계속 감지
  void _startLocationUpdates() {
    _positionSubscription?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,

      // 사용자가 약 5m 이상 이동했을 때 위치 업데이트
      distanceFilter: 5,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
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

            // 주의:
            // 여기서 매번 카메라를 현재 위치로 이동시키면
            // 사용자가 지도를 둘러보는 중에도 화면이 계속 현재 위치로 끌려감.
            // 그래서 위치 마커만 움직이고, 카메라는 현재 위치 버튼을 눌렀을 때만 이동시킴.
          },
          onError: (error) {
            debugPrint('현재 위치 업데이트 실패: $error');
          },
        );
  }

  // heading 값 보정
  // Geolocator에서 방향을 알 수 없을 때 -1이 들어올 수 있으므로 기존 방향값을 유지함
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

    final hasPermission = await _checkAndRequestLocationPermission();

    if (!mounted) {
      return;
    }

    if (!hasPermission) {
      setState(() {
        _isLocationPermissionGranted = false;
        _isLoadingCurrentLocation = false;
      });
      return;
    }

    setState(() {
      _isLocationPermissionGranted = true;
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) {
        return;
      }

      final currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentUserPosition = currentLatLng;
        _currentHeading = _normalizeHeading(position.heading);
        _isLoadingCurrentLocation = false;
      });

      await _moveCameraToCurrentLocation(currentLatLng);

      // 혹시 위치 스트림이 멈춰 있었을 수 있으므로 다시 시작
      _startLocationUpdates();
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

  // 현재 위치 방향 마커를 생성
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

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCameraPosition,
          onMapCreated: _onMapCreated,

          // 백엔드에서 받아온 장소 목록 + 현재 위치 방향 마커를 함께 표시함
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
          mapType: MapType.normal,

          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,

          compassEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,

          // 현재 위치는 직접 만든 방향 마커로 표시하므로
          // GoogleMap 기본 현재 위치 파란 점은 꺼둠
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
        ),

        // 현재 위치로 이동 버튼
        Positioned(
          right: 16,
          bottom: selectedPlace == null ? 24 : 220,
          child: FloatingActionButton(
            heroTag: 'currentLocationButton',
            onPressed: _isLoadingCurrentLocation
                ? null
                : _onCurrentLocationPressed,
            child: _isLoadingCurrentLocation
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location),
          ),
        ),

        // 마커를 클릭했을 때만 하단에 장소 상세 카드를 보여줌
        if (selectedPlace != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PlaceDetailCard(
              place: selectedPlace,

              // 닫기 버튼을 누르면 선택된 장소를 해제해서 카드를 숨김
              onClose: context.read<MapProvider>().clearSelectedPlace,
            ),
          ),
      ],
    );
  }
}
