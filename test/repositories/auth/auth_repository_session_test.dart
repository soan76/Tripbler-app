import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/network/api_exception.dart';
import 'package:tripbler/models/auth/token_refresh_request.dart';
import 'package:tripbler/models/auth/token_refresh_response.dart';
import 'package:tripbler/models/auth/user_login_request.dart';
import 'package:tripbler/models/auth/user_login_response.dart';
import 'package:tripbler/repositories/auth/auth_repository.dart';
import 'package:tripbler/services/auth/auth_api_service.dart';
import 'package:tripbler/services/auth/token_storage_service.dart';

/// 재발급·로그인·로그아웃·탈퇴 응답을 테스트가 원하는 시점에 끝내는 API 대역.
class ControlledAuthApiService extends AuthApiService {
  final List<Completer<TokenRefreshResponse>> refreshCalls =
      <Completer<TokenRefreshResponse>>[];
  final List<String> refreshTokensSent = <String>[];

  final List<String> logoutRefreshTokens = <String>[];
  Completer<void>? logoutGate;

  final List<String> deleteAccountHeaders = <String>[];

  /// 다음 로그인 응답으로 돌려줄 계정 토큰.
  String nextLoginAccessToken = 'b-access';
  String nextLoginRefreshToken = 'b-refresh';

  @override
  Future<TokenRefreshResponse> refresh(TokenRefreshRequest request) {
    refreshTokensSent.add(request.refreshToken);
    final completer = Completer<TokenRefreshResponse>();
    refreshCalls.add(completer);
    return completer.future;
  }

  @override
  Future<UserLoginResponse> login(UserLoginRequest request) async {
    return UserLoginResponse(
      id: 2,
      loginId: request.loginId,
      accessToken: nextLoginAccessToken,
      refreshToken: nextLoginRefreshToken,
      tokenType: 'Bearer',
    );
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    logoutRefreshTokens.add(refreshToken);

    final gate = logoutGate;

    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<void> deleteAccount({required String authorizationHeader}) async {
    deleteAccountHeaders.add(authorizationHeader);
  }

  @override
  void dispose() {}
}

/// 메모리 토큰 저장소. 세 값(Access, Refresh, 토큰 종류)을 따로 보관한다.
class MemoryTokenStorageService extends TokenStorageService {
  MemoryTokenStorageService({
    this.accessToken = 'a-access',
    this.refreshToken = 'a-refresh',
    this.tokenType = 'Bearer',
  });

  String? accessToken;
  String? refreshToken;
  String? tokenType;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.tokenType = tokenType;
  }

  /// true면 Access Token 저장이 조용히 반영되지 않는다(기기 저장소 이상 흉내).
  bool dropAccessTokenOnSave = false;

  @override
  Future<void> saveAccessToken({
    required String accessToken,
    String? tokenType,
  }) async {
    if (dropAccessTokenOnSave) {
      this.accessToken = null;
      return;
    }

    this.accessToken = accessToken;

    if (tokenType != null) {
      this.tokenType = tokenType;
    }
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<String?> readTokenType() async => tokenType;

  @override
  Future<String?> readAuthorizationHeader() async {
    final token = accessToken;

    if (token == null || token.isEmpty) {
      return null;
    }

    return '${tokenType ?? 'Bearer'} $token';
  }

  @override
  Future<bool> hasTokens() async =>
      (accessToken?.isNotEmpty ?? false) && (refreshToken?.isNotEmpty ?? false);

  /// 남은 횟수만큼 clearTokens가 실패한다.
  int clearFailuresRemaining = 0;
  int clearCallCount = 0;

  @override
  Future<void> clearTokens() async {
    clearCallCount++;

    if (clearFailuresRemaining > 0) {
      clearFailuresRemaining--;
      throw StateError('테스트용 저장소 삭제 실패');
    }

    accessToken = null;
    refreshToken = null;
    tokenType = null;
  }

  bool get isEmpty =>
      accessToken == null && refreshToken == null && tokenType == null;
}

const ApiException _unauthorized = ApiException(
  statusCode: 401,
  code: 'UNAUTHORIZED',
  message: '인증이 필요합니다.',
);

TokenRefreshResponse _refreshed(String accessToken) {
  return TokenRefreshResponse.fromJson({
    'accessToken': accessToken,
    'tokenType': 'Bearer',
  });
}

/// 첫 전송은 [firstResponse]가 끝날 때까지 기다리고, 이후 전송은 바로 성공하는 요청.
class RecordedRequest {
  RecordedRequest(this.firstResponse);

