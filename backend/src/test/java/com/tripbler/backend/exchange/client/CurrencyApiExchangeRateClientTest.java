package com.tripbler.backend.exchange.client;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

import java.math.BigDecimal;
import java.net.ConnectException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.tripbler.backend.common.cache.ProviderFailures;
import com.tripbler.backend.common.exception.ExchangeProviderException;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;

/** currency-api 대체 클라이언트. 외부 API는 호출하지 않고 MockRestServiceServer로 대신한다. */
class CurrencyApiExchangeRateClientTest {
    private static final String BASE_URL = "https://cdn.jsdelivr.net";
    private static final String TODAY_URL =
        BASE_URL + "/npm/@fawazahmed0/currency-api@2026-11-21/v1/currencies/krw.json";
    private static final String YESTERDAY_URL =
        BASE_URL + "/npm/@fawazahmed0/currency-api@2026-11-20/v1/currencies/krw.json";
    private static final Clock CLOCK =
        Clock.fixed(Instant.parse("2026-11-21T03:00:00Z"), ZoneOffset.UTC);

    private MockRestServiceServer server;
    private CurrencyApiExchangeRateClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        server = MockRestServiceServer.bindTo(builder).build();
        client = new CurrencyApiExchangeRateClient(builder.build(), CLOCK);
    }

    private static String body(String date, String rates) {
        return "{\"date\":\"" + date + "\",\"krw\":{" + rates + "}}";
    }

    @Test
    void 오늘_날짜_데이터로_요청한_통화만_대문자로_돌려준다() {
        server.expect(requestTo(TODAY_URL)).andExpect(method(HttpMethod.GET))
            .andRespond(withSuccess(
                body("2026-11-21", "\"usd\":0.00068,\"jpy\":0.1065,\"eur\":0.00065"),
                MediaType.APPLICATION_JSON));

        ExchangeRateResponse response = client.getLatestRates("KRW", List.of("USD", "JPY"));

        assertEquals("KRW", response.baseCurrency());
        assertEquals(Map.of("USD", new BigDecimal("0.00068"), "JPY", new BigDecimal("0.1065")),
            response.rates());
        assertEquals(List.of("USD", "JPY"), List.copyOf(response.rates().keySet()));
        assertEquals(LocalDate.of(2026, 11, 21), response.rateDate());
        assertEquals(ExchangeRateResponse.SOURCE_CURRENCY_API, response.source());
        assertFalse(response.stale());
        server.verify();
    }

    @Test
    void 오늘_데이터가_아직_없으면_전날_데이터를_쓴다() {
        server.expect(requestTo(TODAY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(404)));
        server.expect(requestTo(YESTERDAY_URL))
            .andRespond(withSuccess(body("2026-11-20", "\"usd\":0.00068"), MediaType.APPLICATION_JSON));

        ExchangeRateResponse response = client.getLatestRates("KRW", List.of("USD"));

        assertEquals(LocalDate.of(2026, 11, 20), response.rateDate());
        assertEquals(new BigDecimal("0.00068"), response.rates().get("USD"));
        server.verify();
    }

    @Test
    void 전날_데이터도_없으면_실패한다() {
        server.expect(requestTo(TODAY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(404)));
        server.expect(requestTo(YESTERDAY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(404)));

        assertThrows(ExchangeProviderException.class,
            () -> client.getLatestRates("KRW", List.of("USD")));
        server.verify();
    }

    @Test
    void 서버_오류는_일시적_장애로_표시해_던지고_전날로_다시_요청하지_않는다() {
        server.expect(requestTo(TODAY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(503)));

        ExchangeProviderException exception = assertThrows(ExchangeProviderException.class,
            () -> client.getLatestRates("KRW", List.of("USD")));

        assertTrue(ProviderFailures.isTransient(exception));
        server.verify();
    }

    @Test
    void 연결_실패는_일시적_장애로_던진다() {
        server.expect(requestTo(TODAY_URL))
            .andRespond(withException(new ConnectException("Connection refused")));

        ExchangeProviderException exception = assertThrows(ExchangeProviderException.class,
            () -> client.getLatestRates("KRW", List.of("USD")));

        assertTrue(ProviderFailures.isTransient(exception));
        server.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "{\"date\":\"2026-11-21\",\"krw\":{\"jpy\":0.1}}",          // 요청한 통화 없음
        "{\"date\":\"2026-11-21\",\"krw\":{\"usd\":0}}",            // 0 환율
        "{\"date\":\"2026-11-21\",\"krw\":{\"usd\":-0.1}}",         // 음수 환율
        "{\"date\":\"2026-11-21\",\"krw\":{\"usd\":\"0.1\"}}",      // 숫자가 아님
        "{\"date\":\"2026-11-21\",\"usd\":{\"krw\":1400}}",         // 기준 통화 묶음 없음
        "{\"date\":\"not-a-date\",\"krw\":{\"usd\":0.00068}}",      // 날짜 형식 오류
        "{\"krw\":{\"usd\":0.00068}}"                               // 날짜 없음
    })
    void 응답_형식이_올바르지_않으면_일시적_장애가_아닌_실패로_던진다(String json) {
        server.expect(requestTo(TODAY_URL)).andRespond(withSuccess(json, MediaType.APPLICATION_JSON));

        ExchangeProviderException exception = assertThrows(ExchangeProviderException.class,
            () -> client.getLatestRates("KRW", List.of("USD")));

        assertFalse(ProviderFailures.isTransient(exception));
        server.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-11-22", "2026-11-19"})   // 미래, 이틀 전
    void 오늘_데이터의_date가_전날_오늘_범위를_벗어나면_일시적_장애가_아닌_실패로_던진다(String date) {
        server.expect(requestTo(TODAY_URL))
            .andRespond(withSuccess(body(date, "\"usd\":0.00068"), MediaType.APPLICATION_JSON));

        ExchangeProviderException exception = assertThrows(ExchangeProviderException.class,
            () -> client.getLatestRates("KRW", List.of("USD")));

        assertFalse(ProviderFailures.isTransient(exception));
        server.verify();
    }

    @Test
    void 전날_데이터의_date가_이틀_전이면_실패한다() {
        server.expect(requestTo(TODAY_URL)).andRespond(withStatus(HttpStatusCode.valueOf(404)));
        server.expect(requestTo(YESTERDAY_URL))
            .andRespond(withSuccess(body("2026-11-19", "\"usd\":0.00068"), MediaType.APPLICATION_JSON));

        ExchangeProviderException exception = assertThrows(ExchangeProviderException.class,
            () -> client.getLatestRates("KRW", List.of("USD")));

        assertFalse(ProviderFailures.isTransient(exception));
        server.verify();
    }

    @Test
    void 오늘_주소에서_전날_date를_받아도_허용한다() {
        server.expect(requestTo(TODAY_URL))
            .andRespond(withSuccess(body("2026-11-20", "\"usd\":0.00068"), MediaType.APPLICATION_JSON));

        assertEquals(LocalDate.of(2026, 11, 20),
            client.getLatestRates("KRW", List.of("USD")).rateDate());
        server.verify();
    }
}
