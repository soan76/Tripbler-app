import 'package:url_launcher/url_launcher.dart';

import '../../models/place_model.dart';

/// 외부 URL을 여는 함수. 기본값은 `url_launcher`의 [launchUrl]이고 테스트에서 바꿔 넣는다.
typedef ExternalUrlLauncher = Future<bool> Function(Uri url, {LaunchMode mode});

/// 길찾기 열기 결과.
enum RouteLaunchResult {
  /// 외부 앱이나 브라우저로 넘겼다.
  opened,

  /// 열지 못했다(`false` 반환 또는 예외. `PlatformException` 외의 예외도 포함).
  failed,

  /// 앞선 열기가 아직 끝나지 않아 이번 요청은 무시했다.
  ignored,
}

/// 선택한 장소를 목적지로 한 Google 지도 길찾기를 외부 앱으로 연다.
///
/// 출발지와 이동 수단은 넣지 않는다. 현재 위치와 경로 선택은 Google 지도에 맡긴다.
/// `canLaunchUrl`로 미리 확인하지 않고 바로 열기 때문에 Android `<queries>` 설정이
/// 필요 없다.
class RouteLauncher {
  RouteLauncher({ExternalUrlLauncher launch = launchUrl}) : _launch = launch;

  final ExternalUrlLauncher _launch;

  bool _launching = false;

  /// 열기가 진행 중인지. 진행 중에 다시 요청하면 무시한다.
  bool get isLaunching => _launching;

  /// Google 지도 길찾기 URL.
  ///
  /// 장소 ID를 쓰더라도 `destination`은 필수라 이름을 함께 넣는다. 좌표가 없는 장소도
  /// 장소 ID로 열 수 있다. 이름의 `&`·`#`·한글은 [Uri.https]가 인코딩한다.
  static Uri directionsUri(PlaceModel place) {
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': place.name,
      'destination_place_id': place.id,
    });
  }

  /// 길찾기를 연다. 진행 중이면 [RouteLaunchResult.ignored]를 돌려준다.
  Future<RouteLaunchResult> openDirections(PlaceModel place) async {
    if (_launching) {
      return RouteLaunchResult.ignored;
    }

    _launching = true;

    try {
      final opened = await _launch(
        directionsUri(place),
        mode: LaunchMode.externalApplication,
      );

      return opened ? RouteLaunchResult.opened : RouteLaunchResult.failed;
    } catch (_) {
      // `PlatformException` 외에 플러그인 누락(`MissingPluginException`)이나
      // 지원하지 않는 플랫폼 오류도 사용자에게는 같은 실패 안내를 보여준다.
      return RouteLaunchResult.failed;
    } finally {
      _launching = false;
    }
  }
}
