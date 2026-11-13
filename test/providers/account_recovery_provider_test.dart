import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/providers/account_recovery_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';

class _ThrowingRepository extends AuthRepository {
  _ThrowingRepository(this.error);

  final Object error;

  @override
  Future<void> sendFindIdVerificationCode({required String email}) async {
    throw error;
  }

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {}
}

void main() {
  ProviderContainer containerWith(AuthRepository repository) {
    return ProviderContainer.test(
      overrides: [
        accountRecoveryRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  test('실패하면 errorMessage를 남기고 isLoading을 끈다', () async {
    final container = containerWith(_ThrowingRepository(Exception('boom')));
    final notifier = container.read(accountRecoveryProvider.notifier);

    final success = await notifier.sendFindIdVerificationCode(email: 'a@b.com');

    final state = container.read(accountRecoveryProvider);
    expect(success, isFalse);
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, '인증코드 전송 중 오류가 발생했습니다.');
  });

  test('ApiException이면 서버 메시지를 errorMessage로 쓴다', () async {
    final container = containerWith(
      _ThrowingRepository(const ApiException(message: '코드가 틀렸습니다.')),
    );
    final notifier = container.read(accountRecoveryProvider.notifier);

    await notifier.sendFindIdVerificationCode(email: 'a@b.com');

    expect(container.read(accountRecoveryProvider).errorMessage, '코드가 틀렸습니다.');
  });

  test('성공하면 이전 오류를 지우고 true를 반환한다', () async {
    final container = containerWith(_ThrowingRepository(Exception('boom')));
    final notifier = container.read(accountRecoveryProvider.notifier);
    await notifier.sendFindIdVerificationCode(email: 'a@b.com');

    final success = await notifier.resetPassword(
      resetToken: 't',
      newPassword: 'pw',
    );

    final state = container.read(accountRecoveryProvider);
    expect(success, isTrue);
    expect(state.errorMessage, isNull);
    expect(state.isLoading, isFalse);
  });
}
