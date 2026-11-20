import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/models/user/login_id_availability_response.dart';
import 'package:tripbler/providers/auth/auth_provider.dart';
import 'package:tripbler/providers/auth/login_id_check_provider.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';

/// 아이디 중복확인만 쓰는 가짜 저장소. 다른 메서드를 부르면 [Fake]가 실패시킨다.
class _CheckRepository extends Fake implements AuthRepository {
  @override
  int sessionId = 0;

  final List<String> requestedLoginIds = [];

  /// 지정하면 이 Completer가 끝날 때까지 응답을 미룬다.
  Completer<void>? gate;

  Object? error;
  bool available = true;

  @override
  Future<LoginIdAvailabilityResponse> checkLoginIdAvailability(
    String loginId,
  ) async {
    requestedLoginIds.add(loginId);

    final pending = gate;

    if (pending != null) {
      await pending.future;
    }

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    return LoginIdAvailabilityResponse(loginId: loginId, available: available);
  }

  @override
  void dispose() {}
}

void main() {
  late _CheckRepository repository;
  late ProviderContainer container;
  late int notifications;
  late int authNotifications;

  // 아이디 중복확인 상태를 읽고 부르는 곳. 상태를 옮기면 이 세 줄만 바꾼다.
  LoginIdCheckState read() => container.read(loginIdCheckProvider);
  Future<void> check(String loginId) => container
      .read(loginIdCheckProvider.notifier)
      .checkLoginIdAvailability(loginId);
  void reset() =>
      container.read(loginIdCheckProvider.notifier).resetLoginIdAvailability();

  setUp(() {
    repository = _CheckRepository();
    container = ProviderContainer.test(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    notifications = 0;
    container.listen(loginIdCheckProvider, (_, _) => notifications++);
    authNotifications = 0;
    container.listen(authProvider, (_, _) => authNotifications++);
  });

  test('빈 아이디는 요청하지 않고 입력 안내를 띄운다', () async {
    await check('   ');

    expect(repository.requestedLoginIds, isEmpty);
    expect(read().loginIdCheckMessage, '아이디를 입력해 주세요.');
    expect(read().isLoginIdAvailable, isNull);
    expect(read().isCheckingLoginId, isFalse);
  });

  test('4자 미만이나 30자 초과는 요청하지 않고 길이 안내를 띄운다', () async {
    for (final loginId in ['abc', 'a' * 31]) {
      await check(loginId);

      expect(read().loginIdCheckMessage, '아이디는 4자 이상 30자 이하여야 합니다.');
    }

    expect(repository.requestedLoginIds, isEmpty);
  });

  test('사용 가능한 아이디는 공백을 뺀 아이디로 확인하고 결과를 남긴다', () async {
    await check('  tripper  ');

    expect(repository.requestedLoginIds, ['tripper']);
    expect(read().checkedLoginId, 'tripper');
    expect(read().isLoginIdAvailable, isTrue);
    expect(read().loginIdCheckMessage, '사용 가능한 아이디입니다.');
    expect(read().isCheckingLoginId, isFalse);
    expect(read().isLoginIdCheckedAndAvailable(' tripper '), isTrue);
    expect(read().isLoginIdCheckedAndAvailable('tripper2'), isFalse);
  });

  test('이미 쓰는 아이디는 사용 불가로 남긴다', () async {
    repository.available = false;

    await check('tripper');

    expect(read().isLoginIdAvailable, isFalse);
    expect(read().loginIdCheckMessage, '이미 사용 중인 아이디입니다.');
    expect(read().isLoginIdCheckedAndAvailable('tripper'), isFalse);
  });

  test('요청이 실패하면 결과를 비우고 실패 안내를 띄운다', () async {
    await check('tripper');
    repository.error = Exception('network');

    await check('tripper');

    expect(read().isLoginIdAvailable, isNull);
    expect(read().checkedLoginId, isNull);
    expect(read().loginIdCheckMessage, '아이디 중복확인에 실패했습니다.');
    expect(read().isCheckingLoginId, isFalse);
  });

  test('확인 중에는 이전 결과를 비우고, 다시 눌러도 요청을 보내지 않는다', () async {
    await check('tripper');
    final gate = repository.gate = Completer<void>();

    final first = check('voyager');

    expect(read().isCheckingLoginId, isTrue);
    expect(read().isLoginIdAvailable, isNull);
    expect(read().checkedLoginId, isNull);
    expect(read().loginIdCheckMessage, isNull);

    await check('voyager');
    expect(repository.requestedLoginIds, ['tripper', 'voyager']);

    gate.complete();
    await first;

    expect(read().checkedLoginId, 'voyager');
    expect(read().isCheckingLoginId, isFalse);
  });

  test('중복확인은 로그인 로딩·오류 상태를 건드리지 않는다', () async {
    await check('tripper');

    final auth = container.read(authProvider);
    expect(auth.isLoading, isFalse);
    expect(auth.errorMessage, isNull);
    expect(auth.isAuthenticated, isFalse);
    expect(authNotifications, 0);
  });

  test('초기화는 결과와 안내를 모두 비운다', () async {
    await check('tripper');

    reset();

    expect(read().isLoginIdAvailable, isNull);
    expect(read().checkedLoginId, isNull);
    expect(read().loginIdCheckMessage, isNull);
  });

  test('비울 결과가 없으면 초기화해도 상태를 내보내지 않는다', () {
    reset();

    expect(notifications, 0);
  });
}
