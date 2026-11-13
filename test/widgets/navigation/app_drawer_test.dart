import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/main.dart' show buildAppScope;
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/screens/auth/login_screen.dart';
import 'package:tripbler/screens/settings_screen.dart';
import 'package:tripbler/screens/user/user_page.dart';
import 'package:tripbler/widgets/navigation/app_drawer.dart';

/// 서랍이 읽는 값만 흉내 내는 대역.
class _FakeAuth extends AuthNotifier {
  _FakeAuth({
    this.isAuthenticated = true,
    this.nickname,
    this.loginId,
    this.profileImageUrl,
    this.isLoading = false,
    this.logoutGate,
  });

  final bool isAuthenticated;
  final String? nickname;
  final String? loginId;
  final String? profileImageUrl;
  final bool isLoading;

  /// 주어지면 로그아웃이 이 Future가 끝날 때까지 기다린다(느린 연결 흉내).
  final Future<void>? logoutGate;

  int logoutCount = 0;

  @override
  AuthState build() {
    return AuthState(
      isInitialized: true,
      isAuthenticated: isAuthenticated,
      nickname: nickname,
      loginId: loginId,
      profileImageUrl: profileImageUrl,
      isLoading: isLoading,
    );
  }

  /// 실제 [AuthNotifier.logout]처럼 진행 중에는 [AuthState.isLoading]을 켜고,
  /// 끝나면 로그인 상태를 지운다.
  @override
  Future<void> logout() async {
    logoutCount++;
    state = state.copyWith(isLoading: true);
    await logoutGate;
    state = state.withoutUser().copyWith(isLoading: false);
  }
}

/// 서랍이 밀어 넣은 화면을 기록하고, 대상 화면이 요구하는 Provider 없이 시험하도록
/// 화면을 그리기 전에 바로 걷어 낸다.
class _PushRecorder extends NavigatorObserver {
  bool armed = false;
  final List<Type> pushedPages = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!armed || route is! MaterialPageRoute) {
      return;
    }
    pushedPages.add(route.builder(route.navigator!.context).runtimeType);
    // 화면은 다음 프레임에 그려지므로, 그 전에 실행되는 마이크로태스크에서 걷어 낸다.
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }
}

Future<void> _openDrawer(
  WidgetTester tester,
  _FakeAuth auth, {
  Size size = const Size(360, 760),
  double textScale = 1,
  ThemeData? theme,
  NavigatorObserver? observer,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    buildAppScope(
      overrides: [authProvider.overrideWith(() => auth)],
      child: MaterialApp(
        theme: theme,
        navigatorObservers: [?observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(drawer: AppDrawer(), body: SizedBox.expand()),
      ),
    ),
  );
  await _reopenDrawer(tester);
}

Future<void> _reopenDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await tester.pumpAndSettle();
}

/// 서랍의 항목을 누르면 서랍이 닫히고 [page] 화면 하나가 열리는지 확인한다.
Future<void> _expectOpens(
  WidgetTester tester,
  _FakeAuth auth,
  String label,
  Type page,
) async {
  final observer = _PushRecorder();
  await _openDrawer(tester, auth, observer: observer);
  observer.armed = true;

  await tester.tap(find.text(label));
  await tester.pumpAndSettle();

  expect(find.byType(Drawer), findsNothing);
  expect(observer.pushedPages, [page]);
  expect(tester.takeException(), isNull);
}

/// 프로필 사진 자리(원형) 안의 기본 아이콘.
final _avatarIcon = find.descendant(
  of: find.byType(ClipOval),
  matching: find.byIcon(Icons.account_circle_outlined),
);

/// [getUrl] 결과만 정해 주는 HTTP 클라이언트 대역(실제 네트워크를 쓰지 않는다).
class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this._getUrl);

  final Future<HttpClientRequest> Function(Uri url) _getUrl;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _getUrl(url);
}

TextButton _logoutButton(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, '로그아웃'));

