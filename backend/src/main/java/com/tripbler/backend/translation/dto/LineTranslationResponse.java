package com.tripbler.backend.translation.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 줄별 번역 결과. 줄 순서는 요청과 같다.
 *
 * @param sourceLanguageCode 원본 언어. 요청이 auto면 감지한 언어 코드(모르면 "auto").
 */
public record LineTranslationResponse(
    String sourceLanguageCode,
    String targetLanguageCode,
    List<TranslatedLine> lines
) {

    /**
     * @param pronunciation 원문을 소리 나는 대로 적은 한글. 원문이 이미 번역 언어이거나 숫자·기호뿐이면 null.
     *                      참고용이다(가게 이름 같은 고유명사는 틀릴 수 있다).
     * @param price         줄에서 찾은 가격. 없으면 null.
     */
    public record TranslatedLine(
        String original,
        String translated,
        String pronunciation,
        Price price
    ) {
    }

    /**
     * 줄에서 찾은 가격과 원화 환산.
     *
     * @param text          줄에 적힌 가격 글자 그대로(예: "980円", "+150円").
     * @param amount        금액(부호 없음).
     * @param currency      ISO 통화 코드.
     * @param krwAmount     원화로 바꾼 금액(원 단위 반올림). 환율을 받지 못했거나 이미 원화면 null.
     * @param krwRate       1 [currency] = krwRate 원. krwAmount가 null이면 null.
     * @param rateFetchedAt 환율을 가져온 시각. krwAmount가 null이면 null.
     * @param rateStale     일시적 장애로 마지막 성공 환율을 썼는지.
     */
    public record Price(
        String text,
        BigDecimal amount,
        String currency,
        BigDecimal krwAmount,
        BigDecimal krwRate,
        LocalDateTime rateFetchedAt,
        boolean rateStale
    ) {
    }
}
