package com.tripbler.backend.common.ratelimit;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.TooManyRequestsException;

class AuthRateLimiterTest {

    private static final String IP = "10.0.0.1";
    private static final String EMAIL = "user@gmail.com";

    private final MutableClock clock = new MutableClock(Instant.parse("2026-11-12T00:00:00Z"));

    private AuthRateLimiter limiter(int capacity) {
        return new AuthRateLimiter(clock, capacity);
    }

    private long retryAfter(Runnable request) {
        TooManyRequestsException exception = assertThrows(TooManyRequestsException.class, request::run);
        assertEquals(ErrorCode.TOO_MANY_REQUESTS, exception.getErrorCode());
        return exception.getRetryAfterSeconds();
    }

    @Test
    void allowsUpToMaxThenRejectsWithRetryAfter() {
        AuthRateLimiter limiter = limiter(100);

        for (int i = 0; i < 10; i++) {
            limiter.acquire(RateLimitBucket.LOGIN_IP, IP);
        }

        assertEquals(60, retryAfter(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, IP)));
    }

    @Test
    void passesExactlyAtAllowedTime() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 10; i++) {
            limiter.acquire(RateLimitBucket.LOGIN_IP, IP);
        }
        clock.advance(Duration.ofSeconds(59));
        assertEquals(1, retryAfter(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, IP)));

        clock.advance(Duration.ofSeconds(1));

        assertDoesNotThrow(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, IP));
    }

    @Test
    void emailMinIntervalBoundary() {
        AuthRateLimiter limiter = limiter(100);
        limiter.acquireSendCode(IP, EMAIL);

        clock.advance(Duration.ofSeconds(59));
        assertEquals(1, retryAfter(() -> limiter.acquireSendCode("10.0.0.2", EMAIL)));

        clock.advance(Duration.ofSeconds(1));
        assertDoesNotThrow(() -> limiter.acquireSendCode("10.0.0.2", EMAIL));
    }

    @Test
    void emailHourlyLimitBoundary() {
        AuthRateLimiter limiter = limiter(100);
        // IP 한도(10분 5회)에 걸리지 않도록 매번 다른 IP를 쓴다.
        for (int i = 0; i < 5; i++) {
            limiter.acquireSendCode("10.0.1." + i, EMAIL);
            clock.advance(Duration.ofSeconds(60));
        }
        // 첫 발송은 5분 전, 60분이 되려면 55분 남음
        assertEquals(55 * 60, retryAfter(() -> limiter.acquireSendCode("10.0.2.1", EMAIL)));

        clock.advance(Duration.ofMinutes(55));
        assertDoesNotThrow(() -> limiter.acquireSendCode("10.0.2.1", EMAIL));
    }

    @Test
    void normalizesEmailAcrossFlows() {
        AuthRateLimiter limiter = limiter(100);
        List<String> variants = List.of(
            " User@Gmail.com ", "user@gmail.com", "USER@GMAIL.COM", "user@Gmail.com ", "\tuser@gmail.com"
        );
        for (int i = 0; i < variants.size(); i++) {
            limiter.acquireSendCode("10.0.3." + i, variants.get(i));
            clock.advance(Duration.ofSeconds(61));
        }

        retryAfter(() -> limiter.acquireSendCode("10.0.4.1", "user@gmail.com"));
    }

    @Test
    void sendCodeReturnsLongerWaitWhenBothLimited() {
        AuthRateLimiter limiter = limiter(100);
        // IP: 다른 이메일로 5회 → 10분 한도 소진
        for (int i = 0; i < 5; i++) {
            limiter.acquireSendCode(IP, "other" + i + "@gmail.com");
        }
        clock.advance(Duration.ofSeconds(30));
        // 이메일: 다른 IP로 한 번 보내 60초 간격 시작
        limiter.acquireSendCode("10.0.9.9", EMAIL);

        // IP는 570초, 이메일은 60초 남음 → 긴 쪽
        assertEquals(570, retryAfter(() -> limiter.acquireSendCode(IP, EMAIL)));
    }

    @Test
    void rejectionByOneLimitDoesNotConsumeTheOther() {
        AuthRateLimiter limiter = limiter(100);
        limiter.acquireSendCode("10.0.9.9", EMAIL);

        // 이메일 간격으로 거절 → IP 횟수는 그대로여야 한다
        retryAfter(() -> limiter.acquireSendCode(IP, EMAIL));
        for (int i = 0; i < 5; i++) {
            limiter.acquireSendCode(IP, "fresh" + i + "@gmail.com");
        }

        // IP 한도로 거절 → 새 이메일 횟수는 그대로여야 한다
        retryAfter(() -> limiter.acquireSendCode(IP, "untouched@gmail.com"));
        assertDoesNotThrow(() -> limiter.acquireSendCode("10.0.8.8", "untouched@gmail.com"));
    }

    @Test
    void bucketsAreIndependent() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 10; i++) {
            limiter.acquire(RateLimitBucket.LOGIN_IP, IP);
        }

        assertDoesNotThrow(() -> limiter.acquire(RateLimitBucket.SESSION_IP, IP));
    }

    @Test
    void retryAfterRoundsUpSubSecond() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 10; i++) {
            limiter.acquire(RateLimitBucket.LOGIN_IP, IP);
        }

        clock.advance(Duration.ofMillis(59_800));

        assertEquals(1, retryAfter(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, IP)));
    }

    @Test
    void fullCapacityRejectsNewKeyUntilEarliestExpires() {
        AuthRateLimiter limiter = limiter(2);
        limiter.acquire(RateLimitBucket.LOGIN_IP, "a");
        clock.advance(Duration.ofSeconds(10));
        limiter.acquire(RateLimitBucket.LOGIN_IP, "b");

        assertEquals(50, retryAfter(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, "c")));

        clock.advance(Duration.ofSeconds(50));
        assertDoesNotThrow(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, "c"));

        // 기존 키 b의 기록은 유지된다: 9번 더 보내면 한도
        for (int i = 0; i < 9; i++) {
            limiter.acquire(RateLimitBucket.LOGIN_IP, "b");
        }
        retryAfter(() -> limiter.acquire(RateLimitBucket.LOGIN_IP, "b"));
    }

    private static final List<RateLimitBucket> PLACE_SEARCH = List.of(
        RateLimitBucket.PLACE_SEARCH_USER_MINUTE,
        RateLimitBucket.PLACE_SEARCH_USER_HOUR
    );

    private static final List<RateLimitBucket> PLACE_DETAILS = List.of(
        RateLimitBucket.PLACE_DETAILS_USER_MINUTE,
        RateLimitBucket.PLACE_DETAILS_USER_HOUR
    );

    @Test
    void 장소_검색은_1분_10회까지_허용한다() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 10; i++) {
            limiter.acquireAll("u1", PLACE_SEARCH);
        }

        assertEquals(60, retryAfter(() -> limiter.acquireAll("u1", PLACE_SEARCH)));
    }

    @Test
    void 장소_검색은_1시간_100회까지_허용한다() {
        AuthRateLimiter limiter = limiter(100);
        // 6초 간격이면 1분 창은 넘지 않는다.
        for (int i = 0; i < 100; i++) {
            limiter.acquireAll("u1", PLACE_SEARCH);
            clock.advance(Duration.ofSeconds(6));
        }

        // 첫 요청(0초)에서 60분이 되려면 600초가 지난 지금 3000초 남음
        assertEquals(3000, retryAfter(() -> limiter.acquireAll("u1", PLACE_SEARCH)));

        clock.advance(Duration.ofSeconds(3000));
        assertDoesNotThrow(() -> limiter.acquireAll("u1", PLACE_SEARCH));
    }

    @Test
    void 장소_상세는_1분_20회와_1시간_200회까지_허용한다() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 20; i++) {
            limiter.acquireAll("u1", PLACE_DETAILS);
        }
        assertEquals(60, retryAfter(() -> limiter.acquireAll("u1", PLACE_DETAILS)));

        AuthRateLimiter hourly = limiter(100);
        clock.advance(Duration.ofHours(2));
        // 3초 간격이면 1분 창은 넘지 않는다.
        for (int i = 0; i < 200; i++) {
            hourly.acquireAll("u2", PLACE_DETAILS);
            clock.advance(Duration.ofSeconds(3));
        }
        assertEquals(3000, retryAfter(() -> hourly.acquireAll("u2", PLACE_DETAILS)));
    }

    @Test
    void 사용자와_종류별로_따로_센다() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 10; i++) {
            limiter.acquireAll("u1", PLACE_SEARCH);
        }
        retryAfter(() -> limiter.acquireAll("u1", PLACE_SEARCH));

        assertDoesNotThrow(() -> limiter.acquireAll("u2", PLACE_SEARCH));
        assertDoesNotThrow(() -> limiter.acquireAll("u1", PLACE_DETAILS));
    }

    @Test
    void 한_창이_거절하면_다른_창도_기록하지_않는다() {
        AuthRateLimiter limiter = limiter(100);
        for (int i = 0; i < 10; i++) {
            limiter.acquireAll("u1", PLACE_SEARCH);
        }
        // 1분 창에 걸린 요청 5번: 1시간 창에도 기록되면 아래에서 100회 전에 막힌다.
        for (int i = 0; i < 5; i++) {
            retryAfter(() -> limiter.acquireAll("u1", PLACE_SEARCH));
        }

        clock.advance(Duration.ofSeconds(60));
        for (int i = 0; i < 90; i++) {
            assertDoesNotThrow(() -> limiter.acquireAll("u1", PLACE_SEARCH));
            clock.advance(Duration.ofSeconds(6));
        }
        retryAfter(() -> limiter.acquireAll("u1", PLACE_SEARCH));
    }

    // 장소 전역 상한: 서버 전체에서 하나의 키("*")로 센다. PlaceService와 같은 조합으로 판정한다.
    private static final String GLOBAL = "*";

    private static void search(AuthRateLimiter limiter, String user) {
        limiter.acquireKeys(List.of(
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_SEARCH_USER_MINUTE, user),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_SEARCH_USER_HOUR, user),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_SEARCH_USER_DAY, user),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_SEARCH_GLOBAL_HOUR, GLOBAL),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_SEARCH_GLOBAL_DAY, GLOBAL)
        ));
    }

    private static void details(AuthRateLimiter limiter, String user) {
        limiter.acquireKeys(List.of(
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_DETAILS_USER_MINUTE, user),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_DETAILS_USER_HOUR, user),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_DETAILS_USER_DAY, user),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_DETAILS_GLOBAL_HOUR, GLOBAL),
            new AuthRateLimiter.Key(RateLimitBucket.PLACE_DETAILS_GLOBAL_DAY, GLOBAL)
        ));
    }

    // 전역 1시간 한도에 걸리지 않게 1시간마다 perHour명씩 batches번 채운다. 끝나면 시계는 batches시간 뒤다.
    private void fillGlobalDay(AuthRateLimiter limiter, boolean detailsKind, int perHour, int batches) {
        for (int batch = 0; batch < batches; batch++) {
            for (int i = 0; i < perHour; i++) {
                String user = "g" + batch + "-" + i;
                if (detailsKind) {
                    details(limiter, user);
                } else {
                    search(limiter, user);
                }
            }
            clock.advance(Duration.ofHours(1));
        }
    }

    @Test
    void 장소_검색_전역_하루_1000회를_넘으면_다른_사용자도_거절한다() {
        AuthRateLimiter limiter = limiter(10_000);
        fillGlobalDay(limiter, false, 125, 8);

        // 지금은 8시간 뒤, 첫 기록(0시)에서 24시간이 되려면 16시간 남음(전역 1시간 창은 비어 있다)
        assertEquals(16 * 3600, retryAfter(() -> search(limiter, "newcomer")));

        clock.advance(Duration.ofHours(16));
        assertDoesNotThrow(() -> search(limiter, "newcomer"));
    }

    @Test
    void 장소_상세_전역_하루_2000회를_넘으면_다른_사용자도_거절한다() {
        AuthRateLimiter limiter = limiter(10_000);
        fillGlobalDay(limiter, true, 250, 8);

        assertEquals(16 * 3600, retryAfter(() -> details(limiter, "newcomer")));

        clock.advance(Duration.ofHours(16));
        assertDoesNotThrow(() -> details(limiter, "newcomer"));
    }

    @Test
    void 장소_검색은_사용자_하루_50회까지_허용한다() {
        AuthRateLimiter limiter = limiter(100);
        // 10분 간격: 1분 10회·1시간 100회·전역 1시간 125회에 걸리지 않는다.
        for (int i = 0; i < 50; i++) {
            search(limiter, "u1");
            clock.advance(Duration.ofMinutes(10));
        }

        // 지금은 500분, 첫 기록(0분)에서 24시간이 되려면 940분 남음
        assertEquals(940 * 60, retryAfter(() -> search(limiter, "u1")));
        assertDoesNotThrow(() -> search(limiter, "u2"));

        clock.advance(Duration.ofMinutes(940));
        assertDoesNotThrow(() -> search(limiter, "u1"));
    }

    @Test
    void 장소_상세는_사용자_하루_100회까지_허용한다() {
        AuthRateLimiter limiter = limiter(100);
        // 5분 간격: 1분 20회·1시간 200회·전역 1시간 250회에 걸리지 않는다.
        for (int i = 0; i < 100; i++) {
            details(limiter, "u1");
            clock.advance(Duration.ofMinutes(5));
        }

        assertEquals(940 * 60, retryAfter(() -> details(limiter, "u1")));
        assertDoesNotThrow(() -> details(limiter, "u2"));

        clock.advance(Duration.ofMinutes(940));
        assertDoesNotThrow(() -> details(limiter, "u1"));
    }

    @Test
    void 장소_검색_전역_1시간_125회를_넘으면_다른_사용자도_거절한다() {
        AuthRateLimiter limiter = limiter(10_000);
        for (int i = 0; i < 125; i++) {
            search(limiter, "g" + i);
        }
        clock.advance(Duration.ofMinutes(10));

        long retryAfter = retryAfter(() -> search(limiter, "newcomer"));
        assertEquals(50 * 60, retryAfter);
        assertTrue(retryAfter <= 3600);

        clock.advance(Duration.ofMinutes(50));
        assertDoesNotThrow(() -> search(limiter, "newcomer"));
    }

    @Test
    void 장소_상세_전역_1시간_250회를_넘으면_다른_사용자도_거절한다() {
        AuthRateLimiter limiter = limiter(10_000);
        for (int i = 0; i < 250; i++) {
            details(limiter, "g" + i);
        }
        clock.advance(Duration.ofMinutes(10));

        long retryAfter = retryAfter(() -> details(limiter, "newcomer"));
        assertEquals(50 * 60, retryAfter);
        assertTrue(retryAfter <= 3600);

        clock.advance(Duration.ofMinutes(50));
        assertDoesNotThrow(() -> details(limiter, "newcomer"));
    }

    @Test
    void 계정_하나로는_전역_하루_한도를_채울_수_없다() {
        AuthRateLimiter limiter = limiter(100);
        // 하루(0분~1439분) 동안 1분마다 한 번씩 시도한다. 사용자 1분·1시간과 전역 1시간에는 걸리지 않는다.
        int successes = 0;
        for (int minute = 0; minute < 1440; minute++) {
            try {
                search(limiter, "u1");
                successes++;
            } catch (TooManyRequestsException exception) {
                // 사용자 하루 한도
            }
            if (minute < 1439) {
                clock.advance(Duration.ofMinutes(1));
            }
        }
        assertEquals(50, successes);

        // 전역 하루 사용량은 50이다: 전역 묶음만 직접 확인하면 950번 더 허용되고 그다음 거절된다.
        for (int i = 0; i < 950; i++) {
            limiter.acquire(RateLimitBucket.PLACE_SEARCH_GLOBAL_DAY, GLOBAL);
        }
        retryAfter(() -> limiter.acquire(RateLimitBucket.PLACE_SEARCH_GLOBAL_DAY, GLOBAL));
    }

    @Test
    void 사용자_한도로_거절된_요청은_전역_사용량을_늘리지_않는다() {
        AuthRateLimiter limiter = limiter(10_000);
        for (int i = 0; i < 10; i++) {
            search(limiter, "u1");
        }
        // 사용자 1분 한도로 5번 거절: 전역 1시간 창에 기록되면 아래 115명 중 마지막 5명이 막힌다.
        for (int i = 0; i < 5; i++) {
            retryAfter(() -> search(limiter, "u1"));
        }

        for (int i = 0; i < 115; i++) {
            String user = "g" + i;
            assertDoesNotThrow(() -> search(limiter, user));
        }
        retryAfter(() -> search(limiter, "newcomer"));
    }

    @Test
    void 전역_한도로_거절된_요청은_사용자_사용량을_늘리지_않는다() {
        AuthRateLimiter limiter = limiter(10_000);
        fillGlobalDay(limiter, false, 125, 8);
        // 지금은 8시간 뒤. 전역 하루 창이 열리기 30초 전으로 옮긴다.
        clock.advance(Duration.ofHours(16).minusSeconds(30));
        // 전역 한도로 5번 거절: u1의 1분 창에 기록되면 30초 뒤 10회 중 6번째에서 막힌다.
        for (int i = 0; i < 5; i++) {
            retryAfter(() -> search(limiter, "u1"));
        }

        clock.advance(Duration.ofSeconds(30));
        for (int i = 0; i < 10; i++) {
            assertDoesNotThrow(() -> search(limiter, "u1"));
        }
        retryAfter(() -> search(limiter, "u1"));
    }

    @Test
    void concurrentGlobalAndUserKeysReserveOnce() throws Exception {
        AuthRateLimiter limiter = limiter(10_000);
        for (int i = 0; i < 124; i++) {
            search(limiter, "g" + i);
        }
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Future<Boolean>> futures = new ArrayList<>();
            for (int i = 0; i < 2; i++) {
                String user = "racer" + i;
                futures.add(executor.submit(() -> {
                    start.await();
                    try {
                        search(limiter, user);
                        return true;
                    } catch (TooManyRequestsException exception) {
                        return false;
                    }
                }));
            }
            start.countDown();
            int successes = 0;
            for (Future<Boolean> future : futures) {
                if (future.get(10, TimeUnit.SECONDS)) {
                    successes++;
                }
            }
            assertEquals(1, successes);
        } finally {
            executor.shutdownNow();
        }
    }

    // 전역 한도 WARN은 버킷이 거절 상태로 바뀔 때 한 번만 남긴다. 운영 코드는 그대로 두고 로그를 붙잡아 확인한다.
    private static ListAppender<ILoggingEvent> captureLimiterLogs() {
        Logger logger = (Logger) LoggerFactory.getLogger(AuthRateLimiter.class);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        return appender;
    }

    private static void detach(ListAppender<ILoggingEvent> appender) {
        ((Logger) LoggerFactory.getLogger(AuthRateLimiter.class)).detachAppender(appender);
    }

    private static List<ILoggingEvent> globalWarnings(ListAppender<ILoggingEvent> appender) {
        return appender.list.stream()
            .filter(event -> event.getLevel() == Level.WARN)
            .filter(event -> event.getFormattedMessage().contains("서버 전체 요청 한도"))
            .toList();
    }

    @Test
    void 전역_한도_WARN은_거절_상태로_바뀔_때_한_번만_남긴다() {
        AuthRateLimiter limiter = limiter(10_000);
        ListAppender<ILoggingEvent> appender = captureLimiterLogs();
        try {
            for (int i = 0; i < 125; i++) {
                search(limiter, "g" + i);
            }
            assertEquals(0, globalWarnings(appender).size());

            // 계속 거절되는 동안에는 한 번만 남긴다.
            for (int i = 0; i < 5; i++) {
                retryAfter(() -> search(limiter, "secret-user-id"));
            }
            List<ILoggingEvent> first = globalWarnings(appender);
            assertEquals(1, first.size());
            String message = first.get(0).getFormattedMessage();
            assertTrue(message.contains("PLACE_SEARCH_GLOBAL_HOUR"), message);
            assertFalse(message.contains("secret-user-id"), message);

            // 다시 허용된 뒤 또 걸리면 그때 한 번 더 남긴다.
            clock.advance(Duration.ofHours(1));
            assertDoesNotThrow(() -> search(limiter, "after"));
            for (int i = 0; i < 124; i++) {
                search(limiter, "h" + i);
            }
            for (int i = 0; i < 3; i++) {
                String user = "late" + i;
                retryAfter(() -> search(limiter, user));
            }
            assertEquals(2, globalWarnings(appender).size());
        } finally {
            detach(appender);
        }
    }

    @Test
    void 사용자_한도_거절은_전역_WARN을_남기지_않는다() {
        AuthRateLimiter limiter = limiter(100);
        ListAppender<ILoggingEvent> appender = captureLimiterLogs();
        try {
            for (int i = 0; i < 10; i++) {
                search(limiter, "u1");
            }
            for (int i = 0; i < 3; i++) {
                retryAfter(() -> search(limiter, "u1"));
            }
            assertEquals(0, globalWarnings(appender).size());
        } finally {
            detach(appender);
        }
    }

    @Test
    void concurrentSendCodeReservesOnce() throws Exception {
        AuthRateLimiter limiter = limiter(100);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Future<Boolean>> futures = new ArrayList<>();
            for (int i = 0; i < 2; i++) {
                futures.add(executor.submit(() -> {
                    start.await();
                    try {
                        limiter.acquireSendCode(IP, EMAIL);
                        return true;
                    } catch (TooManyRequestsException exception) {
                        return false;
                    }
                }));
            }
            start.countDown();
            int successes = 0;
            for (Future<Boolean> future : futures) {
                if (future.get(10, TimeUnit.SECONDS)) {
                    successes++;
                }
            }
            assertEquals(1, successes);
        } finally {
            executor.shutdownNow();
        }
    }

    private static final class MutableClock extends Clock {

        private Instant now;

        MutableClock(Instant now) {
            this.now = now;
        }

        void advance(Duration duration) {
            now = now.plus(duration);
        }

        @Override
        public ZoneId getZone() {
            return ZoneId.of("UTC");
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
