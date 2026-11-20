import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/providers/map/session_expiry_notice.dart';

void main() {
  late SessionExpiryNotice notice;
  late int currentSessionId;
  late int sessionIdReads;

  int readSessionId() {
    sessionIdReads++;
    return currentSessionId;
  }

  bool raise(int? expiredSessionId, {bool isSignedIn = false}) {
    return notice.raise(
      expiredSessionId,
      isSignedIn: isSignedIn,
      currentSessionId: readSessionId,
    );
  }

  setUp(() {
    notice = SessionExpiryNotice();
    currentSessionId = 2;
    sessionIdReads = 0;
  });

  group('raise', () {
    test('로그아웃 상태에서 만료되면 안내를 대기시키고 세션 번호를 읽는다', () {
      expect(raise(1), isTrue);
      expect(notice.isPending, isTrue);
      expect(sessionIdReads, 1);
    });

    test('같은 만료 세션은 소비한 뒤에도 한 번만 안내한다', () {
      expect(raise(1), isTrue);
      expect(notice.consume(), isTrue);

      expect(raise(1), isFalse);
      expect(notice.isPending, isFalse);
      expect(sessionIdReads, 1);
    });

    test('다른 만료 세션은 다시 안내한다', () {
      expect(raise(1), isTrue);
      expect(notice.consume(), isTrue);

      expect(raise(3), isTrue);
      expect(notice.isPending, isTrue);
    });

    test('세션 번호가 없는 만료는 매번 안내할 수 있다', () {
      expect(raise(null), isTrue);
      expect(notice.consume(), isTrue);

      expect(raise(null), isTrue);
    });

    test('로그인 상태면 안내하지 않고 그 세션을 기록하지도 않는다', () {
      expect(raise(1, isSignedIn: true), isFalse);
      expect(notice.isPending, isFalse);
      expect(sessionIdReads, 0);

      // 기록하지 않았으므로 로그아웃 상태에서 같은 세션은 안내한다.
      expect(raise(1), isTrue);
    });

    test('이미 대기 중이면 새로 대기시키지 않지만 만료 세션은 기록한다', () {
      expect(raise(1), isTrue);

      currentSessionId = 5;
      expect(raise(3), isFalse);
      expect(sessionIdReads, 1);

      expect(notice.consume(), isTrue);
      expect(raise(3), isFalse);
    });
  });

  group('consume', () {
    test('대기 중인 안내가 없으면 false다', () {
      expect(notice.consume(), isFalse);
    });

    test('대기 중인 안내를 소비한다', () {
      raise(1);

      expect(notice.consume(), isTrue);
      expect(notice.isPending, isFalse);
      expect(notice.consume(), isFalse);
    });
  });

  group('authChanged', () {
    test('대기 중인 안내가 없으면 바뀌지 않는다', () {
      expect(notice.authChanged(sessionId: 9, isAuthenticated: true), isFalse);
    });

    test('다시 로그인하면 대기 중인 안내를 무효로 한다', () {
      raise(1);

      expect(notice.authChanged(sessionId: 2, isAuthenticated: true), isTrue);
      expect(notice.isPending, isFalse);
    });

    test('안내를 띄운 뒤 세션이 또 바뀌면 무효로 한다', () {
      raise(1);

      expect(notice.authChanged(sessionId: 3, isAuthenticated: false), isTrue);
      expect(notice.isPending, isFalse);
    });

    test('같은 세션의 로그아웃 상태 알림은 안내를 유지한다', () {
      raise(1);

      expect(notice.authChanged(sessionId: 2, isAuthenticated: false), isFalse);
      expect(notice.isPending, isTrue);
    });
  });

  group('검색 진행 기록', () {
    test('보낸 검색은 끝날 때까지 진행 중이다', () {
      notice.searchStarted(1);
      expect(notice.isSearchInFlight(1), isTrue);
      expect(notice.isSearchInFlight(2), isFalse);

      notice.searchFinished(1);
      expect(notice.isSearchInFlight(1), isFalse);
    });

    test('최신 검색이면 만료를 확정한다', () {
      notice.searchStarted(1);

      expect(notice.confirmsExpiry(1, isCurrentSearch: true), isTrue);
    });

    test('최신이 아니고 로그아웃 전에 진행 중이지 않았으면 확정하지 않는다', () {
      notice.searchStarted(1);

      expect(notice.confirmsExpiry(1, isCurrentSearch: false), isFalse);
    });

    test('로그아웃 순간 진행 중이던 검색이 만료로 끝나면 확정한다', () {
      notice.searchStarted(1);
      notice.searchStarted(2);
      notice.sessionChanged();
      notice.searchStarted(3);

      expect(notice.confirmsExpiry(1, isCurrentSearch: false), isTrue);
      expect(notice.confirmsExpiry(2, isCurrentSearch: false), isTrue);
      // 세션이 바뀐 뒤 보낸 검색은 해당하지 않는다.
      expect(notice.confirmsExpiry(3, isCurrentSearch: false), isFalse);
    });

    test('끝난 검색은 로그아웃 기록에서도 지운다', () {
      notice.searchStarted(1);
      notice.sessionChanged();
      notice.searchFinished(1);

      expect(notice.confirmsExpiry(1, isCurrentSearch: false), isFalse);
    });

    test('세션이 바뀐 순간 이미 끝난 검색은 기록하지 않는다', () {
      notice.searchStarted(1);
      notice.searchFinished(1);
      notice.sessionChanged();

      expect(notice.confirmsExpiry(1, isCurrentSearch: false), isFalse);
    });
  });
}
