import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/auth/social_account_status_response.dart';
import 'package:tripbler/models/auth/token_refresh_response.dart';
import 'package:tripbler/models/auth/user_login_response.dart';
import 'package:tripbler/models/user/login_id_availability_response.dart';
import 'package:tripbler/models/user/user_response.dart';
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.hasStoredTokens = true, UserResponse? currentUser})
    : currentUser =
          currentUser ??
          const UserResponse(
            id: 1,
            loginId: 'testuser01',
            nickname: '테스트사용자',
            profileImageUrl: 'https://example.com/profile.png',
          );

  bool hasStoredTokens;
  UserResponse currentUser;

  Object? deleteAccountError;
  Object? clearTokensError;
  Object? updateProfileImageError;
  Object? deleteProfileImageError;

  UserResponse? updateProfileImageResponse;

  String? receivedProfileImageFilePath;

  int deleteAccountCallCount = 0;
  int clearTokensCallCount = 0;
  int updateProfileImageCallCount = 0;
  int deleteProfileImageCallCount = 0;

  @override
  Future<bool> hasTokens() async => hasStoredTokens;

  @override
  Future<UserResponse> getCurrentUser() async => currentUser;

  @override
  Future<UserResponse> updateNickname({required String nickname}) {
    throw UnsupportedError('updateNickname()은 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<UserResponse> updateProfileImage({required String filePath}) async {
    updateProfileImageCallCount++;
    receivedProfileImageFilePath = filePath;

    final error = updateProfileImageError;

    if (error != null) {
      throw error;
    }

    return updateProfileImageResponse ??
        const UserResponse(
          id: 1,
          loginId: 'testuser01',
          nickname: '테스트사용자',
          profileImageUrl: 'https://example.com/updated-profile.png',
        );
  }

  @override
  Future<void> deleteProfileImage() async {
    deleteProfileImageCallCount++;

    final error = deleteProfileImageError;

    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCallCount++;

    final error = deleteAccountError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> clearTokens() async {
    clearTokensCallCount++;

    final error = clearTokensError;
    if (error != null) {
      throw error;
    }

    hasStoredTokens = false;
  }

  // 아래 메서드들은 이 테스트 파일에서 사용하지 않는다.
  // Fake가 실제 AuthRepository 구현으로 흘러가지 않도록 모두 명시적으로 구현한다.
  // 새로운 테스트에서 필요해지면 UnsupportedError 대신 테스트용 동작을 구현한다.

  @override
  Future<UserResponse> signup({
    required String loginId,
    String? nickname,
    required String password,
  }) {
    throw UnsupportedError('signup()은 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<LoginIdAvailabilityResponse> checkLoginIdAvailability(String loginId) {
    throw UnsupportedError(
      'checkLoginIdAvailability()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  @override
  Future<void> sendFindIdVerificationCode({required String email}) {
    throw UnsupportedError(
      'sendFindIdVerificationCode()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  @override
  Future<String> verifyFindIdVerificationCode({
    required String email,
    required String code,
  }) {
    throw UnsupportedError(
      'verifyFindIdVerificationCode()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  @override
  Future<void> sendPasswordResetVerificationCode({
    required String loginId,
    required String email,
  }) {
    throw UnsupportedError(
      'sendPasswordResetVerificationCode()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  @override
  Future<String> verifyPasswordResetVerificationCode({
    required String loginId,
    required String email,
    required String code,
  }) {
    throw UnsupportedError(
      'verifyPasswordResetVerificationCode()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) {
    throw UnsupportedError('resetPassword()는 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<UserLoginResponse> login({
    required String loginId,
    required String password,
  }) {
    throw UnsupportedError('login()은 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<void> linkGoogleAccount() {
    throw UnsupportedError('linkGoogleAccount()는 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<void> unlinkGoogleAccount() {
    throw UnsupportedError('unlinkGoogleAccount()는 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<TokenRefreshResponse> refreshAccessToken() {
    throw UnsupportedError('refreshAccessToken()은 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<SocialAccountStatusResponse> getLinkedSocialAccounts() {
    throw UnsupportedError(
      'getLinkedSocialAccounts()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  @override
  Future<void> logout() {
    throw UnsupportedError('logout()은 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readAuthorizationHeader() async => null;

  @override
  void dispose() {}
}

void main() {
  late FakeAuthRepository repository;
  late AuthProvider provider;

  setUp(() {
    repository = FakeAuthRepository();
    provider = AuthProvider(authRepository: repository);
  });

  tearDown(() {
    provider.dispose();
  });

  group('AuthProvider restoreSession', () {
    test('세션 복구 시 프로필 이미지 URL을 복원한다', () async {
      repository.currentUser = const UserResponse(
        id: 1,
        loginId: 'testuser01',
        nickname: '테스트사용자',
        profileImageUrl: 'https://example.com/restored-profile.png',
      );

      await provider.restoreSession();

      expect(provider.isAuthenticated, isTrue);
      expect(provider.userId, 1);
      expect(provider.loginId, 'testuser01');
      expect(provider.nickname, '테스트사용자');
      expect(
        provider.profileImageUrl,
        'https://example.com/restored-profile.png',
      );
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });
  });

  group('AuthProvider updateProfileImage', () {
    test('프로필 이미지 변경 성공 시 새 이미지 URL을 반영한다', () async {
      await provider.restoreSession();

      repository.updateProfileImageResponse = const UserResponse(
        id: 1,
        loginId: 'testuser01',
        nickname: '테스트사용자',
        profileImageUrl: 'https://example.com/new-profile.png',
      );

      final success = await provider.updateProfileImage(
        filePath: '/test/profile.jpg',
      );

      expect(success, isTrue);
      expect(repository.updateProfileImageCallCount, 1);
      expect(repository.receivedProfileImageFilePath, '/test/profile.jpg');
      expect(provider.profileImageUrl, 'https://example.com/new-profile.png');
      expect(provider.isAuthenticated, isTrue);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('프로필 이미지 변경 실패 시 기존 이미지 URL을 유지한다', () async {
      await provider.restoreSession();

      repository.updateProfileImageError = const ApiException(
        statusCode: 400,
        message: '프로필 이미지 변경에 실패했습니다.',
      );

      final success = await provider.updateProfileImage(
        filePath: '/test/profile.jpg',
      );

      expect(success, isFalse);
      expect(repository.updateProfileImageCallCount, 1);
      expect(provider.profileImageUrl, 'https://example.com/profile.png');
      expect(provider.errorMessage, '프로필 이미지 변경에 실패했습니다.');
      expect(provider.isLoading, isFalse);
    });

    test('로그인 상태가 아니면 프로필 이미지 변경 요청을 하지 않는다', () async {
      repository.hasStoredTokens = false;

      await provider.restoreSession();

      final success = await provider.updateProfileImage(
        filePath: '/test/profile.jpg',
      );

      expect(success, isFalse);
      expect(repository.updateProfileImageCallCount, 0);
      expect(provider.profileImageUrl, isNull);
    });
  });

  group('AuthProvider deleteProfileImage', () {
    test('프로필 이미지 삭제 성공 시 이미지 URL을 초기화한다', () async {
      await provider.restoreSession();

      expect(provider.profileImageUrl, 'https://example.com/profile.png');

      final success = await provider.deleteProfileImage();

      expect(success, isTrue);
      expect(repository.deleteProfileImageCallCount, 1);
      expect(provider.profileImageUrl, isNull);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('프로필 이미지 삭제 실패 시 기존 이미지 URL을 유지한다', () async {
      await provider.restoreSession();

      repository.deleteProfileImageError = const ApiException(
        statusCode: 500,
        message: '프로필 이미지 삭제에 실패했습니다.',
      );

      final success = await provider.deleteProfileImage();

      expect(success, isFalse);
      expect(repository.deleteProfileImageCallCount, 1);
      expect(provider.profileImageUrl, 'https://example.com/profile.png');
      expect(provider.errorMessage, '프로필 이미지 삭제에 실패했습니다.');
      expect(provider.isLoading, isFalse);
    });

    test('로그인 상태가 아니면 프로필 이미지 삭제 요청을 하지 않는다', () async {
      repository.hasStoredTokens = false;

      await provider.restoreSession();

      final success = await provider.deleteProfileImage();

      expect(success, isFalse);
      expect(repository.deleteProfileImageCallCount, 0);
      expect(provider.profileImageUrl, isNull);
    });
  });

  group('AuthProvider clearSession', () {
    test('로컬 토큰과 현재 사용자 상태를 모두 초기화한다', () async {
      await provider.restoreSession();
      expect(provider.isAuthenticated, isTrue);

      await provider.clearSession();

      expect(repository.clearTokensCallCount, 1);
      expect(repository.hasStoredTokens, isFalse);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.userId, isNull);
      expect(provider.loginId, isNull);
      expect(provider.nickname, isNull);
      expect(provider.profileImageUrl, isNull);
      expect(provider.googleLinked, isNull);
    });

    test('토큰 삭제가 실패해도 현재 사용자 상태는 강제로 초기화한다', () async {
      await provider.restoreSession();
      expect(provider.isAuthenticated, isTrue);

      repository.clearTokensError = StateError('테스트용 토큰 삭제 실패');

      await provider.clearSession();

      expect(repository.clearTokensCallCount, 1);
      expect(repository.hasStoredTokens, isTrue);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.userId, isNull);
      expect(provider.loginId, isNull);
      expect(provider.nickname, isNull);
      expect(provider.profileImageUrl, isNull);
      expect(provider.googleLinked, isNull);
    });
  });
}
