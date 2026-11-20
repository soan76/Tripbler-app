package com.tripbler.backend.exchange.client;

import java.util.List;

import com.tripbler.backend.exchange.dto.ExchangeRateResponse;

/**
 * 기본 환율 출처가 일시적으로 실패했을 때만 쓰는 최신 환율 출처.
 * 기간별 시세는 제공하지 않는다.
 */
public interface LatestRateFallbackClient {

    ExchangeRateResponse getLatestRates(
        String baseCurrency,
        List<String> targetCurrencies
    );
}
