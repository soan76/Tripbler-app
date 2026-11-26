package com.tripbler.backend.translation.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.List;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;

import com.tripbler.backend.common.config.SecurityConfig;
import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.Price;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.TranslatedParagraph;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.TranslationSource;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PhotoImageInspector;
import com.tripbler.backend.translation.service.PhotoRequestValidator;
import com.tripbler.backend.translation.service.PhotoTranslationService;
import com.tripbler.backend.translation.service.TranslationService;

// 사진 번역은 로그인이 필요하므로 실제 SecurityConfig를 불러온다.
// multipart 크기 한도(413)는 MockMvc가 실제 multipart 해석을 하지 않아 PhotoTranslationNoStorageIT에서 확인한다.
@WebMvcTest(TranslationController.class)
@Import({
    GlobalExceptionHandler.class,
    SecurityConfig.class,
    CustomAuthenticationEntryPoint.class,
    CustomAccessDeniedHandler.class
})
@ExtendWith(OutputCaptureExtension.class)
class PhotoTranslationControllerTest {

    private static final String PATH = "/api/v1/translation/photo";
    private static final String SECRET = "ZZ_SECRET_TEXT_ZZ";

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private PhotoTranslationService photoTranslationService;

    @MockitoBean
    private LineTranslationService lineTranslationService;

