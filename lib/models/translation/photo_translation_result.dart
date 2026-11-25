import 'package:flutter/foundation.dart' show immutable;

/// 사진 번역 응답(`POST /api/v1/translation/photo`)의 문단 번역 출처.
enum PhotoTranslationSource {
  /// AI가 사진을 보고 번역했다.
  ai,

  /// 사진은 못 쓰고 OCR 텍스트만으로 번역했다.
  ocrText,

  /// 원문과 번역 언어가 같아 서버에 보내지 않았다. 앱에서만 쓰며 서버 값이 아니다.
  original;

  /// 서버 값(`AI`·`OCR_TEXT`)만 받는다. 그 밖의 값은 [FormatException]이다.
  static PhotoTranslationSource fromServer(Object? value) {
    return switch (value) {
      'AI' => PhotoTranslationSource.ai,
      'OCR_TEXT' => PhotoTranslationSource.ocrText,
      _ => throw const FormatException('translationSource 값이 올바르지 않습니다.'),
    };
  }
}

@immutable
class PhotoPrice {
  const PhotoPrice({
    required this.text,
    required this.amount,
    required this.currency,
    required this.confirmed,
    this.krwAmount,
    this.krwRate,
    this.rateFetchedAt,
    this.rateStale = false,
  });

  /// 원문에 적힌 가격 그대로(예: `980円`).
  final String text;

  /// 확정하지 못한 가격이면 null.
  final double? amount;
  final String? currency;

  /// 금액과 통화를 서버가 확정했는지. 아니면 환산값이 없다.
  final bool confirmed;

  /// 원화로 바꾼 금액. 확정하지 못했거나 환율이 없으면 null.
  final double? krwAmount;

  /// 1 [currency]당 원화.
  final double? krwRate;

  /// 환율을 받아 온 시각. 서버는 시간대 없이 보내므로 기기 시각으로 읽는다.
  final DateTime? rateFetchedAt;

  /// 환율 제공자 장애로 마지막 성공 환율을 썼으면 true.
  final bool rateStale;

  factory PhotoPrice.fromJson(Map<String, dynamic> json) {
    final fetchedAt = json['rateFetchedAt'];
    final currency = json['currency'];

    return PhotoPrice(
      text: _requiredString(json, 'text'),
      amount: _optionalDouble(json['amount']),
      currency: currency is String ? currency : null,
      confirmed: json['confirmed'] == true,
      krwAmount: _optionalDouble(json['krwAmount']),
      krwRate: _optionalDouble(json['krwRate']),
      rateFetchedAt: fetchedAt is String
          ? DateTime.tryParse(fetchedAt.trim())
          : null,
      rateStale: json['rateStale'] == true,
    );
  }
}

@immutable
class TranslatedParagraph {
  const TranslatedParagraph({
    required this.id,
    required this.original,
    required this.translated,
    required this.uncertain,
    required this.source,
    this.pronunciation,
    this.prices = const <PhotoPrice>[],
  });

  final String id;
  final String original;
  final String translated;

  /// 읽기·번역이 불확실한 문단.
  final bool uncertain;
  final PhotoTranslationSource source;

  /// 원문을 소리 나는 대로 적은 한글(참고용). 없으면 null.
  final String? pronunciation;
  final List<PhotoPrice> prices;

  factory TranslatedParagraph.fromJson(Map<String, dynamic> json) {
    final rawPrices = json['prices'];

    if (rawPrices != null && rawPrices is! List) {
      throw const FormatException('prices가 목록이 아닙니다.');
    }

    final pronunciation = json['pronunciation'];

    return TranslatedParagraph(
      id: _requiredString(json, 'id'),
      original: _requiredString(json, 'original'),
      translated: _requiredString(json, 'translated'),
      uncertain: json['uncertain'] == true,
      source: PhotoTranslationSource.fromServer(json['translationSource']),
      pronunciation: pronunciation is String && pronunciation.trim().isNotEmpty
          ? pronunciation
          : null,
      prices: List<PhotoPrice>.unmodifiable(
        (rawPrices as List? ?? const []).map((raw) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('가격 항목이 객체가 아닙니다.');
          }

          return PhotoPrice.fromJson(raw);
        }),
      ),
    );
  }
}

/// 사진 번역 응답. 응답에 없는 문단은 결과에서도 빠진다(호출부가 원문을 그대로 둔다).
@immutable
class PhotoTranslationResult {
  const PhotoTranslationResult({
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.paragraphs,
  });

  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslatedParagraph> paragraphs;

  /// 요청에 없는 ID는 버리고, 같은 ID가 다시 나오면 처음 것만 쓴다.
  /// 형식이 맞지 않으면 [FormatException]을 던진다.
  static PhotoTranslationResult fromJson(
    Map<String, dynamic> json, {
    required Set<String> requestedIds,
  }) {
    final rawParagraphs = json['paragraphs'];

    if (rawParagraphs is! List) {
      throw const FormatException('paragraphs가 목록이 아닙니다.');
    }

    final seen = <String>{};
    final paragraphs = <TranslatedParagraph>[];

    for (final raw in rawParagraphs) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('문단 항목이 객체가 아닙니다.');
      }

      final paragraph = TranslatedParagraph.fromJson(raw);

      if (requestedIds.contains(paragraph.id) && seen.add(paragraph.id)) {
        paragraphs.add(paragraph);
      }
    }

    return PhotoTranslationResult(
      sourceLanguageCode: _requiredString(json, 'sourceLanguageCode'),
      targetLanguageCode: _requiredString(json, 'targetLanguageCode'),
      paragraphs: List<TranslatedParagraph>.unmodifiable(paragraphs),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];

  if (value is! String) {
    throw FormatException('$key가 문자열이 아닙니다.');
  }

  return value;
}

double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;
