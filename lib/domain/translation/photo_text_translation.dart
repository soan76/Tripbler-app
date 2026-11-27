import '../../models/translation/line_translation_result.dart';
import '../../models/translation/photo_translation_result.dart';
import 'line_request_limits.dart';
import 'photo_paragraphs.dart';

/// 기기에서 읽은 문단의 글자만 번역해 문단 ID에 붙인다. 사진은 보내지 않는다.
///
/// - 로그인했으면 [translateLines](줄별 번역 API)에 문단마다 한 줄로 보내 번역·발음·가격을 받는다.
/// - 아니면 [translateText](통번역 API)로 문단마다 번역한다(동시에 [maxConcurrent]개까지).
///
/// 줄별 번역 API 제한(줄 수·줄 길이·합계)을 넘어 보내지 못한 문단은 결과에서 빠지고, 화면이
/// "번역하지 못한 문단"으로 알린다. 보낼 문단이 없으면 서버를 부르지 않고 빈 결과를 돌려준다.
///
/// 통번역 중 한 문단이라도 실패하면 새 요청을 더 보내지 않고, 진행 중인 요청을 기다리지 않고
/// 그 오류를 바로 던진다. 이미 나간 요청은 끝나도 결과를 쓰지 않는다.
Future<PhotoTranslationResult> translateParagraphText({
  required List<OcrParagraph> paragraphs,
  required String sourceLanguageCode,
  required String targetLanguageCode,
  required bool signedIn,
  required Future<LineTranslationResult> Function(List<String> lines)
  translateLines,
  required Future<String> Function(String text) translateText,
  int maxConcurrent = 4,
}) async {
  // 문단 안 줄바꿈은 한 줄로 이어 보낸다(줄별 API는 한 줄 단위). 빈 문단은 보내지 않는다
  // (linesForRequest가 빈 줄을 건너뛰어 순서가 어긋나지 않게 미리 뺀다).
  final sendable = <({OcrParagraph paragraph, String text})>[
    for (final paragraph in paragraphs)
      (
        paragraph: paragraph,
        text: paragraph.text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim(),
      ),
  ].where((item) => item.text.isNotEmpty).toList();
  final ordered = [for (final item in sendable) item.paragraph];
  final (selected, _) = linesForRequest([
    for (final item in sendable) item.text,
  ]);

  final translated = <TranslatedParagraph>[];
  if (selected.isEmpty) {
    // 줄별 번역 API는 1줄 이상을 요구한다. 보낼 글자가 없으면 부르지 않는다.
  } else if (signedIn) {
    final result = await translateLines(selected);
    // 방어 분기: 실제 줄별 번역 서비스는 줄 수가 요청과 다르면 ApiException을 던지므로
    // 응답이 더 짧은 경우는 오지 않는다. 콜백이 그 검사를 거치지 않을 때만 남는 문단을 뺀다.
    final count = result.lines.length < selected.length
        ? result.lines.length
        : selected.length;
    for (var i = 0; i < count; i++) {
      final line = result.lines[i];
      final price = line.price;
      translated.add(
        TranslatedParagraph(
          id: ordered[i].id,
          original: ordered[i].text,
          translated: line.translated,
          uncertain: false,
          source: PhotoTranslationSource.deviceText,
          pronunciation: line.pronunciation,
          prices: price == null ? const [] : [_toPhotoPrice(price)],
        ),
      );
    }
  } else {
    final results = List<String?>.filled(selected.length, null);
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (!failed && next < selected.length) {
        final index = next++;
        try {
          results[index] = await translateText(selected[index]);
        } catch (_) {
          failed = true;
          rethrow;
        }
      }
    }

    await Future.wait(eagerError: true, [
      for (var i = 0; i < maxConcurrent && i < selected.length; i++) worker(),
    ]);
    for (var i = 0; i < selected.length; i++) {
      translated.add(
        TranslatedParagraph(
          id: ordered[i].id,
          original: ordered[i].text,
          translated: results[i]!,
          uncertain: false,
          source: PhotoTranslationSource.deviceText,
        ),
      );
    }
  }

  return PhotoTranslationResult(
    sourceLanguageCode: sourceLanguageCode,
    targetLanguageCode: targetLanguageCode,
    paragraphs: List<TranslatedParagraph>.unmodifiable(translated),
  );
}

// 줄별 번역의 가격은 서버가 금액·통화를 확정한 값이다.
PhotoPrice _toPhotoPrice(LinePrice price) => PhotoPrice(
  text: price.text,
  amount: price.amount.toDouble(),
  currency: price.currency,
  confirmed: true,
  krwAmount: price.krwAmount?.toDouble(),
  krwRate: price.krwRate?.toDouble(),
  rateFetchedAt: price.rateFetchedAt,
  rateStale: price.rateStale,
);
