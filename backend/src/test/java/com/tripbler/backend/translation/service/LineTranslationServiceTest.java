package com.tripbler.backend.translation.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.*;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.ExchangeProviderException;
import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.common.ratelimit.RateLimitBucket;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.dto.LineTranslationRequest;
import com.tripbler.backend.translation.dto.LineTranslationResponse;

/** 번역 제공자와 환율은 대역으로 대신한다. */
class LineTranslationServiceTest {

    private static final LocalDateTime FETCHED_AT = LocalDateTime.of(2026, 11, 22, 9, 30);

    private static final String IP = "203.0.113.7";

    /** 받은 요청을 기록하고, 줄마다 [prefix] + 원문, 발음 [pronunciation]을 돌려준다. */
    private static final class FakeClient implements LineTranslationClient {
        final List<List<String>> calls = new ArrayList<>();
        final String prefix;
        final String pronunciation;
        String detected = "ja";
        RuntimeException failure;

        FakeClient(String prefix, String pronunciation) {
            this.prefix = prefix;
            this.pronunciation = pronunciation;
        }

        @Override
        public Result translate(List<String> lines, String source, String target) {
            calls.add(lines);
            if (failure != null) throw failure;
            return new Result(detected, lines.stream().map(line -> new Line(prefix + line, pronunciation)).toList());
        }
    }

    private FakeClient client;
    private FakeClient fallbackClient;
    private ExchangeService exchangeService;
    private AuthRateLimiter rateLimiter;
    private LineTranslationService service;

    @BeforeEach
    void setUp() {
        client = new FakeClient("번역:", "발음");
        fallbackClient = new FakeClient("구글:", null);
        exchangeService = mock(ExchangeService.class);
        rateLimiter = mock(AuthRateLimiter.class);
        service = new LineTranslationService(client, fallbackClient, new PriceExtractor(), exchangeService, rateLimiter);
    }

    private static LineTranslationRequest request(String source, String... lines) {
        return new LineTranslationRequest(List.of(lines), source, "ko");
    }

    private static ExchangeRateResponse krw(String base, String rate, boolean stale) {
        return new ExchangeRateResponse(base, Map.of("KRW", new BigDecimal(rate)), LocalDate.of(2026, 11, 21),
            FETCHED_AT, stale);
    }

    @Test
    void 줄마다_번역과_발음을_순서대로_돌려주고_가격은_원화로_바꾼다() {
        when(exchangeService.getRates("JPY", "KRW")).thenReturn(krw("JPY", "9.245", false));

        LineTranslationResponse response = service.translate("user-1", IP,
            request("ja", " 醤油ラーメン 980円 ", "大盛り +150円", "食券は入口で"));

        assertEquals("ja", response.sourceLanguageCode());
        assertEquals("ko", response.targetLanguageCode());
        assertEquals(List.of("醤油ラーメン 980円", "大盛り +150円", "食券は入口で"), client.calls.get(0));

        LineTranslationResponse.TranslatedLine first = response.lines().get(0);
        assertEquals("醤油ラーメン 980円", first.original());
        assertEquals("번역:醤油ラーメン 980円", first.translated());
        assertEquals("발음", first.pronunciation());
        assertEquals("980円", first.price().text());
        assertEquals("JPY", first.price().currency());
        assertEquals(new BigDecimal("9060"), first.price().krwAmount()); // 980 × 9.245 = 9060.1
        assertEquals(new BigDecimal("9.245"), first.price().krwRate());
        assertEquals(FETCHED_AT, first.price().rateFetchedAt());
        assertFalse(first.price().rateStale());

        assertEquals(new BigDecimal("1387"), response.lines().get(1).price().krwAmount()); // 150 × 9.245 = 1386.75
        assertNull(response.lines().get(2).price());

        // 같은 통화는 한 번만 묻는다.
        verify(exchangeService, times(1)).getRates("JPY", "KRW");
    }

    @Test
    void 마지막_성공_환율을_쓰면_stale로_알린다() {
        when(exchangeService.getRates("JPY", "KRW")).thenReturn(krw("JPY", "9.2", true));

        assertTrue(service.translate("user-1", IP, request("ja", "ラーメン 980円")).lines().get(0).price().rateStale());
    }

