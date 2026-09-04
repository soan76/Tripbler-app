import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/auth/token_refresh_request.dart';
import 'package:tripbler/models/auth/token_refresh_response.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';
import 'package:tripbler/services/auth/auth_api_service.dart';
import 'package:tripbler/services/auth/token_storage_service.dart';

class FakeAuthApiService extends AuthApiService {
  final List<String> deleteAuthorizationHeaders = <String>[];

  int deleteAccountCallCount = 0;
  int refreshCallCount = 0;

  bool failFirstDeleteWith401 = false;
  Object? deleteAccountError;
  Object? refreshError;

  @override
  Future<void> deleteAccount({required String authorizationHeader}) async {
    deleteAccountCallCount++;
    deleteAuthorizationHeaders.add(authorizationHeader);

    if (failFirstDeleteWith401 && deleteAccountCallCount == 1) {
      throw const ApiException(
        statusCode: 401,
        message: 'Access Token이 만료되었습니다.',
      );
    }

    final error = deleteAccountError;
    if (error != null) {
      throw error;
    }
  }

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

  Object? clearTokensError;

  int clearTokensCallCount = 0;
  int saveAccessTokenCallCount = 0;

  @override
  Future<String?> readAuthorizationHeader() async {
    return authorizationHeader;
  }

  @override
  Future<String?> readRefreshToken() async {
    return refreshToken;
  }

  @override
  Future<void> saveAccessToken({
    required String accessToken,
    String? tokenType,
  }) async {
    saveAccessTokenCallCount++;

    final effectiveTokenType = tokenType ?? 'Bearer';

    authorizationHeader = '$effectiveTokenType $accessToken';
  }

  @override
  Future<void> clearTokens() async {
    clearTokensCallCount++;

    final error = clearTokensError;
    if (error != null) {
      throw error;
    }

    authorizationHeader = null;
    refreshToken = null;
  }
}

void main() {
  late FakeAuthApiService apiService;
  late FakeTokenStorageService tokenStorageService;
  late AuthRepository repository;

  setUp(() {
    apiService = FakeAuthApiService();
    tokenStorageService = FakeTokenStorageService();

    repository = AuthRepository(
      authApiService: apiService,
      tokenStorageService: tokenStorageService,
    );
  });

  tearDown(() {
    repository.dispose();
  });

  group('AuthRepository deleteAccount', () {
    test('계정 탈퇴 성공 시 Access Token으로 API를 호출하고 로컬 토큰을 삭제한다', () async {
      await repository.deleteAccount();

      expect(apiService.deleteAccountCallCount, 1);
      expect(apiService.deleteAuthorizationHeaders, <String>[
        'Bearer old-access-token',
      ]);

      expect(tokenStorageService.clearTokensCallCount, 1);
      expect(tokenStorageService.authorizationHeader, isNull);
      expect(tokenStorageService.refreshToken, isNull);
    });

    test('계정 탈퇴 API가 실패하면 예외를 전달하고 로컬 토큰을 유지한다', () async {
      apiService.deleteAccountError = const ApiException(
        statusCode: 500,
        message: '계정 탈퇴 처리에 실패했습니다.',
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 500)
              .having((error) => error.message, 'message', '계정 탈퇴 처리에 실패했습니다.'),
        ),
      );

      expect(apiService.deleteAccountCallCount, 1);
      expect(tokenStorageService.clearTokensCallCount, 0);
      expect(
        tokenStorageService.authorizationHeader,
        'Bearer old-access-token',
      );
      expect(tokenStorageService.refreshToken, 'refresh-token');
    });

    test('Access Token 401이면 재발급 후 계정 탈퇴 요청을 한 번 재시도한다', () async {
      apiService.failFirstDeleteWith401 = true;

      await repository.deleteAccount();

      expect(apiService.deleteAccountCallCount, 2);
      expect(apiService.refreshCallCount, 1);
      expect(tokenStorageService.saveAccessTokenCallCount, 1);

      expect(apiService.deleteAuthorizationHeaders, <String>[
        'Bearer old-access-token',
        'Bearer new-access-token',
      ]);

      expect(tokenStorageService.clearTokensCallCount, 1);
      expect(tokenStorageService.authorizationHeader, isNull);
      expect(tokenStorageService.refreshToken, isNull);
    });

    test('저장된 Access Token이 없으면 계정 탈퇴 API를 호출하지 않는다', () async {
      tokenStorageService.authorizationHeader = null;

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<AuthSessionException>().having(
            (error) => error.message,
            'message',
            '저장된 Access Token이 없습니다.',
          ),
        ),
      );

      expect(apiService.deleteAccountCallCount, 0);
      expect(apiService.refreshCallCount, 0);
      expect(tokenStorageService.clearTokensCallCount, 0);
    });

    test('401 이후 Refresh Token이 없으면 재발급하지 않고 예외를 전달한다', () async {
      apiService.failFirstDeleteWith401 = true;
      tokenStorageService.refreshToken = null;

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<AuthSessionException>().having(
            (error) => error.message,
            'message',
            '저장된 Refresh Token이 없습니다.',
          ),
        ),
      );

      expect(apiService.deleteAccountCallCount, 1);
      expect(apiService.refreshCallCount, 0);
      expect(tokenStorageService.saveAccessTokenCallCount, 0);
      expect(tokenStorageService.clearTokensCallCount, 0);
    });

    test('401 이후 Refresh API가 실패하면 탈퇴 요청을 재시도하지 않는다', () async {
      apiService.failFirstDeleteWith401 = true;
      apiService.refreshError = const ApiException(
        statusCode: 401,
        message: 'Refresh Token이 만료되었습니다.',
      );

      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.message,
                'message',
                'Refresh Token이 만료되었습니다.',
              ),
        ),
      );

      expect(apiService.deleteAccountCallCount, 1);
      expect(apiService.refreshCallCount, 1);
      expect(tokenStorageService.saveAccessTokenCallCount, 0);
      expect(tokenStorageService.clearTokensCallCount, 0);

      expect(
        tokenStorageService.authorizationHeader,
        'Bearer old-access-token',
      );
      expect(tokenStorageService.refreshToken, 'refresh-token');
    });

    test('서버 계정 삭제 성공 후 로컬 토큰 삭제가 실패해도 예외를 다시 던지지 않는다', () async {
      tokenStorageService.clearTokensError = StateError('테스트용 토큰 삭제 실패');

      await repository.deleteAccount();

      expect(apiService.deleteAccountCallCount, 1);
      expect(apiService.refreshCallCount, 0);
      expect(tokenStorageService.clearTokensCallCount, 1);

      // 현재 Repository는 clearTokens 실패를 로그만 남기고 흡수한다.
      expect(
        tokenStorageService.authorizationHeader,
        'Bearer old-access-token',
      );
      expect(tokenStorageService.refreshToken, 'refresh-token');
    });
  });
}