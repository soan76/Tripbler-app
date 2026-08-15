import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'compass_service.dart';
import 'location_service.dart';

/// 현재 위치와 휴대폰 방향 상태를 관리함.
class MapLocationController extends ChangeNotifier {
  final LocationService _locationService;
  final CompassService _compassService;

  MapLocationController({
    LocationService locationService = const LocationService(),
    CompassService compassService = const CompassService(),
  }) : _locationService = locationService,
       _compassService = compassService;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<double>? _compassSubscription;
  Timer? _headingSmoothingTimer;

  LatLng? _currentPosition;

  double _currentHeading = 0;
  double _targetHeading = 0;

  bool _isLoading = false;

  // timeout 메시지가 반복되는 것을 방지함.
  bool _hasShownTimeoutMessage = false;

  LatLng? get currentPosition => _currentPosition;

  double get currentHeading => _currentHeading;

  bool get isLoading => _isLoading;

  bool get hasShownTimeoutMessage => _hasShownTimeoutMessage;

  /// 방향 보간 처리를 시작함.
  void initialize() {
    _startHeadingSmoothing();
  }

  /// 현재 위치 권한을 확인하고 위치를 가져옴.
  ///
  /// 반환값:
  /// 위치를 가져왔으면 LatLng,
  /// 위치를 아직 확보하지 못했으면 null.
  Future<LatLng?> requestCurrentLocation() async {
    if (_isLoading) {
      return _currentPosition;
    }

    _setLoading(true);

    try {
      await _locationService.ensureLocationPermission();

      _hasShownTimeoutMessage = false;

      /*
       * 이미 위치 Stream 등을 통해 현재 위치가 있다면
       * 우선 기존 위치를 사용할 수 있음.
       */
      LatLng? availablePosition = _currentPosition;

      /*
       * 현재 위치가 없다면 기기의 최근 위치를 먼저 확인함.
       */
      if (availablePosition == null) {
        final lastPosition = await _locationService.getLastKnownPosition();

        if (lastPosition != null) {
          availablePosition = _setCurrentPosition(lastPosition);
        }
      }

      /*
       * 실제 최신 위치를 요청함.
       */
      try {
        final currentPosition = await _locationService.getCurrentPosition();

        availablePosition = _setCurrentPosition(currentPosition);

        _hasShownTimeoutMessage = false;
      } on TimeoutException {
        debugPrint('현재 위치 요청 시간 초과');

        /*
         * 최근 위치라도 있으면 그것을 유지하고
         * 위치 Stream에서 새로운 위치를 기다림.
         */
        _hasShownTimeoutMessage = availablePosition == null;
      }

      startTracking();

      return availablePosition;
    } finally {
      _setLoading(false);
    }
  }

  /// 위치 및 방향 실시간 추적을 시작함.
  void startTracking() {
    _startLocationUpdates();
    _startCompassUpdates();
  }

  /// 위치 Stream을 시작함.
  void _startLocationUpdates() {
    _positionSubscription?.cancel();

    _positionSubscription = _locationService.getPositionStream().listen(
      (position) {
        _setCurrentPosition(position);

        // 실제 위치를 받았으므로 timeout 상태 초기화
        _hasShownTimeoutMessage = false;
      },
      onError: (error) {
        debugPrint('현재 위치 업데이트 실패: $error');
      },
    );
  }

  /// 휴대폰 방향 센서를 시작함.
  void _startCompassUpdates() {
    _compassSubscription?.cancel();

    _compassSubscription = _compassService.getHeadingStream().listen(
      (heading) {
        _targetHeading = heading;
      },
      onError: (error) {
        debugPrint('방향 센서 업데이트 실패: $error');
      },
    );
  }

  /// Position을 LatLng로 변환하고 상태에 저장함.
  LatLng _setCurrentPosition(Position position) {
    final latLng = LatLng(position.latitude, position.longitude);

    _currentPosition = latLng;

    notifyListeners();

    return latLng;
  }

  /// heading을 부드럽게 회전시킴.
  void _startHeadingSmoothing() {
    _headingSmoothingTimer?.cancel();

    _headingSmoothingTimer = Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
      final difference = _shortestHeadingDifference(
        _currentHeading,
        _targetHeading,
      );

      if (difference.abs() < 0.1) {
        return;
      }

      _currentHeading = (_currentHeading + difference * 0.18 + 360) % 360;

      notifyListeners();
    });
  }

  /// 두 heading 사이의 가장 짧은 회전 거리를 계산함.
  double _shortestHeadingDifference(double current, double target) {
    return (target - current + 540) % 360 - 180;
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;

    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    _headingSmoothingTimer?.cancel();

    super.dispose();
  }
}
