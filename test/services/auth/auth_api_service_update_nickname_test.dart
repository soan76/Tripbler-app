import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/config/api_config.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/services/auth/auth_api_service.dart';

void main() {
  group('AuthApiService updateNickname', () {
    test('PATCH 요청에 Authorization 헤더와 닉네임 JSON을 포함한다', () async {
      late http.Request capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;

        return http.Response(
          jsonEncode({'id': 1, 'loginId': 'testuser01', 'nickname': '새닉네임'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AuthApiService(client: client);

      final response = await service.updateNickname(
        authorizationHeader: 'Bearer access-token',
        nickname: '새닉네임',
      );

      expect(capturedRequest.method, 'PATCH');
      expect(capturedRequest.url, ApiConfig.usersMeNicknameUri);
      expect(capturedRequest.headers['Authorization'], 'Bearer access-token');
      expect(capturedRequest.headers['Accept'], 'application/json');
      expect(capturedRequest.headers['Content-Type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), {'nickname': '새닉네임'});

      expect(response.id, 1);
      expect(response.loginId, 'testuser01');
      expect(response.nickname, '새닉네임');

      service.dispose();
    });

    test('Authorization 헤더 앞뒤 공백을 제거해서 전송한다', () async {
      late http.Request capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;

        return http.Response(
          jsonEncode({'id': 1, 'loginId': 'testuser01', 'nickname': '가'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AuthApiService(client: client);

      await service.updateNickname(
        authorizationHeader: '  Bearer access-token  ',
        nickname: '가',
      );

      expect(capturedRequest.headers['Authorization'], 'Bearer access-token');

      service.dispose();
    });

    test('400 ErrorResponse를 ApiException으로 변환한다', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'timestamp': '2026-09-07T19:00:00Z',
            'status': 400,
            'code': 'INVALID_REQUEST',
            'message': '닉네임은 1자 이상 20자 이하여야 합니다.',
            'path': '/api/v1/users/me/nickname',
          }),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = AuthApiService(client: client);

      await expectLater(
        service.updateNickname(
          authorizationHeader: 'Bearer access-token',
          nickname: '123456789012345678901',
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.code, 'code', 'INVALID_REQUEST')
              .having(
                (error) => error.message,
                'message',
                '닉네임은 1자 이상 20자 이하여야 합니다.',
              )
              .having(
                (error) => error.path,
                'path',
                '/api/v1/users/me/nickname',
              ),
        ),
      );

      service.dispose();
    });
  });
}