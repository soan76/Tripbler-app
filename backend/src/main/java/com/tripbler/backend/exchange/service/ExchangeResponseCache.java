package com.tripbler.backend.exchange.service;

import java.time.*;
import java.util.List;
import java.util.Optional;
import java.util.function.Supplier;
import org.springframework.stereotype.Component;
import com.tripbler.backend.common.cache.TimeoutFallbackCache;
import com.tripbler.backend.exchange.dto.*;

@Component
public class ExchangeResponseCache {
    /** Frankfurter 최신 환율 TTL. */
    static final Duration LATEST_TTL = Duration.ofMinutes(5);
    /** 대체 출처 값은 Frankfurter가 복구되면 빨리 돌아가도록 짧게 둔다. */
    static final Duration FALLBACK_LATEST_TTL = Duration.ofMinutes(1);

    private record LatestKey(String base, List<String> targets) {}
    private record HistoryKey(String base, String target, LocalDate start, LocalDate end) {}
    private final TimeoutFallbackCache<LatestKey, ExchangeRateResponse> latest;
    private final TimeoutFallbackCache<HistoryKey, HistoricalRateResponse> histories;

    public ExchangeResponseCache() { this(Clock.systemUTC()); }
    ExchangeResponseCache(Clock clock) {
        latest = new TimeoutFallbackCache<>(clock, LATEST_TTL, Duration.ofDays(3), 256);
        histories = new TimeoutFallbackCache<>(clock, Duration.ofHours(1), Duration.ofDays(7), 512);
    }
    public ExchangeRateResponse latest(String base, List<String> targets, Supplier<ExchangeRateResponse> loader) {
        return latest.get(latestKey(base, targets), loader, ExchangeRateResponse::asStale,
            response -> ExchangeRateResponse.SOURCE_CURRENCY_API.equals(response.source())
                ? FALLBACK_LATEST_TTL : LATEST_TTL);
    }
    /** 마지막 최신 환율 성공값(만료돼도 포함). 없으면 비어 있다. 슬롯을 만들지 않는다. */
    public Optional<ExchangeRateResponse> peekLatest(String base, List<String> targets) {
        return Optional.ofNullable(latest.peek(latestKey(base, targets)));
    }
    private static LatestKey latestKey(String base, List<String> targets) {
        return new LatestKey(base, targets.stream().sorted().toList());
    }
    public HistoricalRateResponse history(String base, String target, LocalDate start, LocalDate end,
                                           Supplier<HistoricalRateResponse> loader) {
        return histories.get(new HistoryKey(base, target, start, end), loader, HistoricalRateResponse::asStale);
    }
}
