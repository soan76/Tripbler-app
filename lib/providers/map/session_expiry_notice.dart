/// 지도 검색·상세 조회에서 세션 만료가 확정됐을 때 띄울 안내를 관리한다.
///
/// 사용자 검색에서 만료가 확정됐을 때만, 만료된 세션당 한 번 안내한다.
/// 검색 중 만료되면 AuthNotifier가 로그인 상태를 먼저 해제하고 그 알림으로 검색 상태가
/// 비워진 뒤에 만료 예외가 도착한다. 그래서 로그인이 풀린 순간 진행 중이던 검색 요청을
/// 따로 기억해 두고, 그 요청이 만료로 끝나면 안내한다.
///
/// 상태를 바꾸는 메서드는 화면에 알려야 하면(안내 대기 여부가 바뀌면) true를 돌려준다.
class SessionExpiryNotice {
  /// 응답을 기다리는 검색 요청 번호들(최신이 아닌 요청 포함).
  final Set<int> _inFlightSearchIds = <int>{};

  /// 로그인이 풀린 순간 진행 중이던 검색 요청 번호들.
  final Set<int> _signedOutSearchIds = <int>{};

  /// 이미 안내했거나 안내를 기다리는 만료 세션 번호들.
  final Set<int> _noticedExpiredSessionIds = <int>{};

  bool _isPending = false;

  /// 기다리는 만료 안내를 띄울 때의 세션 번호. 그 뒤 세션이 또 바뀌면(다시 로그인,
  /// 로그아웃 등) 안내는 지난 일이라 표시하지 않는다.
  int? _noticeSessionId;

  /// 표시를 기다리는 만료 안내가 있는지.
  bool get isPending => _isPending;

  /// [requestId] 검색이 아직 응답을 기다리는지.
  bool isSearchInFlight(int requestId) =>
      _inFlightSearchIds.contains(requestId);

  /// 검색 요청을 보냈다.
  void searchStarted(int requestId) {
    _inFlightSearchIds.add(requestId);
  }

  /// 검색 요청이 끝났다(성공·실패·버림 모두).
  void searchFinished(int requestId) {
    _inFlightSearchIds.remove(requestId);
    _signedOutSearchIds.remove(requestId);
  }

  /// 만료로 끝난 [requestId] 검색이 만료를 확정했는지: 로그인이 풀리기 전에 시작된
  /// 최신 검색이었거나([isCurrentSearch]), 로그인이 풀린 순간 진행 중이던 검색이다
  /// (최신이 아니어도 같은 세션의 사용자 검색).
  bool confirmsExpiry(int requestId, {required bool isCurrentSearch}) {
    return isCurrentSearch || _signedOutSearchIds.contains(requestId);
  }

  /// 세션이 바뀐 순간 진행 중이던 검색을 기억한다. 만료로 끝나면 사용자 검색이 만료를
  /// 확정한 것이다.
  void sessionChanged() {
    _signedOutSearchIds.addAll(_inFlightSearchIds);
  }

  /// 만료된 세션([expiredSessionId])의 안내를 한 번만 대기시킨다.
  /// 이미 다시 로그인했다면([isSignedIn], 이전 세션의 늦은 예외) 새 화면에 띄우지 않는다.
  /// [currentSessionId]는 안내를 대기시킬 때만 읽는다.
  bool raise(
    int? expiredSessionId, {
    required bool isSignedIn,
    required int Function() currentSessionId,
  }) {
    if (isSignedIn) {
      return false;
    }

    if (expiredSessionId != null &&
        !_noticedExpiredSessionIds.add(expiredSessionId)) {
      return false;
    }

    if (_isPending) {
      return false;
    }

    _isPending = true;
    _noticeSessionId = currentSessionId();
    return true;
  }

  /// 화면이 안내를 표시했다.
  bool consume() {
    if (!_isPending) {
      return false;
    }

    _isPending = false;
    return true;
  }

  /// 로그인 세션([sessionId])이나 로그인 여부가 바뀌었다. 새로 로그인했거나, 안내를
  /// 기다리는 동안 세션이 또 바뀌었으면 아직 표시하지 않은 이전 세션의 안내는 무효다.
  bool authChanged({required int sessionId, required bool isAuthenticated}) {
    if (_isPending && (isAuthenticated || sessionId != _noticeSessionId)) {
      _isPending = false;
      return true;
    }

    return false;
  }
}
