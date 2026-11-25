import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';
import 'package:tripbler/widgets/translation/photo/paragraph_detail_sheet.dart';

// 문단 상세: 원문·번역·한글 발음·가격(원화)·표시 이유.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester,
    TranslatedParagraph paragraph, {
    Size size = const Size(400, 900),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: Scaffold(body: ParagraphDetailSheet(paragraph: paragraph)),
      ),
    );
  }

  const confirmedPrice = PhotoPrice(
    text: '980円',
    amount: 980,
    currency: 'JPY',
    confirmed: true,
    krwAmount: 8930,
    krwRate: 9.112,
  );

  testWidgets('원문·번역·한글 발음·확정 가격의 원화를 보여 준다', (tester) async {
    await pumpSheet(
      tester,
      const TranslatedParagraph(
        id: 'p1',
        original: 'ラーメン定食 980円',
        translated: '라멘 정식 980엔',
        uncertain: false,
        source: PhotoTranslationSource.ai,
        pronunciation: '라멘 테이쇼쿠',
        prices: [confirmedPrice],
      ),
    );

    expect(find.text('ラーメン定食 980円'), findsOneWidget);
    expect(find.text('라멘 정식 980엔'), findsOneWidget);
    expect(find.text('라멘 테이쇼쿠'), findsOneWidget);
    expect(find.textContaining('980円'), findsWidgets);
    expect(find.textContaining('8,930원'), findsOneWidget);
    expect(find.text(ParagraphDetailSheet.unconfirmedPriceLabel), findsNothing);
  });

  testWidgets('확인되지 않은 가격은 원문 가격만 보이고 원화는 없다', (tester) async {
    await pumpSheet(
      tester,
      const TranslatedParagraph(
        id: 'p1',
        original: '1,2OO円',
        translated: '1,2OO엔',
        uncertain: false,
        source: PhotoTranslationSource.ai,
        prices: [
          PhotoPrice(
            text: '1,2OO円',
            amount: null,
            currency: null,
            confirmed: false,
          ),
        ],
      ),
    );

    expect(
      find.text(ParagraphDetailSheet.unconfirmedPriceLabel),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'[0-9]원')), findsNothing);
  });

  testWidgets('확정했지만 환율이 없으면 원화 없이 가격만, 미확인 표시도 없다', (tester) async {
    await pumpSheet(
      tester,
      const TranslatedParagraph(
        id: 'p1',
        original: '12 EUR',
        translated: '12유로',
        uncertain: false,
        source: PhotoTranslationSource.ai,
        prices: [
          PhotoPrice(
            text: '12 EUR',
            amount: 12,
            currency: 'EUR',
            confirmed: true,
          ),
        ],
      ),
    );

    expect(find.text('12 EUR'), findsWidgets);
    expect(find.text(ParagraphDetailSheet.unconfirmedPriceLabel), findsNothing);
    expect(find.textContaining(RegExp(r'[0-9]원')), findsNothing);
  });

  testWidgets('불확실·대체 번역이면 이유를 한 줄로 알린다', (tester) async {
    await pumpSheet(
      tester,
      const TranslatedParagraph(
        id: 'p1',
        original: '毎週?曜休',
        translated: '매주 [읽을 수 없음] 휴무',
        uncertain: true,
        source: PhotoTranslationSource.ocrText,
      ),
    );

    expect(find.text(ParagraphDetailSheet.uncertainReason), findsOneWidget);
    expect(find.text(ParagraphDetailSheet.fallbackReason), findsOneWidget);
  });

  testWidgets('작은 화면·글자 배율 2·긴 글에서도 넘치지 않는다', (tester) async {
    await pumpSheet(
      tester,
      TranslatedParagraph(
        id: 'p1',
        original: '長い原文' * 40,
        translated: '아주 긴 번역 문장 ' * 40,
        uncertain: true,
        source: PhotoTranslationSource.ocrText,
        pronunciation: '나가이 겐분' * 10,
        prices: const [confirmedPrice],
      ),
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('다크 모드·작은 화면에서 확인되지 않은 가격도 넘치지 않는다', (tester) async {
    await pumpSheet(
      tester,
      TranslatedParagraph(
        id: 'p1',
        original: '長い原文' * 20,
        translated: '아주 긴 번역 문장 ' * 20,
        uncertain: false,
        source: PhotoTranslationSource.ai,
        prices: const [
          PhotoPrice(
            text: '1,280,000,000円',
            amount: 1280000000,
            currency: 'JPY',
            confirmed: false,
          ),
        ],
      ),
      size: const Size(320, 568),
      textScale: 2,
      theme: AppTheme.darkTheme,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.text(ParagraphDetailSheet.unconfirmedPriceLabel),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'[0-9]원')), findsNothing);
  });
}