  final Completer<String> firstResponse;
  final List<String> headers = <String>[];

  Future<String> call(String authorizationHeader) {
    headers.add(authorizationHeader);

    if (headers.length == 1) {
      return firstResponse.future;
    }

    return Future<String>.value('ok:$authorizationHeader');
  }
}

/// 마이크로태스크를 비워 순차 처리 경로와 await 뒤의 처리를 진행시킨다.
Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ControlledAuthApiService api;
  late MemoryTokenStorageService storage;
  late AuthRepository repository;

  setUp(() {
    api = ControlledAuthApiService();
    storage = MemoryTokenStorageService();
    repository = AuthRepository(
      authApiService: api,
      tokenStorageService: storage,
    );
  });

  tearDown(() {
    repository.dispose();
  });

  /// A 계정에서 B 계정으로 전환한다(로그아웃 → 로그인).
  Future<void> switchToAccountB() async {
    await repository.logout();
    await repository.login(loginId: 'userB', password: 'pw');
  }

  group('계정 전환 후 재시도 차단', () {
    test('A의 요청이 전환 뒤 401을 받아도 B의 토큰으로 재전송하지 않는다', () async {
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();

      await switchToAccountB();
      request.firstResponse.completeError(_unauthorized);

      await expectLater(pending, throwsA(isA<SessionChangedException>()));

      expect(request.headers, ['Bearer a-access']);
      expect(api.refreshCalls, isEmpty);
      expect(storage.accessToken, 'b-access');
      expect(storage.refreshToken, 'b-refresh');
    });

    test('A의 요청이 전환 뒤 성공해도 결과를 돌려주지 않는다(B 화면에 반영 금지)', () async {
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();

      await switchToAccountB();
      request.firstResponse.complete('A의 닉네임 변경 결과');

      await expectLater(pending, throwsA(isA<SessionChangedException>()));
      expect(storage.accessToken, 'b-access');
    });

    test('A의 요청이 전환 뒤 서버 오류를 받아도 세션 변경으로 끝낸다', () async {
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();

      await switchToAccountB();
      request.firstResponse.completeError(
        const ApiException(statusCode: 500, message: '서버 오류'),
      );

      await expectLater(pending, throwsA(isA<SessionChangedException>()));
    });

    test('세션 변경은 세션 만료로 판정하지 않는다', () {
      expect(
        AuthRepository.isSessionExpiredError(const SessionChangedException()),
        isFalse,
      );
    });
  });

  group('재발급 뒤 기기 저장소 이상', () {
    test(
      '재발급에 성공했는데 저장한 토큰을 다시 읽지 못하면 세션 만료가 아니라 저장소 오류로 끝나고 Refresh Token을 남긴다',
      () async {
        storage.dropAccessTokenOnSave = true;

        final request = RecordedRequest(Completer<String>());
        final pending = repository.authorizedRequest<String>(request.call);
        await _flush();
        request.firstResponse.completeError(_unauthorized);
        await _flush();
        api.refreshCalls.single.complete(_refreshed('a-access-new'));

        Object? thrown;

        try {
          await pending;
        } catch (error) {
          thrown = error;
        }

        expect(thrown, isA<TokenStorageException>());
        expect(AuthRepository.isSessionExpiredError(thrown!), isFalse);
        expect(storage.refreshToken, 'a-refresh');
        // 다시 보내지 않았다(읽은 토큰이 없으므로).
        expect(request.headers, ['Bearer a-access']);
      },
    );
  });

