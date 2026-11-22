package com.tripbler.backend.translation.service;

import static org.junit.jupiter.api.Assertions.*;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

class PriceExtractorTest {

    private final PriceExtractor extractor = new PriceExtractor();

    @ParameterizedTest(name = "{0}")
    @CsvSource(delimiter = '|', value = {
        "醤油ラーメン 980円|ja|980円|980|JPY",
        "味噌ラーメン 1,080円|ja|1,080円|1080|JPY",
        "大盛り +150円|ja|+150円|150|JPY",
        "餃子 ￥450|ja|￥450|450|JPY",
        "小笼包 ¥28|zh|¥28|28|CNY",
        "牛肉面 25元|zh|25元|25|CNY",
        "Burger $12.50|en|$12.50|12.50|USD",
        "Croissant €3.2|en|€3.2|3.2|EUR",
        "Tea £4|en|£4|4|GBP",
        "Pad thai 60 บาท|th|60 บาท|60|THB",
        "Pho 45,000₫|vi|45,000₫|45000|VND",
        "김밥 3,500원|ko|3,500원|3500|KRW",
        "Ramen 980 JPY|en|980 JPY|980|JPY"
    })
    void 줄에서_가격과_통화를_찾는다(String line, String language, String text, String amount, String currency) {
        PriceExtractor.Found found = extractor.find(line, language).orElseThrow();

        assertEquals(text, found.text());
        assertEquals(0, new BigDecimal(amount).compareTo(found.amount()));
        assertEquals(currency, found.currency());
    }

    @Test
    void 엔_기호는_언어를_모르면_엔으로_본다() {
        assertEquals("JPY", extractor.find("¥500", "auto").orElseThrow().currency());
        assertEquals("JPY", extractor.find("¥500", null).orElseThrow().currency());
    }

    @Test
    void 여러_가격이_있으면_먼저_나온_것을_쓴다() {
        assertEquals("¥300", extractor.find("セット ¥300 (単品 500円)", "ja").orElseThrow().text());
        assertEquals("500円", extractor.find("単品 500円 / セット ¥300", "ja").orElseThrow().text());
    }

    @Test
    void 첫_후보가_0원이면_다음_가격을_본다() {
        PriceExtractor.Found found = extractor.find("お通し 0円 / ビール 500円", "ja").orElseThrow();

        assertEquals("500円", found.text());
        assertEquals(0, new BigDecimal("500").compareTo(found.amount()));
    }

    @Test
    void 먼저_나온_가격은_글자가_아니라_위치로_고른다() {
        // "500円"이라는 글자가 앞의 "1500円" 안에도 있어 indexOf로 비교하면 위치를 잘못 잡는다.
        assertEquals("1500円", extractor.find("1500円 ¥800 500円", "ja").orElseThrow().text());
        assertEquals("¥800", extractor.find("¥800 1500円", "ja").orElseThrow().text());
    }

    @Test
    void 할인_표시_앞의_빼기_기호가_붙으면_가격이_아니다() {
        assertEquals(Optional.empty(), extractor.find("クーポン -100円", "ja"));
        assertEquals(Optional.empty(), extractor.find("割引 − 100円", "ja"));
        assertEquals(Optional.empty(), extractor.find("Discount -$5", "en"));
        // 빼기 뒤에 정가가 따로 있으면 그 정가를 쓴다.
        assertEquals("980円", extractor.find("-100円 引き 980円", "ja").orElseThrow().text());
        // 가타카나 장음(ー) 뒤의 가격은 그대로 가격이다.
        assertEquals("500円", extractor.find("コーヒー500円", "ja").orElseThrow().text());
        // 범위 표시(숫자-숫자)의 뒤 숫자는 빼기가 아니다.
        assertEquals("1000円", extractor.find("500-1000円", "ja").orElseThrow().text());
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "12.345円",
        "1,2345円",
        "5 EURO",
        "3THBx",
        "3块肉",
        "$12.505",
        "-100円"
    })
    void 숫자_앞뒤_경계가_맞지_않으면_가격이_아니다(String line) {
        assertEquals(Optional.empty(), extractor.find(line, "zh"), line);
    }

    @Test
    void 块_뒤에_钱이면_가격이다() {
        PriceExtractor.Found found = extractor.find("一碗 10块钱", "zh").orElseThrow();

        assertEquals("10块", found.text());
        assertEquals("CNY", found.currency());
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "食券は入口の券売機で購入してください",
        "2人前",
        "営業時間 11:00-22:00",
        "3동 101호",
        "0円",
        "",
        "   "
    })
    void 가격이_아니면_찾지_않는다(String line) {
        assertEquals(Optional.empty(), extractor.find(line, "ja"));
    }
}
