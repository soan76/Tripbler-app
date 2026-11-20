import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/repositories/auth/auth_token_session.dart';
import 'package:tripbler/services/auth/token_storage_service.dart';

/// 메모리 토큰 저장소. clearTokens 실패 횟수와 지연을 테스트가 정한다.
class _MemoryTokenStorage extends TokenStorageService {
  _MemoryTokenStorage();

  String? accessToken = 'a-access';
  String? refreshToken = 'a-refresh';
  String? tokenType = 'Bearer';

  int saveTokensCount = 0;
  int clearCallCount = 0;

  /// 남은 횟수만큼 clearTokens가 실패한다.
  int clearFailuresRemaining = 0;

  /// 설정되면 clearTokens가 이 Future가 끝날 때까지 기다린다.
  Completer<void>? clearGate;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String tokenType,
  }) async {
    saveTokensCount++;
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.tokenType = tokenType;
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
  Future<void> clearTokens() async {
    clearCallCount++;

    final gate = clearGate;

    if (gate != null) {
      await gate.future;
    }

    if (clearFailuresRemaining > 0) {
      clearFailuresRemaining--;
      throw StateError('테스트용 저장소 삭제 실패');
    }

    accessToken = null;
    refreshToken = null;
    tokenType = null;
  }
}

void main() {
  late _MemoryTokenStorage storage;
  late AuthTokenSession session;

  setUp(() {
    storage = _MemoryTokenStorage();
    session = AuthTokenSession(storage);
  });

  test('세션 시작은 번호를 1 올리고 새 토큰을 저장한다', () async {
    expect(session.sessionId, 0);

    await session.startSession(
      accessToken: 'b-access',
      refreshToken: 'b-refresh',
      tokenType: 'Bearer',
    );

    expect(session.sessionId, 1);
    expect(storage.saveTokensCount, 1);
    expect(storage.accessToken, 'b-access');
    expect(storage.refreshToken, 'b-refresh');
  });

  test('clearTokensIfSession은 다른 세션이면 false를 돌려주고 지우지 않는다', () async {
    final cleared = await session.clearTokensIfSession(5);

    expect(cleared, isFalse);
    expect(session.sessionId, 0);
    expect(storage.clearCallCount, 0);
    expect(storage.accessToken, 'a-access');
  });

  test('clearTokensIfSession은 같은 세션이면 번호를 올리고 지운다', () async {
    final cleared = await session.clearTokensIfSession(0);

    expect(cleared, isTrue);
    expect(session.sessionId, 1);
    expect(storage.clearCallCount, 1);
    expect(storage.accessToken, isNull);
  });

  test('로그아웃 로컬 부분은 삭제가 한 번 실패하면 다시 시도해 성공한다', () async {
    storage.clearFailuresRemaining = 1;

    final result = await session.endSessionForLogout();

    expect(result.refreshToken, 'a-refresh');
    expect(result.clearError, isNull);
    expect(result.clearStackTrace, isNull);
    expect(session.sessionId, 1);
    expect(storage.clearCallCount, 2);
    expect(storage.accessToken, isNull);
  });

  test('로그아웃 로컬 부분은 삭제가 두 번 실패하면 오류를 돌려주고 번호는 올린다', () async {
    storage.clearFailuresRemaining = 2;

    final result = await session.endSessionForLogout();

    expect(result.refreshToken, 'a-refresh');
    expect(result.clearError, isA<StateError>());
    expect(result.clearStackTrace, isNotNull);
    expect(session.sessionId, 1);
    expect(storage.clearCallCount, 2);
    expect(storage.accessToken, 'a-access');
  });

  test('번호+헤더 읽기는 먼저 시작한 세션 변경이 끝난 뒤에 실행된다', () async {
    final gate = Completer<void>();
    storage.clearGate = gate;

    final clearing = session.clearTokens();
    final reading = session.readSessionAuth();

    var readDone = false;
    unawaited(reading.then((_) => readDone = true));

    await pumpEventQueue();

    // 삭제가 끝나지 않았으므로 읽기도 아직 실행되지 않는다.
    expect(storage.clearCallCount, 1);
    expect(readDone, isFalse);

    gate.complete();
    await clearing;

    final auth = await reading;

    expect(auth.sessionId, 1);
    expect(auth.header, isNull);
  });

  test('재발급 저장은 세션이 바뀌었으면 저장하지 않는다', () async {
    await session.clearTokens();

    final saved = await session.saveRefreshedAccessToken(
      0,
      accessToken: 'new-access',
      tokenType: 'Bearer',
    );

    expect(saved.sameSession, isFalse);
    expect(saved.header, isNull);
    expect(storage.accessToken, isNull);
  });
}
