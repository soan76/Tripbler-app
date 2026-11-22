package com.tripbler.backend.translation.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class TranslatedCurrencyFixerTest {

    private final TranslatedCurrencyFixer fixer = new TranslatedCurrencyFixer();

    private String fix(String translated, String amount, String currency) {
        return fixer.fix(translated, new BigDecimal(amount), currency, "ko");
    }

    @Test
    void 중국어_엔화_기호를_엔으로_옮긴_번역을_위안으로_바꾼다() {
        assertEquals("쿵파오 치킨 38위안", fix("쿵파오 치킨 38엔", "38", "CNY"));
    }

    @Test
    void 엔화_가격을_원으로_옮긴_번역을_엔으로_바꾼다() {
        assertEquals("간장 라멘 980엔", fix("간장 라멘 980원", "980", "JPY"));
    }

    @Test
    void 숫자와_단어_사이_공백과_천_단위_쉼표가_달라도_맞춘다() {
        assertEquals("된장 라멘 1080 엔", fix("된장 라멘 1080 원", "1080", "JPY"));
        assertEquals("세트 1,200위안", fix("세트 1,200엔", "1200", "CNY"));
    }

    @Test
    void 뒤에_조사가_붙어도_바꾼다() {
        assertEquals("38위안에 판매", fix("38엔에 판매", "38", "CNY"));
        assertEquals("1000엔이고 세트는 1200엔", fix("1000원이고 세트는 1200엔", "1000", "JPY"));
        assertEquals("980엔으로 할인", fix("980원으로 할인", "980", "JPY"));
        assertEquals("980엔입니다", fix("980원입니다", "980", "JPY"));
        assertEquals("1000엔짜리 쿠폰", fix("1000원짜리 쿠폰", "1000", "JPY"));
        assertEquals("38위안은 비싸다", fix("38엔은 비싸다", "38", "CNY"));
        assertEquals("38위안을 낸다", fix("38엔을 낸다", "38", "CNY"));
    }

    @Test
    void 이미_맞는_단어와_통화_단어가_없는_번역은_그대로_둔다() {
        assertEquals("간장 라멘 980엔", fix("간장 라멘 980엔", "980", "JPY"));
        assertEquals("쿵파오 치킨 ¥38", fix("쿵파오 치킨 ¥38", "38", "CNY"));
        assertEquals("세트 메뉴", fix("세트 메뉴", "38", "CNY"));
    }

    @Test
    void 숫자가_다르면_바꾸지_않는다() {
        // 380엔·138엔은 38과 다른 숫자다.
        assertEquals("380엔, 138엔", fix("380엔, 138엔", "38", "CNY"));
        assertEquals("3.8엔", fix("3.8엔", "38", "CNY"));
    }

    @Test
    void 같은_숫자의_다른_통화_가격은_건드리지_않는다() {
        // 원문 ¥38 / $38: 첫 짝 "38위안"이 이미 맞으므로 "38달러"는 그대로 둔다.
        assertEquals("38위안 / 38달러", fix("38위안 / 38달러", "38", "CNY"));
    }

    @Test
    void 같은_숫자가_두_번_나오면_첫_번째만_바꾼다() {
        assertEquals("38위안 세트, 38엔 추가", fix("38엔 세트, 38엔 추가", "38", "CNY"));
    }

    @Test
    void 통화_단어와_겹치는_낱말은_통화로_보지_않는다() {
        assertEquals("1원칙", fix("1원칙", "1", "CNY"));
        assertEquals("V8 8엔진", fix("V8 8엔진", "8", "CNY"));
        assertEquals("2엔터 키", fix("2엔터 키", "2", "CNY"));
        assertEquals("100원두", fix("100원두", "100", "JPY"));
        assertEquals("3원산지", fix("3원산지", "3", "JPY"));
        assertEquals("2원래", fix("2원래", "2", "JPY"));
    }

    @Test
    void 낱말과_겹친_짝은_건너뛰고_다음_짝을_본다() {
        assertEquals("1원칙: 1위안", fix("1원칙: 1엔", "1", "CNY"));
    }

    @Test
    void 동은_일반_낱말과_겹쳐_다른_통화로_바꾸지_않는다() {
        assertEquals("3동안 영업", fix("3동안 영업", "3", "JPY"));
        // 베트남 동 가격에서 다른 단어를 "동"으로 바꾸는 것은 한다.
        assertEquals("50000동", fix("50000원", "50000", "VND"));
    }

    @Test
    void 소수_가격도_맞춘다() {
        assertEquals("버거 9.99달러", fix("버거 9.99유로", "9.99", "USD"));
    }

    @Test
    void 소수_표기가_달라도_값이_같으면_맞춘다() {
        assertEquals("38.5위안", fix("38.5엔", "38.50", "CNY"));
        assertEquals("38.50위안", fix("38.50엔", "38.5", "CNY"));
    }

    @Test
    void 소수_쉼표_표기는_천_단위_숫자로_보지_않는다() {
        // "10,80"은 3자리 묶음이 아니라 1080이 아니다.
        assertEquals("10,80엔", fix("10,80엔", "1080", "CNY"));
    }

    @Test
    void 앞에_쉼표나_기호가_붙어도_숫자_시작으로_본다() {
        assertEquals("메뉴,38위안", fix("메뉴,38엔", "38", "CNY"));
        assertEquals("곱빼기 +150엔", fix("곱빼기 +150원", "150", "JPY"));
    }

    @Test
    void 범위_앞쪽에_같은_틀린_단어가_있으면_함께_바꾼다() {
        assertEquals("500위안~1000위안", fix("500엔~1000엔", "1000", "CNY"));
        assertEquals("500위안 - 1000위안", fix("500엔 - 1000엔", "1000", "CNY"));
    }

    @Test
    void 범위_앞쪽_숫자가_가격이면_뒤쪽_끝도_같은_틀린_단어일_때_함께_바꾼다() {
        // 500円〜1000円은 추출기가 앞의 500을 고른다.
        assertEquals("500위안~1000위안", fix("500엔~1000엔", "500", "CNY"));
        assertEquals("500위안 – 1000위안", fix("500엔 – 1000엔", "500", "CNY"));
        // 뒤쪽 단어가 다르거나 없으면 뒤쪽은 그대로 둔다.
        assertEquals("500위안~1000달러", fix("500엔~1000달러", "500", "CNY"));
        assertEquals("500위안~1000", fix("500엔~1000", "500", "CNY"));
        // 범위가 아니면 뒤에 같은 단어가 있어도 바꾸지 않는다.
        assertEquals("500위안, 1000엔", fix("500엔, 1000엔", "500", "CNY"));
    }

    @Test
    void 범위_앞쪽에_단어가_없으면_뒤쪽만_바꾼다() {
        assertEquals("500~1000위안", fix("500~1000엔", "1000", "CNY"));
    }

    @Test
    void 한국어가_아닌_번역이나_모르는_통화는_그대로_둔다() {
        assertEquals("Kung pao 38 yen", fixer.fix("Kung pao 38 yen", new BigDecimal("38"), "CNY", "en"));
        assertEquals("38엔", fix("38엔", "38", "XYZ"));
    }

    @Test
    void 값이_빠지면_그대로_돌려준다() {
        assertEquals("38엔", fixer.fix("38엔", null, "CNY", "ko"));
        assertEquals("38엔", fixer.fix("38엔", new BigDecimal("38"), null, "ko"));
        assertNull(fixer.fix(null, new BigDecimal("38"), "CNY", "ko"));
    }
}
