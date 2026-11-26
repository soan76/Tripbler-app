package com.tripbler.backend.translation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.junit.jupiter.api.Test;

import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.exchange.service.ExchangeService;

class KrwPriceConverterTest {

    private static final LocalDateTime FETCHED_AT = LocalDateTime.of(2026, 11, 21, 9, 0);

    private final ExchangeService exchangeService = mock(ExchangeService.class);

    private static ExchangeRateResponse rate(String base, String krw, boolean stale) {
        return new ExchangeRateResponse(base, Map.of("KRW", new BigDecimal(krw)), LocalDate.of(2026, 11, 21),
            FETCHED_AT, stale);
    }

    @Test
    void convert는_원화이면_비어_있다() {
        KrwPriceConverter converter = new KrwPriceConverter(exchangeService, Duration.ofSeconds(1));

        assertThat(converter.convert(new BigDecimal("1000"), "KRW", Map.of())).isEmpty();
    }

    @Test
    void convert는_환율을_곱해_소수_없이_반올림한다() {
        KrwPriceConverter converter = new KrwPriceConverter(exchangeService, Duration.ofSeconds(1));
        Map<String, Optional<ExchangeRateResponse>> rates = Map.of("JPY", Optional.of(rate("JPY", "9.29", true)));

        Optional<KrwPriceConverter.KrwConversion> result = converter.convert(new BigDecimal("980"), "JPY", rates);

        assertThat(result).isPresent();
        assertThat(result.get().krwAmount()).isEqualByComparingTo("9104");
        assertThat(result.get().krwRate()).isEqualByComparingTo("9.29");
        assertThat(result.get().fetchedAt()).isEqualTo(FETCHED_AT);
        assertThat(result.get().stale()).isTrue();
    }

    @Test
    void convert는_환율이_없으면_비어_있다() {
        KrwPriceConverter converter = new KrwPriceConverter(exchangeService, Duration.ofSeconds(1));

        assertThat(converter.convert(new BigDecimal("980"), "JPY", Map.of())).isEmpty();
        assertThat(converter.convert(new BigDecimal("980"), "JPY", Map.of("JPY", Optional.empty()))).isEmpty();
    }

    @Test
    void ratesFor는_예산을_넘긴_통화를_비워_돌려준다() {
        when(exchangeService.getRates("USD", "KRW")).thenReturn(rate("USD", "1400", false));
        when(exchangeService.getRates("JPY", "KRW")).thenAnswer(invocation -> {
            Thread.sleep(2000);
            return rate("JPY", "9.29", false);
        });
        KrwPriceConverter converter = new KrwPriceConverter(exchangeService, Duration.ofMillis(200));

        try {
            Map<String, Optional<ExchangeRateResponse>> rates = converter.ratesFor(Set.of("USD", "JPY"));

            assertThat(rates.get("USD")).isPresent();
            assertThat(rates.get("JPY")).isEmpty();
        } finally {
            converter.destroy();
        }
    }
}
