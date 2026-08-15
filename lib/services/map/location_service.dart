import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// 위치 서비스와 권한을 관리하는 서비스 클래스
class LocationService {
  const LocationService();

  // 위치 서비스와 권한 상태를 확인하고,
  // 필요하면 사용자에게 위치 권한을 요청함.
  Future<void> ensureLocationPermission() async {
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isServiceEnabled) {
      throw const LocationServiceException(
        message: '기기의 위치 서비스가 꺼져 있습니다. 위치 서비스를 켜 주세요.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationServiceException(
        message: '현재 위치를 사용하려면 위치 권한을 허용해야 합니다.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationServiceException(
        message: '위치 권한이 차단되어 있습니다. 앱 설정에서 위치 권한을 허용해 주세요.',
      );
    }
  }

  // 저장되어 있는 최근 위치를 가져옴.
  Future<Position?> getLastKnownPosition() async {
    await ensureLocationPermission();

    try {
      return await Geolocator.getLastKnownPosition();
    } catch (error) {
      debugPrint('최근 위치 가져오기 실패: $error');

      return null;
    }
  }

  // 현재 위치를 1회 가져옴.
  Future<Position> getCurrentPosition({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await ensureLocationPermission();

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: timeout,
    );

    return Geolocator.getCurrentPosition(locationSettings: locationSettings);
  }

  // 사용자의 위치 변화를 지속적으로 감지함.
  Stream<Position> getPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,

      // 약 5m 이상 이동했을 때 위치 업데이트
      distanceFilter: 5,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}

/// 위치 관련 오류를 화면 계층으로 전달하기 위한 예외
class LocationServiceException implements Exception {
  final String message;

  const LocationServiceException({required this.message});

  @override
  String toString() {
    return message;
  }
}
