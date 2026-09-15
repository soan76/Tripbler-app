import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/widgets/user/user_info_section.dart';

void main() {
  Widget buildTestWidget({ImageProvider<Object>? profileImage}) {
    return MaterialApp(
      home: Scaffold(
        body: UserInfoSection(
          displayName: '테스트사용자',
          loginId: 'testuser01',
          profileImage: profileImage,
          onEditNickname: () {},
          onChangeProfileImage: () {},
          onDeleteProfileImage: () {},
        ),
      ),
    );
  }

  group('UserInfoSection 프로필 이미지', () {
    testWidgets('프로필 이미지가 없으면 기본 사용자 아이콘을 표시한다', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('프로필 이미지 로딩에 실패하면 기본 사용자 아이콘을 표시한다', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          profileImage: const NetworkImage(
            'https://invalid.example/profile.png',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });
}
