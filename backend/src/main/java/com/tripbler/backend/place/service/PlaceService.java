package com.tripbler.backend.place.service;

import java.util.ArrayList;
import java.util.List;

import org.springframework.stereotype.Service;

import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.common.ratelimit.RateLimitBucket;
import com.tripbler.backend.place.client.PlaceClient;
import com.tripbler.backend.place.dto.PlaceResponse;

@Service
public class PlaceService {

    // 검색과 상세는 사용자(JWT sub)별 1분·1시간·하루 창과 서버 전체 1시간·하루 창을 함께 센다.
    // 하나라도 거절하면 어느 쪽에도 기록하지 않는다. 숫자는 RateLimitBucket의 초기 설정값.
    private static final String GLOBAL_KEY = "*";

    private static final List<RateLimitBucket> SEARCH_USER_LIMITS = List.of(
        RateLimitBucket.PLACE_SEARCH_USER_MINUTE,
        RateLimitBucket.PLACE_SEARCH_USER_HOUR,
        RateLimitBucket.PLACE_SEARCH_USER_DAY
    );

    private static final List<RateLimitBucket> SEARCH_GLOBAL_LIMITS = List.of(
        RateLimitBucket.PLACE_SEARCH_GLOBAL_HOUR,
        RateLimitBucket.PLACE_SEARCH_GLOBAL_DAY
    );

    private static final List<RateLimitBucket> DETAILS_USER_LIMITS = List.of(
        RateLimitBucket.PLACE_DETAILS_USER_MINUTE,
        RateLimitBucket.PLACE_DETAILS_USER_HOUR,
        RateLimitBucket.PLACE_DETAILS_USER_DAY
    );

    private static final List<RateLimitBucket> DETAILS_GLOBAL_LIMITS = List.of(
        RateLimitBucket.PLACE_DETAILS_GLOBAL_HOUR,
        RateLimitBucket.PLACE_DETAILS_GLOBAL_DAY
    );

    private final PlaceClient placeClient;
    private final AuthRateLimiter rateLimiter;

    public PlaceService(
        PlaceClient placeClient,
        AuthRateLimiter rateLimiter
    ) {
        this.placeClient = placeClient;
        this.rateLimiter = rateLimiter;
    }

    public List<PlaceResponse> searchNearby(
        double latitude,
        double longitude,
        String type,
        int radius
    ) {
        return placeClient.searchNearby(
            latitude,
            longitude,
            type,
            radius
        );
    }

    // 한도를 넘으면 TooManyRequestsException(429)이고 Google을 호출하지 않는다.
    public PlaceResponse getPlaceDetails(
        String userId,
        String placeId
    ) {
        rateLimiter.acquireKeys(
            limitsFor(userId, DETAILS_USER_LIMITS, DETAILS_GLOBAL_LIMITS)
        );

        return placeClient.getPlaceDetails(placeId);
    }

    // 한도를 넘으면 TooManyRequestsException(429)이고 Google을 호출하지 않는다.
    // 입력 검증은 컨트롤러가 먼저 하므로 검증에 실패한 요청은 한도를 쓰지 않는다.
    public List<PlaceResponse> searchText(
        String userId,
        String query,
        Double latitude,
        Double longitude
    ) {
        rateLimiter.acquireKeys(
            limitsFor(userId, SEARCH_USER_LIMITS, SEARCH_GLOBAL_LIMITS)
        );

        return placeClient.searchText(
            query,
            latitude,
            longitude
        );
    }

    private static List<AuthRateLimiter.Key> limitsFor(
        String userId,
        List<RateLimitBucket> userLimits,
        List<RateLimitBucket> globalLimits
    ) {
        List<AuthRateLimiter.Key> keys = new ArrayList<>(userLimits.size() + globalLimits.size());
        for (RateLimitBucket bucket : userLimits) {
            keys.add(new AuthRateLimiter.Key(bucket, userId));
        }
        for (RateLimitBucket bucket : globalLimits) {
            keys.add(new AuthRateLimiter.Key(bucket, GLOBAL_KEY));
        }
        return keys;
    }
}
