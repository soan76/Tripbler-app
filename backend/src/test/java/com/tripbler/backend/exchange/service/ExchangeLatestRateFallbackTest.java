package com.tripbler.backend.exchange.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import java.math.BigDecimal;
import java.net.SocketTimeoutException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.ResourceAccessException;

import com.tripbler.backend.common.exception.ExchangeProviderException;
import com.tripbler.backend.exchange.client.ExchangeRateClient;
import com.tripbler.backend.exchange.client.LatestRateFallbackClient;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;

/** Frankfurter가 일시적으로 실패할 때 대체 출처와 캐시를 쓰는 순서. 외부 API는 대역으로 대신한다. */
class ExchangeLatestRateFallbackTest {
    private static final List<String> TARGETS = List.of("USD");

    private final MutableClock clock = new MutableClock();
    private ExchangeRateClient primary;
    private LatestRateFallbackClient fallback;
    private ExchangeService service;

    @BeforeEach
    void setUp() {
        primary = mock(ExchangeRateClient.class);
        fallback = mock(LatestRateFallbackClient.class);
        service = new ExchangeService(primary, fallback, new ExchangeResponseCache(clock));
    }

    private static ExchangeRateResponse frankfurter(String usd) {
        return new ExchangeRateResponse("KRW", Map.of("USD", new BigDecimal(usd)),
            LocalDate.of(2026, 11, 20), LocalDateTime.of(2026, 11, 21, 9, 0));
    }

    private static ExchangeRateResponse currencyApi(String usd) {
        return new ExchangeRateResponse("KRW", Map.of("USD", new BigDecimal(usd)),
            LocalDate.of(2026, 11, 21), LocalDateTime.of(2026, 11, 21, 9, 10), false,
            ExchangeRateResponse.SOURCE_CURRENCY_API);
    }

    private static ExchangeProviderException transientFailure() {
        return new ExchangeProviderException(503);
    }

    private static ExchangeProviderException timeout() {
        return new ExchangeProviderException(
            new ResourceAccessException("timeout", new SocketTimeoutException("Read timed out")));
    }

    @Test
    void 정상이면_Frankfurter_값을_쓰고_대체_출처는_부르지_않는다() {
        when(primary.getLatestRates("KRW", TARGETS)).thenReturn(frankfurter("0.00068"));

        ExchangeRateResponse response = service.getRates("KRW", "USD");

        assertEquals(ExchangeRateResponse.SOURCE_FRANKFURTER, response.source());
        verifyNoInteractions(fallback);
    }

