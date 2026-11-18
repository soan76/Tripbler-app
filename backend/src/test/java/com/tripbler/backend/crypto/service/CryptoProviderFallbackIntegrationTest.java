package com.tripbler.backend.crypto.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

import java.net.ConnectException;
import java.time.*;
import java.util.stream.Stream;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.ResponseCreator;
import org.springframework.web.client.RestClient;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.crypto.client.CoinGeckoClientTestSupport;
import com.tripbler.backend.crypto.config.CoinGeckoProperties;
import com.tripbler.backend.crypto.config.CryptoCacheProperties;

/** 실제 CoinGecko 클라이언트가 던진 예외가 캐시를 거쳐 stale 응답이 되는지 확인한다. 외부 API는 호출하지 않는다. */
class CryptoProviderFallbackIntegrationTest {
    private static final String BASE_URL = "https://api.coingecko.com/api/v3";
    private static final String PRICE_URL = BASE_URL + "/simple/price?ids=bitcoin&vs_currencies=krw";
    private static final String HISTORY_URL = BASE_URL + "/coins/bitcoin/market_chart?vs_currency=krw&days=7";
    private static final String PRICE_BODY = "{\"bitcoin\":{\"krw\":123456789}}";
    private static final String HISTORY_BODY = "{\"prices\":[[1700000000000,100],[1700003600000,101]]}";

    private final MutableClock clock = new MutableClock();
    private final CryptoCacheProperties cacheProperties = new CryptoCacheProperties();
    private MockRestServiceServer server;
    private CryptoService service;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        server = MockRestServiceServer.bindTo(builder).build();
        CoinGeckoProperties properties = new CoinGeckoProperties();
        properties.setApiKey("test-demo-key");
        service = new CryptoService(
            CoinGeckoClientTestSupport.create(builder.build(), properties),
            new CryptoResponseCache(cacheProperties, clock));
    }

    static Stream<Arguments> transientFailures() {
        return Stream.of(
            Arguments.of("429", withStatus(HttpStatusCode.valueOf(429))),
            Arguments.of("503", withStatus(HttpStatusCode.valueOf(503))),
            Arguments.of("connection refused", withException(new ConnectException("Connection refused")))
        );
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("transientFailures")
    void currentPriceFallsBackToLastSuccessOnTransientProviderFailure(String name, ResponseCreator failure) {
        server.expect(requestTo(PRICE_URL)).andRespond(withSuccess(PRICE_BODY, MediaType.APPLICATION_JSON));
        server.expect(requestTo(PRICE_URL)).andRespond(failure);

        var first = service.getCurrentPrice("bitcoin", "KRW");
        clock.advance(cacheProperties.getPriceTtl());
        var stale = service.getCurrentPrice("bitcoin", "KRW");

        assertFalse(first.stale());
        assertTrue(stale.stale());
        assertEquals(first.fetchedAt(), stale.fetchedAt());
        assertEquals(first.price(), stale.price());
        server.verify();
    }

    @Test
    void historyFallsBackToLastSuccessOnThrottling() {
        server.expect(requestTo(HISTORY_URL)).andRespond(withSuccess(HISTORY_BODY, MediaType.APPLICATION_JSON));
        server.expect(requestTo(HISTORY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(429)));

        var first = service.getHistoricalPrices("bitcoin", "KRW", "7D");
        clock.advance(cacheProperties.getHistoryTtl());
        var stale = service.getHistoricalPrices("bitcoin", "KRW", "7D");

        assertFalse(first.stale());
        assertTrue(stale.stale());
        assertEquals(first.fetchedAt(), stale.fetchedAt());
        assertEquals(first.prices(), stale.prices());
        server.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {400, 401})
    void nonTransientProviderErrorIsNotReplacedWithCachedValue(int status) {
        server.expect(requestTo(PRICE_URL)).andRespond(withSuccess(PRICE_BODY, MediaType.APPLICATION_JSON));
        server.expect(requestTo(PRICE_URL)).andRespond(withStatus(HttpStatusCode.valueOf(status)));

        service.getCurrentPrice("bitcoin", "KRW");
        clock.advance(cacheProperties.getPriceTtl());

        BusinessException error = assertThrows(BusinessException.class,
            () -> service.getCurrentPrice("bitcoin", "KRW"));
        assertEquals(ErrorCode.CRYPTO_PROVIDER_UNAVAILABLE, error.getErrorCode());
        server.verify();
    }

    private static final class MutableClock extends Clock {
        private Instant now = Instant.parse("2026-10-07T00:00:00Z");
        void advance(Duration duration) { now = now.plus(duration); }
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }
}