void main() {
  testWidgets('로그인하면 이름·아이디, 구분선 아래 설정, 맨 아래 로그아웃을 둔다', (tester) async {
    await _openDrawer(
      tester,
      _FakeAuth(nickname: '여행자', loginId: 'tripbler_user'),
    );

    expect(find.text('여행자'), findsOneWidget);
    expect(find.text('tripbler_user'), findsOneWidget);
    expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);

    final name = tester.getRect(find.text('여행자'));
    final id = tester.getRect(find.text('tripbler_user'));
    final divider = tester.getRect(find.byType(Divider));
    final settings = tester.getRect(find.text('설정'));
    final logout = tester.getRect(find.text('로그아웃'));
    final drawer = tester.getRect(find.byType(Drawer));
    expect(id.top, greaterThan(name.bottom));
    expect(divider.top, greaterThan(id.bottom));
    expect(settings.top, greaterThan(divider.bottom));
    // 로그아웃은 메뉴와 떨어진 서랍 맨 아래에 있다.
    expect(logout.top, greaterThan(drawer.center.dy));
    expect(drawer.bottom - logout.bottom, lessThan(48));

    final colors = Theme.of(tester.element(find.byType(Drawer))).colorScheme;
    final logoutButton = find.widgetWithText(TextButton, '로그아웃');
    expect(
      tester
          .widget<TextButton>(logoutButton)
          .style!
          .foregroundColor!
          .resolve({}),
      colors.error,
    );
    // 터치 영역 48 이상.
    expect(tester.getSize(logoutButton).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(find.widgetWithText(ListTile, '설정')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('닉네임이 없으면 아이디를 이름 자리에 쓰고 보조 글자는 없다', (tester) async {
    await _openDrawer(tester, _FakeAuth(loginId: 'tripbler_user'));

    expect(find.text('tripbler_user'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('로그인하지 않았으면 로그인 진입을 두고 로그아웃은 없다', (tester) async {
    await _openDrawer(tester, _FakeAuth(isAuthenticated: false));

    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
    expect(find.text('로그아웃'), findsNothing);
  });

  testWidgets('로그아웃을 누르면 서랍을 닫고 한 번 로그아웃한다', (tester) async {
    final auth = _FakeAuth(nickname: '여행자', loginId: 'tripbler_user');
    await _openDrawer(tester, auth);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(auth.logoutCount, 1);
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('로그아웃되었습니다.'), findsOneWidget);
  });

  testWidgets('로그아웃이 서랍이 닫힌 뒤에 끝나도 안내를 띄운다', (tester) async {
    final gate = Completer<void>();
    final auth = _FakeAuth(
      nickname: '여행자',
      loginId: 'tripbler_user',
      logoutGate: gate.future,
    );
    await _openDrawer(tester, auth);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    // 서랍은 이미 닫혀 트리에서 빠졌고 로그아웃은 아직 진행 중이다.
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('로그아웃되었습니다.'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('로그아웃되었습니다.'), findsOneWidget);
  });

  testWidgets('로그아웃이 진행 중이면 다시 연 서랍의 로그아웃은 눌리지 않는다', (tester) async {
    final gate = Completer<void>();
    final auth = _FakeAuth(
      nickname: '여행자',
      loginId: 'tripbler_user',
      logoutGate: gate.future,
    );
    await _openDrawer(tester, auth);
    expect(_logoutButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    await _reopenDrawer(tester);

    expect(_logoutButton(tester).onPressed, isNull);
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(auth.logoutCount, 1);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('인증 작업이 진행 중이면 로그아웃은 비활성이다', (tester) async {
    final auth = _FakeAuth(nickname: '여행자', isLoading: true);
    await _openDrawer(tester, auth);

    expect(_logoutButton(tester).onPressed, isNull);
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(auth.logoutCount, 0);
    expect(find.byType(Drawer), findsOneWidget);
  });

  testWidgets('다크 테마에서도 로그아웃은 위험 색이다', (tester) async {
    final dark = ThemeData(brightness: Brightness.dark);
    await _openDrawer(tester, _FakeAuth(nickname: '여행자'), theme: dark);

    final colors = Theme.of(tester.element(find.byType(Drawer))).colorScheme;
    expect(colors.brightness, Brightness.dark);
    expect(
      _logoutButton(tester).style!.foregroundColor!.resolve({}),
      colors.error,
    );
    expect(colors.error, isNot(ThemeData().colorScheme.error));
  });

  for (final (nickname, loginId) in [(null, null), ('', ''), ('   ', ' ')]) {
    testWidgets('닉네임 "$nickname"·아이디 "$loginId"이면 "사용자"로 쓴다', (tester) async {
      await _openDrawer(
        tester,
        _FakeAuth(nickname: nickname, loginId: loginId),
      );

      expect(find.text('사용자'), findsOneWidget);
      expect(find.text('로그아웃'), findsOneWidget);
    });
  }

  testWidgets('긴 이름과 아이디는 한 줄로 말줄임한다', (tester) async {
    const name = '아주아주아주아주아주아주아주 긴 여행자 이름입니다';
    const id = 'tripbler_user_with_a_really_really_long_login_identifier';
    await _openDrawer(tester, _FakeAuth(nickname: name, loginId: id));
    expect(tester.takeException(), isNull);

    for (final text in [name, id]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(paragraph.maxLines, 1);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(paragraph.didExceedMaxLines, isTrue, reason: text);
    }
  });

  testWidgets('프로필 사진을 받는 동안에는 기본 아이콘을 보여 준다', (tester) async {
    // 응답이 오지 않는 연결: 사진은 계속 받는 중이다.
    debugNetworkImageHttpClientProvider = () =>
        _FakeHttpClient((_) => Completer<HttpClientRequest>().future);
    addTearDown(() => debugNetworkImageHttpClientProvider = null);

    await _openDrawer(
      tester,
      _FakeAuth(
        nickname: '여행자',
        profileImageUrl: 'https://example.com/loading.png',
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(_avatarIcon, findsOneWidget);
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('프로필 사진을 받지 못하면 기본 아이콘으로 바꾼다', (tester) async {
    var requests = 0;
    debugNetworkImageHttpClientProvider = () => _FakeHttpClient((_) {
      requests++;
      return Future.error(const SocketException('연결 끊김'));
    });
    addTearDown(() => debugNetworkImageHttpClientProvider = null);

    await _openDrawer(
      tester,
      _FakeAuth(
        nickname: '여행자',
        profileImageUrl: 'https://example.com/broken.png',
      ),
    );

    // 요청이 실제로 나갔다가 실패한 뒤의 화면이다.
    expect(requests, 1);
    expect(_avatarIcon, findsOneWidget);
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('설정을 누르면 서랍을 닫고 설정 화면을 연다', (tester) async {
    await _expectOpens(
      tester,
      _FakeAuth(nickname: '여행자'),
      '설정',
      SettingsScreen,
    );
  });

  testWidgets('계정 영역을 누르면 서랍을 닫고 내 정보 화면을 연다', (tester) async {
    await _expectOpens(tester, _FakeAuth(nickname: '여행자'), '여행자', UserPage);
  });

  testWidgets('로그인 영역을 누르면 서랍을 닫고 로그인 화면을 연다', (tester) async {
    await _expectOpens(
      tester,
      _FakeAuth(isAuthenticated: false),
      '로그인',
      LoginScreen,
    );
  });

  testWidgets('계정 영역은 이름과 아이디를 버튼 하나로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _openDrawer(
      tester,
      _FakeAuth(nickname: '여행자', loginId: 'tripbler_user'),
    );

    final node = tester.getSemantics(find.text('여행자'));
    expect(node.label, contains('여행자'));
    expect(node.label, contains('tripbler_user'));
    expect(node.hint, '내 정보 열기');
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('글자를 두 배로 키운 가로 화면에서도 넘치지 않고 로그아웃에 닿는다', (tester) async {
    await _openDrawer(
      tester,
      _FakeAuth(nickname: '아주 긴 여행자 이름입니다', loginId: 'tripbler_user_long_id'),
      size: const Size(640, 320),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('로그아웃'),
      100,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    // 바뀐 스크롤 위치는 다음 프레임에 반영된다.
    await tester.pump();
    expect(find.text('로그아웃').hitTestable(), findsOneWidget);
  });
}
