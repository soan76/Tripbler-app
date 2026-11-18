package com.tripbler.backend.common.cache;

import static org.junit.jupiter.api.Assertions.*;
import java.net.SocketTimeoutException;
import java.time.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class TimeoutFallbackCacheTest {
    private static final class MutableClock extends Clock {
        Instant now = Instant.parse("2026-10-07T00:00:00Z");
        public ZoneId getZone() { return ZoneOffset.UTC; }
        public Clock withZone(ZoneId zone) { return this; }
        public Instant instant() { return now; }
    }
    private record Value(int price, Instant fetchedAt, boolean stale) {
        Value asStale() { return new Value(price, fetchedAt, true); }
    }
    private RuntimeException timeout() { return new RuntimeException(new SocketTimeoutException()); }

    @Test void expiredSuccessSurvivesTimeoutWithoutExtendingTimestampOrFallbackDeadline() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofSeconds(60), Duration.ofMinutes(10), 8);
        var original = new Value(100, clock.instant(), false);
        cache.get("BTC", () -> original, Value::asStale);
        clock.now = clock.now.plusSeconds(60);
        AtomicInteger calls = new AtomicInteger();
        var stale = cache.get("BTC", () -> { calls.incrementAndGet(); throw timeout(); }, Value::asStale);
        assertTrue(stale.stale());
        assertEquals(original.fetchedAt(), stale.fetchedAt());
        assertEquals(stale, cache.get("BTC", () -> { calls.incrementAndGet(); throw timeout(); }, Value::asStale));
        assertEquals(1, calls.get());
        clock.now = original.fetchedAt().plusSeconds(660);
        assertThrows(RuntimeException.class, () -> cache.get("BTC", () -> { throw timeout(); }, Value::asStale));
    }

    static java.util.stream.Stream<RuntimeException> transientFailures() {
        return java.util.stream.Stream.of(
            new RuntimeException(new java.net.ConnectException("Connection refused")),
            new RuntimeException(new java.net.SocketException("Connection reset")),
            new RuntimeException(new java.net.UnknownHostException("api.example.com")),
            new RuntimeException(new ProviderFailures.TransientProviderFailure())
        );
    }

    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.MethodSource("transientFailures")
    void connectionFailureAndProviderOutageFallBackLikeTimeout(RuntimeException failure) {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofMinutes(5), Duration.ofDays(3), 8);
        var original = new Value(100, clock.instant(), false);
        cache.get("USD", () -> original, Value::asStale);
        clock.now = clock.now.plus(Duration.ofHours(1));
        AtomicInteger calls = new AtomicInteger();
        var stale = cache.get("USD", () -> { calls.incrementAndGet(); throw failure; }, Value::asStale);
        assertTrue(stale.stale());
        assertEquals(original.fetchedAt(), stale.fetchedAt());
        // 15초 재시도 억제도 시간 초과와 같게 적용된다.
        cache.get("USD", () -> { calls.incrementAndGet(); throw failure; }, Value::asStale);
        assertEquals(1, calls.get());
        // 허용 기간이 지나면 일시적 장애라도 실패를 그대로 돌려준다.
        clock.now = original.fetchedAt().plus(Duration.ofMinutes(5)).plus(Duration.ofDays(3));
        assertSame(failure, assertThrows(RuntimeException.class,
            () -> cache.get("USD", () -> { throw failure; }, Value::asStale)));
    }

    @Test void transientFailureWithoutCachedValueStillFails() {
        var cache = new TimeoutFallbackCache<String, Value>(new MutableClock(), Duration.ofSeconds(60), Duration.ofMinutes(10), 8);
        var failure = new RuntimeException(new java.net.ConnectException("Connection refused"));
        assertSame(failure, assertThrows(RuntimeException.class,
            () -> cache.get("USD", () -> { throw failure; }, Value::asStale)));
    }

    @Test void nonTimeoutAndColdTimeoutDoNotReturnAnotherKeysData() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofSeconds(60), Duration.ofMinutes(10), 8);
        cache.get("BTC", () -> new Value(100, clock.instant(), false), Value::asStale);
        clock.now = clock.now.plusSeconds(60);
        assertThrows(IllegalArgumentException.class, () -> cache.get("BTC", () -> { throw new IllegalArgumentException(); }, Value::asStale));
        assertThrows(RuntimeException.class, () -> cache.get("ETH", () -> { throw timeout(); }, Value::asStale));
        var recovered = cache.get("BTC", () -> new Value(200, clock.instant(), false), Value::asStale);
        assertEquals(200, recovered.price());
        assertFalse(recovered.stale());
    }
}
