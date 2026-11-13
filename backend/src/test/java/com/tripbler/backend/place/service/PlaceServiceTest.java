package com.tripbler.backend.place.service;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.ratelimit.TestRateLimiters;
import com.tripbler.backend.place.client.PlaceClient;
import com.tripbler.backend.place.dto.PlaceResponse;

/**
 * 장소 검색·상세의 호출 제한을 실제 제한기(고정 시계)로 확인한다.
 * 한도를 넘은 요청은 Google 클라이언트를 부르지 않아야 한다(완료 조건).
 */
@ExtendWith(MockitoExtension.class)
class PlaceServiceTest {

    @Mock
    private PlaceClient placeClient;

    private final MutableClock clock = new MutableClock(Instant.parse("2026-11-13T00:00:00Z"));

    private PlaceService placeService;

    @BeforeEach
    void setUp() {
        placeService = new PlaceService(placeClient, TestRateLimiters.withClock(clock));
    }

    private static PlaceResponse place() {
        return new PlaceResponse("p1", "경복궁", 37.5, 126.9, "서울", null, "tourist_attraction", null);
    }

    @Test
    void 검색_한도를_넘으면_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.searchText(anyString(), any(), any())).thenReturn(List.of());

        for (int i = 0; i < 10; i++) {
            placeService.searchText("u1", "경복궁", null, null);
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.searchText("u1", "경복궁", null, null)
        );
        verify(placeClient, times(10)).searchText(anyString(), any(), any());
    }

    @Test
    void 상세_한도를_넘으면_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.getPlaceDetails("p1")).thenReturn(place());

        for (int i = 0; i < 20; i++) {
            placeService.getPlaceDetails("u1", "p1");
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.getPlaceDetails("u1", "p1")
        );
        verify(placeClient, times(20)).getPlaceDetails("p1");
    }

    @Test
    void 다른_사용자는_따로_센다() {
        when(placeClient.searchText(anyString(), any(), any())).thenReturn(List.of());

        for (int i = 0; i < 10; i++) {
            placeService.searchText("u1", "경복궁", null, null);
        }

        placeService.searchText("u2", "경복궁", null, null);
        verify(placeClient, times(11)).searchText(anyString(), any(), any());
    }

    @Test
    void 검색_사용자_하루_한도에_도달하면_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.searchText(anyString(), any(), any())).thenReturn(List.of());

        // 10분 간격이라 사용자 1분·1시간 한도에는 걸리지 않고 하루 50회만 찬다.
        for (int i = 0; i < 50; i++) {
            placeService.searchText("u1", "경복궁", null, null);
            clock.advance(Duration.ofMinutes(10));
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.searchText("u1", "경복궁", null, null)
        );
        verify(placeClient, times(50)).searchText(anyString(), any(), any());
    }

    @Test
    void 상세_사용자_하루_한도에_도달하면_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.getPlaceDetails("p1")).thenReturn(place());

        // 5분 간격이라 사용자 1분·1시간 한도에는 걸리지 않고 하루 100회만 찬다.
        for (int i = 0; i < 100; i++) {
            placeService.getPlaceDetails("u1", "p1");
            clock.advance(Duration.ofMinutes(5));
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.getPlaceDetails("u1", "p1")
        );
        verify(placeClient, times(100)).getPlaceDetails("p1");
    }

    @Test
    void 검색_전역_1시간_한도에_도달하면_새_사용자도_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.searchText(anyString(), any(), any())).thenReturn(List.of());

        for (int i = 0; i < 125; i++) {
            placeService.searchText("g" + i, "경복궁", null, null);
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.searchText("newcomer", "경복궁", null, null)
        );
        verify(placeClient, times(125)).searchText(anyString(), any(), any());
    }

    @Test
    void 상세_전역_1시간_한도에_도달하면_새_사용자도_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.getPlaceDetails("p1")).thenReturn(place());

        for (int i = 0; i < 250; i++) {
            placeService.getPlaceDetails("g" + i, "p1");
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.getPlaceDetails("newcomer", "p1")
        );
        verify(placeClient, times(250)).getPlaceDetails("p1");
    }

    @Test
    void 검색_전역_하루_한도에_도달하면_새_사용자도_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.searchText(anyString(), any(), any())).thenReturn(List.of());

        // 1시간마다 125명씩 8번: 사용자 한도와 전역 1시간 한도에는 걸리지 않고 전역 하루 1,000회만 찬다.
        for (int batch = 0; batch < 8; batch++) {
            for (int i = 0; i < 125; i++) {
                placeService.searchText("g" + batch + "-" + i, "경복궁", null, null);
            }
            clock.advance(Duration.ofHours(1));
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.searchText("newcomer", "경복궁", null, null)
        );
        verify(placeClient, times(1000)).searchText(anyString(), any(), any());
    }

    @Test
    void 상세_전역_하루_한도에_도달하면_새_사용자도_429이고_클라이언트를_더_부르지_않는다() {
        when(placeClient.getPlaceDetails("p1")).thenReturn(place());

        // 1시간마다 250명씩 8번: 전역 하루 2,000회만 찬다.
        for (int batch = 0; batch < 8; batch++) {
            for (int i = 0; i < 250; i++) {
                placeService.getPlaceDetails("g" + batch + "-" + i, "p1");
            }
            clock.advance(Duration.ofHours(1));
        }

        assertThrows(
            TooManyRequestsException.class,
            () -> placeService.getPlaceDetails("newcomer", "p1")
        );
        verify(placeClient, times(2000)).getPlaceDetails("p1");
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
