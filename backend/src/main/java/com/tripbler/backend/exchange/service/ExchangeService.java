package com.tripbler.backend.exchange.service;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.tripbler.backend.common.cache.ProviderFailures;
import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.exchange.client.ExchangeRateClient;
import com.tripbler.backend.exchange.client.LatestRateFallbackClient;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.exchange.dto.HistoricalRateResponse;

@Service
public class ExchangeService {

    private static final int MAX_HISTORY_YEARS = 5;

    private static final Logger log = LoggerFactory.getLogger(ExchangeService.class);

    private final ExchangeRateClient exchangeRateClient;

    /** 최신 환율의 대체 출처. null이면 대체 출처 없이 캐시만 쓴다. */
    private final LatestRateFallbackClient fallbackClient;
    private final ExchangeResponseCache cache;

    @Autowired
    public ExchangeService(
        ExchangeRateClient exchangeRateClient,
        LatestRateFallbackClient fallbackClient,
        ExchangeResponseCache cache
    ) {
        this.exchangeRateClient = exchangeRateClient;
        this.fallbackClient = fallbackClient;
        this.cache = cache == null ? new ExchangeResponseCache() : cache;
    }

    public ExchangeService(ExchangeRateClient exchangeRateClient, ExchangeResponseCache cache) {
        this(exchangeRateClient, null, cache);
    }

    public ExchangeService(ExchangeRateClient exchangeRateClient) {
        this(exchangeRateClient, new ExchangeResponseCache());
    }

    public ExchangeRateResponse getRates(
        String baseCurrency,
        String targets
    ) {
        String normalizedBase =
            normalizeCurrencyCode(baseCurrency);

        List<String> targetCurrencies =
            parseTargetCurrencies(
                targets,
                normalizedBase
            );

        return cache.latest(normalizedBase, targetCurrencies,
            () -> loadLatestRates(normalizedBase, targetCurrencies));
    }

    /**
     * Frankfurter에서 최신 환율을 받는다. Frankfurter가 일시적으로 실패하면(시간 초과, 연결 실패, 429·5xx)
     * 대체 출처에서 받는다. 대체 출처도 실패하면 Frankfurter의 원래 예외를 던져, 캐시가 그 예외로
     * 마지막 성공값(stale)을 쓸지 정하게 한다. 대체 값의 기준일이 캐시된 마지막 값보다 과거여도
     * 같은 방식으로 버린다. 일시적 장애가 아닌 실패는 대체 출처를 쓰지 않는다.
     */
    private ExchangeRateResponse loadLatestRates(String baseCurrency, List<String> targetCurrencies) {
        try {
            return exchangeRateClient.getLatestRates(baseCurrency, targetCurrencies);
        } catch (RuntimeException primaryFailure) {
            if (fallbackClient == null || !ProviderFailures.isTransient(primaryFailure)) {
                throw primaryFailure;
            }

            ExchangeRateResponse response;

            try {
                response = fallbackClient.getLatestRates(baseCurrency, targetCurrencies);
            } catch (RuntimeException fallbackFailure) {
                log.warn("Frankfurter와 대체 출처 모두 실패 base={} fallbackError={}",
                    baseCurrency, fallbackFailure.getClass().getSimpleName());
                primaryFailure.addSuppressed(fallbackFailure);
                throw primaryFailure;
            }

            // 대체 출처는 실패하지 않았으므로 suppressed는 붙이지 않는다.
            if (isOlderThanCached(baseCurrency, targetCurrencies, response)) {
                log.warn("대체 출처 기준일이 캐시된 값보다 과거라 사용하지 않음 base={}", baseCurrency);
                throw primaryFailure;
            }

            log.warn("Frankfurter 일시 장애로 대체 출처 환율 사용 base={}", baseCurrency);
            return response;
        }
    }

