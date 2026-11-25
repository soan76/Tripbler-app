import 'package:flutter_test/flutter_test.dart';
import 'package:tripbler/domain/translation/live_translation_rules.dart';

// 실시간 번역 규칙: 언어 감지 결정·투표, 번역 캐시 키, 감지 재시도 간격.
void main() {
  group('decideLiveLanguage', () {
    test('가나가 있으면 식별기가 중국어라고 해도 일본어', () {
      expect(
        decideLiveLanguage('醤油ラーメン', [(tag: 'zh', confidence: 0.9)]),
        LiveLanguage.japanese,
      );
    });

    test('로마자가 대부분인 글에 가나가 몇 글자 섞이면 가나 규칙으로 일본어라고 정하지 않는다', () {
      // 일본어 인식기가 영어 문제집의 로마자 일부를 가나로 읽었다(한자·가나 중 가나 비율은 높다).
      const misread = 'The documentary shows a small fishing boat ボート港';
      expect(liveKanaRatio(misread), greaterThan(0.1));
      expect(
        decideLiveLanguage(misread, [(tag: 'en', confidence: 0.9)]),
        LiveLanguage.english,
      );
    });

    test('로마자가 70% 이상인데 식별 결과가 일본어·중국어면 확정에 쓰지 않는다(보류)', () {
      const misread = 'The documentary shows a small fishing boat ボート';
      final judged = judgeLiveLanguage(misread, [(tag: 'ja', confidence: 1)]);
      expect(judged.language, isNull);
      expect(judged.deferred, isTrue);
      expect(decideLiveLanguage(misread, [(tag: 'ja', confidence: 1)]), isNull);
      expect(
        judgeLiveLanguage('Fishing boats leave early', [
          (tag: 'zh', confidence: 0.9),
        ]).deferred,
        isTrue,
      );
      // 영어 결과는 보류하지 않는다.
      expect(judgeLiveLanguage(misread, [(tag: 'en', confidence: 0.9)]), (
        language: LiveLanguage.english,
        deferred: false,
      ));
    });

    test('영어가 섞인 일본어 메뉴는 가나 3자 이상이고 한자·가나가 30% 이상이라 일본어로 본다', () {
      expect(
        decideLiveLanguage('ラーメン Ramen ¥980', [(tag: 'en', confidence: 0.9)]),
        LiveLanguage.japanese,
      );
      expect(
        decideLiveLanguage('ラーメン Ramen ¥980', [(tag: 'ja', confidence: 0.9)]),
        LiveLanguage.japanese,
      );
    });

    test('가나 조건은 일본어 전체의 필수 조건이 아니다: 한자만 있어도 식별 결과가 일본어면 일본어', () {
      expect(
        decideLiveLanguage('本日休業', [(tag: 'ja', confidence: 0.9)]),
        LiveLanguage.japanese,
      );
      // 가나가 3자 미만이면 가나 규칙은 쓰지 않고 식별 결과를 따른다.
      expect(
        decideLiveLanguage('醤油の味', [(tag: 'ja', confidence: 0.9)]),
        LiveLanguage.japanese,
      );
    });

    test('신뢰도가 기준 이상인 지원 언어면 그 언어, 낮거나 지원하지 않으면 null', () {
      expect(
        decideLiveLanguage('牛肉面', [(tag: 'zh', confidence: 0.8)]),
        LiveLanguage.chinese,
      );
      expect(
        decideLiveLanguage('Beef', [
          (tag: 'en', confidence: 0.7),
          (tag: 'de', confidence: 0.2),
        ]),
        LiveLanguage.english,
      );
      expect(decideLiveLanguage('OK', [(tag: 'en', confidence: 0.3)]), isNull);
      expect(
        decideLiveLanguage('Bonjour', [(tag: 'fr', confidence: 0.9)]),
        isNull,
      );
      expect(
        decideLiveLanguage('niu rou', [(tag: 'zh-Latn', confidence: 0.9)]),
        isNull,
      );
      expect(decideLiveLanguage('', const []), isNull);
    });
  });

  group('LiveTranslationCache', () {
    test('키는 (원문, 원문 언어, 번역 언어)이고 값은 번역 글자만 둔다', () {
      final cache = LiveTranslationCache();
      cache.put((text: 'ラーメン', source: 'ja', target: 'ko'), '라멘');

      expect(cache.get((text: 'ラーメン', source: 'ja', target: 'ko')), '라멘');
      expect(cache.get((text: 'ラーメン', source: 'zh', target: 'ko')), isNull);
      expect(cache.get((text: 'ラーメン ', source: 'ja', target: 'ko')), isNull);
    });

    test('용량을 넘으면 가장 오래 쓰지 않은 항목부터 지운다', () {
      final cache = LiveTranslationCache(capacity: 2);
      cache.put((text: 'a', source: 'ja', target: 'ko'), 'A');
      cache.put((text: 'b', source: 'ja', target: 'ko'), 'B');
      cache.get((text: 'a', source: 'ja', target: 'ko'));
      cache.put((text: 'c', source: 'ja', target: 'ko'), 'C');

      expect(cache.length, 2);
      expect(cache.get((text: 'b', source: 'ja', target: 'ko')), isNull);
      expect(cache.get((text: 'a', source: 'ja', target: 'ko')), 'A');
    });
  });

  test('liveDetectionRetryDelay: 글자 없음이 이어질수록 두 배로 늘고 2초에서 멈춘다', () {
    expect(liveDetectionRetryDelay(0), Duration.zero);
    expect(liveDetectionRetryDelay(1), const Duration(milliseconds: 800));
    expect(liveDetectionRetryDelay(2), const Duration(milliseconds: 1600));
    expect(liveDetectionRetryDelay(3), liveDetectionMaxRetryDelay);
    expect(liveDetectionRetryDelay(50), liveDetectionMaxRetryDelay);
  });

  group('LiveLanguageVote', () {
    test('세 번 중 같은 언어가 두 번 나오면 확정하고, 세 번 모두 다르면 모호하다', () {
      final vote = LiveLanguageVote();
      expect(vote.add(LiveLanguage.japanese).language, isNull);
      expect(vote.add(LiveLanguage.english).language, isNull);
      expect(vote.add(LiveLanguage.japanese).language, LiveLanguage.japanese);

      vote.reset();
      vote
        ..add(null)
        ..add(LiveLanguage.chinese);
      final result = vote.add(LiveLanguage.english);
      expect(result.language, isNull);
      expect(result.ambiguous, isTrue);
    });
  });
}
