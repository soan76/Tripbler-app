/// 찍기 모드 줄별 번역 응답(`POST /api/v1/translation/lines`).
///
/// 계약은 `backend/docs/translation-lines-api.md`. 줄 순서와 개수는 요청과 같다.
class LineTranslationResult {
  const LineTranslationResult({
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.lines,
  });

  /// 요청이 `auto`면 서버가 감지한 언어(모르면 `auto`).
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final List<TranslatedLine> lines;

  /// 발음이 있는 줄이 하나라도 있는지. 서버가 Google 대체 경로로 번역했으면 모두 없다.
  bool get hasPronunciation => lines.any((line) => line.pronunciation != null);

  /// 원화로 바꾼 가격을 통화마다 하나씩(그 통화의 첫 가격), 줄에 나온 순서대로.
  /// 화면 위쪽에 통화별 환율·시각을 한 줄씩 보여 줄 때 쓴다.
  List<LinePrice> get firstConvertedPricePerCurrency {
    final seen = <String>{};

    return [
      for (final line in lines)
        if (line.price case final price?
            when price.krwAmount != null && seen.add(price.currency))
          price,
    ];
  }

  /// 형식이 맞지 않으면 [FormatException]을 던진다.
  factory LineTranslationResult.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];

    if (rawLines is! List) {
      throw const FormatException('lines가 목록이 아닙니다.');
    }

    return LineTranslationResult(
      sourceLanguageCode: _requiredString(json, 'sourceLanguageCode'),
      targetLanguageCode: _requiredString(json, 'targetLanguageCode'),
      lines: List<TranslatedLine>.unmodifiable(
        rawLines.map((raw) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('줄 항목이 객체가 아닙니다.');
          }

          return TranslatedLine.fromJson(raw);
        }),
      ),
    );
  }
}

class TranslatedLine {
  const TranslatedLine({
    required this.original,
    required this.translated,
    this.pronunciation,
    this.price,
  });

  final String original;
  final String translated;

  /// 원문을 소리 나는 대로 적은 한글(참고용). 없으면 null.
  final String? pronunciation;

  /// 줄에서 찾은 가격 하나. 없으면 null.
  final LinePrice? price;

  factory TranslatedLine.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];

    if (rawPrice != null && rawPrice is! Map<String, dynamic>) {
      throw const FormatException('price가 객체가 아닙니다.');
    }

    return TranslatedLine(
      original: _requiredString(json, 'original'),
      translated: _requiredString(json, 'translated'),
      pronunciation: _optionalNonBlankString(json, 'pronunciation'),
      price: rawPrice == null
          ? null
          : LinePrice.fromJson(rawPrice as Map<String, dynamic>),
    );
  }
}

class LinePrice {
  const LinePrice({
    required this.text,
    required this.amount,
    required this.currency,
    this.krwAmount,
    this.krwRate,
    this.rateFetchedAt,
    this.rateStale = false,
  });

  /// 원문에 적힌 가격 그대로(예: `980円`).
  final String text;
  final num amount;

  /// 통화 코드(예: JPY).
  final String currency;

  /// 원화로 바꾼 금액(원 단위). 원화 가격이거나 환율을 받지 못했으면 null.
  final num? krwAmount;

  /// 1 [currency]당 원화.
  final num? krwRate;

  /// 환율을 받아 온 시각. 서버는 시간대 없이 보내므로 환율 화면(`ExchangeRateResponse.fetchedAt`)과
  /// 같이 기기 시각으로 읽고, 보여 줄 때 `toLocal()`을 쓴다(서버가 오프셋을 붙이면 그대로 맞게 바뀐다).
  final DateTime? rateFetchedAt;

  /// 환율 제공자 장애로 마지막 성공 환율을 썼으면 true.
  final bool rateStale;

  factory LinePrice.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];

    if (amount is! num) {
      throw const FormatException('amount가 숫자가 아닙니다.');
    }

    final krwAmount = json['krwAmount'];
    final krwRate = json['krwRate'];
    final fetchedAt = json['rateFetchedAt'];
    final stale = json['rateStale'];

    return LinePrice(
      text: _requiredString(json, 'text'),
      amount: amount,
      currency: _requiredString(json, 'currency'),
      krwAmount: krwAmount is num ? krwAmount : null,
      krwRate: krwRate is num ? krwRate : null,
      rateFetchedAt: fetchedAt is String
          ? DateTime.tryParse(fetchedAt.trim())
          : null,
      rateStale: stale == true,
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

String? _optionalNonBlankString(Map<String, dynamic> json, String key) {
  final value = json[key];

  if (value is String && value.trim().isNotEmpty) {
    return value;
  }

  return null;
}
