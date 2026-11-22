package com.tripbler.backend.translation.service;

import java.math.BigDecimal;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 한국어 번역 글자 속 가격의 통화 단어를 원문에서 찾은 통화에 맞춘다.
 *
 * <p>번역기가 기호의 뜻을 잘못 고르는 경우가 있다. 예: 중국어 {@code 宫保鸡丁 ¥38}을 Google이 "38엔"으로 옮기지만
 * 가격은 위안(CNY)으로 환산되므로 화면의 번역 글자와 원화가 서로 맞지 않는다.
 *
 * <p>번역 글자에서 "숫자 + 통화 단어" 짝을 앞에서부터 찾아, 숫자 값이 원문 가격과 같은 <b>첫 번째 짝 하나만</b> 본다.
 * 그 단어가 원문 통화와 다를 때만 바꾸고, 맞으면 아무것도 바꾸지 않는다. 같은 숫자의 다른 가격(예: {@code ¥38 / $38}의
 * "38달러")은 건드리지 않기 위해서다. 바꾼 짝 바로 앞에 범위 기호로 이어진 "숫자 + 같은 틀린 단어"가 있으면
 * (예: "500엔~1000엔") 함께 바꾼다. 번역 언어가 한국어가 아니면 바꾸지 않는다.
 * 상태가 없어 {@link LineTranslationService}가 직접 만들어 쓴다.
 */
public class TranslatedCurrencyFixer {

    private static final Map<String, String> KOREAN_WORDS = Map.of(
        "JPY", "엔",
        "CNY", "위안",
        "USD", "달러",
        "EUR", "유로",
        "GBP", "파운드",
        "THB", "바트",
        "VND", "동",
        "KRW", "원"
    );

    /** "동"은 "3동안"·"2동네"처럼 일반 낱말과 겹쳐, 원문 통화가 동일 때만 통화 단어로 본다(다른 통화 단어로 바꾸지 않는다). */
    private static final String DONG = "동";

    /**
     * 숫자: 앞이 숫자이거나 "숫자+소수점/쉼표"이면 숫자의 중간이므로 시작으로 보지 않는다("380"의 "80", "3.8"의 "8",
     * "10,80"의 "80"). 천 단위 쉼표는 3자리 묶음이 맞을 때만 받는다("10,80"은 숫자로 읽지 않는다).
     */
    private static final String NUMBER = "(?<!\\d)(?<!\\d[.,])(\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?|\\d+(?:\\.\\d+)?)";

    /**
     * 통화 단어. "원"·"엔" 뒤에 오면 통화가 아닌 낱말이 되는 글자는 제외한다(조사 이·은·을·에·으로·입니다·짜리·대·어치 등은 허용).
     * <ul>
     *   <li>원: 원칙·원두·원산지·원래·원형·원본·원작·원조·원룸·원장·원자·원소·원리·원료·원문·원숭이·원앙·원예·원탁·원피스·원점·원년·원유·원망·원통·원판·원서·원고.
     *       "원인"(1000원인 메뉴)·"원주"(1000원 주고)·"원하"(1000원 하는)·"원가"(1000원가량)·"원정"(1000원정도)은 가격 표현과 겹쳐 넣지 않았다.</li>
     *   <li>엔: 엔진·엔터·엔딩·엔트리·엔드·엔젤·엔지니어·엔티티·엔간·엔조이·엔비. "엔화"는 통화라 허용한다.</li>
     *   <li>위안·달러·유로·파운드·바트는 숫자 바로 뒤에서 겹치는 흔한 낱말이 없어 제외 목록을 두지 않는다.</li>
     * </ul>
     */
    private static final String WORD = "(위안|달러|유로|파운드|바트|" + DONG
        + "|엔(?!진|터|딩|트|드|젤|지|티|간|조이|비)"
        + "|원(?!칙|두|산|래|형|본|작|조|룸|장|자|소|리|료|문|숭이|앙|예|탁|피스|점|년|유|망|통|판|서|고))";

    /** 번역 속 "숫자 + 선택 공백 하나 + 통화 단어" 짝. 그룹 1: 숫자, 3: 통화 단어. */
    private static final Pattern AMOUNT_WITH_WORD = Pattern.compile(NUMBER + "(\\s?)" + WORD);

    /** 바꾼 짝 바로 앞에서 범위 기호로 이어진 짝(예: "500엔~"). 그룹 3: 통화 단어. */
    private static final Pattern RANGE_START_BEFORE = Pattern.compile(
        NUMBER + "(\\s?)" + WORD + "\\s*[~\\-–〜～]\\s*\\z"
    );

    /** 바꾼 짝 바로 뒤에서 범위 기호로 이어진 짝(예: "~1000엔"). 영역 시작에 붙여(lookingAt) 쓴다. 그룹 3: 통화 단어. */
    private static final Pattern RANGE_END_AFTER = Pattern.compile(
        "\\s*[~\\-–〜～]\\s*" + NUMBER + "(\\s?)" + WORD
    );

    /**
     * @param translated     번역 글자
     * @param amount         원문에서 찾은 가격 값
     * @param currency       원문 가격의 통화 코드
     * @param targetLanguage 번역 언어 코드(소문자)
     * @return 통화 단어를 맞춘 번역 글자. 바꿀 것이 없거나 값이 빠졌으면 {@code translated} 그대로
     */
    public String fix(String translated, BigDecimal amount, String currency, String targetLanguage) {
        if (translated == null || amount == null || currency == null || !"ko".equals(targetLanguage)) {
            return translated;
        }

        String correctWord = KOREAN_WORDS.get(currency);

        if (correctWord == null) {
            return translated;
        }

        Matcher pair = AMOUNT_WITH_WORD.matcher(translated);

        while (pair.find()) {
            String word = pair.group(3);

            // 원문 통화가 동이 아니면 "동"은 통화 단어로 보지 않고 다음 짝을 본다.
            if (DONG.equals(word) && !DONG.equals(correctWord)) {
                continue;
            }

            if (new BigDecimal(pair.group(1).replace(",", "")).compareTo(amount) != 0) {
                continue;
            }

            if (word.equals(correctWord)) {
                return translated;
            }

            StringBuilder fixed = new StringBuilder(translated);

            // 범위의 앞쪽 숫자가 원문 가격이면(예: 500円〜1000円은 앞의 500을 고른다) 뒤쪽 끝도 같은 틀린 단어일 때 함께 바꾼다.
            // 위치는 모두 원래 글자 기준이므로 뒤에서부터 바꾼다(뒤쪽 끝 → 이 짝 → 앞쪽 시작).
            Matcher rangeEnd = RANGE_END_AFTER.matcher(translated).region(pair.end(), translated.length());

            if (rangeEnd.lookingAt() && rangeEnd.group(3).equals(word)) {
                fixed.replace(rangeEnd.start(3), rangeEnd.end(3), correctWord);
            }

            fixed.replace(pair.start(3), pair.end(3), correctWord);

            // 뒤쪽을 먼저 바꿨으므로 앞쪽 범위 시작의 위치는 그대로다.
            Matcher rangeStart = RANGE_START_BEFORE.matcher(translated.substring(0, pair.start()));

            if (rangeStart.find() && rangeStart.group(3).equals(word)) {
                fixed.replace(rangeStart.start(3), rangeStart.end(3), correctWord);
            }

            return fixed.toString();
        }

        return translated;
    }
}