    /**
     * 캐시된 마지막 값의 기준일이 대체 값보다 뒤인지 본다. 그렇다면 대체 값을 쓰지 않고 Frankfurter
     * 예외를 던져 캐시가 그 값을 stale로 돌려주게 한다(갱신 시각만 최신이고 기준일은 과거인 응답 방지).
     * 이 메서드는 캐시 로더 안, 즉 같은 키의 슬롯 lock을 잡은 스레드에서 불린다. peek는 같은 lock을
     * 다시 잡는 재진입이라 교착되지 않는다.
     */
    private boolean isOlderThanCached(
        String baseCurrency,
        List<String> targetCurrencies,
        ExchangeRateResponse fallbackResponse
    ) {
        LocalDate fallbackDate = fallbackResponse.rateDate();

        return fallbackDate != null && cache.peekLatest(baseCurrency, targetCurrencies)
            .map(ExchangeRateResponse::rateDate)
            .filter(cachedDate -> cachedDate.isAfter(fallbackDate))
            .isPresent();
    }

    public HistoricalRateResponse getHistoricalRates(
        String baseCurrency,
        String targetCurrency,
        LocalDate startDate,
        LocalDate endDate
    ) {
        String normalizedBase =
            normalizeCurrencyCode(baseCurrency);

        String normalizedTarget =
            normalizeCurrencyCode(targetCurrency);

        validateHistoryRequest(
            normalizedBase,
            normalizedTarget,
            startDate,
            endDate
        );

        return cache.history(normalizedBase, normalizedTarget, startDate, endDate,
            () -> exchangeRateClient.getHistoricalRates(normalizedBase, normalizedTarget, startDate, endDate));
    }

    private void validateHistoryRequest(
        String baseCurrency,
        String targetCurrency,
        LocalDate startDate,
        LocalDate endDate
    ) {
        if (baseCurrency.equals(targetCurrency)) {
            throw new BusinessException(
                ErrorCode.INVALID_REQUEST,
                "기준 통화와 대상 통화는 서로 달라야 합니다."
            );
        }

        if (startDate == null || endDate == null) {
            throw new BusinessException(
                ErrorCode.INVALID_REQUEST,
                "시작일과 종료일은 필수입니다."
            );
        }

        if (startDate.isAfter(endDate)) {
            throw new BusinessException(
                ErrorCode.INVALID_REQUEST,
                "시작일은 종료일보다 늦을 수 없습니다."
            );
        }

        if (endDate.isAfter(LocalDate.now())) {
            throw new BusinessException(
                ErrorCode.INVALID_REQUEST,
                "종료일은 오늘보다 늦을 수 없습니다."
            );
        }

        // 앱의 최장 차트 기간과 동일하게 달력 기준 5년을 허용한다.
        // 일수로 제한하면 윤년이 포함된 기간의 경계가 달라진다.
        if (startDate.isBefore(endDate.minusYears(MAX_HISTORY_YEARS))) {
            throw new BusinessException(
                ErrorCode.INVALID_REQUEST,
                "기간별 환율은 최대 5년까지 조회할 수 있습니다."
            );
        }
    }

    private List<String> parseTargetCurrencies(
        String targets,
        String baseCurrency
    ) {
        if (targets == null || targets.isBlank()) {
            throw new BusinessException(
                ErrorCode.TARGET_CURRENCY_REQUIRED
            );
        }

        List<String> currencies = Arrays
            .stream(targets.split(","))
            .map(String::trim)
            .filter(currency -> !currency.isBlank())
            .map(this::normalizeCurrencyCode)
            .filter(currency ->
                !currency.equals(baseCurrency)
            )
            .distinct()
            .toList();

        if (currencies.isEmpty()) {
            throw new BusinessException(
                ErrorCode.TARGET_CURRENCY_REQUIRED
            );
        }

        return currencies;
    }

    private String normalizeCurrencyCode(
        String currencyCode
    ) {
        if (currencyCode == null) {
            throw new BusinessException(
                ErrorCode.INVALID_CURRENCY_CODE
            );
        }

        String normalized = currencyCode
            .trim()
            .toUpperCase(Locale.ROOT);

        if (!normalized.matches("^[A-Z]{3}$")) {
            throw new BusinessException(
                ErrorCode.INVALID_CURRENCY_CODE
            );
        }

        return normalized;
    }
}
