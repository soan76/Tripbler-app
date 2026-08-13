import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapMarkerIconService {
  const MapMarkerIconService();

  // PNG 원본 크기가 커도 지도 마커에서는 지정한 크기로 보이도록 리사이즈함.
  //
  // assetPath:
  // assets/images/current_location_arrow.png 같은 이미지 경로.
  //
  // targetWidth:
  // 지도에 표시할 마커 이미지 너비.
  Future<BitmapDescriptor> createResizedBitmapDescriptor({
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
      throw Exception('지도 마커 아이콘 변환에 실패했습니다.');
    }

    return BitmapDescriptor.fromBytes(resizedData.buffer.asUint8List());
  }
}
