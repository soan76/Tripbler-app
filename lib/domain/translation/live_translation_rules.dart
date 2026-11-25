import 'dart:collection';

// 실시간 번역의 언어 판단·번역 캐시 규칙(순수 계산).
// 실시간 번역은 제거됐고, 새 번역 흐름에서 쓸지 정하기 전까지 남겨 둔다. 지금 앱에서 부르는 곳은 없다.

/// 실시간 번역이 지원하는 원문 언어. 번역 언어는 한국어 하나다.
enum LiveLanguage {
  japanese('ja', '일본어'),
  chinese('zh', '중국어'),
  english('en', '영어');

  const LiveLanguage(this.code, this.label);

  /// BCP-47 언어 코드(ML Kit 번역 모델 이름과 같다).
  final String code;

  /// 화면 이름.
  final String label;
}

/// 번역 언어(한국어) 코드.
const String liveTargetLanguageCode = 'ko';

/// 언어 감지 결과 하나(ML Kit 언어 식별 결과를 옮긴 값).
typedef LiveLanguageGuess = ({String tag, double confidence});

/// 언어 감지를 믿을 최소 신뢰도. 이보다 낮으면 사용자에게 언어를 고르게 한다.
const double liveLanguageMinConfidence = 0.5;

/// 가나 우선 규칙의 추가 조건: 유효 글자(글자·숫자, 공백·문장부호·기호 제외) 중 한자·가나 비율의 하한과
/// 가나 글자 수의 하한. 일본어 인식기가 영어의 로마자 몇 글자를 가나로 잘못 읽으면 한자·가나 중 가나 비율은
/// 높게 나오지만(실기기 진단 0.47), 전체 글자 중 한자·가나는 아주 적다.
const double liveKanaRuleMinCjkShare = 0.3;
const int liveKanaRuleMinKana = 3;

/// 유효 글자 중 로마자가 이 비율 이상이면 일본어·중국어 판단을 바로 쓰지 않는다(보류).
const double liveLatinDominantShare = 0.7;

/// 언어 판단 결과. [deferred]가 true면 글자 구성(로마자 우세)과 판단(일본어·중국어)이 맞지 않아 이 관측을
/// 확정에 쓰지 않는다([language]는 null).
typedef LiveLanguageJudgement = ({LiveLanguage? language, bool deferred});

/// 인식한 [text]와 감지 결과 [guesses]로 원문 언어를 정한다. 정할 수 없으면 null(사용자 선택 요청).
/// 글자 구성과 맞지 않는 판단도 null이다([judgeLiveLanguage]로 구분한다).
LiveLanguage? decideLiveLanguage(String text, List<LiveLanguageGuess> guesses) {
  return judgeLiveLanguage(text, guesses).language;
}

/// [decideLiveLanguage]의 판단과 보류 여부.
///
/// - 가나 우선: 가나(히라가나·가타카나)가 한자·가나 글자의 10% 이상이고, 유효 글자 중 한자·가나가
///   [liveKanaRuleMinCjkShare] 이상이고, 가나가 [liveKanaRuleMinKana]자 이상이면 일본어로 본다. 일본어 메뉴는
///   한자가 많아 언어 식별기가 중국어로 판단하기 쉬운데, 가나는 중국어에 쓰이지 않기 때문이다. 이 조건은 가나
///   규칙에만 쓰며, 만족하지 않아도 식별 결과가 일본어면 일본어로 볼 수 있다(한자만 있는 일본어 등).
/// - 그 밖에는 신뢰도가 가장 높은 결과가 지원 언어이고 [liveLanguageMinConfidence] 이상일 때만 쓴다.
///   중국어 로마자 표기(`zh-Latn`)는 중국어 글자가 아니므로 쓰지 않는다.
/// - 유효 글자 중 로마자가 [liveLatinDominantShare] 이상인데 판단이 일본어·중국어면 보류한다. 일본어 인식기가
///   영어 일부를 가나로 읽으면 식별기도 일본어(실기기 `ja 1.00`)를 돌려줄 수 있어, 다른 관측(영어 인식기로
///   읽은 결과 포함)으로 확인한다.
LiveLanguageJudgement judgeLiveLanguage(
  String text,
  List<LiveLanguageGuess> guesses,
) {
  final counts = liveScriptCounts(text);
  final latinDominant =
      counts.effective > 0 &&
      counts.latin / counts.effective >= liveLatinDominantShare;

  LiveLanguageJudgement judged(LiveLanguage? language) {
    if (latinDominant &&
        (language == LiveLanguage.japanese ||
            language == LiveLanguage.chinese)) {
      return (language: null, deferred: true);
    }
    return (language: language, deferred: false);
  }

  final cjk = counts.kana + counts.han;
  if (cjk > 0 &&
      counts.kana / cjk >= 0.1 &&
      cjk / counts.effective >= liveKanaRuleMinCjkShare &&
      counts.kana >= liveKanaRuleMinKana) {
    return judged(LiveLanguage.japanese);
  }
  return judged(_languageFromGuesses(guesses));
}

LiveLanguage? _languageFromGuesses(List<LiveLanguageGuess> guesses) {
  LiveLanguageGuess? best;
  for (final guess in guesses) {
    if (best == null || guess.confidence > best.confidence) {
      best = guess;
    }
  }
  if (best == null || best.confidence < liveLanguageMinConfidence) {
    return null;
  }

  final tag = best.tag.toLowerCase();
  if (tag == 'ja') {
    return LiveLanguage.japanese;
  }
  if (tag == 'en') {
    return LiveLanguage.english;
  }
  if (tag == 'zh' || (tag.startsWith('zh-') && tag != 'zh-latn')) {
    return LiveLanguage.chinese;
  }
  return null;
}