    @Test
    void Frankfurter가_일시적으로_실패하면_대체_출처_값을_쓴다() {
        when(primary.getLatestRates("KRW", TARGETS)).thenThrow(transientFailure());
        when(fallback.getLatestRates("KRW", TARGETS)).thenReturn(currencyApi("0.00069"));

        ExchangeRateResponse response = service.getRates("KRW", "USD");

        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API, response.source());
        assertEquals(new BigDecimal("0.00069"), response.rates().get("USD"));
        assertFalse(response.stale());
    }

    @Test
    void 시간_초과도_일시적_장애로_보고_대체_출처를_쓴다() {
        when(primary.getLatestRates("KRW", TARGETS)).thenThrow(timeout());
        when(fallback.getLatestRates("KRW", TARGETS)).thenReturn(currencyApi("0.00069"));

        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API,
            service.getRates("KRW", "USD").source());
    }

    @Test
    void 캐시가_있어도_대체_출처를_먼저_쓴다() {
        when(primary.getLatestRates("KRW", TARGETS))
            .thenReturn(frankfurter("0.00068"))
            .thenThrow(transientFailure());
        when(fallback.getLatestRates("KRW", TARGETS)).thenReturn(currencyApi("0.00069"));

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));
        ExchangeRateResponse response = service.getRates("KRW", "USD");

        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API, response.source());
        assertFalse(response.stale());
    }

    @Test
    void 둘_다_실패하면_마지막_Frankfurter_값을_stale로_돌려준다() {
        when(primary.getLatestRates("KRW", TARGETS))
            .thenReturn(frankfurter("0.00068"))
            .thenThrow(transientFailure());
        when(fallback.getLatestRates("KRW", TARGETS)).thenThrow(transientFailure());

        ExchangeRateResponse first = service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));
        ExchangeRateResponse stale = service.getRates("KRW", "USD");

        assertTrue(stale.stale());
        assertEquals(ExchangeRateResponse.SOURCE_FRANKFURTER, stale.source());
        assertEquals(first.fetchedAt(), stale.fetchedAt());
        assertEquals(first.rates(), stale.rates());
    }

    @Test
    void 대체_출처_값이_캐시된_뒤_둘_다_실패하면_대체_출처_값을_stale로_돌려준다() {
        when(primary.getLatestRates("KRW", TARGETS)).thenThrow(transientFailure());
        when(fallback.getLatestRates("KRW", TARGETS))
            .thenReturn(currencyApi("0.00069"))
            .thenThrow(transientFailure());

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));
        ExchangeRateResponse stale = service.getRates("KRW", "USD");

        assertTrue(stale.stale());
        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API, stale.source());
    }

    @Test
    void 둘_다_실패하고_캐시도_없으면_Frankfurter_원래_예외를_던진다() {
        ExchangeProviderException primaryFailure = transientFailure();
        ExchangeProviderException fallbackFailure = transientFailure();
        when(primary.getLatestRates("KRW", TARGETS)).thenThrow(primaryFailure);
        when(fallback.getLatestRates("KRW", TARGETS)).thenThrow(fallbackFailure);

        ExchangeProviderException thrown = assertThrows(ExchangeProviderException.class,
            () -> service.getRates("KRW", "USD"));

        assertSame(primaryFailure, thrown);
        assertSame(fallbackFailure, thrown.getSuppressed()[0]);
    }

    @Test
    void 일시적_장애가_아닌_실패는_대체_출처를_쓰지_않는다() {
        when(primary.getLatestRates("KRW", TARGETS)).thenThrow(new ExchangeProviderException(400));

        assertThrows(ExchangeProviderException.class, () -> service.getRates("KRW", "USD"));
        verifyNoInteractions(fallback);
    }

    @Test
    void 기간별_시세는_대체_출처를_쓰지_않는다() {
        when(primary.getHistoricalRates(anyString(), anyString(), any(), any()))
            .thenThrow(transientFailure());

        assertThrows(ExchangeProviderException.class, () -> service.getHistoricalRates(
            "KRW", "USD", LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 5)));
        verify(fallback, never()).getLatestRates(anyString(), anyList());
    }

    private static ExchangeRateResponse frankfurterOn(LocalDate rateDate) {
        return new ExchangeRateResponse("KRW", Map.of("USD", new BigDecimal("0.00068")),
            rateDate, LocalDateTime.of(2026, 11, 21, 9, 0));
    }

    private static ExchangeRateResponse currencyApiOn(LocalDate rateDate) {
        return new ExchangeRateResponse("KRW", Map.of("USD", new BigDecimal("0.00069")),
            rateDate, LocalDateTime.of(2026, 11, 21, 9, 10), false,
            ExchangeRateResponse.SOURCE_CURRENCY_API);
    }

    @Test
    void 대체_출처_값은_1분_뒤_Frankfurter를_다시_부른다() {
        when(primary.getLatestRates("KRW", TARGETS))
            .thenThrow(transientFailure())
            .thenReturn(frankfurter("0.00068"));
        when(fallback.getLatestRates("KRW", TARGETS)).thenReturn(currencyApi("0.00069"));

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofSeconds(59));
        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API, service.getRates("KRW", "USD").source());
        verify(primary, times(1)).getLatestRates("KRW", TARGETS);

        clock.advance(Duration.ofSeconds(1));
        ExchangeRateResponse recovered = service.getRates("KRW", "USD");

        assertEquals(ExchangeRateResponse.SOURCE_FRANKFURTER, recovered.source());
        assertFalse(recovered.stale());
        verify(primary, times(2)).getLatestRates("KRW", TARGETS);
    }

    @Test
    void Frankfurter_값은_여전히_5분_유지된다() {
        when(primary.getLatestRates("KRW", TARGETS)).thenReturn(frankfurter("0.00068"));

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(4).plusSeconds(59));
        service.getRates("KRW", "USD");
        verify(primary, times(1)).getLatestRates("KRW", TARGETS);

        clock.advance(Duration.ofSeconds(1));
        service.getRates("KRW", "USD");
        verify(primary, times(2)).getLatestRates("KRW", TARGETS);
    }

    @Test
    void 캐시된_Frankfurter_기준일이_대체_값보다_뒤면_대체_값을_버리고_stale로_돌려준다() {
        ExchangeProviderException primaryFailure = transientFailure();
        when(primary.getLatestRates("KRW", TARGETS))
            .thenReturn(frankfurterOn(LocalDate.of(2026, 11, 21)))
            .thenThrow(primaryFailure);
        when(fallback.getLatestRates("KRW", TARGETS)).thenReturn(currencyApiOn(LocalDate.of(2026, 11, 20)));

        ExchangeRateResponse first = service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));
        ExchangeRateResponse stale = service.getRates("KRW", "USD");

        assertTrue(stale.stale());
        assertEquals(ExchangeRateResponse.SOURCE_FRANKFURTER, stale.source());
        assertEquals(first.rateDate(), stale.rateDate());
        assertEquals(first.fetchedAt(), stale.fetchedAt());
        assertEquals(first.rates(), stale.rates());
        assertEquals(0, primaryFailure.getSuppressed().length);
        verify(fallback, times(1)).getLatestRates("KRW", TARGETS);
    }

    @Test
    void 대체_값을_버렸는데_캐시도_쓸_수_없으면_Frankfurter_원래_예외를_던진다() {
        ExchangeProviderException primaryFailure = transientFailure();
        when(primary.getLatestRates("KRW", TARGETS))
            .thenReturn(frankfurterOn(LocalDate.of(2026, 11, 21)))
            .thenThrow(primaryFailure);
        when(fallback.getLatestRates("KRW", TARGETS)).thenReturn(currencyApiOn(LocalDate.of(2026, 11, 20)));

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5).plus(Duration.ofDays(3)));

        assertSame(primaryFailure,
            assertThrows(ExchangeProviderException.class, () -> service.getRates("KRW", "USD")));
        assertEquals(0, primaryFailure.getSuppressed().length);
    }

    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(strings = {"2026-11-20", "2026-11-21"})
    void 캐시된_기준일과_같거나_대체_값이_더_최근이면_대체_값을_쓴다(String fallbackDate) {
        when(primary.getLatestRates("KRW", TARGETS))
            .thenReturn(frankfurterOn(LocalDate.of(2026, 11, 20)))
            .thenThrow(transientFailure());
        when(fallback.getLatestRates("KRW", TARGETS))
            .thenReturn(currencyApiOn(LocalDate.parse(fallbackDate)));

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));
        ExchangeRateResponse response = service.getRates("KRW", "USD");

        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API, response.source());
        assertEquals(LocalDate.parse(fallbackDate), response.rateDate());
        assertFalse(response.stale());
    }

    private static final class MutableClock extends Clock {
        private Instant now = Instant.parse("2026-11-21T00:00:00Z");
        void advance(Duration duration) { now = now.plus(duration); }
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
}
