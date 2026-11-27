import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/line_request_limits.dart';
import 'package:tripbler/domain/translation/photo_paragraphs.dart';
import 'package:tripbler/domain/translation/photo_text_translation.dart';
import 'package:tripbler/models/translation/line_translation_result.dart';
import 'package:tripbler/models/translation/photo_translation_result.dart';

// 기본 방식(사진 안 보냄): 기기 OCR 문단의 글자만 번역해 문단 ID에 붙인다.
void main() {
  OcrParagraph paragraph(String id, String text) => OcrParagraph(
    id: id,
    text: text,
    box: const Rect.fromLTWH(0, 0, 10, 10),
    lineCount: 1,
  );

  LineTranslationResult lineResult(List<String> lines) => LineTranslationResult(
    sourceLanguageCode: 'ja',
    targetLanguageCode: 'ko',
    lines: [
      for (final line in lines)
        TranslatedLine(original: line, translated: 'ko:$line'),
    ],
  );

  Future<String> noText(String _) =>
      throw StateError('로그인 상태에서는 통번역을 쓰지 않아야 한다');
  Future<LineTranslationResult> noLines(List<String> _) =>
      throw StateError('로그아웃 상태에서는 줄별 번역을 쓰지 않아야 한다');

  test(
    'signedIn_sendsEachParagraphAsOneLine_andAttachesPronunciationAndPrice',
    () async {
      List<String>? sent;
      final result = await translateParagraphText(
        paragraphs: [paragraph('p1', '醤油\nラーメン'), paragraph('p2', '980円')],
        sourceLanguageCode: 'auto',
        targetLanguageCode: 'ko',
        signedIn: true,
        translateLines: (lines) async {
          sent = lines;
          return LineTranslationResult(
            sourceLanguageCode: 'ja',
            targetLanguageCode: 'ko',
            lines: [
              const TranslatedLine(
                original: '醤油 ラーメン',
                translated: '간장 라멘',
                pronunciation: '쇼유 라멘',
              ),
              TranslatedLine(
                original: '980円',
                translated: '980엔',
                price: LinePrice(
                  text: '980円',
                  amount: 980,
                  currency: 'JPY',
                  krwAmount: 9310,
                  krwRate: 9.5,
                  rateFetchedAt: DateTime(2026, 11, 27),
                  rateStale: true,
                ),
              ),
            ],
          );
        },
        translateText: noText,
      );

      // 문단 안 줄바꿈은 한 줄로 이어 보낸다.
      expect(sent, ['醤油 ラーメン', '980円']);
      expect(result.paragraphs.map((p) => p.id), ['p1', 'p2']);
      final first = result.paragraphs.first;
      expect(first.original, '醤油\nラーメン');
      expect(first.translated, '간장 라멘');
      expect(first.pronunciation, '쇼유 라멘');
      expect(first.source, PhotoTranslationSource.deviceText);
      expect(first.uncertain, isFalse);
      final price = result.paragraphs.last.prices.single;
      expect(price.confirmed, isTrue);
      expect(price.amount, 980);
      expect(price.currency, 'JPY');
      expect(price.krwAmount, 9310);
      expect(price.krwRate, 9.5);
      expect(price.rateStale, isTrue);
    },
  );

  test('signedIn_overLineLimit_leavesLaterParagraphsUntranslated', () async {
    final paragraphs = [
      for (var i = 0; i < LineRequestLimits.maxLines + 3; i++)
        paragraph('p$i', 'line $i'),
    ];
    List<String>? sent;
    final result = await translateParagraphText(
      paragraphs: paragraphs,
      sourceLanguageCode: 'ja',
      targetLanguageCode: 'ko',
      signedIn: true,
      translateLines: (lines) async {
        sent = lines;
        return lineResult(lines);
      },
      translateText: noText,
    );

    expect(sent, hasLength(LineRequestLimits.maxLines));
    expect(result.paragraphs, hasLength(LineRequestLimits.maxLines));
    expect(result.paragraphs.last.id, 'p${LineRequestLimits.maxLines - 1}');
  });

  test('blankParagraph_isSkipped_withoutShiftingLaterIds', () async {
    final result = await translateParagraphText(
      paragraphs: [
        paragraph('p1', 'a'),
        paragraph('p2', ' \n '),
        paragraph('p3', 'c'),
      ],
      sourceLanguageCode: 'ja',
      targetLanguageCode: 'ko',
      signedIn: true,
      translateLines: (lines) async => lineResult(lines),
      translateText: noText,
    );

    expect(result.paragraphs.map((p) => (p.id, p.translated)), [
      ('p1', 'ko:a'),
      ('p3', 'ko:c'),
    ]);
  });

  test('signedIn_noSendableParagraph_doesNotCallServer', () async {
    final result = await translateParagraphText(
      paragraphs: [paragraph('p1', ' '), paragraph('p2', ' \n ')],
      sourceLanguageCode: 'ja',
      targetLanguageCode: 'ko',
      signedIn: true,
      translateLines: noLines,
      translateText: noText,
    );

    expect(result.paragraphs, isEmpty);
  });

  // 실제 줄별 번역 서비스는 줄 수가 다르면 ApiException을 던져 이 상황이 오지 않는다.
  // 콜백이 그 검사를 거치지 않았을 때를 위한 방어 분기만 확인한다.
  test(
    'signedIn_shortResponse_defensiveBranch_attachesOnlyReturnedLines',
    () async {
      final result = await translateParagraphText(
        paragraphs: [paragraph('p1', 'a'), paragraph('p2', 'b')],
        sourceLanguageCode: 'ja',
        targetLanguageCode: 'ko',
        signedIn: true,
        translateLines: (lines) async => lineResult(['a']),
        translateText: noText,
      );

      expect(result.paragraphs.map((p) => p.id), ['p1']);
    },
  );

  test('signedOut_translatesEachParagraph_inOrder_atMostFourAtOnce', () async {
    final pending = <String, Completer<String>>{};
    var running = 0, peak = 0;
    final future = translateParagraphText(
      paragraphs: [for (var i = 0; i < 6; i++) paragraph('p$i', 't$i')],
      sourceLanguageCode: 'ja',
      targetLanguageCode: 'ko',
      signedIn: false,
      translateLines: noLines,
      translateText: (text) {
        running++;
        if (running > peak) peak = running;
        final completer = Completer<String>();
        pending[text] = completer;
        return completer.future.whenComplete(() => running--);
      },
    );

    // 늦게 시작한 문단부터 끝나도 결과는 문단 순서를 따른다.
    for (var round = 0; round < 6; round++) {
      await pumpEventQueue();
      final key = pending.keys.last;
      pending.remove(key)!.complete('ko:$key');
    }
    final result = await future;

    expect(peak, 4);
    expect(result.paragraphs.map((p) => (p.id, p.translated)), [
      for (var i = 0; i < 6; i++) ('p$i', 'ko:t$i'),
    ]);
    expect(result.paragraphs.every((p) => p.pronunciation == null), isTrue);
    expect(result.paragraphs.every((p) => p.prices.isEmpty), isTrue);
  });

  test('signedOut_oneParagraphFails_throwsAtOnce_andStopsSending', () async {
    final pending = <String, Completer<String>>{};
    final future = translateParagraphText(
      paragraphs: [for (var i = 0; i < 6; i++) paragraph('p$i', 't$i')],
      sourceLanguageCode: 'ja',
      targetLanguageCode: 'ko',
      signedIn: false,
      translateLines: noLines,
      translateText: (text) {
        final completer = Completer<String>();
        pending[text] = completer;
        return completer.future;
      },
    );
    Object? thrown;
    var settled = false;
    unawaited(
      future.then<void>(
        (_) => settled = true,
        onError: (Object error) {
          thrown = error;
          settled = true;
        },
      ),
    );

    await pumpEventQueue();
    pending['t0']!.completeError(StateError('실패'));
    await pumpEventQueue();

    // 진행 중인 다른 문단을 기다리지 않고 바로 실패한다.
    expect(settled, isTrue);
    expect(thrown, isA<StateError>());

    // 남은 요청이 끝나도 새 문단을 보내지 않는다.
    for (final key in ['t1', 't2', 't3']) {
      pending[key]!.complete('ko:$key');
    }
    await pumpEventQueue();
    expect(pending.keys, ['t0', 't1', 't2', 't3']);
  });

  test('signedOut_noSendableParagraph_doesNotCallServer', () async {
    final result = await translateParagraphText(
      paragraphs: [paragraph('p1', ' ')],
      sourceLanguageCode: 'ja',
      targetLanguageCode: 'ko',
      signedIn: false,
      translateLines: noLines,
      translateText: noText,
    );

    expect(result.paragraphs, isEmpty);
  });
}
