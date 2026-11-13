import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/main.dart';

int calls = 0;

final failing = Provider<int>((ref) {
  calls++;
  throw StateError('x');
});

void main() {
  testWidgets('buildAppScope는 자동 재시도를 하지 않는다', (tester) async {
    calls = 0;
    await tester.pumpWidget(
      buildAppScope(
        child: Consumer(
          builder: (_, ref, _) {
            // 오류 상태 구독
            ref.watch(failing.select((_) => 0));
            return const SizedBox();
          },
        ),
      ),
    );
    tester.takeException();
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
    expect(calls, 1);
  });
}
