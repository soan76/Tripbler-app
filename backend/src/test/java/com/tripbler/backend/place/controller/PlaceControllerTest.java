package com.tripbler.backend.place.controller;

import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.nullValue;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.net.SocketTimeoutException;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.tripbler.backend.common.config.SecurityConfig;
import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.common.exception.PlacesProviderException;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.place.dto.PlaceResponse;
import com.tripbler.backend.place.service.PlaceService;

// 검색·상세는 @AuthenticationPrincipal Jwt를 받으므로 실제 SecurityConfig를 불러온다.
@WebMvcTest(PlaceController.class)
@Import({
    GlobalExceptionHandler.class,
    SecurityConfig.class,
    CustomAuthenticationEntryPoint.class,
    CustomAccessDeniedHandler.class
})
class PlaceControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private PlaceService placeService;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    private static final String QUERY_MESSAGE =
        "검색어는 공백을 제외하고 1~100자여야 합니다.";

    @Test
    void 검색_429는_ErrorResponse와_Retry_After를_준다() throws Exception {
        when(placeService.searchText("user", "경복궁", null, null))
            .thenThrow(new TooManyRequestsException(42));

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
            )
            .andExpect(status().isTooManyRequests())
            .andExpect(header().string("Retry-After", "42"))
            .andExpect(jsonPath("$.code").value("TOO_MANY_REQUESTS"))
            .andExpect(jsonPath("$.path").value("/api/v1/places/search"));
    }

    @Test
    void 검증에_실패한_검색은_한도를_쓰지_않는다() throws Exception {
        // 서비스(한도 판정 위치)까지 가지 않아야 한다.
        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "   ")
            )
            .andExpect(status().isBadRequest());

        verifyNoInteractions(placeService);
    }

    @Test
    void 상세_조회_대상이_없으면_404를_반환한다() throws Exception {
        when(
            placeService.getPlaceDetails("user", "unknown-id")
        ).thenThrow(
            new BusinessException(
                ErrorCode.RESOURCE_NOT_FOUND,
                "요청한 장소를 찾을 수 없습니다."
            )
        );

        // 상세 조회는 로그인이 필요하다. 토큰을 붙여 장소의 404를 검증한다.
        mockMvc.perform(get("/api/v1/places/unknown-id").with(jwt()))
            .andExpect(status().isNotFound())
            .andExpect(
                jsonPath("$.code").value("RESOURCE_NOT_FOUND")
            );
    }

    @Test
    void 검색은_공백을_제거한_검색어와_좌표로_서비스를_호출한다() throws Exception {
        PlaceResponse place = new PlaceResponse(
            "place-1", "경복궁", 37.5796, 126.977,
            "서울특별시 종로구 사직로 161", null, "tourist_attraction", null
        );

        when(
            placeService.searchText("user", "경복궁", 37.5665, 126.978)
        ).thenReturn(List.of(place));

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "  경복궁  ")
                    .param("lat", "37.5665")
                    .param("lng", "126.978")
            )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$[0].id").value("place-1"))
            .andExpect(jsonPath("$[0].name").value("경복궁"))
            // 두 필드는 빠지지 않고 null 값으로 내려간다(기존 /nearby 응답과 같은 형식).
            .andExpect(jsonPath("$[0]", hasKey("rating")))
            .andExpect(jsonPath("$[0]", hasKey("openNow")))
            .andExpect(jsonPath("$[0].rating").value(nullValue()))
            .andExpect(jsonPath("$[0].openNow").value(nullValue()));

        verify(placeService).searchText("user", "경복궁", 37.5665, 126.978);
    }

    @Test
    void 좌표_없는_검색은_좌표를_null로_전달한다() throws Exception {
        when(
            placeService.searchText("user", "경복궁", null, null)
        ).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
            )
            .andExpect(status().isOk())
            .andExpect(content().json("[]"));

        verify(placeService).searchText("user", "경복궁", null, null);
    }

    @Test
    void 검색_결과의_위치가_없으면_좌표를_null로_내려보낸다() throws Exception {
        PlaceResponse place = new PlaceResponse(
            "place-1", "경복궁", null, null,
            "서울특별시 종로구 사직로 161", null, "tourist_attraction", null
        );

        when(
            placeService.searchText("user", "경복궁", null, null)
        ).thenReturn(List.of(place));

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
            )
            .andExpect(status().isOk())
            // 필드는 빠지지 않고 null로 내려가야 앱이 목록에만 표시한다.
            .andExpect(jsonPath("$[0]", hasKey("latitude")))
            .andExpect(jsonPath("$[0]", hasKey("longitude")))
            .andExpect(jsonPath("$[0].latitude").value(nullValue()))
            .andExpect(jsonPath("$[0].longitude").value(nullValue()));
    }

    @Test
    void 검색어_1자와_100자는_허용한다() throws Exception {
        String oneChar = "가";
        String hundredChars = "가".repeat(100);

        when(placeService.searchText("user", oneChar, null, null)).thenReturn(List.of());
        when(placeService.searchText("user", hundredChars, null, null)).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search").with(jwt()).param("query", oneChar)
            )
            .andExpect(status().isOk());

        mockMvc.perform(
                get("/api/v1/places/search").with(jwt()).param("query", hundredChars)
            )
            .andExpect(status().isOk());

        verify(placeService).searchText("user", oneChar, null, null);
        verify(placeService).searchText("user", hundredChars, null, null);
    }

    @Test
    void 공백을_제거하면_100자인_검색어는_허용한다() throws Exception {
        String hundredChars = "a".repeat(100);

        when(placeService.searchText("user", hundredChars, null, null)).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "   " + hundredChars + "   ")
            )
            .andExpect(status().isOk());

        verify(placeService).searchText("user", hundredChars, null, null);
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "   ", "\t"})
    void 검색어가_비었거나_공백뿐이면_400을_반환한다(String query) throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", query)
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.message").value(QUERY_MESSAGE));

        verifyNoInteractions(placeService);
    }

    // String.strip()이 지우지 못하는 유니코드 공백류만 보낸 경우다.
    // NBSP(U+00A0), 제로폭 공백(U+200B), BOM(U+FEFF), 전각 공백(U+3000)
    @ParameterizedTest
    @ValueSource(strings = {
        " ",
        "​",
        "﻿",
        "　",
        " ​﻿　 \t"
    })
    void 검색어가_유니코드_공백류뿐이면_400을_반환한다(String query) throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", query)
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.message").value(QUERY_MESSAGE));

        verifyNoInteractions(placeService);
    }

    @Test
    void 검색어_앞뒤의_유니코드_공백류를_제거하고_서비스를_호출한다() throws Exception {
        when(placeService.searchText("user", "경복궁", null, null)).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", " 경복궁​")
            )
            .andExpect(status().isOk());

        verify(placeService).searchText("user", "경복궁", null, null);
    }

    @Test
    void 검색어_가운데의_ZWJ는_그대로_전달한다() throws Exception {
        // 가족 이모지: 남자 + ZWJ + 여자 + ZWJ + 여자아이
        String family = "👨‍👩‍👧";

        when(placeService.searchText("user", family, null, null)).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "​" + family + " ")
            )
            .andExpect(status().isOk());

        verify(placeService).searchText("user", family, null, null);
    }

    @Test
    void 검색어_끝의_지역_깃발_이모지는_태그_문자까지_그대로_전달한다() throws Exception {
        // 스코틀랜드 깃발: 검은 깃발 + 태그 문자(g b s c t) + 태그 끝(U+E007F).
        // 태그 문자는 서식 문자(Cf)라 공백처럼 지우면 깃발이 깨진다.
        String scotland = new String(
            new int[] {0x1F3F4, 0xE0067, 0xE0062, 0xE0073, 0xE0063, 0xE0074, 0xE007F},
            0,
            7
        );
        String query = "에든버러 " + scotland;

        when(placeService.searchText("user", query, null, null)).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "​" + query + " ")
            )
            .andExpect(status().isOk());

        verify(placeService).searchText("user", query, null, null);
    }

    @Test
    void 검색어가_101자면_400을_반환한다() throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "가".repeat(101))
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.message").value(QUERY_MESSAGE));

        verifyNoInteractions(placeService);
    }

    @Test
    void 검색어가_없으면_400을_반환한다() throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search").with(jwt())
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.message").value("필수 요청 파라미터가 없습니다: query"));

        verifyNoInteractions(placeService);
    }

    @ParameterizedTest
    @CsvSource({
        "lat, 37.5665",
        "lng, 126.978"
    })
    void 좌표가_하나만_오면_400을_반환한다(String name, String value) throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
                    .param(name, value)
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.message").value("위도와 경도는 함께 보내야 합니다."));

        verifyNoInteractions(placeService);
    }

    @ParameterizedTest
    @CsvSource({
        "90.0001, 126.978",
        "-90.0001, 126.978",
        "37.5665, 180.0001",
        "37.5665, -180.0001",
        "NaN, 126.978",
        "37.5665, Infinity",
        "abc, 126.978"
    })
    void 검색_좌표가_범위를_벗어나거나_형식이_틀리면_400을_반환한다(
        String lat,
        String lng
    ) throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
                    .param("lat", lat)
                    .param("lng", lng)
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));

        verifyNoInteractions(placeService);
    }

    @Test
    void 검색_중_Google_장애면_503을_반환한다() throws Exception {
        when(
            placeService.searchText("user", "경복궁", null, null)
        ).thenThrow(
            new PlacesProviderException(
                new SocketTimeoutException("Read timed out")
            )
        );

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
            )
            .andExpect(status().isServiceUnavailable())
            .andExpect(jsonPath("$.code").value("PLACES_PROVIDER_UNAVAILABLE"));
    }
}