    @Test
    void 원화_가격은_바꾸지_않고_환율도_묻지_않는다() {
        LineTranslationResponse.Price price = service.translate("user-1", IP, request("ko", "김밥 3,500원"))
            .lines().get(0).price();

        assertEquals("KRW", price.currency());
        assertNull(price.krwAmount());
        verifyNoInteractions(exchangeService);
    }

    @Test
    void 환율을_받지_못하면_원화_없이_번역은_돌려준다() {
        when(exchangeService.getRates("VND", "KRW")).thenThrow(new ExchangeProviderException(422));

        LineTranslationResponse response = service.translate("user-1", IP, request("vi", "Phở 45,000₫"));

        assertEquals("번역:Phở 45,000₫", response.lines().get(0).translated());
        assertEquals("VND", response.lines().get(0).price().currency());
        assertNull(response.lines().get(0).price().krwAmount());
    }

    @Test
    void 자동_감지면_감지한_언어로_엔과_위안을_가른다() {
        client.detected = "zh";
        when(exchangeService.getRates("CNY", "KRW")).thenReturn(krw("CNY", "190", false));

        LineTranslationResponse response = service.translate("user-1", IP, request("auto", "小笼包 ¥28"));

        assertEquals("zh", response.sourceLanguageCode());
        assertEquals("CNY", response.lines().get(0).price().currency());
    }

    @Test
    void 자동_감지인데_언어를_모르면_auto로_둔다() {
        client.detected = null;

        assertEquals("auto", service.translate("user-1", IP, request("auto", "hello")).sourceLanguageCode());
    }

    @Test
    void 전체_글자가_5000자를_넘으면_한도를_쓰지_않고_거절한다() {
        String line = "あ".repeat(200);
        String[] lines = Collections.nCopies(26, line).toArray(String[]::new); // 5200자

        BusinessException exception = assertThrows(BusinessException.class,
            () -> service.translate("user-1", IP, request("ja", lines)));

        assertEquals(ErrorCode.INVALID_REQUEST, exception.getErrorCode());
        verifyNoInteractions(rateLimiter);
        assertTrue(client.calls.isEmpty());
    }