  group('이전 세션의 토큰 저장 차단', () {
    test('재발급 중 로그아웃하면 늦은 재발급 결과를 저장하지 않아 저장소가 비어 있다', () async {
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();
      request.firstResponse.completeError(_unauthorized);
      await _flush();
      expect(api.refreshCalls, hasLength(1));

      await repository.logout();
      api.refreshCalls.single.complete(_refreshed('a-access-new'));

      await expectLater(pending, throwsA(isA<SessionChangedException>()));
      expect(storage.isEmpty, isTrue);
      expect(request.headers, ['Bearer a-access']);
    });

    test('재발급 중 B로 재로그인해도 B의 토큰이 그대로 남는다', () async {
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();
      request.firstResponse.completeError(_unauthorized);
      await _flush();

      await switchToAccountB();
      api.refreshCalls.single.complete(_refreshed('a-access-new'));

      await expectLater(pending, throwsA(isA<SessionChangedException>()));
      expect(storage.accessToken, 'b-access');
      expect(storage.refreshToken, 'b-refresh');
      expect(request.headers, ['Bearer a-access']);
    });

    test('A의 재발급이 만료로 늦게 실패해도 B는 만료로 판정되지 않는다', () async {
      final requestA = RecordedRequest(Completer<String>());
      final pendingA = repository.authorizedRequest<String>(requestA.call);
      await _flush();
      requestA.firstResponse.completeError(_unauthorized);
      await _flush();

      await switchToAccountB();

      // B의 요청도 401을 받아 B 자신의 재발급을 시작한다(A의 재발급에 합류하지 않음).
      final requestB = RecordedRequest(Completer<String>());
      final pendingB = repository.authorizedRequest<String>(requestB.call);
      await _flush();
      requestB.firstResponse.completeError(_unauthorized);
      await _flush();

      expect(api.refreshCalls, hasLength(2));
      expect(api.refreshTokensSent, ['a-refresh', 'b-refresh']);

      // A의 재발급이 늦게 만료로 실패한다.
      api.refreshCalls[0].completeError(
        const ApiException(
          statusCode: 401,
          code: 'EXPIRED_REFRESH_TOKEN',
          message: 'Refresh Token이 만료되었습니다.',
        ),
      );
      await expectLater(pendingA, throwsA(isA<SessionChangedException>()));

      // B의 재발급은 계속 진행되고 B의 요청은 새 토큰으로 한 번 재시도한다.
      api.refreshCalls[1].complete(_refreshed('b-access-new'));

      expect(await pendingB, 'ok:Bearer b-access-new');
      expect(requestB.headers, ['Bearer b-access', 'Bearer b-access-new']);
      expect(storage.accessToken, 'b-access-new');
      expect(storage.refreshToken, 'b-refresh');
    });
  });

  group('같은 세션의 동시 401', () {
    test('재발급은 한 번만 실행하고 두 요청은 각각 새 토큰으로 한 번씩 재시도한다', () async {
      final first = RecordedRequest(Completer<String>());
      final second = RecordedRequest(Completer<String>());

      final pendingFirst = repository.authorizedRequest<String>(first.call);
      final pendingSecond = repository.authorizedRequest<String>(second.call);
      await _flush();

      first.firstResponse.completeError(_unauthorized);
      second.firstResponse.completeError(_unauthorized);
      await _flush();

      expect(api.refreshCalls, hasLength(1));
      api.refreshCalls.single.complete(_refreshed('a-access-new'));

      expect(await pendingFirst, 'ok:Bearer a-access-new');
      expect(await pendingSecond, 'ok:Bearer a-access-new');
      expect(api.refreshCalls, hasLength(1));
      expect(first.headers, ['Bearer a-access', 'Bearer a-access-new']);
      expect(second.headers, ['Bearer a-access', 'Bearer a-access-new']);
      expect(storage.accessToken, 'a-access-new');
    });

    test('재발급이 끝난 뒤 401을 받은 요청은 다시 재발급하지 않고 새 토큰을 쓴다', () async {
      final first = RecordedRequest(Completer<String>());
      final second = RecordedRequest(Completer<String>());

      final pendingFirst = repository.authorizedRequest<String>(first.call);
      final pendingSecond = repository.authorizedRequest<String>(second.call);
      await _flush();

      first.firstResponse.completeError(_unauthorized);
      await _flush();
      api.refreshCalls.single.complete(_refreshed('a-access-new'));
      expect(await pendingFirst, 'ok:Bearer a-access-new');

      second.firstResponse.completeError(_unauthorized);

      expect(await pendingSecond, 'ok:Bearer a-access-new');
      expect(api.refreshCalls, hasLength(1));
    });

    test('Access Token 재발급은 세션 번호를 바꾸지 않는다', () async {
      final before = repository.sessionId;
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();
      request.firstResponse.completeError(_unauthorized);
      await _flush();
      api.refreshCalls.single.complete(_refreshed('a-access-new'));
      await pending;

      expect(repository.sessionId, before);
    });
  });

