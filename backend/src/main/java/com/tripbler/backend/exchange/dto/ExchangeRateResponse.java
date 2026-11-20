package com.tripbler.backend.exchange.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;

/**
 * 최신 환율 응답.
 *
 * @param source 환율을 받은 출처. 평소에는 {@link #SOURCE_FRANKFURTER}이고, Frankfurter가 일시적으로
 *               실패해 대체 출처에서 받았으면 {@link #SOURCE_CURRENCY_API}이다. 두 출처는 기준이 달라
 *               값이 조금 다를 수 있다.
 */
public record ExchangeRateResponse(
    String baseCurrency,
    Map<String, BigDecimal> rates,
    LocalDate rateDate,
    LocalDateTime fetchedAt,
    boolean stale,
    String source
) {
    /** Frankfurter(유럽중앙은행 기준). */
    public static final String SOURCE_FRANKFURTER = "FRANKFURTER";

    /** fawazahmed0 currency-api(대체 출처, 하루 1회 갱신). */
    public static final String SOURCE_CURRENCY_API = "CURRENCY_API";

    public ExchangeRateResponse(String baseCurrency, Map<String, BigDecimal> rates, LocalDate rateDate, LocalDateTime fetchedAt) { this(baseCurrency, rates, rateDate, fetchedAt, false, SOURCE_FRANKFURTER); }
    public ExchangeRateResponse(String baseCurrency, Map<String, BigDecimal> rates, LocalDate rateDate, LocalDateTime fetchedAt, boolean stale) { this(baseCurrency, rates, rateDate, fetchedAt, stale, SOURCE_FRANKFURTER); }
    public ExchangeRateResponse asStale() { return new ExchangeRateResponse(baseCurrency, rates, rateDate, fetchedAt, true, source); }

}
