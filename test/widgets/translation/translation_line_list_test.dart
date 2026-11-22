import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/models/translation/line_translation_result.dart';
import 'package:tripbler/widgets/translation/translation_line_list.dart';

LinePrice _yen({
  String text = '980円',
  num amount = 980,
  num? krwAmount = 9060,
  bool stale = false,
}) {
  return LinePrice(
    text: text,
    amount: amount,
    currency: 'JPY',
    krwAmount: krwAmount,
    krwRate: krwAmount == null ? null : 9.25,
    rateFetchedAt: krwAmount == null ? null : DateTime(2026, 11, 17, 9, 30),
    rateStale: stale,
  );
}

LineTranslationResult _result(List<TranslatedLine> lines) {
  return LineTranslationResult(
    sourceLanguageCode: 'ja',
    targetLanguageCode: 'ko',
    lines: lines,
  );
}

const _pronounceNote = '발음은 참고용이에요. 가게 이름 같은 고유명사는 다를 수 있어요.';

void main() {
  Future<void> pumpList(
    WidgetTester tester,
    LineTranslationResult result, {
    int omittedLineCount = 0,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: TranslationLineList(
              result: result,
              imagePath: null,
              omittedLineCount: omittedLineCount,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('줄마다 번역, 원화, 원문, 발음, 원래 가격을 보여 준다', (tester) async {
    await pumpList(
      tester,
      _result([
        TranslatedLine(
          original: '醤油ラーメン',
          translated: '간장 라멘',
          pronunciation: '쇼유 라멘',
          price: _yen(),
        ),
      ]),
    );

    expect(find.text('1줄을 번역했어요'), findsOneWidget);
    expect(find.text('간장 라멘'), findsOneWidget);
    expect(find.text('약 9,060원'), findsOneWidget);
    expect(find.text('醤油ラーメン'), findsOneWidget);
    expect(find.text('쇼유 라멘'), findsOneWidget);
    expect(find.text('980円'), findsOneWidget);
    expect(find.text('1 JPY = 9.25원 (11.17 09:30 기준)'), findsOneWidget);
    expect(find.text(_pronounceNote), findsOneWidget);
    expect(find.textContaining('저장된 환율'), findsNothing);
  });

  testWidgets('낭독기는 한 줄을 번역, 원화, 원문, 발음, 원래 가격 순서로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpList(
      tester,
      _result([
        TranslatedLine(
          original: '醤油ラーメン',
          translated: '간장 라멘',
          pronunciation: '쇼유 라멘',
          price: _yen(),
        ),
      ]),
    );

    expect(
      find.bySemanticsLabel('간장 라멘, 약 9,060원, 원문 醤油ラーメン, 발음 쇼유 라멘, 원래 가격 980円'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('발음이 없으면 발음 안내를 숨긴다', (tester) async {
    await pumpList(
      tester,
      _result([const TranslatedLine(original: '餃子', translated: '교자')]),
    );

    expect(find.text('교자'), findsOneWidget);
    expect(find.text(_pronounceNote), findsNothing);
  });

  testWidgets('원화로 바꾸지 못한 가격은 원래 가격만 보여 준다', (tester) async {
    await pumpList(
      tester,
      _result([
        TranslatedLine(
          original: '大盛り 150円',
          translated: '곱빼기 150엔',
          price: _yen(text: '150円', amount: 150, krwAmount: null),
        ),
      ]),
    );

    expect(find.text('150円'), findsOneWidget);
    expect(find.textContaining('약 '), findsNothing);
    expect(find.textContaining('1 JPY'), findsNothing);
    expect(find.text('환율을 받지 못한 가격은 원래 가격만 보여요.'), findsOneWidget);
  });

  testWidgets('원화 가격은 원래 가격만 보여 주고 환율 실패 안내를 띄우지 않는다', (tester) async {
    await pumpList(
      tester,
      _result([
        const TranslatedLine(
          original: '비빔밥 9,000원',
          translated: 'Bibimbap 9,000 won',
          price: LinePrice(text: '9,000원', amount: 9000, currency: 'KRW'),
        ),
      ]),
    );

    expect(find.text('9,000원'), findsOneWidget);
    expect(find.text('환율을 받지 못한 가격은 원래 가격만 보여요.'), findsNothing);
  });

  testWidgets('저장된 환율로 계산했으면 알린다', (tester) async {
    await pumpList(
      tester,
      _result([
        TranslatedLine(
          original: '醤油ラーメン',
          translated: '간장 라멘',
          price: _yen(stale: true),
        ),
      ]),
    );

    expect(find.text('최신 환율을 받지 못해 저장된 환율로 계산했어요'), findsOneWidget);
    expect(find.text('약 9,060원'), findsOneWidget);
  });

  testWidgets('환산한 통화마다 그 통화의 첫 가격 기준 환율을 한 줄씩 보여 주고 저장된 환율은 그 줄에 표시한다', (
    tester,
  ) async {
    await pumpList(
      tester,
      _result([
        TranslatedLine(
          original: 'ラーメン 980円',
          translated: '라멘 980엔',
          price: _yen(),
        ),
        TranslatedLine(
          original: 'Coke \$2',
          translated: '콜라 2달러',
          price: LinePrice(
            text: '\$2',
            amount: 2,
            currency: 'USD',
            krwAmount: 2800,
            krwRate: 1400,
            rateFetchedAt: DateTime(2026, 11, 17, 8, 0),
            rateStale: true,
          ),
        ),
        TranslatedLine(
          original: '餃子 450円',
          translated: '교자 450엔',
          price: _yen(text: '450円', amount: 450, krwAmount: 4163),
        ),
        const TranslatedLine(
          original: 'Pho 45,000₫',
          translated: '쌀국수 45,000동',
          price: LinePrice(
            text: '45,000₫',
            amount: 45000,
            currency: 'VND',
            krwAmount: 2475,
            krwRate: 0.055,
          ),
        ),
      ]),
    );

    expect(find.text('1 JPY = 9.25원 (11.17 09:30 기준)'), findsOneWidget);
    expect(
      find.text('1 USD = 1,400원 (11.17 08:00 기준) · 저장된 환율'),
      findsOneWidget,
    );
    expect(find.text('1 VND = 0.055원'), findsOneWidget);
    // 같은 통화(JPY)는 한 번만.
    expect(find.textContaining('1 JPY'), findsOneWidget);
    expect(find.text('최신 환율을 받지 못해 저장된 환율로 계산했어요'), findsOneWidget);
  });

  test('환율이 1원보다 작으면 유효 숫자 3자리까지 보여 준다', () {
    expect(TranslationLineList.formatRate(9.246), '9.25');
    expect(TranslationLineList.formatRate(1400), '1,400');
    expect(TranslationLineList.formatRate(0.0553), '0.0553');
    expect(TranslationLineList.formatRate(0.055), '0.055');
    expect(TranslationLineList.formatRate(0.5), '0.5');
    expect(TranslationLineList.formatRate(0.00123456), '0.00123');
  });

  testWidgets('보내지 못한 줄이 있으면 안내한다', (tester) async {
    await pumpList(
      tester,
      _result([const TranslatedLine(original: '餃子', translated: '교자')]),
      omittedLineCount: 3,
    );

    expect(find.text('글자가 많아 아래쪽 3줄은 번역하지 않았어요. 나눠서 찍어 보세요.'), findsOneWidget);
  });

  testWidgets('번역이 원문과 같으면 원문을 다시 보여 주지 않는다', (tester) async {
    await pumpList(
      tester,
      _result([const TranslatedLine(original: '라멘', translated: '라멘')]),
    );

    expect(find.text('라멘'), findsOneWidget);
  });

  testWidgets('줄을 길게 누르면 번역을 복사한다', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpList(
      tester,
      _result([const TranslatedLine(original: '餃子', translated: '교자')]),
    );

    await tester.longPress(find.text('교자'));
    await tester.pump();

    expect(copied, '교자');
    expect(find.text('번역을 복사했어요'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('폭 320, 큰 글자, 긴 문구에서 넘치지 않는다 (다크 $dark)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final longTranslation = '특제 돈코츠 간장 라멘 곱빼기와 반숙 달걀, 차슈 세 장 추가' * 2;
      final longOriginal = '特製とんこつ醤油ラーメン大盛り味玉チャーシュー三枚追加' * 2;

      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TranslationLineList(
                result: _result([
                  TranslatedLine(
                    original: longOriginal,
                    translated: longTranslation,
                    pronunciation: '토쿠세이 톤코츠 쇼유 라멘 오오모리 아지타마 차슈 산마이 츠이카',
                    price: _yen(
                      text: '12,345,678円',
                      amount: 12345678,
                      krwAmount: 114135000,
                      stale: true,
                    ),
                  ),
                  TranslatedLine(
                    original: '大盛り',
                    translated: '곱빼기',
                    price: _yen(text: '150円', amount: 150, krwAmount: null),
                  ),
                ]),
                imagePath: 'missing.jpg',
                omittedLineCount: 12,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('약 114,135,000원'), findsOneWidget);
    });
  }
}
