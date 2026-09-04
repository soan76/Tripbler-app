import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tripbler/core/config/api_config.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/services/auth/auth_api_messages.dart';
import 'package:tripbler/services/auth/auth_api_service.dart';

class _TestAuthApiMessages extends AuthApiMessages {
  const _TestAuthApiMessages();

  @override
  String get requestSerializationFailed => 'REQUEST_SERIALIZATION_FAILED';

  @override
  String get requestTimeout => 'REQUEST_TIMEOUT';

  @override
  String get connectionFailed => 'CONNECTION_FAILED';

  @override
  String get invalidServerResponse => 'INVALID_SERVER_RESPONSE';

  @override
  String get invalidLoginResponse => 'INVALID_LOGIN_RESPONSE';

  @override
  String get invalidSignupResponse => 'INVALID_SIGNUP_RESPONSE';

  @override
  String get invalidLoginIdAvailabilityResponse =>
      'INVALID_LOGIN_ID_AVAILABILITY_RESPONSE';

  @override
  String get invalidFindIdResponse => 'INVALID_FIND_ID_RESPONSE';

  @override
  String get invalidPasswordResetVerificationResponse =>
      'INVALID_PASSWORD_RESET_VERIFICATION_RESPONSE';

  @override
  String get invalidTokenRefreshResponse => 'INVALID_TOKEN_REFRESH_RESPONSE';

  @override
  String get invalidCurrentUserResponse => 'INVALID_CURRENT_USER_RESPONSE';

  @override
  String get invalidSocialAccountStatusResponse =>
      'INVALID_SOCIAL_ACCOUNT_STATUS_RESPONSE';

  @override
  String forStatusCode({required int statusCode, String? serverMessage}) {
    if (serverMessage != null && serverMessage.trim().isNotEmpty) {
      return serverMessage;
    }

    return 'STATUS_$statusCode';
  }
}

void main() {
  group('AuthApiService deleteAccount', () {
    AuthApiService createService(MockClient client) {
      final service = AuthApiService(
        client: client,
        messages: const _TestAuthApiMessages(),
      );

      addTearDown(service.dispose);

      return service;
    }

    test(
      'DELETE /api/v1/users/me 요청에 Authorization 헤더를 포함하고 204를 성공 처리한다',
      () async {
        late http.Request capturedRequest;

        final client = MockClient((request) async {
          capturedRequest = request;

          return http.Response('', 204);
        });

        final service = createService(client);

        await service.deleteAccount(authorizationHeader: 'Bearer access-token');

        expect(capturedRequest.method, 'DELETE');
        expect(capturedRequest.url, ApiConfig.usersMeUri);
        expect(capturedRequest.headers['Authorization'], 'Bearer access-token');
        expect(capturedRequest.headers['Accept'], 'application/json');

        // 현재 AuthApiService는 본문 없는 DELETE에도
        // Content-Type: application/json을 명시한다.
        expect(capturedRequest.headers['Content-Type'], 'application/json');
      },
    );

    test('Authorization 헤더 앞뒤 공백을 제거해서 전송한다', () async {
      late http.Request capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;

        return http.Response('', 204);
      });

      final service = createService(client);

      await service.deleteAccount(
        authorizationHeader: '  Bearer access-token  ',
      );

      expect(capturedRequest.headers['Authorization'], 'Bearer access-token');
    });

    test('200 응답이면서 본문이 비어 있으면 호환 성공으로 처리한다', () async {
      final client = MockClient((request) async {
        return http.Response('', 200);
      });

      final service = createService(client);

      await expectLater(
        service.deleteAccount(authorizationHeader: 'Bearer access-token'),
        completes,
      );
    });

    test('401 ErrorResponse를 ApiException으로 변환한다', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'timestamp': '2026-09-04T15:00:00Z',
            'status': 401,
            'code': 'UNAUTHORIZED',
            'message': 'Access Token이 만료되었습니다.',
            'path': '/api/v1/users/me',
          }),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = createService(client);

      await expectLater(
        service.deleteAccount(authorizationHeader: 'Bearer expired-token'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.code, 'code', 'UNAUTHORIZED')
              .having(
                (error) => error.message,
                'message',
                'Access Token이 만료되었습니다.',
              )
              .having((error) => error.path, 'path', '/api/v1/users/me'),
        ),
      );
    });

    test('500 응답 본문이 비어 있으면 상태코드 메시지 선택 로직을 사용한다', () async {
      final client = MockClient((request) async {
        return http.Response('', 500);
      });

      final service = createService(client);

      await expectLater(
        service.deleteAccount(authorizationHeader: 'Bearer access-token'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 500)
              .having((error) => error.message, 'message', 'STATUS_500'),
        ),
      );
    });

    test('HTTP Client 연결 오류를 connectionFailed 메시지로 변환한다', () async {
      final client = MockClient((request) async {
        throw http.ClientException('테스트용 네트워크 오류', request.url);
      });

      final service = createService(client);

      await expectLater(
        service.deleteAccount(authorizationHeader: 'Bearer access-token'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'CONNECTION_FAILED',
          ),
        ),
      );
    });

    test('200 응답에 본문이 있으면 성공으로 처리하지 않고 ApiException을 발생시킨다', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'timestamp': '2026-09-04T15:00:00Z',
            'status': 200,
            'code': 'UNEXPECTED_BODY',
            'message': '예상하지 않은 응답 본문입니다.',
            'path': '/api/v1/users/me',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = createService(client);

      await expectLater(
        service.deleteAccount(authorizationHeader: 'Bearer access-token'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 200)
              .having((error) => error.message, 'message', '예상하지 않은 응답 본문입니다.'),
        ),
      );
    });

    test('비 JSON 오류 본문은 invalidServerResponse로 변환한다', () async {
      final client = MockClient((request) async {
        return http.Response(
          '<html><body>Bad Gateway</body></html>',
          502,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final service = createService(client);

      await expectLater(
        service.deleteAccount(authorizationHeader: 'Bearer access-token'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 502)
              .having(
                (error) => error.message,
                'message',
                'INVALID_SERVER_RESPONSE',
              ),
        ),
      );
    });

    test('빈 Authorization 값은 Authorization 헤더 없이 전송한다', () async {
      late http.Request capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;

        return http.Response('', 204);
      });

      final service = createService(client);

      await service.deleteAccount(authorizationHeader: '   ');

      expect(capturedRequest.headers.containsKey('Authorization'), isFalse);
    });
  });
}