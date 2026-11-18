package com.tripbler.backend.exchange.service;

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

import com.tripbler.backend.common.exception.ExchangeProviderException;
import com.tripbler.backend.exchange.client.FrankfurterClientTestSupport;

/** 실제 Frankfurter 클라이언트가 던진 예외가 캐시를 거쳐 stale 응답이 되는지 확인한다. 외부 API는 호출하지 않는다. */
class ExchangeProviderFallbackIntegrationTest {
    private static final String BASE_URL = "https://api.frankfurter.dev/v1";
    private static final String LATEST_URL = BASE_URL + "/latest?base=KRW&symbols=USD";
    private static final String HISTORY_URL = BASE_URL + "/2026-07-01..2026-07-03?base=KRW&symbols=USD";
    private static final LocalDate START = LocalDate.of(2026, 7, 1);
    private static final LocalDate END = LocalDate.of(2026, 7, 3);
    private static final String LATEST_BODY =
        "{\"amount\":1.0,\"base\":\"KRW\",\"date\":\"2026-08-04\",\"rates\":{\"USD\":0.0007}}";
    private static final String HISTORY_BODY =
        "{\"amount\":1.0,\"base\":\"KRW\",\"start_date\":\"2026-07-01\",\"end_date\":\"2026-07-03\","
            + "\"rates\":{\"2026-07-01\":{\"USD\":0.00064},\"2026-07-03\":{\"USD\":0.00066}}}";

    private final MutableClock clock = new MutableClock();
    private MockRestServiceServer server;
    private ExchangeService service;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        server = MockRestServiceServer.bindTo(builder).build();
        service = new ExchangeService(
            FrankfurterClientTestSupport.create(builder.build()), new ExchangeResponseCache(clock));
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
    void latestRatesFallBackToLastSuccessOnTransientProviderFailure(String name, ResponseCreator failure) {
        server.expect(requestTo(LATEST_URL)).andRespond(withSuccess(LATEST_BODY, MediaType.APPLICATION_JSON));
        server.expect(requestTo(LATEST_URL)).andRespond(failure);

        var first = service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));
        var stale = service.getRates("KRW", "USD");

        assertFalse(first.stale());
        assertTrue(stale.stale());
        assertEquals(first.fetchedAt(), stale.fetchedAt());
        assertEquals(first.rates(), stale.rates());
        server.verify();
    }

    @Test
    void historicalRatesFallBackToLastSuccessOnServerError() {
        server.expect(requestTo(HISTORY_URL)).andRespond(withSuccess(HISTORY_BODY, MediaType.APPLICATION_JSON));
        server.expect(requestTo(HISTORY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(503)));

        var first = service.getHistoricalRates("KRW", "USD", START, END);
        clock.advance(Duration.ofHours(1));
        var stale = service.getHistoricalRates("KRW", "USD", START, END);

        assertFalse(first.stale());
        assertTrue(stale.stale());
        assertEquals(first.fetchedAt(), stale.fetchedAt());
        assertEquals(first.rates(), stale.rates());
        server.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {400, 401})
    void nonTransientProviderErrorIsNotReplacedWithCachedValue(int status) {
        server.expect(requestTo(LATEST_URL)).andRespond(withSuccess(LATEST_BODY, MediaType.APPLICATION_JSON));
        server.expect(requestTo(LATEST_URL)).andRespond(withStatus(HttpStatusCode.valueOf(status)));

        service.getRates("KRW", "USD");
        clock.advance(Duration.ofMinutes(5));

        assertThrows(ExchangeProviderException.class, () -> service.getRates("KRW", "USD"));
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
