import 'dart:async';

import 'package:tripbler/models/place_model.dart';
import 'package:tripbler/services/place_api_service.dart';

PlaceModel testPlace(String id) {
  return PlaceModel(
    id: id,
    name: '장소 $id',
    latitude: 37.5,
    longitude: 126.9,
    address: '주소 $id',
    rating: null,
    category: 'tourist_attraction',
    openNow: null,
  );
}

/// 검색·상세 응답 시점을 테스트가 [Completer]로 정하는 장소 API 대역.
class HeldPlaceApi extends PlaceApiService {
  final List<String> searchQueries = <String>[];
  final List<Completer<List<PlaceModel>>> searches =
      <Completer<List<PlaceModel>>>[];
  final List<String> detailCalls = <String>[];
  final List<Completer<PlaceModel>> details = <Completer<PlaceModel>>[];

  @override
  Future<List<PlaceModel>> searchPlaces({
    required String query,
    double? latitude,
    double? longitude,
    required String authorizationHeader,
  }) {
    searchQueries.add(query);
    final completer = Completer<List<PlaceModel>>();
    searches.add(completer);
    return completer.future;
  }

  @override
  Future<PlaceModel> fetchPlaceDetails({
    required String placeId,
    required String authorizationHeader,
  }) {
    detailCalls.add(placeId);
    final completer = Completer<PlaceModel>();
    details.add(completer);
    return completer.future;
  }
}

/// 토큰만 붙여 요청을 그대로 실행하는 요청 실행기(`authorizedRequestRunnerProvider` 대역).
Future<T> passThroughRunner<T>(
  Future<T> Function(String authorizationHeader) request,
) => request('Bearer test-access-token');