/// 언어 감지에 쓸 최소 글자 수(글자·숫자 기준). 이보다 적으면 관측으로 세지 않는다.
const int liveDetectionMinChars = 4;

/// 언어 감지 관측 결과.
typedef LiveVoteResult = ({
  /// 확정한 언어. 아직 정하지 못했으면 null.
  LiveLanguage? language,

  /// 관측이 [LiveLanguageVote.window]번 모였는데 서로 맞지 않는다(사용자 선택 필요).
  bool ambiguous,
});

/// 언어 감지를 여러 관측으로 확정한다. 흔들린 프레임 한 장으로 언어를 정하지 않는다.
///
/// 최근 [window]번의 관측 중 같은 언어가 [needed]번 나오면 확정한다. [window]번이 모였는데 확정하지 못하면
/// 모호하다고 알린다. 관측(언어를 정하지 못한 결과 null 포함)은 글자가 충분한 프레임만 넣는다.
class LiveLanguageVote {
  LiveLanguageVote({this.window = 3, this.needed = 2})
    : assert(needed <= window);

  final int window;
  final int needed;
  final List<LiveLanguage?> _recent = <LiveLanguage?>[];

  int get count => _recent.length;

  void reset() => _recent.clear();

  LiveVoteResult add(LiveLanguage? observed) {
    _recent.add(observed);
    if (_recent.length > window) {
      _recent.removeAt(0);
    }
    for (final language in LiveLanguage.values) {
      final hits = _recent.where((value) => value == language).length;
      if (hits >= needed) {
        return (language: language, ambiguous: false);
      }
    }
    return (language: null, ambiguous: _recent.length >= window);
  }
}

/// 글자가 없어 언어 감지가 [consecutiveEmpty]번 이어졌을 때 다음 감지까지 기다릴 시간.
///
/// 기본 인식 간격(400ms)에서 실패할 때마다 두 배로 늘리고 [liveDetectionMaxRetryDelay]에서 멈춘다
/// (1번 800ms, 2번 1.6초, 3번부터 2초). 글자가 없는 곳을 비추는 동안 배터리를 아낀다.
Duration liveDetectionRetryDelay(int consecutiveEmpty) {
  if (consecutiveEmpty <= 0) {
    return Duration.zero;
  }
  const base = 400;
  final shift = consecutiveEmpty > 8 ? 8 : consecutiveEmpty;
  final millis = base * (1 << shift);
  return millis >= liveDetectionMaxRetryDelay.inMilliseconds
      ? liveDetectionMaxRetryDelay
      : Duration(milliseconds: millis);
}

/// 글자가 없을 때 감지 간격의 상한.
const Duration liveDetectionMaxRetryDelay = Duration(seconds: 2);

/// [text]의 한자·가나 글자 중 가나(히라가나·가타카나) 비율. 한자·가나가 없으면 null.
double? liveKanaRatio(String text) {
  var kana = 0;
  var cjk = 0;
  for (final rune in text.runes) {
    final isKana = rune >= 0x3040 && rune <= 0x30FF;
    final isHan = rune >= 0x4E00 && rune <= 0x9FFF;
    if (isKana) {
      kana++;
    }
    if (isKana || isHan) {
      cjk++;
    }
  }
  return cjk == 0 ? null : kana / cjk;
}

final RegExp _effectiveCharPattern = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// [text]의 유효 글자(글자·숫자) 수와 그중 가나·한자·로마자 수. 공백·문장부호·기호는 세지 않는다.
/// 가나·한자 범위는 [liveKanaRatio]와 같다.
({int effective, int kana, int han, int latin}) liveScriptCounts(String text) {
  var effective = 0;
  var kana = 0;
  var han = 0;
  var latin = 0;
  for (final rune in text.runes) {
    if (!_effectiveCharPattern.hasMatch(String.fromCharCode(rune))) {
      continue;
    }
    effective++;
    if (rune >= 0x3040 && rune <= 0x30FF) {
      kana++;
    } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
      han++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xFF21 && rune <= 0xFF3A) ||
        (rune >= 0xFF41 && rune <= 0xFF5A) ||
        (rune >= 0xC0 && rune <= 0x24F)) {
      latin++;
    }
  }
  return (effective: effective, kana: kana, han: han, latin: latin);
}

/// 번역 캐시 키: 원문, 원문 언어, 번역 언어.
typedef LiveTranslationKey = ({String text, String source, String target});

/// 줄 번역 캐시. 값은 번역 글자만 둔다(위치는 늘 현재 프레임의 인식 결과에서 가져온다).
/// [capacity]를 넘으면 가장 오래 쓰지 않은 항목부터 지운다.
class LiveTranslationCache {
  LiveTranslationCache({this.capacity = 300});

  final int capacity;
  final LinkedHashMap<LiveTranslationKey, String> _entries =
      LinkedHashMap<LiveTranslationKey, String>();

  int get length => _entries.length;

  String? get(LiveTranslationKey key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  void put(LiveTranslationKey key, String translated) {
    _entries.remove(key);
    _entries[key] = translated;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}
