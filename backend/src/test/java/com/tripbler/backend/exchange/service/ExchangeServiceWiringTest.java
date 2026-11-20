package com.tripbler.backend.exchange.service;

import static org.junit.jupiter.api.Assertions.*;

import java.util.function.Supplier;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.web.client.RestClient;

import com.tripbler.backend.exchange.client.CurrencyApiExchangeRateClient;
import com.tripbler.backend.exchange.client.FrankfurterExchangeRateClient;
import com.tripbler.backend.exchange.client.LatestRateFallbackClient;

/**
 * DB 없이 환율 빈만 띄워, 스프링이 ExchangeService에 Frankfurter와 대체 출처를 함께 연결하는지 확인한다.
 * 빈을 만들기만 하고 외부 API는 호출하지 않는다.
 */
class ExchangeServiceWiringTest {

    @Test
    void 대체_출처_클라이언트가_서비스에_연결된다() throws Exception {
        try (var context = new AnnotationConfigApplicationContext()) {
            Supplier<RestClient.Builder> builder = RestClient::builder;
            context.registerBean(RestClient.Builder.class, builder);
            context.register(
                FrankfurterExchangeRateClient.class,
                CurrencyApiExchangeRateClient.class,
                ExchangeResponseCache.class,
                ExchangeService.class
            );
            context.refresh();

            ExchangeService service = context.getBean(ExchangeService.class);
            var field = ExchangeService.class.getDeclaredField("fallbackClient");
            field.setAccessible(true);

            assertInstanceOf(CurrencyApiExchangeRateClient.class, field.get(service));
            assertSame(context.getBean(LatestRateFallbackClient.class), field.get(service));
        }
    }
}
