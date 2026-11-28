import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_provider.dart';

/// 일정의 장소 고르기 화면이 쓰는 검색·선택 상태(docs/mockups/schedule.md 3-2절).
///
/// 지도 탭([mapProvider])과 같은 [MapNotifier]지만 따로 만든 상태라 지도 탭의 검색 결과·
/// 선택과 섞이지 않는다. 장소 고르기 화면을 닫으면 함께 사라진다.
final placePickerMapProvider =
    NotifierProvider.autoDispose<MapNotifier, MapState>(MapNotifier.new);
