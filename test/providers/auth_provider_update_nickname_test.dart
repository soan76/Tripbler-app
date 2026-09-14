import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/user/user_response.dart';
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';

class FakeNicknameAuthRepository extends AuthRepository {
  bool hasStoredTokens = true;

  UserResponse currentUser = const UserResponse(
    id: 1,
    loginId: 'testuser01',
    nickname: '기존닉네임',
    profileImageUrl: 'https://example.com/profile.png',
  );

  int updateNicknameCallCount = 0;
  String? receivedNickname;

  Object? updateNicknameError;

  @override
  Future<bool> hasTokens() async => hasStoredTokens;

  @override
  Future<UserResponse> getCurrentUser() async {
    return currentUser;
  }

  @override
  Future<UserResponse> updateNickname({required String nickname}) async {
    updateNicknameCallCount++;
    receivedNickname = nickname;

    final error = updateNicknameError;

    if (error != null) {
      throw error;
    }

    currentUser = UserResponse(
      id: currentUser.id,
      loginId: currentUser.loginId,
      nickname: nickname,
      profileImageUrl: currentUser.profileImageUrl,
    );

    return currentUser;
  }

  @override
  void dispose() {}
}

void main() {
  late FakeNicknameAuthRepository repository;
  late AuthProvider provider;

  setUp(() {
    repository = FakeNicknameAuthRepository();

    provider = AuthProvider(authRepository: repository);
  });

  tearDown(() {
    provider.dispose();
  });

  group('AuthProvider updateNickname', () {
    test('닉네임 변경 성공 시 Provider의 사용자 정보를 최신 응답으로 갱신한다', () async {
      await provider.restoreSession();

      expect(provider.nickname, '기존닉네임');
      expect(provider.isAuthenticated, isTrue);

      final success = await provider.updateNickname(nickname: '새닉네임');

      expect(success, isTrue);
      expect(repository.updateNicknameCallCount, 1);
      expect(repository.receivedNickname, '새닉네임');

      expect(provider.userId, 1);
      expect(provider.loginId, 'testuser01');
      expect(provider.nickname, '새닉네임');
      expect(provider.profileImageUrl, 'https://example.com/profile.png');
      expect(provider.isAuthenticated, isTrue);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('앞뒤 공백을 제거한 닉네임을 Repository에 전달한다', () async {
      await provider.restoreSession();

      final success = await provider.updateNickname(nickname: '  가  ');

      expect(success, isTrue);
      expect(repository.receivedNickname, '가');
      expect(provider.nickname, '가');
    });

    test('닉네임 변경 실패 시 기존 사용자 상태를 유지하고 오류 메시지를 저장한다', () async {
      await provider.restoreSession();

      repository.updateNicknameError = const ApiException(
        statusCode: 400,
        message: '닉네임 변경 요청이 올바르지 않습니다.',
      );

      final success = await provider.updateNickname(nickname: '새닉네임');

      expect(success, isFalse);
      expect(repository.updateNicknameCallCount, 1);

      expect(provider.userId, 1);
      expect(provider.loginId, 'testuser01');
      expect(provider.nickname, '기존닉네임');
      expect(provider.isAuthenticated, isTrue);
      expect(provider.errorMessage, '닉네임 변경 요청이 올바르지 않습니다.');
      expect(provider.isLoading, isFalse);
    });

    test('중복 닉네임이면 기존 닉네임을 유지하고 중복 오류 메시지를 저장한다', () async {
      await provider.restoreSession();

      repository.updateNicknameError = const ApiException(
        statusCode: 409,
        code: 'DUPLICATE_NICKNAME',
        message: '이미 사용 중인 닉네임입니다.',
      );

      final success = await provider.updateNickname(nickname: '사용중닉네임');

      expect(success, isFalse);
      expect(repository.updateNicknameCallCount, 1);

      expect(provider.nickname, '기존닉네임');
      expect(provider.isAuthenticated, isTrue);

      expect(provider.errorMessage, '이미 사용 중인 닉네임입니다.');

      expect(provider.isLoading, isFalse);
    });

    test('로그인 상태가 아니면 닉네임 변경 요청을 실행하지 않는다', () async {
      repository.hasStoredTokens = false;

      await provider.restoreSession();

      final success = await provider.updateNickname(nickname: '새닉네임');

      expect(success, isFalse);
      expect(repository.updateNicknameCallCount, 0);
      expect(provider.isAuthenticated, isFalse);
    });
  });
}