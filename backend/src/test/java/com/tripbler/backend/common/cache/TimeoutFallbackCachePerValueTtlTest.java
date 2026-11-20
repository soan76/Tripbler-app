package com.tripbler.backend.common.cache;

import static org.junit.jupiter.api.Assertions.*;

import java.net.SocketTimeoutException;
import java.time.*;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

/** 값별 TTL과 peek. */
class TimeoutFallbackCachePerValueTtlTest {
    private static final class MutableClock extends Clock {
        Instant now = Instant.parse("2026-11-21T00:00:00Z");
        public ZoneId getZone() { return ZoneOffset.UTC; }
        public Clock withZone(ZoneId zone) { return this; }
        public Instant instant() { return now; }
        void advance(Duration duration) { now = now.plus(duration); }
    }
    private record Value(int price, boolean shortLived, boolean stale) {
        Value asStale() { return new Value(price, shortLived, true); }
    }
    private static Duration ttlOf(Value value) {
        return value.shortLived() ? Duration.ofMinutes(1) : Duration.ofMinutes(5);
    }
    private static RuntimeException timeout() { return new RuntimeException(new SocketTimeoutException()); }

    @Test void 값별_TTL이_적용된다() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofMinutes(5), Duration.ofDays(3), 8);
        AtomicInteger calls = new AtomicInteger();

        cache.get("K", () -> { calls.incrementAndGet(); return new Value(1, true, false); },
            Value::asStale, TimeoutFallbackCachePerValueTtlTest::ttlOf);
        clock.advance(Duration.ofSeconds(59));
        cache.get("K", () -> { calls.incrementAndGet(); return new Value(2, false, false); },
            Value::asStale, TimeoutFallbackCachePerValueTtlTest::ttlOf);
        assertEquals(1, calls.get());

        clock.advance(Duration.ofSeconds(1));
        Value reloaded = cache.get("K", () -> { calls.incrementAndGet(); return new Value(2, false, false); },
            Value::asStale, TimeoutFallbackCachePerValueTtlTest::ttlOf);
        assertEquals(2, calls.get());
        assertEquals(2, reloaded.price());

        // 새로 받은 값은 자기 TTL(5분)을 쓴다.
        clock.advance(Duration.ofMinutes(4).plusSeconds(59));
        assertEquals(2, cache.get("K", () -> { calls.incrementAndGet(); return new Value(3, false, false); },
            Value::asStale, TimeoutFallbackCachePerValueTtlTest::ttlOf).price());
        assertEquals(2, calls.get());
    }

    @Test void 짧은_TTL_값도_stale_허용_기간은_만료_시각부터_센다() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofMinutes(5), Duration.ofDays(3), 8);
        cache.get("K", () -> new Value(1, true, false), Value::asStale, TimeoutFallbackCachePerValueTtlTest::ttlOf);

        clock.advance(Duration.ofMinutes(1).plus(Duration.ofDays(3)).minusSeconds(1));
        assertTrue(cache.get("K", () -> { throw timeout(); }, Value::asStale,
            TimeoutFallbackCachePerValueTtlTest::ttlOf).stale());

        clock.advance(Duration.ofSeconds(16));
        assertThrows(RuntimeException.class, () -> cache.get("K", () -> { throw timeout(); },
            Value::asStale, TimeoutFallbackCachePerValueTtlTest::ttlOf));
    }

    @Test void 기존_get은_고정_TTL을_그대로_쓴다() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofMinutes(5), Duration.ofDays(3), 8);
        AtomicInteger calls = new AtomicInteger();
        cache.get("K", () -> { calls.incrementAndGet(); return new Value(1, true, false); }, Value::asStale);

        clock.advance(Duration.ofMinutes(4).plusSeconds(59));
        cache.get("K", () -> { calls.incrementAndGet(); return new Value(2, true, false); }, Value::asStale);
        assertEquals(1, calls.get());

        clock.advance(Duration.ofSeconds(1));
        cache.get("K", () -> { calls.incrementAndGet(); return new Value(2, true, false); }, Value::asStale);
        assertEquals(2, calls.get());
    }

    @Test void peek은_슬롯을_만들지_않고_만료된_값도_돌려준다() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofMinutes(5), Duration.ofDays(3), 1);
        assertNull(cache.peek("A"));

        cache.get("B", () -> new Value(1, false, false), Value::asStale);
        // 용량 1인데 peek("A")가 슬롯을 만들었다면 B가 밀려났을 것이다.
        assertNull(cache.peek("A"));
        clock.advance(Duration.ofDays(10));
        assertEquals(new Value(1, false, false), cache.peek("B"));
    }

    @Test void 로더_안에서_같은_키를_peek해도_막히지_않는다() {
        var clock = new MutableClock();
        var cache = new TimeoutFallbackCache<String, Value>(clock, Duration.ofMinutes(5), Duration.ofDays(3), 8);
        cache.get("K", () -> new Value(1, false, false), Value::asStale);
        clock.advance(Duration.ofMinutes(5));

        Value loaded = cache.get("K", () -> new Value(cache.peek("K").price() + 1, false, false), Value::asStale);

        assertEquals(2, loaded.price());
    }
}
