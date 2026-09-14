import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/auth/token_refresh_request.dart';
import 'package:tripbler/models/auth/token_refresh_response.dart';
import 'package:tripbler/models/user/user_response.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';
import 'package:tripbler/services/auth/auth_api_service.dart';
import 'package:tripbler/services/auth/token_storage_service.dart';

class FakeNicknameAuthApiService extends AuthApiService {
  final List<String> authorizationHeaders = <String>[];
  final List<String> nicknames = <String>[];

  int updateNicknameCallCount = 0;
  int refreshCallCount = 0;

  bool failFirstUpdateWith401 = false;
  Object? updateNicknameError;

  @override
  Future<UserResponse> updateNickname({
    required String authorizationHeader,
    required String nickname,
  }) async {
    updateNicknameCallCount++;
    authorizationHeaders.add(authorizationHeader);
    nicknames.add(nickname);

    if (failFirstUpdateWith401 && updateNicknameCallCount == 1) {
      throw const ApiException(
        statusCode: 401,
        message: 'Access Token이 만료되었습니다.',
      );
    }

    final error = updateNicknameError;

    if (error != null) {
      throw error;
    }

    return UserResponse(
      id: 1,
      loginId: 'testuser01',
      nickname: nickname,
      profileImageUrl: 'https://example.com/profile.png',
    );
  }

  @override
  Future<TokenRefreshResponse> refresh(TokenRefreshRequest request) async {
    refreshCallCount++;

    return TokenRefreshResponse.fromJson({
      'accessToken': 'new-access-token',
      'tokenType': 'Bearer',
    });
  }

  @override
  void dispose() {}
}

class FakeNicknameTokenStorageService extends TokenStorageService {
  FakeNicknameTokenStorageService({
    this.authorizationHeader = 'Bearer old-access-token',
    this.refreshToken = 'refresh-token',
  });

  String? authorizationHeader;
  String? refreshToken;

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

    final normalizedTokenType = tokenType?.trim();

    authorizationHeader =
        normalizedTokenType != null && normalizedTokenType.isNotEmpty
        ? '$normalizedTokenType $accessToken'
        : accessToken;
  }
}

  void main() {
    late FakeNicknameAuthApiService apiService;
    late FakeNicknameTokenStorageService tokenStorageService;
    late AuthRepository repository;

    setUp(() {
      apiService = FakeNicknameAuthApiService();

      tokenStorageService = FakeNicknameTokenStorageService();

      repository = AuthRepository(
        authApiService: apiService,
        tokenStorageService: tokenStorageService,
      );
    });

    tearDown(() {
      repository.dispose();
    });

    group('AuthRepository updateNickname', () {
      test('현재 Access Token으로 닉네임 변경 API를 호출하고 UserResponse를 반환한다', () async {
        final response = await repository.updateNickname(nickname: '새닉네임');

        expect(apiService.updateNicknameCallCount, 1);
        expect(apiService.authorizationHeaders, <String>[
          'Bearer old-access-token',
        ]);
        expect(apiService.nicknames, <String>['새닉네임']);

        expect(response.loginId, 'testuser01');
        expect(response.nickname, '새닉네임');
        expect(response.profileImageUrl, 'https://example.com/profile.png');

        expect(apiService.refreshCallCount, 0);
      });

      test('Access Token이 만료되면 재발급 후 닉네임 변경 요청을 한 번 재시도한다', () async {
        apiService.failFirstUpdateWith401 = true;

        final response = await repository.updateNickname(nickname: '변경닉네임');

        expect(apiService.updateNicknameCallCount, 2);
        expect(apiService.refreshCallCount, 1);
        expect(tokenStorageService.saveAccessTokenCallCount, 1);

        expect(apiService.authorizationHeaders, <String>[
          'Bearer old-access-token',
          'Bearer new-access-token',
        ]);

        expect(response.nickname, '변경닉네임');
        expect(response.profileImageUrl, 'https://example.com/profile.png');
      });

      test('저장된 Access Token이 없으면 닉네임 변경 API를 호출하지 않는다', () async {
        tokenStorageService.authorizationHeader = null;

        await expectLater(
          repository.updateNickname(nickname: '새닉네임'),
          throwsA(
            isA<AuthSessionException>().having(
              (error) => error.message,
              'message',
              '저장된 Access Token이 없습니다.',
            ),
          ),
        );

        expect(apiService.updateNicknameCallCount, 0);
        expect(apiService.refreshCallCount, 0);
      });

      test('401이 아닌 API 오류는 재발급 없이 그대로 전달한다', () async {
        apiService.updateNicknameError = const ApiException(
          statusCode: 500,
          message: '닉네임 변경에 실패했습니다.',
        );

        await expectLater(
          repository.updateNickname(nickname: '새닉네임'),
          throwsA(
            isA<ApiException>()
                .having((error) => error.statusCode, 'statusCode', 500)
                .having(
                  (error) => error.message,
                  'message',
                  '닉네임 변경에 실패했습니다.',
                ),
          ),
        );

        expect(apiService.updateNicknameCallCount, 1);
        expect(apiService.refreshCallCount, 0);
      });
    });
}
