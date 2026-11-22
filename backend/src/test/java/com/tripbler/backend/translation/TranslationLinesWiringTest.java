package com.tripbler.backend.translation;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

import java.util.function.Supplier;

import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;

import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.translation.client.ClaudeLineTranslationClient;
import com.tripbler.backend.translation.client.GoogleLineTranslationClient;
import com.tripbler.backend.translation.client.GoogleTranslationClient;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PriceExtractor;

/**
 * DB 없이 줄별 번역 빈만 띄워, 생성자가 여러 개인 Claude 클라이언트를 스프링이 공개 생성자로 만들고
 * 서비스에 연결하는지, 같은 인터페이스의 Google 대체 클라이언트와 함께 있어도 이름으로 구분해 주입되는지
 * 확인한다. 키가 없고 번역을 부르지 않으므로 외부 호출은 일어나지 않는다.
 */
class TranslationLinesWiringTest {

    @Test
    void 키가_없어도_빈이_만들어지고_서비스에_연결된다() {
        try (var context = new AnnotationConfigApplicationContext()) {
            Supplier<ExchangeService> exchange = () -> mock(ExchangeService.class);
            Supplier<AuthRateLimiter> limiter = () -> mock(AuthRateLimiter.class);
            context.registerBean(ExchangeService.class, exchange);
            context.registerBean(AuthRateLimiter.class, limiter);
            context.registerBean(GoogleTranslationClient.class, () -> mock(GoogleTranslationClient.class));
            context.register(
                ClaudeLineTranslationClient.class,
                GoogleLineTranslationClient.class,
                PriceExtractor.class,
                LineTranslationService.class
            );
            context.refresh();

            assertEquals(2, context.getBeansOfType(LineTranslationClient.class).size());
            assertInstanceOf(ClaudeLineTranslationClient.class, context.getBean("claudeLineTranslationClient"));
            assertInstanceOf(GoogleLineTranslationClient.class, context.getBean("googleLineTranslationClient"));
            assertNotNull(context.getBean(LineTranslationService.class));
        }
    }
}
