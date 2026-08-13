import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  const LocationService();

  // 위치 서비스와 권한 상태를 확인하고,
  // 필요하면 사용자에게 위치 권한을 요청함.
  //
  // 이 서비스는 UI를 직접 알면 안 되기 때문에 SnackBar를 띄우지 않음.
  // 대신 실패 이유를 LocationServiceException으로 던지고,
  // 화면에서 그 메시지를 받아 SnackBar로 표시함.
  Future<void> ensureLocationPermission() async {
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isServiceEnabled) {
      throw const LocationServiceException(
        message: '기기의 위치 서비스가 꺼져 있습니다. 위치 서비스를 켜 주세요.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();

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

  // 현재 위치를 1회 가져옴.
  Future<Position> getCurrentPosition({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await ensureLocationPermission();

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(timeout);
  }

  // 사용자의 위치와 방향 변화를 계속 감지하는 스트림을 반환함.
  Stream<Position> getPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,

      // 사용자가 약 5m 이상 이동했을 때 위치 업데이트
      distanceFilter: 5,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}

class LocationServiceException implements Exception {
  final String message;

  const LocationServiceException({required this.message});

  @override
  String toString() {
    return message;
  }
}
