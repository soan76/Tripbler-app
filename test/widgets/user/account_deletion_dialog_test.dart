import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/user/account_deletion_dialog.dart';

void main() {
  group('AccountDeletionDialog', () {
    testWidgets('탈퇴 안내 문구와 취소/탈퇴 버튼을 표시한다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AccountDeletionDialog())),
      );

      // 안내 문구는 하나의 Text 위젯으로 구성되어 있으므로
      // 핵심 문구가 포함되어 있는지만 검증한다.
      expect(find.textContaining('탈퇴 시 계정 정보가 소멸되며'), findsOneWidget);
      expect(find.textContaining('복구가 불가능합니다'), findsOneWidget);
      expect(find.textContaining('정말로 탈퇴하시겠습니까?'), findsOneWidget);

      expect(find.text('취소'), findsOneWidget);
      expect(find.text('탈퇴'), findsOneWidget);
    });

    testWidgets('취소 버튼을 누르면 false를 반환한다', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await AccountDeletionDialog.show(context);
                  },
                  child: const Text('다이얼로그 열기'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('다이얼로그 열기'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionDialog), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.byType(AccountDeletionDialog), findsNothing);
    });

    testWidgets('탈퇴 버튼을 누르면 true를 반환한다', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await AccountDeletionDialog.show(context);
                  },
                  child: const Text('다이얼로그 열기'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('다이얼로그 열기'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('탈퇴'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.byType(AccountDeletionDialog), findsNothing);
    });

    testWidgets('시스템 뒤로가기로 닫으면 false를 반환한다', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await AccountDeletionDialog.show(context);
                  },
                  child: const Text('다이얼로그 열기'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('다이얼로그 열기'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionDialog), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionDialog), findsNothing);
      expect(result, isFalse);
    });

    testWidgets('바깥 영역을 눌러도 확인 다이얼로그가 닫히지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AccountDeletionDialog.show(context);
                  },
                  child: const Text('다이얼로그 열기'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('다이얼로그 열기'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionDialog), findsOneWidget);

      // AlertDialog 바깥의 ModalBarrier 영역을 누른다.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(AccountDeletionDialog), findsOneWidget);
    });

    testWidgets('취소/탈퇴 버튼에 지정한 배경색을 사용한다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AccountDeletionDialog())),
      );

      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '취소'),
      );

      final deleteButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '탈퇴'),
      );

      expect(
        cancelButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFFAFAFAB),
      );

      expect(
        deleteButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xFFEE7234),
      );
    });
  });

  group('AccountDeletionLoadingDialog', () {
    testWidgets('로딩 인디케이터와 처리 중 문구를 표시한다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AccountDeletionLoadingDialog())),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('계정 탈퇴 처리 중...'), findsOneWidget);
      expect(find.byType(PopScope), findsOneWidget);

      final popScope = tester.widget<PopScope>(find.byType(PopScope));

      expect(popScope.canPop, isFalse);
    });

    testWidgets('시스템 뒤로가기를 시도해도 로딩 다이얼로그가 닫히지 않는다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const AccountDeletionLoadingDialog(),
                    );
                  },
                  child: const Text('로딩 열기'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('로딩 열기'));

      // CircularProgressIndicator는 계속 애니메이션되므로
      // pumpAndSettle()을 사용하면 테스트가 끝나지 않을 수 있다.
      // 다이얼로그 진입 애니메이션에 필요한 프레임만 유한하게 진행한다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AccountDeletionLoadingDialog), findsOneWidget);

      await tester.binding.handlePopRoute();

      // PopScope(canPop: false)로 뒤로가기가 차단되는지만 확인하면 되므로
      // 계속 애니메이션되는 로딩 인디케이터가 settle될 때까지 기다리지 않는다.
      await tester.pump();

      expect(find.byType(AccountDeletionLoadingDialog), findsOneWidget);
    });
  });
}