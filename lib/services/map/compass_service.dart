import 'package:flutter_compass/flutter_compass.dart';

/// 휴대폰이 바라보는 방향(heading)을 제공하는 서비스.
class CompassService {
  const CompassService();

  // 휴대폰의 방향값을 실시간으로 전달함.
  Stream<double> getHeadingStream() {
    final events = FlutterCompass.events;

    // 방향 센서 Stream을 사용할 수 없으면 빈 Stream 반환
    if (events == null) {
      return const Stream<double>.empty();
    }

    return events
        // heading이 없는 이벤트는 제외
        .where((event) => event.heading != null)
        // heading 값을 0 ~ 360도로 보정
        .map((event) => _normalizeHeading(event.heading!));
  }

  // heading 값을 0 ~ 360도 범위로 보정함.
  double _normalizeHeading(double heading) {
    final normalized = heading % 360;

    if (normalized < 0) {
      return normalized + 360;
    }

    return normalized;
  }
}
