import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/user/nickname_edit_dialog.dart';

const Duration _minimumLoadingDuration = Duration(seconds: 1);

Future<void> _pumpAndOpenDialog(
  WidgetTester tester, {
  String? initialNickname,
  required NicknameSubmitCallback onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                NicknameEditDialog.show(
                  context,
                  initialNickname: initialNickname,
                  onSubmit: onSubmit,
                );
              },
              child: const Text('닉네임 변경 열기'),
            );
          },
        ),
      ),
    ),
  );

  await tester.tap(find.text('닉네임 변경 열기'));

  await tester.pumpAndSettle();
}

void main() {
  group('NicknameEditDialog', () {
    testWidgets('정상 닉네임 제출에 성공하면 다이얼로그를 닫는다', (tester) async {
      int submitCallCount = 0;
      String? receivedNickname;

      await _pumpAndOpenDialog(
        tester,
        initialNickname: '기존닉네임',
        onSubmit: (nickname) async {
          submitCallCount++;
          receivedNickname = nickname;

          return null;
        },
      );

      await tester.enterText(find.byType(TextField), '새닉네임');

      await tester.tap(find.text('확인'));

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      expect(submitCallCount, 1);
      expect(receivedNickname, '새닉네임');

      await tester.pump(_minimumLoadingDuration);

      await tester.pumpAndSettle();

      expect(find.text('닉네임 변경'), findsNothing);

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('중복 닉네임이면 오류 메시지를 표시하고 다이얼로그를 유지한다', (tester) async {
      int submitCallCount = 0;
      String? receivedNickname;

      await _pumpAndOpenDialog(
        tester,
        initialNickname: '기존닉네임',
        onSubmit: (nickname) async {
          submitCallCount++;
          receivedNickname = nickname;

          return '이미 사용 중인 닉네임입니다.';
        },
      );

      expect(find.text('닉네임 변경'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '사용중닉네임');

      await tester.tap(find.text('확인'));

      // 제출 직후 로딩 상태로 전환된다.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      expect(submitCallCount, 1);
      expect(receivedNickname, '사용중닉네임');

      await tester.pump(_minimumLoadingDuration);

      await tester.pump();

      expect(find.text('이미 사용 중인 닉네임입니다.'), findsOneWidget);

      // 실패했으므로 다이얼로그는 유지된다.
      expect(find.text('닉네임 변경'), findsOneWidget);

      // 오류 처리 후 다시 제출할 수 있다.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('앞뒤 공백을 제거한 닉네임을 onSubmit에 전달한다', (tester) async {
      String? receivedNickname;

      await _pumpAndOpenDialog(
        tester,
        initialNickname: '기존닉네임',
        onSubmit: (nickname) async {
          receivedNickname = nickname;

          return null;
        },
      );

      await tester.enterText(find.byType(TextField), '  여행자  ');

      await tester.tap(find.text('확인'));

      await tester.pump();

      expect(receivedNickname, '여행자');

      // 진행 중인 최소 로딩 시간을 완료한다.
      await tester.pump(_minimumLoadingDuration);

      await tester.pumpAndSettle();
    });

    testWidgets('빈 닉네임이면 API 요청 없이 입력 오류를 표시한다', (tester) async {
      int submitCallCount = 0;

      await _pumpAndOpenDialog(
        tester,
        initialNickname: null,
        onSubmit: (nickname) async {
          submitCallCount++;

          return null;
        },
      );

      await tester.tap(find.text('확인'));

      await tester.pump();

      expect(find.text('닉네임을 입력해 주세요.'), findsOneWidget);

      expect(submitCallCount, 0);

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}