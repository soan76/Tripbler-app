package com.tripbler.backend.place.controller;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpMethod;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidationException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.tripbler.backend.common.config.SecurityConfig;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.place.dto.PlaceResponse;
import com.tripbler.backend.place.service.PlaceService;

// 실제 SecurityConfig를 불러와 장소 API의 인증 규칙을 확인한다.
// 검색·상세는 로그인이 필요하고, 주변·최근접은 외부 접근을 막는다.
@WebMvcTest(PlaceController.class)
@Import({
    SecurityConfig.class,
    CustomAuthenticationEntryPoint.class,
    CustomAccessDeniedHandler.class,
    GlobalExceptionHandler.class
})
class PlaceControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private PlaceService placeService;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    @Test
    void 토큰_없이_검색하면_401을_반환한다() throws Exception {
        mockMvc.perform(
                get("/api/v1/places/search")
                    .param("query", "경복궁")
            )
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.status").value(401))
            .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
            .andExpect(jsonPath("$.message").value("인증이 필요합니다."))
            .andExpect(jsonPath("$.path").value("/api/v1/places/search"));

        verifyNoInteractions(placeService);
    }

    @Test
    void 만료된_토큰으로_검색하면_401을_반환하고_서비스를_호출하지_않는다() throws Exception {
        // 실제 JwtDecoder가 만료된 토큰을 검증할 때 던지는 예외를 흉내 낸다.
        when(jwtDecoder.decode(anyString())).thenThrow(
            new JwtValidationException(
                "Jwt expired",
                List.of(
                    new OAuth2Error(
                        "invalid_token",
                        "Jwt expired at 2026-01-01T00:00:00Z",
                        null
                    )
                )
            )
        );

        mockMvc.perform(
                get("/api/v1/places/search")
                    .header("Authorization", "Bearer expired-access-token")
                    .param("query", "경복궁")
            )
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.status").value(401))
            .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
            .andExpect(jsonPath("$.path").value("/api/v1/places/search"));

        verify(jwtDecoder).decode("expired-access-token");
        verifyNoInteractions(placeService);
    }

    @Test
    void 토큰이_있으면_검색이_상세_조회가_아닌_검색으로_처리된다() throws Exception {
        // /search가 /{placeId}("search"라는 ID)로 처리되지 않아야 한다.
        when(
            placeService.searchText("user", "경복궁", null, null)
        ).thenReturn(List.of());

        mockMvc.perform(
                get("/api/v1/places/search")
                    .with(jwt())
                    .param("query", "경복궁")
            )
            .andExpect(status().isOk());

        verify(placeService).searchText("user", "경복궁", null, null);
        verify(placeService, never()).getPlaceDetails(any(), eq("search"));
    }

    // 주변(코드는 남김)과 최근접(삭제)은 외부 접근을 막는다. GET과 HEAD 모두.
    @ParameterizedTest
    @CsvSource({
        "GET, /api/v1/places/nearby",
        "HEAD, /api/v1/places/nearby",
        "GET, /api/v1/places/nearest",
        "HEAD, /api/v1/places/nearest"
    })
    void 주변과_최근접은_토큰이_없으면_401이다(String method, String path) throws Exception {
        mockMvc.perform(
                request(HttpMethod.valueOf(method), path)
                    .param("lat", "37.5665")
                    .param("lng", "126.978")
            )
            .andExpect(status().isUnauthorized());

        verifyNoInteractions(placeService);
    }

    @ParameterizedTest
    @CsvSource({
        "GET, /api/v1/places/nearby",
        "HEAD, /api/v1/places/nearby",
        "GET, /api/v1/places/nearest",
        "HEAD, /api/v1/places/nearest"
    })
    void 주변과_최근접은_유효한_토큰이어도_403이다(String method, String path) throws Exception {
        mockMvc.perform(
                request(HttpMethod.valueOf(method), path)
                    .with(jwt())
                    .param("lat", "37.5665")
                    .param("lng", "126.978")
            )
            .andExpect(status().isForbidden());

        // nearest가 상세 조회(placeId = "nearest")로 새지 않아야 한다.
        verifyNoInteractions(placeService);
    }

    @ParameterizedTest
    @ValueSource(strings = {"/api/v1/places/nearby/", "/api/v1/places/nearest/"})
    void 끝_슬래시_변형도_서비스를_호출하지_않는다(String path) throws Exception {
        int status = mockMvc.perform(get(path).with(jwt()))
            .andReturn()
            .getResponse()
            .getStatus();

        assertTrue(status >= 400, "끝 슬래시 변형이 " + status + "로 처리됨");
        verifyNoInteractions(placeService);
    }

    @Test
    void 상세는_토큰이_없으면_401이다() throws Exception {
        mockMvc.perform(get("/api/v1/places/place-1"))
            .andExpect(status().isUnauthorized());

        verifyNoInteractions(placeService);
    }

    @Test
    void 상세는_토큰이_있으면_200이다() throws Exception {
        when(
            placeService.getPlaceDetails("user", "place-1")
        ).thenReturn(
            new PlaceResponse(
                "place-1", "경복궁", 37.5796, 126.977,
                "서울특별시 종로구 사직로 161", 4.6, "tourist_attraction", true
            )
        );

        mockMvc.perform(
                get("/api/v1/places/place-1").with(jwt())
            )
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").value("place-1"));
    }
}