  group('세션 시작과 종료', () {
    test('로그인은 세션 번호를 한 번 바꾸고 새 토큰을 저장한다', () async {
      storage.accessToken = null;
      storage.refreshToken = null;
      final before = repository.sessionId;

      await repository.login(loginId: 'userB', password: 'pw');

      expect(repository.sessionId, before + 1);
      expect(storage.accessToken, 'b-access');
      expect(storage.refreshToken, 'b-refresh');
    });

    test('로그아웃은 서버 응답을 기다리지 않고 로컬 토큰을 먼저 지운다', () async {
      api.logoutGate = Completer<void>();
      final before = repository.sessionId;

      await repository.logout();

      expect(storage.isEmpty, isTrue);
      expect(repository.sessionId, before + 1);
      expect(api.logoutRefreshTokens, ['a-refresh']);

      // 서버 로그아웃이 늦게 끝나도 그 사이 로그인한 계정의 토큰을 지우지 않는다.
      await repository.login(loginId: 'userB', password: 'pw');
      api.logoutGate!.complete();
      await _flush();

      expect(storage.accessToken, 'b-access');
    });

    test('로그아웃은 Access Token이 아니라 이 기기의 Refresh Token을 서버에 보낸다', () async {
      storage.accessToken = 'expired-access';

      await repository.logout();

      expect(api.logoutRefreshTokens, ['a-refresh']);
      expect(storage.isEmpty, isTrue);
    });

    test('같은 계정으로 다시 로그인한 뒤 이전 로그아웃이 도착해도 새 세션 토큰은 그대로다', () async {
      api.logoutGate = Completer<void>();

      await repository.logout();

      // 같은 계정으로 다시 로그인해 새 Refresh Token을 받는다.
      api.nextLoginAccessToken = 'a2-access';
      api.nextLoginRefreshToken = 'a2-refresh';
      await repository.login(loginId: 'userA', password: 'pw');

      // 이전 로그아웃이 늦게 끝난다. 서버에는 이전 토큰만 보냈다.
      api.logoutGate!.complete();
      await _flush();

      expect(api.logoutRefreshTokens, ['a-refresh']);
      expect(storage.accessToken, 'a2-access');
      expect(storage.refreshToken, 'a2-refresh');

      // 새 세션의 재발급은 새 Refresh Token으로 나간다.
      final request = RecordedRequest(Completer<String>());
      final pending = repository.authorizedRequest<String>(request.call);
      await _flush();
      request.firstResponse.completeError(_unauthorized);
      await _flush();

      expect(api.refreshTokensSent, ['a2-refresh']);
      api.refreshCalls.single.complete(_refreshed('a2-access-new'));
      expect(await pending, 'ok:Bearer a2-access-new');
    });

    test('서버 로그아웃이 실패해도 로컬 로그아웃은 끝나 있다', () async {
      api.logoutGate = Completer<void>();

      await repository.logout();
      api.logoutGate!.completeError(const ApiException(message: '연결 실패'));
      await _flush();

      expect(storage.isEmpty, isTrue);
    });

    test('로컬 삭제가 한 번 실패하면 다시 지우고 로그아웃을 끝낸다', () async {
      storage.clearFailuresRemaining = 1;

      await repository.logout();

      expect(storage.clearCallCount, 2);
      expect(storage.isEmpty, isTrue);
      expect(api.logoutRefreshTokens, ['a-refresh']);
    });

    test('로컬 삭제가 끝내 실패해도 서버 로그아웃은 보내고 삭제 오류를 알린다', () async {
      storage.clearFailuresRemaining = 2;
      final before = repository.sessionId;

      await expectLater(repository.logout(), throwsA(isA<StateError>()));

      expect(storage.clearCallCount, 2);
      expect(api.logoutRefreshTokens, ['a-refresh']);
      expect(repository.sessionId, before + 1);
    });

    test('로컬 삭제가 실패한 뒤에도 순차 처리 경로는 다음 작업을 막지 않는다', () async {
      storage.clearFailuresRemaining = 2;
      await expectLater(repository.logout(), throwsA(isA<StateError>()));

      await repository.login(loginId: 'userB', password: 'pw');

      expect(storage.accessToken, 'b-access');
    });

    test('계정 탈퇴는 공통 세션 종료 경로로 토큰을 지우고 번호를 한 번만 바꾼다', () async {
      final before = repository.sessionId;

      await repository.deleteAccount();

      expect(api.deleteAccountHeaders, ['Bearer a-access']);
      expect(storage.isEmpty, isTrue);
      expect(repository.sessionId, before + 1);
    });

    test('clearTokensIfSession은 다른 계정으로 바뀐 뒤에는 토큰을 지우지 않는다', () async {
      final oldSession = repository.sessionId;
      await switchToAccountB();

      final cleared = await repository.clearTokensIfSession(oldSession);

      expect(cleared, isFalse);
      expect(storage.accessToken, 'b-access');
    });
  });
}
