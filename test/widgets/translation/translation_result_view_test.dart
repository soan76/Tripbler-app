import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/models/translation/line_translation_result.dart';
import 'package:tripbler/providers/translation_provider.dart';
import 'package:tripbler/widgets/translation/translation_line_list.dart';
import 'package:tripbler/widgets/translation/translation_result_view.dart';

const _slideHint = '좌우로 밀어서 원문과 번역 결과를 확인하세요.';

void main() {
  Future<void> pumpView(
    WidgetTester tester, {
    LineTranslationResult? lineResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TranslationResultView(
            status: TranslationStatus.completed,
            selectedImagePath: null,
            errorMessage: null,
            recognizedText: '醤油ラーメン',
            translatedText: '간장 라멘',
            lineResult: lineResult,
            isProcessing: false,
            sourceLanguageCode: 'auto',
            targetLanguageCode: 'ko',
            languages: const TranslationState().languages,
            onSourceLanguageChanged: (_) {},
            onTargetLanguageChanged: (_) {},
            onSwapLanguages: () {},
            onRetake: () async {},
            onPickFromGallery: () async {},
          ),
        ),
      ),
    );
  }

  testWidgets('줄별 결과가 없으면 원문·번역 넘겨 보기를 보여 준다', (tester) async {
    await pumpView(tester);

    expect(find.text(_slideHint), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(TranslationLineList), findsNothing);
  });

  testWidgets('줄별 결과를 받으면 넘겨 보기 대신 줄 목록을 보여 준다', (tester) async {
    await pumpView(
      tester,
      lineResult: const LineTranslationResult(
        sourceLanguageCode: 'ja',
        targetLanguageCode: 'ko',
        lines: [
          TranslatedLine(
            original: '醤油ラーメン',
            translated: '간장 라멘',
            pronunciation: '쇼유 라멘',
          ),
        ],
      ),
    );

    expect(find.byType(TranslationLineList), findsOneWidget);
    expect(find.text('1줄을 번역했어요'), findsOneWidget);
    expect(find.text('쇼유 라멘'), findsOneWidget);
    expect(find.text(_slideHint), findsNothing);
    expect(find.byType(PageView), findsNothing);
  });
}