    @MockitoBean
    private TranslationService translationService;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    private static byte[] jpeg(int width, int height) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "jpg", out);
        return out.toByteArray();
    }

    private static String requestJson(String id, String text, double left) {
        return """
            {"sourceLanguageCode": "auto", "targetLanguageCode": "ko", "imageWidth": 300, "imageHeight": 200,
             "paragraphs": [{"id": "%s", "text": "%s", "box": {"left": %s, "top": 10, "width": 100, "height": 20}}]}
            """.formatted(id, text, left);
    }

    private static MockMultipartFile imagePart() throws IOException {
        return new MockMultipartFile("image", "photo.jpg", MediaType.IMAGE_JPEG_VALUE, jpeg(300, 200));
    }

    private static MockMultipartFile requestPart(String json) {
        return new MockMultipartFile("request", "", MediaType.APPLICATION_JSON_VALUE,
            json.getBytes(StandardCharsets.UTF_8));
    }

    private MockMultipartHttpServletRequestBuilder validUpload() throws IOException {
        return multipart(PATH).file(imagePart()).file(requestPart(requestJson("p1", "ラーメン ¥980", 10)));
    }

    @Test
    void returns200WithParagraphs() throws Exception {
        when(photoTranslationService.translate(eq("user-1"), eq("203.0.113.7"), any(byte[].class),
            eq(MediaType.IMAGE_JPEG_VALUE), any(PhotoTranslationRequest.class)))
            .thenReturn(new PhotoTranslationResponse("ja", "ko", List.of(
                new TranslatedParagraph("p1", "ラーメン ¥980", "라멘 980엔", false, TranslationSource.AI, "라멘",
                    List.of(new Price("¥980", new BigDecimal("980"), "JPY", true, new BigDecimal("9104"),
                        new BigDecimal("9.29"), LocalDateTime.of(2026, 11, 26, 9, 0), false)))
            )));

        mockMvc.perform(validUpload()
                .with(jwt().jwt(token -> token.subject("user-1")))
                .with(request -> {
                    request.setRemoteAddr("203.0.113.7");
                    return request;
                }))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.sourceLanguageCode").value("ja"))
            .andExpect(jsonPath("$.targetLanguageCode").value("ko"))
            .andExpect(jsonPath("$.paragraphs[0].id").value("p1"))
            .andExpect(jsonPath("$.paragraphs[0].original").value("ラーメン ¥980"))
            .andExpect(jsonPath("$.paragraphs[0].translated").value("라멘 980엔"))
            .andExpect(jsonPath("$.paragraphs[0].uncertain").value(false))
            .andExpect(jsonPath("$.paragraphs[0].translationSource").value("AI"))
            .andExpect(jsonPath("$.paragraphs[0].pronunciation").value("라멘"))
            .andExpect(jsonPath("$.paragraphs[0].prices[0].text").value("¥980"))
            .andExpect(jsonPath("$.paragraphs[0].prices[0].confirmed").value(true))
            .andExpect(jsonPath("$.paragraphs[0].prices[0].krwAmount").value(9104))
            .andExpect(jsonPath("$.paragraphs[0].prices[0].rateFetchedAt").value("2026-11-26T09:00:00"))
            .andExpect(jsonPath("$.paragraphs[0].prices[0].rateStale").value(false));
    }

    @Test
    void returns401WithoutToken() throws Exception {
        mockMvc.perform(validUpload())
            .andExpect(status().isUnauthorized());

        verifyNoInteractions(photoTranslationService);
    }

    @Test
    void returns400OnInvalidId() throws Exception {
        mockMvc.perform(multipart(PATH).file(imagePart()).file(requestPart(requestJson("x1", "abc", 10)))
                .with(jwt()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.path").value(PATH));

        verifyNoInteractions(photoTranslationService);
    }

    @Test
    void returns400OnMissingImagePart() throws Exception {
        mockMvc.perform(multipart(PATH).file(requestPart(requestJson("p1", "abc", 10))).with(jwt()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.path").value(PATH));

        verifyNoInteractions(photoTranslationService);
    }

    @Test
    void returns400OnBrokenJsonPart() throws Exception {
        mockMvc.perform(multipart(PATH).file(imagePart())
                .file(requestPart("{\"sourceLanguageCode\": \"auto\", \"paragraphs\": [{\"id\": \"p1\""))
                .with(jwt()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));

        verifyNoInteractions(photoTranslationService);
    }

    @Test
    void returns429WithRetryAfter() throws Exception {
        when(photoTranslationService.translate(any(), any(), any(), any(), any()))
            .thenThrow(new TooManyRequestsException(30));

        mockMvc.perform(validUpload().with(jwt()))
            .andExpect(status().isTooManyRequests())
            .andExpect(header().string("Retry-After", "30"))
            .andExpect(jsonPath("$.code").value("TOO_MANY_REQUESTS"));
    }

    @Test
    void returns503WhenProvidersFail() throws Exception {
        when(photoTranslationService.translate(any(), any(), any(), any(), any()))
            .thenThrow(new BusinessException(ErrorCode.TRANSLATION_PROVIDER_UNAVAILABLE));

        mockMvc.perform(validUpload().with(jwt()))
            .andExpect(status().isServiceUnavailable())
            .andExpect(jsonPath("$.code").value("TRANSLATION_PROVIDER_UNAVAILABLE"));
    }

    @Test
    void brokenJsonPart_errorLogHasNoRequestText(CapturedOutput output) throws Exception {
        // 잘린 JSON과, 숫자 자리에 글자가 들어간 JSON(Jackson 오류 메시지에 값이 실릴 수 있음).
        List<String> broken = List.of(
            "{\"sourceLanguageCode\": \"auto\", \"paragraphs\": [{\"id\": \"p1\", \"text\": \"" + SECRET,
            requestJson("p1", SECRET, 10).replace("\"imageWidth\": 300", "\"imageWidth\": \"" + SECRET + "\"")
        );

        for (String json : broken) {
            mockMvc.perform(multipart(PATH).file(imagePart()).file(requestPart(json)).with(jwt()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value(not(containsString(SECRET))));
        }

        verifyNoInteractions(photoTranslationService);
        assertThat(output.getAll()).doesNotContain(SECRET);
    }

    @Test
    void nonJsonRequestPart_returns400_andLogHasNoBodyText(CapturedOutput output) throws Exception {
        MockMultipartFile textPart = new MockMultipartFile("request", "", MediaType.TEXT_PLAIN_VALUE,
            requestJson("p1", SECRET, 10).getBytes(StandardCharsets.UTF_8));

        mockMvc.perform(multipart(PATH).file(imagePart()).file(textPart).with(jwt()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
            .andExpect(jsonPath("$.path").value(PATH))
            .andExpect(jsonPath("$.message").value(not(containsString(SECRET))));

        verifyNoInteractions(photoTranslationService);
        assertThat(output.getAll()).doesNotContain(SECRET);
    }

    @Test
    void invalidRequest_warnLogHasNoParagraphText(CapturedOutput output) throws Exception {
        // 서비스 대역이 실제 검사기·검증기를 부른다(검증 실패는 BusinessException으로 WARN 로그가 남는다).
        PhotoImageInspector inspector = new PhotoImageInspector();
        PhotoRequestValidator validator = new PhotoRequestValidator();
        when(photoTranslationService.translate(any(), any(), any(), any(), any())).thenAnswer(invocation -> {
            validator.validate(invocation.getArgument(4), inspector.inspect(invocation.getArgument(2)));
            throw new AssertionError("검증을 통과하면 안 된다");
        });

        // 상자가 사진 밖 → 서비스 검증 실패(400, WARN 로그)
        mockMvc.perform(multipart(PATH).file(imagePart()).file(requestPart(requestJson("p1", SECRET, 290)))
                .with(jwt()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));

        // 문단 300자 초과 → @Valid 검증 실패(400)
        mockMvc.perform(multipart(PATH).file(imagePart())
                .file(requestPart(requestJson("p1", SECRET + "a".repeat(300), 10)))
                .with(jwt()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));

        assertThat(output.getAll()).contains("Business exception: code=INVALID_REQUEST");
        assertThat(output.getAll()).doesNotContain(SECRET);
    }
}
