package com.tripbler.backend.exchange.client;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import com.tripbler.backend.common.exception.ExchangeProviderException;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;

/**
 * fawazahmed0 currency-api(https://github.com/fawazahmed0/exchange-api)에서 최신 환율을 받는다.
 * 키가 필요 없고 하루 1회 갱신된다. Frankfurter가 일시적으로 실패했을 때만 쓴다.
 *
 * <ul>
 *   <li>`@latest`는 CDN 캐시로 하루 늦을 수 있어 오늘(UTC) 날짜를 직접 넣어 요청하고, 아직 올라오지
 *       않았으면(404) 전날 데이터를 받는다.</li>
 *   <li>같은 날짜라도 배포 주소마다 값이 조금 달라 한 응답은 한 주소(jsDelivr)에서만 받는다.</li>
 *   <li>통화 코드는 소문자로 요청하고 대문자로 돌려준다. 요청한 통화가 하나라도 없거나 값이 올바르지
 *       않으면 실패로 본다.</li>
 * </ul>
 */
@Component
public class CurrencyApiExchangeRateClient implements LatestRateFallbackClient {

    private static final String BASE_URL = "https://cdn.jsdelivr.net";

    private static final String LATEST_PATH =
        "/npm/@fawazahmed0/currency-api@{date}/v1/currencies/{base}.json";

    // Frankfurter를 이미 기다린 뒤 부르므로 Frankfurter보다 짧게 기다린다.
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(2);
    private static final Duration READ_TIMEOUT = Duration.ofSeconds(3);

    private static final ParameterizedTypeReference<Map<String, Object>> JSON_OBJECT =
        new ParameterizedTypeReference<>() {};

    private final RestClient restClient;
    private final Clock clock;

    @Autowired
    public CurrencyApiExchangeRateClient(RestClient.Builder restClientBuilder) {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(CONNECT_TIMEOUT);
        requestFactory.setReadTimeout(READ_TIMEOUT);

        this.restClient = restClientBuilder
            .baseUrl(BASE_URL)
            .requestFactory(requestFactory)
            .build();
        this.clock = Clock.systemUTC();
    }

    // 단위 테스트에서 가짜 RestClient와 고정 시계를 주입하기 위한 생성자
    CurrencyApiExchangeRateClient(RestClient restClient, Clock clock) {
        this.restClient = restClient;
        this.clock = clock;
    }

    @Override
    public ExchangeRateResponse getLatestRates(String baseCurrency, List<String> targetCurrencies) {
        LocalDate today = LocalDate.now(clock);

        try {
            Map<String, Object> body;

            try {
                body = fetch(today, baseCurrency);
            } catch (DateNotPublishedException notYet) {
                body = fetch(today.minusDays(1), baseCurrency);
            }

            return toResponse(body, baseCurrency, targetCurrencies, today);
        } catch (DateNotPublishedException notPublished) {
            throw new ExchangeProviderException(404);
        } catch (ExchangeProviderException exception) {
            throw exception;
        } catch (RestClientException exception) {
            throw new ExchangeProviderException(exception);
        }
    }

    private Map<String, Object> fetch(LocalDate date, String baseCurrency) {
        return restClient
            .get()
            .uri(LATEST_PATH, date.toString(), baseCurrency.toLowerCase(Locale.ROOT))
            .retrieve()
            .onStatus(
                status -> status.isError(),
                (request, response) -> {
                    int status = response.getStatusCode().value();

                    if (status == 404) {
                        throw new DateNotPublishedException();
                    }

                    throw new ExchangeProviderException(status);
                }
            )
            .body(JSON_OBJECT);
    }

    private ExchangeRateResponse toResponse(
        Map<String, Object> body,
        String baseCurrency,
        List<String> targetCurrencies,
        LocalDate today
    ) {
        if (body == null) {
            throw invalid("응답이 비어 있습니다.");
        }

        LocalDate rateDate;

        try {
            rateDate = body.get("date") instanceof String date ? LocalDate.parse(date) : null;
        } catch (DateTimeParseException exception) {
            rateDate = null;
        }

        if (rateDate == null) {
            throw invalid("date가 올바르지 않습니다.");
        }

        // 요청한 날짜(오늘 또는 전날)의 데이터만 받는다. 미래이거나 더 오래된 날짜는 잘못된 응답이다.
        if (rateDate.isAfter(today) || rateDate.isBefore(today.minusDays(1))) {
            throw invalid("date가 요청 범위(전날~오늘)를 벗어났습니다.");
        }

        if (!(body.get(baseCurrency.toLowerCase(Locale.ROOT)) instanceof Map<?, ?> baseRates)) {
            throw invalid("기준 통화의 환율이 없습니다.");
        }

        Map<String, BigDecimal> rates = new LinkedHashMap<>();

        for (String target : targetCurrencies) {
            BigDecimal rate = toRate(baseRates.get(target.toLowerCase(Locale.ROOT)));

            if (rate == null) {
                throw invalid("요청한 통화의 환율이 없거나 올바르지 않습니다.");
            }

            rates.put(target, rate);
        }

        return new ExchangeRateResponse(
            baseCurrency,
            rates,
            rateDate,
            LocalDateTime.now(),
            false,
            ExchangeRateResponse.SOURCE_CURRENCY_API
        );
    }

    private static BigDecimal toRate(Object value) {
        if (!(value instanceof Number number)) {
            return null;
        }

        double asDouble = number.doubleValue();

        if (!Double.isFinite(asDouble) || asDouble <= 0) {
            return null;
        }

        return new BigDecimal(number.toString());
    }

    private static ExchangeProviderException invalid(String reason) {
        return new ExchangeProviderException(
            new IllegalStateException("currency-api 최신 환율 " + reason)
        );
    }

    /** 요청한 날짜의 데이터가 아직 배포되지 않았다(404). */
    private static final class DateNotPublishedException extends RuntimeException {
        DateNotPublishedException() {
            super("currency-api date not published", null, false, false);
        }
    }
}
