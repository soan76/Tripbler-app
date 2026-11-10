import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/config/api_config.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/services/place_api_service.dart';

const String _authorizationHeader = 'Bearer test-access-token';

http.Response _jsonResponse(Object body, int statusCode) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

Map<String, Object?> _errorBody(int status, String code, String message) {
  return <String, Object?>{
    'timestamp': '2026-11-10T00:00:00',
    'status': status,
    'code': code,
    'message': message,
    'path': '/api/v1/places/search',
  };
}

Future<ApiException> _searchError(
  http.Client client, {
  String query = '경복궁',
}) async {
  final service = PlaceApiService(client: client);

  try {
    await service.searchPlaces(
      query: query,
      authorizationHeader: _authorizationHeader,
    );
  } on ApiException catch (error) {
    return error;
  }

  fail('ApiException이 발생해야 합니다.');
}

void main() {
  group('ApiConfig 장소 경로', () {
    test('검색 URL은 한글·공백 검색어를 인코딩하고 좌표를 함께 넣는다', () {
      final uri = ApiConfig.placesSearchUri(
        query: '서울 경복궁',
        latitude: 37.5665,
        longitude: 126.978,
      );

      expect(uri.path, '/api/v1/places/search');
      expect(uri.queryParameters, <String, String>{
        'query': '서울 경복궁',
        'lat': '37.5665',
        'lng': '126.978',
      });
      expect(uri.toString(), isNot(contains(' ')));
    });

    test('좌표가 없으면 검색어만 넣는다', () {
      final uri = ApiConfig.placesSearchUri(query: '경복궁');

      expect(uri.queryParameters, <String, String>{'query': '경복궁'});
    });

    test('좌표를 하나만 넣으면 ArgumentError를 던진다', () {
      expect(
        () => ApiConfig.placesSearchUri(query: '경복궁', latitude: 37.5),
        throwsArgumentError,
      );
      expect(
        () => ApiConfig.placesSearchUri(query: '경복궁', longitude: 126.9),
        throwsArgumentError,
      );
    });

    test('상세 URL은 placeId를 경로 조각으로 인코딩한다', () {
      final uri = ApiConfig.placeDetailsUri(placeId: 'a/b?c#d');

      expect(uri.pathSegments, <String>['api', 'v1', 'places', 'a/b?c#d']);
      expect(uri.path, '/api/v1/places/a%2Fb%3Fc%23d');
      expect(uri.hasQuery, isFalse);
      expect(uri.hasFragment, isFalse);
    });

    test('주변·최근접 URL은 기존과 같은 파라미터를 쓴다', () {
      final nearby = ApiConfig.placesNearbyUri(
        latitude: 37.5,
        longitude: 126.9,
        type: 'restaurant',
        radius: 1000,
      );
      final nearest = ApiConfig.placesNearestUri(
        latitude: 37.5,
        longitude: 126.9,
        radius: 40,
      );

      expect(nearby.path, '/api/v1/places/nearby');
      expect(nearby.queryParameters, <String, String>{
        'lat': '37.5',
        'lng': '126.9',
        'type': 'restaurant',
        'radius': '1000',
      });
      expect(nearest.path, '/api/v1/places/nearest');
      expect(nearest.queryParameters, <String, String>{
        'lat': '37.5',
        'lng': '126.9',
        'radius': '40',
      });
    });
  });

  group('PlaceApiService searchPlaces', () {
    test('토큰을 붙여 검색하고 응답을 변환한다(rating·openNow는 null)', () async {
      late http.Request captured;

      final client = MockClient((request) async {
        captured = request;

        return _jsonResponse(<Object?>[
          <String, Object?>{
            'id': 'place-1',
            'name': '경복궁',
            'latitude': 37.5796,
            'longitude': 126.977,
            'address': '서울특별시 종로구 사직로 161',
            'rating': null,
            'category': 'tourist_attraction',
            'openNow': null,
          },
        ], 200);
      });

      final places = await PlaceApiService(client: client).searchPlaces(
        query: '경복궁',
        latitude: 37.5665,
        longitude: 126.978,
        authorizationHeader: _authorizationHeader,
      );

      expect(captured.method, 'GET');
      expect(captured.url.path, '/api/v1/places/search');
      expect(captured.url.queryParameters, <String, String>{
        'query': '경복궁',
        'lat': '37.5665',
        'lng': '126.978',
      });
      expect(captured.headers['Authorization'], _authorizationHeader);

      expect(places, hasLength(1));
      expect(places.single.id, 'place-1');
      expect(places.single.name, '경복궁');
      expect(places.single.latitude, 37.5796);
      expect(places.single.rating, isNull);
      expect(places.single.openNow, isNull);
    });

    test('좌표 없이 검색하면 query만 보낸다', () async {
      late Uri capturedUrl;

      final client = MockClient((request) async {
        capturedUrl = request.url;
        return _jsonResponse(<Object?>[], 200);
      });

      await PlaceApiService(
        client: client,
      ).searchPlaces(query: '경복궁', authorizationHeader: _authorizationHeader);

      expect(capturedUrl.queryParameters, <String, String>{'query': '경복궁'});
    });

    test('결과가 없으면 빈 목록을 돌려준다', () async {
      final client = MockClient((_) async => _jsonResponse(<Object?>[], 200));

      final places = await PlaceApiService(
        client: client,
      ).searchPlaces(query: '없는장소', authorizationHeader: _authorizationHeader);

      expect(places, isEmpty);
    });

    test('400이면 서버 code와 문구를 담는다', () async {
      final error = await _searchError(
        MockClient(
          (_) async => _jsonResponse(
            _errorBody(400, 'INVALID_REQUEST', '검색어는 공백을 제외하고 1~100자여야 합니다.'),
            400,
          ),
        ),
      );

      expect(error.statusCode, 400);
      expect(error.code, 'INVALID_REQUEST');
      expect(error.message, '검색어는 공백을 제외하고 1~100자여야 합니다.');
      expect(error.isNetworkError, isFalse);
    });

    test('401이면 statusCode 401로 던진다(재시도는 authorizedRequest가 맡음)', () async {
      final error = await _searchError(
        MockClient(
          (_) async =>
              _jsonResponse(_errorBody(401, 'UNAUTHORIZED', '인증이 필요합니다.'), 401),
        ),
      );

      expect(error.statusCode, 401);
      expect(error.code, 'UNAUTHORIZED');
    });

    test('503이면 장소 서비스 장애 문구와 code를 담는다', () async {
      final error = await _searchError(
        MockClient(
          (_) async => _jsonResponse(
            _errorBody(
              503,
              'PLACES_PROVIDER_UNAVAILABLE',
              '현재 장소 정보 제공 서비스를 이용할 수 없습니다.',
            ),
            503,
          ),
        ),
      );

      expect(error.statusCode, 503);
      expect(error.code, 'PLACES_PROVIDER_UNAVAILABLE');
      expect(error.message, contains('장소 서비스를 일시적으로 사용할 수 없습니다'));
    });

    test('500이면 일반 실패 문구를 쓴다', () async {
      final error = await _searchError(
        MockClient(
          (_) async => _jsonResponse(
            _errorBody(500, 'INTERNAL_SERVER_ERROR', '서버 내부 오류'),
            500,
          ),
        ),
      );

      expect(error.statusCode, 500);
      expect(error.code, 'INTERNAL_SERVER_ERROR');
      expect(error.message, '장소를 검색하지 못했습니다. 잠시 후 다시 시도해 주세요.');
    });

    test('오류 본문이 JSON이 아니어도 상태 코드를 유지한다', () async {
      final error = await _searchError(
        MockClient((_) async => http.Response('Bad Gateway', 502)),
      );

      expect(error.statusCode, 502);
      expect(error.code, isNull);
      expect(error.isNetworkError, isFalse);
    });

    test('200인데 목록이 아니면 응답 형식 오류로 던진다', () async {
      final error = await _searchError(
        MockClient(
          (_) async =>
              _jsonResponse(<String, Object?>{'places': <Object?>[]}, 200),
        ),
      );

      expect(error.statusCode, 200);
      expect(error.message, '장소 검색 응답 형식이 올바르지 않습니다.');
    });

    test('연결에 실패하면 네트워크 오류로 던진다', () async {
      final error = await _searchError(
        MockClient((_) async => throw http.ClientException('연결 실패')),
      );

      expect(error.isNetworkError, isTrue);
      expect(error.message, contains('연결할 수 없습니다'));
    });

    test('기본 제한 시간은 8초다', () {
      expect(PlaceApiService.defaultTimeout, const Duration(seconds: 8));
    });

    test('응답이 제한 시간 안에 오지 않으면 네트워크 오류로 던진다', () async {
      final neverCompletes = Completer<http.Response>();
      final service = PlaceApiService(
        client: MockClient((_) => neverCompletes.future),
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.searchPlaces(
          query: '경복궁',
          authorizationHeader: _authorizationHeader,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((e) => e.message, 'message', contains('시간이 초과')),
        ),
      );
    });
  });
}
