package com.tripbler.backend.common.ratelimit;

import java.time.Duration;

// 요청 제한 묶음. 같은 키라도 묶음이 다르면 따로 센다.
// 한도는 "최근 window 동안 maxRequests번"이고, minInterval이 있으면
// 마지막 요청 뒤 그 시간이 지나야 다시 허용한다.
public enum RateLimitBucket {

    LOGIN_IP(10, Duration.ofMinutes(1), Duration.ZERO),
    SEND_CODE_IP(5, Duration.ofMinutes(10), Duration.ZERO),
    SEND_CODE_EMAIL(5, Duration.ofMinutes(60), Duration.ofSeconds(60)),
    RECOVERY_SIGNUP_IP(30, Duration.ofMinutes(1), Duration.ZERO),
    SESSION_IP(60, Duration.ofMinutes(1), Duration.ZERO),

    // 장소 API(유료 Google 호출) 사용자별 제한. 키는 JWT sub. 숫자는 개발 초기 설정값이다.
    // 하루 한도가 전역 1시간 한도보다 작아 계정 하나로는 전역 한도를 채울 수 없다.
    // 지금 값에서는 하루 한도가 1시간 한도보다 작아 1시간 한도는 실제로 거절하지 않는다.
    PLACE_SEARCH_USER_MINUTE(10, Duration.ofMinutes(1), Duration.ZERO),
    PLACE_SEARCH_USER_HOUR(100, Duration.ofMinutes(60), Duration.ZERO),
    PLACE_SEARCH_USER_DAY(50, Duration.ofHours(24), Duration.ZERO),
    PLACE_DETAILS_USER_MINUTE(20, Duration.ofMinutes(1), Duration.ZERO),
    PLACE_DETAILS_USER_HOUR(200, Duration.ofMinutes(60), Duration.ZERO),
    PLACE_DETAILS_USER_DAY(100, Duration.ofHours(24), Duration.ZERO),

    // 장소 API 서버 전체 상한(모든 사용자 합산). 키는 고정값 하나라 키 상한과 무관하다.
    // 계정을 여러 개 만들어 사용자별 제한을 피해도 Google 호출 비용이 이 값을 넘지 않게 한다. 초기 설정값이다.
    // 1시간 한도는 몰아치기 공격을 1시간 단위로 끊을 뿐이다. 모두가 함께 쓰는 한도라
    // 계정 여러 개(1시간은 3개, 하루는 20개)로 모든 사용자를 막을 수 있고, 하루 한도를 매일 다시
    // 채우면 계속 막힌다. 근본 대책(가입 인증, IP별 한도)은 docs/places-api.md의 남은 과제다.
    // 이 묶음이 거절 상태로 바뀔 때 AuthRateLimiter가 WARN을 남긴다(포화 중 빈자리마다 다시 남을 수 있음).
    PLACE_SEARCH_GLOBAL_HOUR(125, Duration.ofMinutes(60), Duration.ZERO, true),
    PLACE_SEARCH_GLOBAL_DAY(1000, Duration.ofHours(24), Duration.ZERO, true),
    PLACE_DETAILS_GLOBAL_HOUR(250, Duration.ofMinutes(60), Duration.ZERO, true),
    PLACE_DETAILS_GLOBAL_DAY(2000, Duration.ofHours(24), Duration.ZERO, true);

    private final int maxRequests;
    private final Duration window;
    private final Duration minInterval;
    private final boolean warnOnLimit;

    RateLimitBucket(
        int maxRequests,
        Duration window,
        Duration minInterval
    ) {
        this(maxRequests, window, minInterval, false);
    }

    RateLimitBucket(
        int maxRequests,
        Duration window,
        Duration minInterval,
        boolean warnOnLimit
    ) {
        this.maxRequests = maxRequests;
        this.window = window;
        this.minInterval = minInterval;
        this.warnOnLimit = warnOnLimit;
    }

    public int maxRequests() {
        return maxRequests;
    }

    public Duration window() {
        return window;
    }

    public Duration minInterval() {
        return minInterval;
    }

    // 서버 전체 한도처럼 거절되기 시작하면 운영자가 알아야 하는 묶음인지.
    boolean warnOnLimit() {
        return warnOnLimit;
    }

    // 마지막 기록 뒤 이 시간이 지나면 키의 기록이 모두 의미를 잃는다.
    Duration retention() {
        return window.compareTo(minInterval) >= 0 ? window : minInterval;
    }
}
