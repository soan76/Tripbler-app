package com.tripbler.backend.translation.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.common.ratelimit.RateLimitBucket;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.client.PhotoTranslationClient;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Box;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Paragraph;

/** 동시 처리 상한(M1)과 호출 제한 차감 순서(M2). AI·Google·한도 판정은 대역이다. */
class PhotoTranslationLimitsTest {

    private static final byte[] IMAGE = new byte[] {1, 2, 3};

    /** block이 켜져 있으면 호출이 들어올 때 entered를 내리고 release가 열릴 때까지 붙잡는다. */
    private static final class BlockingAi implements PhotoTranslationClient {
        final CountDownLatch entered = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        volatile boolean block = true;
        volatile RuntimeException failure;

        @Override
        public Result translate(byte[] jpeg, String mediaType, List<PhotoTranslationRequest.Paragraph> paragraphs,
            String source, String target) {
            if (block) {
                entered.countDown();
                try {
                    release.await(10, TimeUnit.SECONDS);
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                }
            }
            if (failure != null) throw failure;
            return new Result("ja", List.of(new PhotoTranslationClient.Paragraph("p1", "a", "번역", false, null,
                List.of())));
        }
    }

    private BlockingAi ai;
    private AuthRateLimiter rateLimiter;
    private PhotoRequestValidator validator;
    private KrwPriceConverter converter;
    private PhotoImageInspector inspector;
    private PhotoTranslationService service;
    private ExecutorService executor;

    @BeforeEach
    void setUp() {
        ai = new BlockingAi();
        rateLimiter = mock(AuthRateLimiter.class);
        validator = mock(PhotoRequestValidator.class);
        inspector = mock(PhotoImageInspector.class);
        when(inspector.inspect(any())).thenReturn(new PhotoImageInspector.Dimensions(1000, 800));
        converter = new KrwPriceConverter(mock(ExchangeService.class), Duration.ofSeconds(1));
        service = serviceWith(googleOk());
        executor = Executors.newCachedThreadPool();
    }

    @AfterEach
    void tearDown() {
        ai.release.countDown();
        executor.shutdownNow();
        converter.destroy();
    }

    private PhotoTranslationService serviceWith(LineTranslationClient google) {
        return new PhotoTranslationService(inspector, validator, ai, google, new PriceExtractor(), converter,
            rateLimiter, 1);
    }

    private static LineTranslationClient googleOk() {
        return (lines, source, target) -> new LineTranslationClient.Result("ja",
            lines.stream().map(line -> new LineTranslationClient.Line("구글", null)).toList());
    }

    private static PhotoTranslationRequest request() {
        return new PhotoTranslationRequest("ja", "ko", 1000, 800,
            List.of(new Paragraph("p1", "a", new Box(10, 10, 100, 30))));
    }

    private void run() {
        service.translate("user-1", "203.0.113.7", IMAGE, "image/jpeg", request());
    }

    private CompletableFuture<Void> runInBackground() {
        return CompletableFuture.runAsync(this::run, executor);
    }

    @Test
    void atCapacity_nextRequestRejectedImmediately_thenAcceptedAfterRelease() throws Exception {
        CompletableFuture<Void> first = runInBackground();
        assertTrue(ai.entered.await(5, TimeUnit.SECONDS));

        TooManyRequestsException rejected = assertThrows(TooManyRequestsException.class, this::run);
        assertEquals(3, rejected.getRetryAfterSeconds());

        ai.release.countDown();
        first.get(5, TimeUnit.SECONDS);

        ai.block = false;
        run(); // 자리가 돌아와 다시 받아진다
    }

    @Test
    @SuppressWarnings("unchecked")
    void rejectedByCapacity_consumesUserAndIpButNotGlobal() throws Exception {
        CompletableFuture<Void> first = runInBackground();
        assertTrue(ai.entered.await(5, TimeUnit.SECONDS));

        assertThrows(TooManyRequestsException.class, this::run);

        ArgumentCaptor<List<AuthRateLimiter.Key>> keys = ArgumentCaptor.forClass(List.class);
        // 첫 요청: 사용자·IP + 전체, 거절된 요청: 사용자·IP만 → 3번
        verify(rateLimiter, times(3)).acquireKeys(keys.capture());
        long globalCalls = keys.getAllValues().stream()
            .filter(list -> list.stream()
                .anyMatch(key -> key.bucket() == RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_HOUR))
            .count();
        assertEquals(1, globalCalls);

        ai.release.countDown();
        first.get(5, TimeUnit.SECONDS);
    }

    @Test
    void aiThrowsUnexpectedException_permitReturned() {
        ai.block = false;
        ai.failure = new IllegalStateException("boom");

        assertThrows(IllegalStateException.class, this::run);

        ai.failure = null;
        run();
    }

    @Test
    void fallbackFails_permitReturned() {
        ai.block = false;
        ai.failure = new TranslationProviderException();
        service = serviceWith((lines, source, target) -> {
            throw new TranslationProviderException();
        });

        // 두 번 모두 자리 부족(429)이 아니라 번역 실패(503)여야 자리가 돌아온 것이다.
        for (int i = 0; i < 2; i++) {
            BusinessException exception = assertThrows(BusinessException.class, this::run);
            assertEquals(ErrorCode.TRANSLATION_PROVIDER_UNAVAILABLE, exception.getErrorCode());
        }
    }

    @Test
    void globalLimitExceeded_permitReturned() {
        ai.block = false;
        // 호출 1: 사용자·IP 통과 → 전체 거절. 호출 2: 모두 통과.
        doNothing().doThrow(new TooManyRequestsException(30)).doNothing().when(rateLimiter).acquireKeys(anyList());

        assertThrows(TooManyRequestsException.class, this::run);
        run();
    }

    @Test
    @SuppressWarnings("unchecked")
    void validationFailure_consumesUserAndIpOnly_neverGlobal() {
        doThrow(new BusinessException(ErrorCode.INVALID_REQUEST, "x")).when(validator).validate(any(), any());

        assertThrows(BusinessException.class, this::run);

        ArgumentCaptor<List<AuthRateLimiter.Key>> keys = ArgumentCaptor.forClass(List.class);
        verify(rateLimiter, times(1)).acquireKeys(keys.capture());
        List<RateLimitBucket> buckets = keys.getValue().stream().map(AuthRateLimiter.Key::bucket).toList();
        assertEquals(List.of(
            RateLimitBucket.TRANSLATION_PHOTO_USER_MINUTE, RateLimitBucket.TRANSLATION_PHOTO_USER_DAY,
            RateLimitBucket.TRANSLATION_PHOTO_IP_MINUTE, RateLimitBucket.TRANSLATION_PHOTO_IP_DAY), buckets);
    }

    @Test
    @SuppressWarnings("unchecked")
    void validRequest_consumesUserIpAndGlobal() {
        ai.block = false;

        run();

        ArgumentCaptor<List<AuthRateLimiter.Key>> keys = ArgumentCaptor.forClass(List.class);
        verify(rateLimiter, times(2)).acquireKeys(keys.capture());
        List<RateLimitBucket> all = keys.getAllValues().stream()
            .flatMap(List::stream).map(AuthRateLimiter.Key::bucket).toList();
        assertEquals(6, all.size());
        assertTrue(all.contains(RateLimitBucket.TRANSLATION_PHOTO_USER_MINUTE));
        assertTrue(all.contains(RateLimitBucket.TRANSLATION_PHOTO_IP_DAY));
        assertTrue(all.contains(RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_HOUR));
        assertTrue(all.contains(RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_DAY));
    }
}