    @Test
    void 사용자별_IP별_전체_한도를_함께_확인하고_넘으면_번역하지_않는다() {
        doThrow(new TooManyRequestsException(30)).when(rateLimiter).acquireKeys(anyList());

        assertThrows(TooManyRequestsException.class, () -> service.translate("user-1", IP, request("ja", "ラーメン")));
        assertTrue(client.calls.isEmpty());

        verify(rateLimiter).acquireKeys(List.of(
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_LINES_USER_MINUTE, "user-1"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_LINES_USER_DAY, "user-1"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_LINES_IP_MINUTE, IP),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_LINES_IP_DAY, IP),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_LINES_GLOBAL_HOUR, "*"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_LINES_GLOBAL_DAY, "*")
        ));
    }

    @Test
    void Claude가_성공하면_대체_경로를_부르지_않는다() {
        service.translate("user-1", IP, request("ja", "ラーメン"));

        assertEquals(1, client.calls.size());
        assertTrue(fallbackClient.calls.isEmpty());
    }

    @Test
    void Claude가_실패하면_Google로_대체하고_발음은_비운다() {
        when(exchangeService.getRates("JPY", "KRW")).thenReturn(krw("JPY", "9.245", false));
        client.failure = new TranslationProviderException();
        fallbackClient.detected = "ja";

        LineTranslationResponse response = service.translate("user-1", IP, request("auto", "醤油ラーメン 980円", "食券"));

        assertEquals(List.of(List.of("醤油ラーメン 980円", "食券")), fallbackClient.calls);
        assertEquals("ja", response.sourceLanguageCode());
        assertEquals("구글:醤油ラーメン 980円", response.lines().get(0).translated());
        assertNull(response.lines().get(0).pronunciation());
        // 가격·원화 환산은 대체 경로에서도 같다.
        assertEquals(new BigDecimal("9060"), response.lines().get(0).price().krwAmount());
        assertNull(response.lines().get(1).price());
    }

    @Test
    void Claude와_Google이_모두_실패하면_503_예외를_던진다() {
        client.failure = new TranslationProviderException();
        fallbackClient.failure = new TranslationProviderException();

        assertThrows(TranslationProviderException.class, () -> service.translate("user-1", IP, request("ja", "ラーメン")));
        assertEquals(1, fallbackClient.calls.size());
    }

    @Test
    void 제공자_예외가_아닌_오류는_대체하지_않는다() {
        client.failure = new IllegalStateException("bug");

        assertThrows(IllegalStateException.class, () -> service.translate("user-1", IP, request("ja", "ラーメン")));
        assertTrue(fallbackClient.calls.isEmpty());
    }

    @Test
    void 환율_응답에_KRW가_없으면_원화_없이_돌려준다() {
        when(exchangeService.getRates("THB", "KRW")).thenReturn(new ExchangeRateResponse("THB",
            Map.of("USD", new BigDecimal("0.03")), LocalDate.of(2026, 11, 21), FETCHED_AT, false));

        LineTranslationResponse.Price price = service.translate("user-1", IP, request("th", "Pad thai 60 บาท"))
            .lines().get(0).price();

        assertEquals("THB", price.currency());
        assertNull(price.krwAmount());
        assertNull(price.krwRate());
        assertNull(price.rateFetchedAt());
    }

    @Test
    void 환율_응답의_rates가_null이면_원화_없이_돌려준다() {
        when(exchangeService.getRates("JPY", "KRW")).thenReturn(new ExchangeRateResponse("JPY", null,
            LocalDate.of(2026, 11, 21), FETCHED_AT, false));

        LineTranslationResponse response = service.translate("user-1", IP, request("ja", "ラーメン 980円"));

        assertEquals("번역:ラーメン 980円", response.lines().get(0).translated());
        assertNull(response.lines().get(0).price().krwAmount());
    }

    @Test
    void 여러_통화는_통화마다_한_번씩만_묻는다() {
        when(exchangeService.getRates("JPY", "KRW")).thenReturn(krw("JPY", "9.245", false));
        when(exchangeService.getRates("USD", "KRW")).thenReturn(krw("USD", "1400", false));
        when(exchangeService.getRates("VND", "KRW")).thenThrow(new ExchangeProviderException(422));

        LineTranslationResponse response = service.translate("user-1", IP,
            request("auto", "ラーメン 980円", "Coke $2", "餃子 450円", "Beer $5", "Pho 45,000₫", "Banh mi 30,000₫"));

        assertEquals(new BigDecimal("2800"), response.lines().get(1).price().krwAmount());
        assertNull(response.lines().get(4).price().krwAmount());
        verify(exchangeService, times(1)).getRates("JPY", "KRW");
        verify(exchangeService, times(1)).getRates("USD", "KRW");
        // 실패한 통화도 요청 안에서 다시 묻지 않는다.
        verify(exchangeService, times(1)).getRates("VND", "KRW");
        verifyNoMoreInteractions(exchangeService);
    }

    @Test
    void 환율_조회가_대기_상한을_넘으면_그_통화만_원화_없이_바로_돌려준다() throws Exception {
        CountDownLatch release = new CountDownLatch(1);
        LineTranslationService shortBudget = new LineTranslationService(
            client, fallbackClient, new PriceExtractor(), exchangeService, rateLimiter, Duration.ofMillis(200));

        try {
            when(exchangeService.getRates("JPY", "KRW")).thenAnswer(invocation -> {
                release.await(10, TimeUnit.SECONDS);
                return krw("JPY", "9.245", false);
            });
            when(exchangeService.getRates("USD", "KRW")).thenReturn(krw("USD", "1400", false));

            long started = System.nanoTime();
            LineTranslationResponse response = shortBudget.translate("user-1", IP,
                request("auto", "ラーメン 980円", "Coke $2"));
            Duration elapsed = Duration.ofNanos(System.nanoTime() - started);

            assertTrue(elapsed.compareTo(Duration.ofSeconds(3)) < 0, "elapsed=" + elapsed);
            assertEquals("번역:ラーメン 980円", response.lines().get(0).translated());
            assertEquals("JPY", response.lines().get(0).price().currency());
            assertNull(response.lines().get(0).price().krwAmount());
            // 늦은 통화와 상관없이 다른 통화는 환산한다.
            assertEquals(new BigDecimal("2800"), response.lines().get(1).price().krwAmount());
        } finally {
            release.countDown();
            shortBudget.destroy();
        }
    }

    @Test
    void Claude와_Google이_모두_실패하면_환율은_묻지_않는다() {
        client.failure = new TranslationProviderException();
        fallbackClient.failure = new TranslationProviderException();

        assertThrows(TranslationProviderException.class,
            () -> service.translate("user-1", IP, request("ja", "ラーメン 980円")));
        verifyNoInteractions(exchangeService);
    }
}
