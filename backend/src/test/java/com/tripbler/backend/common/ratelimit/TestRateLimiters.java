package com.tripbler.backend.common.ratelimit;

import java.time.Clock;

// 테스트 전용: 다른 패키지의 테스트가 고정 시계로 제한기를 만들 수 있게 한다.
public final class TestRateLimiters {

    private TestRateLimiters() {
    }

    public static AuthRateLimiter withClock(Clock clock) {
        return new AuthRateLimiter(clock, 10_000);
    }
}
