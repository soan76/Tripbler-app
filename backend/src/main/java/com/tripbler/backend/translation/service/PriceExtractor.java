package com.tripbler.backend.translation.service;

import java.math.BigDecimal;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.stereotype.Component;

/**
 * 한 줄에서 가격 조각을 찾는다(예: "980円", "￥450", "+150円", "$12.50", "1,080엔").
 * 줄마다 처음 찾은 가격 하나만 쓴다. 통화를 정할 수 없거나 금액이 0이거나 할인 표시(앞에 빼기)면
 * 가격으로 보지 않고 다음 후보를 본다.
 */
@Component
public class PriceExtractor {

    // 숫자: 1,080 / 12.50 / 980. 천 단위 쉼표는 세 자리씩만 허용한다.
    // 앞뒤 경계: 숫자·점·쉼표 바로 뒤에서 시작하지 않고("12.345円"의 "345", "1,2345円"의 "2345" 방지),
    // 숫자나 "점·쉼표+숫자" 바로 앞에서 끝나지 않는다("$12.505"의 "$12" 방지).
    private static final String NUMBER =
        "(?<![\\d.,])(\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.(\\d{1,2}))?(?![\\d]|[.,]\\d)";

    // 앞 기호: ¥ ￥ $ € £ ₩ ฿ ₫
    private static final Pattern PREFIX = Pattern.compile(
        "([+＋]?)\\s*([¥￥$€£₩฿₫])\\s*" + NUMBER
    );

    // 뒤 단위: 円 엔 元 块 圆 원 บาท 바트 ₫, 또는 영문 코드. "1동"처럼 가격이 아닌 글자와 겹치는 "동"·"đ"는 넣지 않는다.
    // 영문 코드는 뒤에 영문자가 이어지면 단위가 아니다("5 EURO", "3THBx").
    // "块"은 조각을 세는 말이기도 해서("3块肉" 고기 세 조각) 뒤에 한자가 이어지면 단위로 보지 않는다.
    // 단 "10块钱"(10위안)처럼 "钱"이 이어지면 돈이다.
    private static final Pattern SUFFIX = Pattern.compile(
        "([+＋]?)\\s*" + NUMBER
            + "\\s*(円|엔|元|块(?![\\p{IsHan}&&[^钱錢]])|圆|원|บาท|바트|₫"
            + "|(?:JPY|CNY|USD|EUR|GBP|THB|VND|KRW)(?![A-Za-z]))",
        Pattern.CASE_INSENSITIVE
    );

    // 할인 표시로 보는 빼기 기호. 가타카나 장음 "ー"는 "コーヒー500円"처럼 가격 바로 앞에 흔히 와서 넣지 않는다.
    private static final String MINUS_SIGNS = "-−－";

    /**
     * @param start 줄에서 가격 조각이 시작하는 위치(먼저 나온 가격을 고를 때 쓴다).
     */
    public record Found(String text, BigDecimal amount, String currency, int start) {
    }

    /**
     * @param languageCode 원문 언어(¥ 기호를 엔/위안으로 가를 때 쓴다). auto나 null이면 엔으로 본다.
     */
    public Optional<Found> find(String line, String languageCode) {
        if (line == null || line.isBlank()) {
            return Optional.empty();
        }

        Found prefix = firstValid(line, PREFIX.matcher(line), true, languageCode);
        Found suffix = firstValid(line, SUFFIX.matcher(line), false, languageCode);

        if (prefix == null) {
            return Optional.ofNullable(suffix);
        }

        if (suffix == null) {
            return Optional.of(prefix);
        }

        // 둘 다 있으면 줄에서 먼저 나온 것을 쓴다.
        return Optional.of(prefix.start() <= suffix.start() ? prefix : suffix);
    }

    // 유효한 가격이 나올 때까지 다음 후보를 본다(예: "0円 ... 500円"이면 500円).
    private static Found firstValid(String line, Matcher matcher, boolean prefixForm, String languageCode) {
        while (matcher.find()) {
            Found found = toFound(line, matcher, prefixForm, languageCode);

            if (found != null) {
                return found;
            }
        }

        return null;
    }

    private static Found toFound(String line, Matcher matcher, boolean prefixForm, String languageCode) {
        String sign = matcher.group(1);
        String integerPart = prefixForm ? matcher.group(3) : matcher.group(2);
        String fractionPart = prefixForm ? matcher.group(4) : matcher.group(3);
        String unit = prefixForm ? matcher.group(2) : matcher.group(4);

        // 앞 공백을 빼고 부호(있으면) 또는 기호·숫자부터 센다.
        int start = sign.isEmpty() ? matcher.start(2) : matcher.start(1);

        if (sign.isEmpty() && isMinusBefore(line, start)) {
            return null;
        }

        String currency = currencyOf(unit, languageCode);

        if (currency == null) {
            return null;
        }

        BigDecimal amount = new BigDecimal(
            integerPart.replace(",", "") + (fractionPart == null ? "" : "." + fractionPart)
        );

        if (amount.signum() <= 0) {
            return null;
        }

        return new Found(line.substring(start, matcher.end()), amount, currency, start);
    }

    // 가격 바로 앞(공백 건너뜀)에 빼기 기호가 있으면 할인 표시로 본다("-100円", "− 100円").
    // "500-1000円"처럼 빼기 앞이 숫자면 범위 표시라 빼기로 보지 않는다.
    private static boolean isMinusBefore(String line, int start) {
        int index = start - 1;

        while (index >= 0 && Character.isWhitespace(line.charAt(index))) {
            index--;
        }

        if (index < 0 || MINUS_SIGNS.indexOf(line.charAt(index)) < 0) {
            return false;
        }

        return index == 0 || !Character.isDigit(line.charAt(index - 1));
    }

    static String currencyOf(String unit, String languageCode) {
        String lower = unit.toLowerCase(Locale.ROOT);

        return switch (lower) {
            case "円", "엔", "jpy" -> "JPY";
            case "元", "块", "圆", "cny" -> "CNY";
            case "¥", "￥" -> "zh".equalsIgnoreCase(languageCode) ? "CNY" : "JPY";
            case "$", "usd" -> "USD";
            case "€", "eur" -> "EUR";
            case "£", "gbp" -> "GBP";
            case "₩", "원", "krw" -> "KRW";
            case "฿", "บาท", "바트", "thb" -> "THB";
            case "₫", "vnd" -> "VND";
            default -> null;
        };
    }
}
