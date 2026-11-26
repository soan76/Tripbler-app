package com.tripbler.backend.translation.client;

import java.util.Locale;
import java.util.regex.Pattern;

/**
 * Claude 번역 클라이언트(줄별·사진)가 함께 쓰는 입력·출력 글자 검사.
 *
 * <p>모델 출력은 그대로 믿지 않는다. 제어 문자와 양방향 서식 문자를 정리하고, 길이 상한과 발음 문자를 검사한다.
 */
final class ClaudeOutputText {

    // 줄 안의 제어 문자(C0·C1)와 줄·문단 구분 문자. 입력에서는 다른 줄로 보이지 않게, 출력에서는 화면이
    // 깨지지 않게 공백으로 바꾼다.
    static final Pattern LINE_BREAKS = Pattern.compile("[\\p{Cc}\\p{Zl}\\p{Zp}]+");

    // 글자 순서를 화면에서 뒤바꿀 수 있는 양방향 서식 문자(ALM, LRM/RLM, LRE~RLO, LRI~PDI). 출력에서 지운다.
    private static final Pattern BIDI_CONTROLS =
        Pattern.compile("[\\u061C\\u200E\\u200F\\u202A-\\u202E\\u2066-\\u2069]");

    // 발음에 허용하는 문자: 한글, 숫자, 문장부호, 공백, 그리고 가격·수량에 흔한 + ~ %.
    private static final Pattern HANGUL_READING =
        Pattern.compile("[\\p{IsHangul}\\p{Nd}\\p{P}\\p{Zs}\\s+~%]+");

    // 번역·발음 길이 상한: max(200, 원문 길이 × 4). 자연스러운 번역은 이보다 훨씬 짧다.
    private static final int MIN_OUTPUT_LIMIT = 200;
    private static final int OUTPUT_LENGTH_FACTOR = 4;

    private ClaudeOutputText() {
    }

    /** 입력 글자 안의 줄바꿈·제어 문자·줄 구분 문자를 공백으로 바꾼다. */
    static String singleLine(String text) {
        return LINE_BREAKS.matcher(text).replaceAll(" ");
    }

    /** 제어 문자·줄 구분은 공백으로, 양방향 서식 문자는 지우고 앞뒤 공백을 없앤다. null은 빈 문자열이다. */
    static String clean(String text) {
        if (text == null) {
            return "";
        }

        return BIDI_CONTROLS.matcher(singleLine(text)).replaceAll("").trim();
    }

    /** 원문 길이에 맞춘 출력 길이 상한. */
    static int lengthLimit(int originalLength) {
        return Math.max(MIN_OUTPUT_LIMIT, originalLength * OUTPUT_LENGTH_FACTOR);
    }

    /** 정리한 발음이 비었거나, 너무 길거나, 한글 외 문자가 섞이면 null(발음은 참고용이라 버린다). */
    static String pronunciationOrNull(String cleanedPronunciation, int limit) {
        if (cleanedPronunciation.isEmpty()
            || cleanedPronunciation.length() > limit
            || !HANGUL_READING.matcher(cleanedPronunciation).matches()) {
            return null;
        }

        return cleanedPronunciation;
    }

    /** ISO 639 언어 코드(2~3자 소문자)로 정리한다. 코드가 아니면 null. */
    static String languageCodeOrNull(String detectedLanguage) {
        String detected = detectedLanguage == null ? "" : detectedLanguage.trim().toLowerCase(Locale.ROOT);

        return detected.matches("[a-z]{2,3}") ? detected : null;
    }
}
