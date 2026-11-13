import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/auth/social_account_status_response.dart';
import 'package:tripbler/models/auth/user_login_response.dart';
import 'package:tripbler/models/user/login_id_availability_response.dart';
import 'package:tripbler/models/user/user_response.dart';
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';

import '../helpers/auth_handle.dart';

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

  /// 실제 AuthRepository처럼 로그인과 세션 종료 때만 바뀐다.
  @override
  int sessionId = 0;

  /// getCurrentUser가 던질 오류. null이면 currentUser를 돌려준다.
  Object? getCurrentUserError;
  int getCurrentUserCallCount = 0;

  /// 지정하면 이 Completer가 끝날 때까지 getCurrentUser 응답을 미룬다.
  Completer<void>? getCurrentUserGate;

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
  Future<UserResponse> getCurrentUser() async {
    getCurrentUserCallCount++;

    final gate = getCurrentUserGate;

    if (gate != null) {
      await gate.future;
    }

    final error = getCurrentUserError;

    if (error != null) {
      throw error;
    }

    return currentUser;
  }

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
    sessionId++;
    clearTokensCallCount++;

    final error = clearTokensError;
    if (error != null) {
      throw error;
    }

    hasStoredTokens = false;
  }

  @override
  Future<bool> clearTokensIfSession(int expectedSessionId) async {
    if (sessionId != expectedSessionId) {
      return false;
    }

    await clearTokens();

    return true;
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

  int loginCallCount = 0;

  @override
  Future<UserLoginResponse> login({
    required String loginId,
    required String password,
  }) async {
    loginCallCount++;
    sessionId++;
    hasStoredTokens = true;

    return UserLoginResponse(
      id: currentUser.id,
      loginId: loginId,
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      tokenType: 'Bearer',
    );
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
  Future<String> refreshAccessToken() {
    throw UnsupportedError('refreshAccessToken()은 이 Fake에서 아직 구현되지 않았습니다.');
  }

  @override
  Future<SocialAccountStatusResponse> getLinkedSocialAccounts() {
    throw UnsupportedError(
      'getLinkedSocialAccounts()는 이 Fake에서 아직 구현되지 않았습니다.',
    );
  }

  int logoutCallCount = 0;

  @override
  Future<void> logout() async {
    logoutCallCount++;
    sessionId++;
    hasStoredTokens = false;
  }

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readAuthorizationHeader() async => null;

  /// authorizedRequest가 던질 오류. null이면 요청을 실행한다.
  Object? authorizedRequestError;
  int authorizedRequestCallCount = 0;

  /// 지정하면 이 Completer가 끝날 때까지 authorizedRequest 응답을 미룬다.
  Completer<void>? authorizedRequestGate;

  @override
  Future<T> authorizedRequest<T>(
    Future<T> Function(String authorizationHeader) request,
  ) async {
    authorizedRequestCallCount++;

    final gate = authorizedRequestGate;

    if (gate != null) {
      await gate.future;
    }

    final error = authorizedRequestError;

    if (error != null) {
      throw error;
    }

    return request('Bearer test-access-token');
  }

  @override
  void dispose() {}
}

void main() {
  late FakeAuthRepository repository;
  late AuthHandle provider;

  setUp(() {
    repository = FakeAuthRepository();
    provider = AuthHandle(repository);
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

  group('AuthProvider runAuthorizedRequest', () {
    test('요청이 성공하면 토큰을 넘겨 실행하고 로그인 상태를 유지한다', () async {
      await provider.restoreSession();

      final result = await provider.runAuthorizedRequest<String>(
        (authorizationHeader) async => '결과:$authorizationHeader',
      );

      expect(result, '결과:Bearer test-access-token');
      expect(repository.authorizedRequestCallCount, 1);
      expect(provider.isAuthenticated, isTrue);
      expect(repository.clearTokensCallCount, 0);
    });

    test(
      'Refresh Token이 만료되면 로그인 상태를 해제하고 SessionExpiredException을 던진다',
      () async {
        await provider.restoreSession();
        repository.authorizedRequestError = const ApiException(
          statusCode: 401,
          code: 'EXPIRED_REFRESH_TOKEN',
          message: 'Refresh Token이 만료되었습니다.',
        );

        await expectLater(
          provider.runAuthorizedRequest<String>((_) async => 'unused'),
          throwsA(isA<SessionExpiredException>()),
        );

        expect(provider.isAuthenticated, isFalse);
        expect(repository.clearTokensCallCount, 1);
      },
    );

    test('Refresh Token이 유효하지 않으면 로그인 상태를 해제한다', () async {
      await provider.restoreSession();
      repository.authorizedRequestError = const ApiException(
        statusCode: 401,
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh Token이 유효하지 않습니다.',
      );

      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(isA<SessionExpiredException>()),
      );

      expect(provider.isAuthenticated, isFalse);
    });

    test('저장된 토큰이 없으면 로그인 상태를 해제한다', () async {
      await provider.restoreSession();
      repository.authorizedRequestError = const AuthSessionException(
        '저장된 Refresh Token이 없습니다.',
      );

      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(isA<SessionExpiredException>()),
      );

      expect(provider.isAuthenticated, isFalse);
    });

    test('네트워크 오류는 그대로 던지고 로그인 상태를 유지한다', () async {
      await provider.restoreSession();
      const networkError = ApiException(message: '서버에 연결할 수 없습니다.');
      repository.authorizedRequestError = networkError;

      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(same(networkError)),
      );

      expect(provider.isAuthenticated, isTrue);
      expect(repository.clearTokensCallCount, 0);
    });

    test('재발급 뒤에도 받은 401이나 5xx는 세션 만료로 보지 않는다', () async {
      await provider.restoreSession();

      for (final error in const <ApiException>[
        ApiException(
          statusCode: 401,
          code: 'UNAUTHORIZED',
          message: '인증이 필요합니다.',
        ),
        ApiException(
          statusCode: 500,
          code: 'INTERNAL_SERVER_ERROR',
          message: '서버 오류',
        ),
        ApiException(
          statusCode: 503,
          code: 'PLACES_PROVIDER_UNAVAILABLE',
          message: '장애',
        ),
      ]) {
        repository.authorizedRequestError = error;

        await expectLater(
          provider.runAuthorizedRequest<String>((_) async => 'unused'),
          throwsA(same(error)),
        );
      }

      expect(provider.isAuthenticated, isTrue);
      expect(repository.clearTokensCallCount, 0);
    });

    test('요청 중 재로그인되면 늦게 온 세션 만료가 새 세션을 해제하지 않는다', () async {
      await provider.restoreSession();

      final gate = Completer<void>();
      repository.authorizedRequestGate = gate;
      repository.authorizedRequestError = const ApiException(
        statusCode: 401,
        code: 'EXPIRED_REFRESH_TOKEN',
        message: 'Refresh Token이 만료되었습니다.',
      );

      final pending = provider.runAuthorizedRequest<String>(
        (_) async => 'unused',
      );

      // 요청이 진행되는 동안 로그아웃 후 다시 로그인한다.
      await provider.clearSession();
      expect(repository.clearTokensCallCount, 1);

      final loggedIn = await provider.login(
        loginId: 'testuser01',
        password: 'test-password',
      );
      expect(loggedIn, isTrue);
      expect(provider.isAuthenticated, isTrue);

      gate.complete();

      await expectLater(pending, throwsA(isA<SessionExpiredException>()));

      expect(provider.isAuthenticated, isTrue);
      expect(provider.loginId, 'testuser01');
      expect(repository.clearTokensCallCount, 1);
      expect(repository.hasStoredTokens, isTrue);
    });

    test('이미 비로그인 상태면 토큰 삭제와 알림 없이 SessionExpiredException만 던진다', () async {
      repository.hasStoredTokens = false;
      await provider.restoreSession();
      expect(provider.isAuthenticated, isFalse);

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      repository.authorizedRequestError = const AuthSessionException(
        '저장된 Access Token이 없습니다.',
      );

      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(isA<SessionExpiredException>()),
      );

      expect(repository.clearTokensCallCount, 0);
      expect(notifyCount, 0);
      expect(provider.isAuthenticated, isFalse);
    });

    test('요청 중 dispose되면 알림 예외 없이 SessionExpiredException만 전달한다', () async {
      // tearDown의 provider.dispose()와 겹치지 않게 별도 인스턴스를 쓴다.
      final disposableRepository = FakeAuthRepository();
      final disposableProvider = AuthHandle(disposableRepository);

      await disposableProvider.restoreSession();

      final gate = Completer<void>();
      disposableRepository.authorizedRequestGate = gate;
      disposableRepository.authorizedRequestError = const ApiException(
        statusCode: 401,
        code: 'EXPIRED_REFRESH_TOKEN',
        message: 'Refresh Token이 만료되었습니다.',
      );

      final pending = disposableProvider.runAuthorizedRequest<String>(
        (_) async => 'unused',
      );

      disposableProvider.dispose();
      gate.complete();

      await expectLater(pending, throwsA(isA<SessionExpiredException>()));

      expect(disposableRepository.clearTokensCallCount, 0);
    });
  });

  group('AuthProvider 세션 변경 예외', () {
    test('runAuthorizedRequest는 세션 변경을 그대로 전달하고 로그인 상태를 건드리지 않는다', () async {
      await provider.restoreSession();
      repository.authorizedRequestError = const SessionChangedException();

      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(isA<SessionChangedException>()),
      );

      expect(provider.isAuthenticated, isTrue);
      expect(repository.clearTokensCallCount, 0);
    });

    test('이전 세션의 작업 결과는 오류 문구 없이 버리고 현재 화면 데이터를 유지한다', () async {
      await provider.restoreSession();
      final profileBefore = provider.profileImageUrl;
      repository.updateProfileImageError = const SessionChangedException();

      final result = await provider.updateProfileImage(
        filePath: '/tmp/profile.png',
      );

      expect(result, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.profileImageUrl, profileBefore);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.isLoading, isFalse);
    });
  });

  group('AuthProvider 세션 복구(토큰 보존 후 수동 재시도)', () {
    for (final entry in <String, Object>{
      '네트워크 오류': const ApiException(message: '서버에 연결할 수 없습니다.'),
      '503': const ApiException(statusCode: 503, message: '서버 장애'),
      '429': const ApiException(statusCode: 429, message: '요청이 많습니다.'),
      '예상하지 못한 오류': StateError('파싱 실패'),
      '재발급 뒤 기기 저장소 읽기 실패': const TokenStorageException(
        '재발급한 Access Token을 기기에서 읽지 못했습니다.',
      ),
      // 403과 재발급 뒤 401은 세션 만료를 확정하지 못하므로 토큰을 보존한다.
      '403': const ApiException(statusCode: 403, message: '권한 없음'),
      '재발급 뒤에도 401': const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: '인증이 필요합니다.',
      ),
      '400': const ApiException(statusCode: 400, message: '잘못된 요청'),
    }.entries) {
      test('${entry.key}로 실패하면 토큰을 남기고 다시 시도 상태가 된다', () async {
        repository.getCurrentUserError = entry.value;

        await provider.restoreSession();

        expect(provider.isInitialized, isTrue);
        expect(provider.isAuthenticated, isFalse);
        expect(provider.sessionRestoreFailed, isTrue);
        expect(repository.clearTokensCallCount, 0);
        expect(repository.hasStoredTokens, isTrue);
      });
    }

    for (final entry in <String, Object>{
      'Refresh Token 만료': const ApiException(
        statusCode: 401,
        code: 'EXPIRED_REFRESH_TOKEN',
        message: 'Refresh Token이 만료되었습니다.',
      ),
      '유효하지 않은 Refresh Token': const ApiException(
        statusCode: 401,
        code: 'INVALID_REFRESH_TOKEN',
        message: 'Refresh Token이 유효하지 않습니다.',
      ),
      '저장된 토큰 없음': const AuthSessionException('저장된 Refresh Token이 없습니다.'),
    }.entries) {
      test('${entry.key}면 세션 만료가 확인되므로 토큰을 지운다', () async {
        repository.getCurrentUserError = entry.value;

        await provider.restoreSession();

        expect(provider.isAuthenticated, isFalse);
        expect(provider.sessionRestoreFailed, isFalse);
        expect(repository.clearTokensCallCount, 1);
        expect(repository.hasStoredTokens, isFalse);
      });
    }

    test('다시 시도가 성공하면 로그인 상태가 되고 배너 상태가 풀린다', () async {
      repository.getCurrentUserError = const ApiException(message: '연결 실패');
      await provider.restoreSession();
      expect(provider.sessionRestoreFailed, isTrue);

      repository.getCurrentUserError = null;
      await provider.retryRestoreSession();

      expect(provider.isAuthenticated, isTrue);
      expect(provider.loginId, 'testuser01');
      expect(provider.sessionRestoreFailed, isFalse);
      expect(repository.getCurrentUserCallCount, 2);
    });

    test('다시 시도도 일시적 장애로 실패하면 토큰을 계속 남긴다', () async {
      repository.getCurrentUserError = const ApiException(message: '연결 실패');
      await provider.restoreSession();

      await provider.retryRestoreSession();

      expect(provider.sessionRestoreFailed, isTrue);
      expect(repository.clearTokensCallCount, 0);
      expect(repository.hasStoredTokens, isTrue);
    });

    test('복구 실패 상태가 아니면 다시 시도는 아무것도 하지 않는다', () async {
      await provider.restoreSession();
      final callsBefore = repository.getCurrentUserCallCount;

      await provider.retryRestoreSession();

      expect(repository.getCurrentUserCallCount, callsBefore);
    });

    test('복구 실패 뒤 직접 로그인하면 배너 상태가 풀린다', () async {
      repository.getCurrentUserError = const ApiException(message: '연결 실패');
      await provider.restoreSession();
      expect(provider.sessionRestoreFailed, isTrue);

      repository.getCurrentUserError = null;
      await provider.login(loginId: 'testuser01', password: 'test-password');

      expect(provider.isAuthenticated, isTrue);
      expect(provider.sessionRestoreFailed, isFalse);
    });

    test('복구 중 세션이 바뀌면 늦게 온 복구 성공을 반영하지 않는다', () async {
      final gate = Completer<void>();
      repository.getCurrentUserGate = gate;

      final pending = provider.restoreSession();

      // 복구 응답을 기다리는 동안 다른 경로로 세션이 끝났다(로그아웃 등).
      repository.sessionId++;
      gate.complete();
      await pending;

      expect(provider.isInitialized, isTrue);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.loginId, isNull);
    });

    test('복구 중 세션이 바뀌면 늦게 온 복구 실패로 토큰을 지우거나 배너를 띄우지 않는다', () async {
      final gate = Completer<void>();
      repository.getCurrentUserGate = gate;
      repository.getCurrentUserError = const ApiException(
        statusCode: 401,
        code: 'EXPIRED_REFRESH_TOKEN',
        message: 'Refresh Token이 만료되었습니다.',
      );

      final pending = provider.restoreSession();
      repository.sessionId++;
      gate.complete();
      await pending;

      expect(repository.clearTokensCallCount, 0);
      expect(provider.sessionRestoreFailed, isFalse);
    });

    test('복구 요청이 세션 변경으로 끝나면 조용히 버린다', () async {
      repository.getCurrentUserError = const SessionChangedException();

      await provider.restoreSession();

      expect(provider.isInitialized, isTrue);
      expect(provider.sessionRestoreFailed, isFalse);
      expect(provider.errorMessage, isNull);
      expect(repository.clearTokensCallCount, 0);
    });
  });

  group('AuthProvider 세션 번호', () {
    test('로그아웃은 로그인 상태를 해제하고 저장소 세션을 한 번 끝낸다', () async {
      await provider.restoreSession();
      final before = repository.sessionId;

      await provider.logout();

      expect(provider.isAuthenticated, isFalse);
      expect(repository.logoutCallCount, 1);
      expect(repository.sessionId, before + 1);
    });

    test('세션 만료로 로그아웃할 때 세션 번호는 한 번만 바뀐다', () async {
      await provider.restoreSession();
      final before = repository.sessionId;
      repository.authorizedRequestError = const ApiException(
        statusCode: 401,
        code: 'EXPIRED_REFRESH_TOKEN',
        message: 'Refresh Token이 만료되었습니다.',
      );

      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(isA<SessionExpiredException>()),
      );

      expect(repository.sessionId, before + 1);
    });

    test('로그인·로그아웃·만료마다 sessionId가 저장소와 같다', () async {
      final c = provider.container;
      expect(c.read(authProvider).sessionId, repository.sessionId);

      await provider.login(loginId: 'testuser01', password: 'password');
      expect(c.read(authProvider).isAuthenticated, isTrue);
      expect(c.read(authProvider).sessionId, repository.sessionId);

      await provider.logout();
      expect(c.read(authProvider).isAuthenticated, isFalse);
      expect(c.read(authProvider).sessionId, repository.sessionId);

      await provider.login(loginId: 'testuser01', password: 'password');
      repository.authorizedRequestError = const ApiException(
        statusCode: 401,
        code: 'EXPIRED_REFRESH_TOKEN',
        message: 'Refresh Token이 만료되었습니다.',
      );
      await expectLater(
        provider.runAuthorizedRequest<String>((_) async => 'unused'),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(c.read(authProvider).isAuthenticated, isFalse);
      expect(c.read(authProvider).sessionId, repository.sessionId);
    });
  });
}
