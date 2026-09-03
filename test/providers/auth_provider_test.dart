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
          const UserResponse(id: 1, loginId: 'testuser01', nickname: '테스트사용자');

  bool hasStoredTokens;
  UserResponse currentUser;

  Object? deleteAccountError;
  Object? clearTokensError;

  int deleteAccountCallCount = 0;
  int clearTokensCallCount = 0;

  @override
  Future<bool> hasTokens() async => hasStoredTokens;

  @override
  Future<UserResponse> getCurrentUser() async => currentUser;

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

  group('AuthProvider deleteAccount', () {
    test('계정 탈퇴 성공 시 사용자 인증 상태를 초기화한다', () async {
      await provider.restoreSession();

      expect(provider.isAuthenticated, isTrue);
      expect(provider.userId, 1);
      expect(provider.loginId, 'testuser01');
      expect(provider.nickname, '테스트사용자');

      final success = await provider.deleteAccount();

      expect(success, isTrue);
      expect(repository.deleteAccountCallCount, 1);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.userId, isNull);
      expect(provider.loginId, isNull);
      expect(provider.nickname, isNull);
      expect(provider.googleLinked, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('계정 탈퇴 실패 시 로그인 상태를 유지하고 오류 메시지를 저장한다', () async {
      await provider.restoreSession();

      repository.deleteAccountError = const ApiException(
        statusCode: 500,
        message: '계정 탈퇴 처리에 실패했습니다.',
      );

      final success = await provider.deleteAccount();

      expect(success, isFalse);
      expect(repository.deleteAccountCallCount, 1);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.userId, 1);
      expect(provider.loginId, 'testuser01');
      expect(provider.nickname, '테스트사용자');
      expect(provider.errorMessage, '계정 탈퇴 처리에 실패했습니다.');
      expect(provider.isLoading, isFalse);
    });

    test('로그인 상태가 아니면 계정 탈퇴 요청을 실행하지 않는다', () async {
      repository.hasStoredTokens = false;

      await provider.restoreSession();

      final success = await provider.deleteAccount();

      expect(success, isFalse);
      expect(repository.deleteAccountCallCount, 0);
      expect(provider.isAuthenticated, isFalse);
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
      expect(provider.googleLinked, isNull);
    });
  });
}