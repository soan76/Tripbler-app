package com.tripbler.backend.translation.controller;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.tripbler.backend.common.config.SecurityConfig;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.translation.dto.LineTranslationRequest;
import com.tripbler.backend.translation.dto.LineTranslationResponse;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PhotoTranslationService;
import com.tripbler.backend.translation.service.TranslationService;

// 줄별 번역은 로그인이 필요하므로 실제 SecurityConfig를 불러온다.
@WebMvcTest(TranslationController.class)
@Import({
    GlobalExceptionHandler.class,
    SecurityConfig.class,
    CustomAuthenticationEntryPoint.class,
    CustomAccessDeniedHandler.class
})
class LineTranslationControllerTest {

    private static final String PATH = "/api/v1/translation/lines";

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private LineTranslationService lineTranslationService;

    // 같은 컨트롤러의 사진 번역이 쓰는 서비스. 이 테스트에서는 부르지 않는다.
    @MockitoBean
    private PhotoTranslationService photoTranslationService;

    @MockitoBean
    private TranslationService translationService;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    private static final String BODY = """
        {"lines": ["醤油ラーメン 980円", "食券は入口で"], "sourceLanguageCode": "auto", "targetLanguageCode": "ko"}
        """;

    @Test
    void 로그인하지_않으면_401이고_서비스를_부르지_않는다() throws Exception {
        mockMvc.perform(post(PATH).contentType(MediaType.APPLICATION_JSON).content(BODY))
            .andExpect(status().isUnauthorized());

        verifyNoInteractions(lineTranslationService);
    }

    @Test
    void 줄마다_번역_발음_가격을_돌려준다() throws Exception {
        when(lineTranslationService.translate(eq("user-1"), eq("203.0.113.7"), any(LineTranslationRequest.class)))
            .thenReturn(new LineTranslationResponse("ja", "ko", List.of(
                new LineTranslationResponse.TranslatedLine("醤油ラーメン 980円", "간장 라멘 980엔", "쇼유 라멘",
                    new LineTranslationResponse.Price("980円", new BigDecimal("980"), "JPY",
                        new BigDecimal("9060"), new BigDecimal("9.245"),
                        LocalDateTime.of(2026, 11, 22, 9, 30), false)),
                new LineTranslationResponse.TranslatedLine("食券は入口で", "식권은 입구에서", "숏켄와 이리구치데", null)
            )));

        mockMvc.perform(post(PATH)
                .with(jwt().jwt(token -> token.subject("user-1")))
                .with(request -> {
                    request.setRemoteAddr("203.0.113.7");
                    return request;
                })
                .contentType(MediaType.APPLICATION_JSON)
                .content(BODY))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sourceLanguageCode").value("ja"))
            .andExpect(jsonPath("$.targetLanguageCode").value("ko"))
            .andExpect(jsonPath("$.lines[0].original").value("醤油ラーメン 980円"))
            .andExpect(jsonPath("$.lines[0].translated").value("간장 라멘 980엔"))
            .andExpect(jsonPath("$.lines[0].pronunciation").value("쇼유 라멘"))
            .andExpect(jsonPath("$.lines[0].price.text").value("980円"))
            .andExpect(jsonPath("$.lines[0].price.currency").value("JPY"))
            .andExpect(jsonPath("$.lines[0].price.krwAmount").value(9060))
            .andExpect(jsonPath("$.lines[0].price.krwRate").value(9.245))
            .andExpect(jsonPath("$.lines[0].price.rateFetchedAt").value("2026-11-22T09:30:00"))
            .andExpect(jsonPath("$.lines[0].price.rateStale").value(false))
            .andExpect(jsonPath("$.lines[1].price").doesNotExist());
    }

    @ParameterizedTest
    @ValueSource(strings = {"/api/v1/translation/lines/", "/api/v1/translation/LINES", "/api/v1/translation/Lines"})
    void 경로를_바꿔도_토큰_없이는_서비스를_부르지_않는다(String path) throws Exception {
        mockMvc.perform(post(path).contentType(MediaType.APPLICATION_JSON).content(BODY))
            .andExpect(result -> assertTrue(result.getResponse().getStatus() >= 400,
                path + " -> " + result.getResponse().getStatus()));

        verifyNoInteractions(lineTranslationService);
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "{\"lines\": [], \"sourceLanguageCode\": \"ja\", \"targetLanguageCode\": \"ko\"}",
        "{\"lines\": [\"  \"], \"sourceLanguageCode\": \"ja\", \"targetLanguageCode\": \"ko\"}",
        "{\"sourceLanguageCode\": \"ja\", \"targetLanguageCode\": \"ko\"}",
        "{\"lines\": [\"a\"], \"sourceLanguageCode\": \"japanese!\", \"targetLanguageCode\": \"ko\"}",
        "{\"lines\": [\"a\"], \"sourceLanguageCode\": \"ja\", \"targetLanguageCode\": \"auto\"}"
    })
    void 잘못된_요청은_400이고_서비스를_부르지_않는다(String body) throws Exception {
        mockMvc.perform(post(PATH).with(jwt()).contentType(MediaType.APPLICATION_JSON).content(body))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.path").value(PATH));

        verifyNoInteractions(lineTranslationService);
    }

    @Test
    void 줄이_50개를_넘거나_한_줄이_200자를_넘으면_400() throws Exception {
        String tooMany = "{\"lines\": [" + String.join(",", Collections.nCopies(51, "\"a\""))
            + "], \"sourceLanguageCode\": \"ja\", \"targetLanguageCode\": \"ko\"}";
        String tooLong = "{\"lines\": [\"" + "a".repeat(201)
            + "\"], \"sourceLanguageCode\": \"ja\", \"targetLanguageCode\": \"ko\"}";

        for (String body : List.of(tooMany, tooLong)) {
            mockMvc.perform(post(PATH).with(jwt()).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest());
        }

        verifyNoInteractions(lineTranslationService);
    }

    @Test
    void 한도를_넘으면_429와_Retry_After() throws Exception {
        when(lineTranslationService.translate(any(), any(), any())).thenThrow(new TooManyRequestsException(30));

        mockMvc.perform(post(PATH).with(jwt()).contentType(MediaType.APPLICATION_JSON).content(BODY))
            .andExpect(status().isTooManyRequests())
            .andExpect(header().string("Retry-After", "30"))
            .andExpect(jsonPath("$.code").value("TOO_MANY_REQUESTS"));
    }

    @Test
    void 번역_제공자_장애는_503() throws Exception {
        when(lineTranslationService.translate(any(), any(), any())).thenThrow(new TranslationProviderException());

        mockMvc.perform(post(PATH).with(jwt()).contentType(MediaType.APPLICATION_JSON).content(BODY))
            .andExpect(status().isServiceUnavailable())
            .andExpect(jsonPath("$.code").value("TRANSLATION_PROVIDER_UNAVAILABLE"));
    }

    @Test
    void 기존_번역_API는_지금처럼_로그인_없이_쓴다() throws Exception {
        mockMvc.perform(post("/api/v1/translation")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"text\": \"Hello\", \"sourceLanguageCode\": \"en\", \"targetLanguageCode\": \"ko\"}"))
            .andExpect(status().isOk());
    }
}
