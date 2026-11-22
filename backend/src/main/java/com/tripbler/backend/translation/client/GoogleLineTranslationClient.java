package com.tripbler.backend.translation.client;

import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.tripbler.backend.translation.dto.GoogleTranslationResponse;

/**
 * 찍기 모드 줄별 번역의 대체 경로. Claude를 쓸 수 없을 때(키·크레딧 없음, 장애, 거절) Google 번역으로
 * 줄마다 번역만 만든다. 한글 발음은 만들지 않는다(모두 null).
 */
@Component
public class GoogleLineTranslationClient implements LineTranslationClient {

    private final GoogleTranslationClient googleClient;

    public GoogleLineTranslationClient(GoogleTranslationClient googleClient) {
        this.googleClient = googleClient;
    }

    @Override
    public Result translate(List<String> lines, String sourceLanguageCode, String targetLanguageCode) {
        List<GoogleTranslationResponse.Translation> translations =
            googleClient.translateAll(lines, sourceLanguageCode, targetLanguageCode);

        List<Line> translatedLines = translations.stream()
            .map(translation -> new Line(translation.translatedText(), null))
            .toList();

        return new Result(mostCommonDetectedLanguage(translations), translatedLines);
    }

    /** 줄마다 감지한 언어 중 가장 많은 것. 한 줄도 없으면 null. 같은 수면 앞 줄의 언어. */
    private static String mostCommonDetectedLanguage(List<GoogleTranslationResponse.Translation> translations) {
        Map<String, Integer> counts = new HashMap<>();
        String best = null;
        int bestCount = 0;

        for (GoogleTranslationResponse.Translation translation : translations) {
            String code = translation.detectedSourceLanguage();

            if (code == null || code.isBlank()) {
                continue;
            }

            // Google은 zh-CN처럼 지역을 붙이기도 한다. 응답 계약은 언어 코드만 쓰므로 앞부분만 남긴다.
            String language = code.split("-", 2)[0].toLowerCase(Locale.ROOT);
            int count = counts.merge(language, 1, Integer::sum);

            if (count > bestCount) {
                best = language;
                bestCount = count;
            }
        }

        return best;
    }
}
