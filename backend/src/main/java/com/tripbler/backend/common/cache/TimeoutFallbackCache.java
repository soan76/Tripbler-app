package com.tripbler.backend.common.cache;

import java.time.*;
import java.util.*;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.function.UnaryOperator;

/**
 * 성공값만 보관한다. 일시적 장애(ProviderFailures.isTransient)일 때만 마지막 성공값으로 fallback하며,
 * fallback은 원래 TTL과 조회 시각을 연장하지 않는다.
 */
public final class TimeoutFallbackCache<K, V> {
    private static final class Slot<V> {
        V value;
        Instant expiresAt;
        Instant retryAt = Instant.MIN;
    }
    private final Map<K, Slot<V>> slots = new LinkedHashMap<>(16, .75f, true);
    private final Clock clock;
    private final Duration ttl;
    private final Duration staleWindow;
    private final int capacity;

    public TimeoutFallbackCache(Clock clock, Duration ttl, Duration staleWindow, int capacity) {
        if (ttl.isNegative() || ttl.isZero() || staleWindow.isNegative() || capacity < 1) {
            throw new IllegalArgumentException("Invalid cache limits");
        }
        this.clock = clock; this.ttl = ttl; this.staleWindow = staleWindow; this.capacity = capacity;
    }

    private synchronized Slot<V> slot(K key) {
        Slot<V> found = slots.get(key);
        if (found != null) return found;
        if (slots.size() >= capacity) slots.remove(slots.keySet().iterator().next());
        Slot<V> created = new Slot<>();
        slots.put(key, created);
        return created;
    }

    public V get(K key, Supplier<V> loader, UnaryOperator<V> stale) {
        return get(key, loader, stale, value -> ttl);
    }

    /**
     * 값마다 TTL을 정한다. stale 허용 기간은 그 값의 만료 시각부터 센다.
     * loader는 이 키의 슬롯 lock을 잡은 채 실행되므로, loader 안에서 같은 키를 {@link #peek}하면
     * 같은 스레드의 재진입이라 막히지 않는다.
     */
    public V get(K key, Supplier<V> loader, UnaryOperator<V> stale, Function<? super V, Duration> ttlOf) {
        Slot<V> slot = slot(key);
        synchronized (slot) {
            Instant now = clock.instant();
            if (slot.value != null && now.isBefore(slot.expiresAt)) return slot.value;
            if (canFallback(slot, now) && now.isBefore(slot.retryAt)) return stale.apply(slot.value);
            try {
                V loaded = Objects.requireNonNull(loader.get());
                Duration loadedTtl = Objects.requireNonNull(ttlOf.apply(loaded));
                if (loadedTtl.isNegative() || loadedTtl.isZero()) throw new IllegalArgumentException("Invalid cache ttl");
                slot.value = loaded;
                slot.expiresAt = clock.instant().plus(loadedTtl);
                slot.retryAt = Instant.MIN;
                return loaded;
            } catch (RuntimeException failure) {
                if (!ProviderFailures.isTransient(failure) || !canFallback(slot, clock.instant())) throw failure;
                // 같은 키로 몰려온 요청이 장애 중인 제공자를 연속으로 호출하지 않도록 짧게 쉬고 재시도한다.
                slot.retryAt = clock.instant().plusSeconds(15);
                return stale.apply(slot.value);
            }
        }
    }

    /**
     * 마지막 성공값을 만료 여부와 관계없이 읽기만 한다. 슬롯을 만들지 않는다. 값이 없으면 null.
     * 캐시 lock을 놓은 뒤 슬롯 lock을 잡으므로(get과 같은 순서) 다른 키와 교착되지 않는다.
     * 다른 스레드가 같은 키를 불러오는 중이면 끝날 때까지 기다린다.
     */
    public V peek(K key) {
        Slot<V> slot;
        synchronized (this) { slot = slots.get(key); }
        if (slot == null) return null;
        synchronized (slot) { return slot.value; }
    }

    private boolean canFallback(Slot<V> slot, Instant now) {
        return slot.value != null && now.isBefore(slot.expiresAt.plus(staleWindow));
    }
}
