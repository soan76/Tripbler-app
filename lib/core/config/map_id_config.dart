import 'dart:io';

class MapIdConfig {
  const MapIdConfig._();

  static const String androidMapId = '9e1a9072546f6f9a95275147';

  static const String iosMapId = '9e1a9072546f6f9af8587e8f';

  static String get current {
    if (Platform.isAndroid) {
      return androidMapId;
    }

    if (Platform.isIOS) {
      return iosMapId;
    }

    throw UnsupportedError('지원하지 않는 플랫폼입니다.');
  }
}
