import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/auth/token_refresh_request.dart';
import 'package:tripbler/models/auth/token_refresh_response.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';
import 'package:tripbler/services/auth/auth_api_service.dart';
import 'package:tripbler/services/auth/token_storage_service.dart';

class FakeRefreshAuthApiService extends AuthApiService {
  int refreshCallCount = 0;

  /// refresh가 던질 오류. null이면 새 Access Token을 돌려준다.
  Object? refreshError;

  @override
  Future<TokenRefreshResponse> refresh(TokenRefreshRequest request) async {
    refreshCallCount++;

    final error = refreshError;

    if (error != null) {
      throw error;
    }

    return TokenRefreshResponse.fromJson({
      'accessToken': 'new-access-token',
      'tokenType': 'Bearer',
    });
  }

  @override
  void dispose() {}
}

class FakeTokenStorageService extends TokenStorageService {
  FakeTokenStorageService({
    this.authorizationHeader = 'Bearer old-access-token',
    this.refreshToken = 'refresh-token',
  });

  String? authorizationHeader;
  String? refreshToken;

  @override
  Future<String?> readAuthorizationHeader() async => authorizationHeader;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveAccessToken({
    required String accessToken,
    String? tokenType,
  }) async {
    authorizationHeader = '${tokenType ?? 'Bearer'} $accessToken';
  }
}

const ApiException _unauthorized = ApiException(
  statusCode: 401,
  code: 'UNAUTHORIZED',
  message: '인증이 필요합니다.',
);

void main() {
  late FakeRefreshAuthApiService apiService;
  late FakeTokenStorageService tokenStorageService;
  late AuthRepository repository;

  setUp(() {
    apiService = FakeRefreshAuthApiService();
    tokenStorageService = FakeTokenStorageService();
    repository = AuthRepository(
      authApiService: apiService,
      tokenStorageService: tokenStorageService,
    );
  });

  tearDown(() {
    repository.dispose();
  });

  group('AuthRepository authorizedRequest', () {
    test('저장된 Access Token으로 요청한다', () async {
      final headers = <String>[];

      final result = await repository.authorizedRequest<String>((header) async {
        headers.add(header);
        return 'ok';
      });

      expect(result, 'ok');
      expect(headers, <String>['Bearer old-access-token']);
      expect(apiService.refreshCallCount, 0);
    });

    test('401이면 재발급한 뒤 새 토큰으로 한 번만 다시 요청한다', () async {
      final headers = <String>[];

      final result = await repository.authorizedRequest<String>((header) async {
        headers.add(header);

        if (headers.length == 1) {
          throw _unauthorized;
        }

        return 'ok';
      });

      expect(result, 'ok');
      expect(headers, <String>[
        'Bearer old-access-token',
        'Bearer new-access-token',
      ]);
      expect(apiService.refreshCallCount, 1);
    });

    test('재발급 뒤에도 401이면 그 오류를 던지고 더 재시도하지 않는다', () async {
      var callCount = 0;

      await expectLater(
        repository.authorizedRequest<String>((_) async {
          callCount++;
          throw _unauthorized;
        }),
        throwsA(same(_unauthorized)),
      );

      expect(callCount, 2);
      expect(apiService.refreshCallCount, 1);
      expect(AuthRepository.isSessionExpiredError(_unauthorized), isFalse);
    });

    test('401이 아닌 오류는 재발급 없이 그대로 던진다', () async {
      const serverError = ApiException(statusCode: 503, message: '장애');

      await expectLater(
        repository.authorizedRequest<String>((_) async => throw serverError),
        throwsA(same(serverError)),
      );

      expect(apiService.refreshCallCount, 0);
    });

    for (final code in <String>[
      'EXPIRED_REFRESH_TOKEN',
      'INVALID_REFRESH_TOKEN',
    ]) {
      test('재발급이 $code로 실패하면 세션 만료로 판정된다', () async {
        final refreshError = ApiException(
          statusCode: 401,
          code: code,
          message: 'Refresh Token 오류',
        );
        apiService.refreshError = refreshError;

        Object? thrown;

        try {
          await repository.authorizedRequest<String>(
            (_) async => throw _unauthorized,
          );
        } catch (error) {
          thrown = error;
        }

        expect(thrown, same(refreshError));
        expect(AuthRepository.isSessionExpiredError(thrown!), isTrue);
      });
    }

    test('저장된 Refresh Token이 없으면 세션 만료로 판정된다', () async {
      tokenStorageService.refreshToken = null;

      Object? thrown;

      try {
        await repository.authorizedRequest<String>(
          (_) async => throw _unauthorized,
        );
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<AuthSessionException>());
      expect(AuthRepository.isSessionExpiredError(thrown!), isTrue);
      expect(apiService.refreshCallCount, 0);
    });

    test('저장된 Access Token이 없으면 요청하지 않고 세션 만료로 판정된다', () async {
      tokenStorageService.authorizationHeader = null;
      var callCount = 0;

      Object? thrown;

      try {
        await repository.authorizedRequest<String>((_) async {
          callCount++;
          return 'unused';
        });
      } catch (error) {
        thrown = error;
      }

      expect(callCount, 0);
      expect(thrown, isA<AuthSessionException>());
      expect(AuthRepository.isSessionExpiredError(thrown!), isTrue);
    });

    test('재발급 중 네트워크 오류나 5xx는 세션 만료로 판정하지 않는다', () async {
      for (final refreshError in const <ApiException>[
        ApiException(message: '서버에 연결할 수 없습니다.'),
        ApiException(
          statusCode: 500,
          code: 'INTERNAL_SERVER_ERROR',
          message: '서버 오류',
        ),
      ]) {
        apiService.refreshError = refreshError;

        Object? thrown;

        try {
          await repository.authorizedRequest<String>(
            (_) async => throw _unauthorized,
          );
        } catch (error) {
          thrown = error;
        }

        expect(thrown, same(refreshError));
        expect(AuthRepository.isSessionExpiredError(thrown!), isFalse);
      }
    });
  });
}
