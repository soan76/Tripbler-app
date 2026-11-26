package com.tripbler.backend.translation.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;

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

/**
 * 동시 처리 자리(사용자별·전체)와 서비스의 전체 한도 차감 순서. 사용자·IP 한도는 인터셉터 몫이라 여기서는 쓰지 않는다
 * (실제 요청 경로는 PhotoTranslationLimitsIT). AI·Google·한도 판정은 대역이다.
 */
class PhotoTranslationLimitsTest {

    private static final byte[] IMAGE = new byte[] {1, 2, 3};

    /** block이 켜져 있으면 호출마다 entered를 하나 올리고 release가 열릴 때까지 붙잡는다. */
    private static final class BlockingAi implements PhotoTranslationClient {
        final Semaphore entered = new Semaphore(0);
        final CountDownLatch release = new CountDownLatch(1);
        volatile boolean block = true;
        volatile RuntimeException failure;

        @Override
        public Result translate(byte[] jpeg, String mediaType, List<PhotoTranslationRequest.Paragraph> paragraphs,
            String source, String target) {
            if (block) {
                entered.release();
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
    private PhotoTranslationSlots slots;
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
        service = serviceWith(googleOk(), new PhotoTranslationSlots(1, 1));
        executor = Executors.newCachedThreadPool();
    }

    @AfterEach
    void tearDown() {
        ai.release.countDown();
        executor.shutdownNow();
        converter.destroy();
    }

    private PhotoTranslationService serviceWith(LineTranslationClient google, PhotoTranslationSlots slots) {
        this.slots = slots;
        return new PhotoTranslationService(inspector, validator, ai, google, new PriceExtractor(), converter,
            rateLimiter, slots);
    }

    private static LineTranslationClient googleOk() {
        return (lines, source, target) -> new LineTranslationClient.Result("ja",
            lines.stream().map(line -> new LineTranslationClient.Line("구글", null)).toList());
    }

    private static PhotoTranslationRequest request() {
        return new PhotoTranslationRequest("ja", "ko", 1000, 800,
            List.of(new Paragraph("p1", "a", new Box(10, 10, 100, 30))));
    }

    private void run(String user) {
        service.translate(user, IMAGE, "image/jpeg", request());
    }

    private void run() {
        run("user-1");
    }

    private CompletableFuture<Void> runInBackground(String user) {
        return CompletableFuture.runAsync(() -> run(user), executor);
    }

    @Test
    void atGlobalCapacity_otherUserRejectedImmediately_thenAcceptedAfterRelease() throws Exception {
        CompletableFuture<Void> first = runInBackground("user-1");
        assertTrue(ai.entered.tryAcquire(5, TimeUnit.SECONDS));

        TooManyRequestsException rejected = assertThrows(TooManyRequestsException.class, () -> run("user-2"));
        assertEquals(3, rejected.getRetryAfterSeconds());

        ai.release.countDown();
        first.get(5, TimeUnit.SECONDS);

        ai.block = false;
        run("user-2"); // 자리가 돌아와 다시 받아진다
        assertEquals(0, slots.trackedUsers(), "끝난 사용자 항목은 지운다");
    }

    @Test
    void sameUserSecondConcurrentRequest_rejected_otherUserAccepted() throws Exception {
        service = serviceWith(googleOk(), new PhotoTranslationSlots(2, 1));

        CompletableFuture<Void> first = runInBackground("user-1");
        assertTrue(ai.entered.tryAcquire(5, TimeUnit.SECONDS));

        TooManyRequestsException rejected = assertThrows(TooManyRequestsException.class, () -> run("user-1"));
        assertEquals(3, rejected.getRetryAfterSeconds());

        // 자리 2개: 다른 사용자는 동시에 처리된다.
        CompletableFuture<Void> other = runInBackground("user-2");
        assertTrue(ai.entered.tryAcquire(5, TimeUnit.SECONDS), "두 요청이 동시에 AI 호출 중");

        ai.release.countDown();
        first.get(5, TimeUnit.SECONDS);
        other.get(5, TimeUnit.SECONDS);
        assertEquals(0, slots.trackedUsers());
    }

    @Test
    @SuppressWarnings("unchecked")
    void rejectedByCapacity_doesNotConsumeGlobal() throws Exception {
        CompletableFuture<Void> first = runInBackground("user-1");
        // 첫 요청은 전체 한도를 차감한 뒤 AI에 들어간다(entered가 그 뒤에 열린다).
        assertTrue(ai.entered.tryAcquire(5, TimeUnit.SECONDS));

        assertThrows(TooManyRequestsException.class, () -> run("user-2"));

        ArgumentCaptor<List<AuthRateLimiter.Key>> keys = ArgumentCaptor.forClass(List.class);
        verify(rateLimiter, times(1)).acquireKeys(keys.capture());
        assertEquals(List.of(RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_HOUR, RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_DAY),
            keys.getValue().stream().map(AuthRateLimiter.Key::bucket).toList());
        assertEquals(0, ai.entered.availablePermits(), "거절된 요청은 AI를 부르지 않는다");

        ai.release.countDown();
        first.get(5, TimeUnit.SECONDS);
    }

    @Test
    void order_validateThenSlotThenGlobalThenAi() {
        ai.block = false;
        PhotoTranslationSlots spySlots = spy(new PhotoTranslationSlots(1, 1));
        PhotoTranslationClient spyAi = spy(ai);
        service = new PhotoTranslationService(inspector, validator, spyAi, googleOk(), new PriceExtractor(),
            converter, rateLimiter, spySlots);

        run();

        InOrder order = inOrder(inspector, validator, spySlots, rateLimiter, spyAi);
        order.verify(inspector).inspect(any());
        order.verify(validator).validate(any(), any());
        order.verify(spySlots).acquire("user-1");
        order.verify(rateLimiter).acquireKeys(anyList());
        order.verify(spyAi).translate(any(), any(), any(), any(), any());
    }

    @Test
    void aiThrowsUnexpectedException_permitReturned() {
        ai.block = false;
        ai.failure = new IllegalStateException("boom");

        assertThrows(IllegalStateException.class, this::run);

        ai.failure = null;
        run();
        assertEquals(0, slots.trackedUsers());
    }

    @Test
    void fallbackFails_permitReturned() {
        ai.block = false;
        ai.failure = new TranslationProviderException();
        service = serviceWith((lines, source, target) -> {
            throw new TranslationProviderException();
        }, new PhotoTranslationSlots(1, 1));

        // 두 번 모두 자리 부족(429)이 아니라 번역 실패(503)여야 자리가 돌아온 것이다.
        for (int i = 0; i < 2; i++) {
            BusinessException exception = assertThrows(BusinessException.class, this::run);
            assertEquals(ErrorCode.TRANSLATION_PROVIDER_UNAVAILABLE, exception.getErrorCode());
        }
    }

    @Test
    void globalLimitExceeded_permitReturned() {
        ai.block = false;
        // 호출 1: 전체 한도 거절. 호출 2: 통과.
        doThrow(new TooManyRequestsException(30)).doNothing().when(rateLimiter).acquireKeys(anyList());

        TooManyRequestsException rejected = assertThrows(TooManyRequestsException.class, this::run);
        assertEquals(30, rejected.getRetryAfterSeconds());
        run();
    }

    @Test
    void validationFailure_takesNoSlotAndNoGlobal() {
        doThrow(new BusinessException(ErrorCode.INVALID_REQUEST, "x")).when(validator).validate(any(), any());

        assertThrows(BusinessException.class, this::run);

        verifyNoInteractions(rateLimiter);
        assertEquals(0, slots.trackedUsers());

        // 자리를 잡지 않았으므로 바로 다음 요청이 받아진다.
        doNothing().when(validator).validate(any(), any());
        ai.block = false;
        run();
    }

    @Test
    void validRequest_consumesGlobalOnly() {
        ai.block = false;

        run();

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<AuthRateLimiter.Key>> keys = ArgumentCaptor.forClass(List.class);
        verify(rateLimiter, times(1)).acquireKeys(keys.capture());
        assertEquals(List.of(
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_HOUR, "*"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_DAY, "*")), keys.getValue());
    }
}
