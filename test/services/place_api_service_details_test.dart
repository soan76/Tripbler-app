import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/services/place_api_service.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('상세 요청에 Authorization 헤더를 붙인다', () async {
    String? sentHeader;
    final service = PlaceApiService(
      client: MockClient((request) async {
        sentHeader = request.headers['Authorization'];
        return _json({'id': 'a', 'name': '경복궁', 'address': '서울'}, 200);
      }),
    );

    final place = await service.fetchPlaceDetails(
      placeId: 'a',
      authorizationHeader: 'Bearer t',
    );

    expect(sentHeader, 'Bearer t');
    expect(place.id, 'a');
  });

  test('상세 401은 statusCode 401인 ApiException', () async {
    final service = PlaceApiService(
      client: MockClient(
        (_) async => _json({
          'status': 401,
          'code': 'UNAUTHORIZED',
          'message': '인증이 필요합니다.',
        }, 401),
      ),
    );

    await expectLater(
      service.fetchPlaceDetails(placeId: 'a', authorizationHeader: 'Bearer t'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });

  test('상세 429는 서버 message를 담은 ApiException', () async {
    const message = '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';
    final service = PlaceApiService(
      client: MockClient(
        (_) async => _json({
          'status': 429,
          'code': 'TOO_MANY_REQUESTS',
          'message': message,
        }, 429),
      ),
    );

    await expectLater(
      service.fetchPlaceDetails(placeId: 'a', authorizationHeader: 'Bearer t'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.code, 'code', 'TOO_MANY_REQUESTS')
            .having((e) => e.message, 'message', message),
      ),
    );
  });

  test('상세 시간 초과는 statusCode가 null인 ApiException', () async {
    final service = PlaceApiService(
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) => Completer<http.Response>().future),
    );

    await expectLater(
      service.fetchPlaceDetails(placeId: 'a', authorizationHeader: 'Bearer t'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', isNull),
      ),
    );
  });

  test('상세 연결 실패는 statusCode가 null인 ApiException', () async {
    final service = PlaceApiService(
      client: MockClient((_) async => throw http.ClientException('연결 실패')),
    );

    await expectLater(
      service.fetchPlaceDetails(placeId: 'a', authorizationHeader: 'Bearer t'),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', isNull),
      ),
    );
  });

  test('상세 요청 중 프로그램 오류는 네트워크 오류로 바꾸지 않는다', () async {
    final service = PlaceApiService(
      client: MockClient((_) async => throw StateError('bug')),
    );

    await expectLater(
      service.fetchPlaceDetails(placeId: 'a', authorizationHeader: 'Bearer t'),
      throwsStateError,
    );
  });

  test('placeId가 비었거나 .. 이면 요청을 보내지 않는다', () async {
    var requests = 0;
    final service = PlaceApiService(
      client: MockClient((_) async {
        requests++;
        return _json(const <String, Object?>{}, 200);
      }),
    );

    for (final bad in ['', ' ', '.', '..']) {
      await expectLater(
        service.fetchPlaceDetails(
          placeId: bad,
          authorizationHeader: 'Bearer t',
        ),
        throwsArgumentError,
      );
    }

    expect(requests, 0);
  });
}
