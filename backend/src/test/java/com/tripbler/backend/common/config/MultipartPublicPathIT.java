package com.tripbler.backend.common.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.core.Ordered;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.web.multipart.MultipartFile;

import com.tripbler.backend.auth.service.AccountDeletionService;
import com.tripbler.backend.auth.service.FindIdVerificationService;
import com.tripbler.backend.auth.service.PasswordResetService;
import com.tripbler.backend.auth.service.PasswordResetVerificationService;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.crypto.controller.CryptoController;
import com.tripbler.backend.crypto.service.CryptoService;
import com.tripbler.backend.exchange.controller.ExchangeController;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.translation.controller.TranslationController;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PhotoTranslationService;
import com.tripbler.backend.translation.service.TranslationService;
import com.tripbler.backend.user.controller.AuthController;
import com.tripbler.backend.user.controller.UserController;
import com.tripbler.backend.user.dto.UserResponse;
import com.tripbler.backend.user.service.AuthService;
import com.tripbler.backend.user.service.ProfileImageService;
import com.tripbler.backend.user.service.UserService;

import jakarta.servlet.Filter;
import jakarta.servlet.http.HttpServletRequest;

/**
 * 실제 내장 Tomcat에서 multipart 본문을 언제 해석하는지 확인한다(보안 지적 N1).
 *
 * <p>로그인 없이 열린 경로(로그인, 없는 경로)에 보낸 multipart는 해석하지 않아야 한다. 해석하면 파트가
 * file-size-threshold(6MB) 아래에서 메모리에 쌓이고, 어떤 호출 한도에도 걸리지 않는다. 그래서
 * spring.servlet.multipart.resolve-lazily=true로 파트를 실제로 읽는 핸들러에서만 해석한다.
 *
 * <p>관찰: 가장 앞의 서블릿 필터가 요청을 감싸 파트·파라미터·본문 스트림 접근을 기록한다(BodyAccessRecorder).
 * Tomcat의 multipart 해석은 이 접근으로만 일어나므로, 기록이 없으면 해석하지 않은 것이다.
 * 대조로 파트를 받는 핸들러(사진 번역, 프로필 이미지)는 그대로 해석·응답하는지 본다.
 * multipart 설정은 application.properties 값을 그대로 쓴다. DB 없이 띄우고 서비스는 대역이다.
 */
@SpringBootTest(classes = MultipartPublicPathIT.App.class,
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class MultipartPublicPathIT {

    private static final String BOUNDARY = "tripbler-public-boundary";
    private static final String PHOTO_JSON = """
        {"sourceLanguageCode": "auto", "targetLanguageCode": "ko", "imageWidth": 16, "imageHeight": 16,
         "paragraphs": [{"id": "p1", "text": "abc", "box": {"left": 0, "top": 0, "width": 8, "height": 8}}]}
        """;
    // Tomcat max-swallow-size(2MB)보다 작게 둔다. 읽지 않고 응답한 본문을 Tomcat이 끝까지 버리며 읽어
    // 연결이 끊기지 않아야 응답을 안정적으로 받는다. 해석 여부 관찰은 크기와 무관하다.
    private static final int FILE_SIZE = 1024 * 1024;
    private static final String PROFILE_PATH = "/api/v1/users/me/profile-image";

    @Value("${local.server.port}")
    int port;

    @Autowired
    BodyAccessRecorder recorder;

    @Autowired
    ProfileUploads profileUploads;

    private final HttpClient http = HttpClient.newHttpClient();

    @BeforeEach
    void reset() {
        recorder.clear();
        profileUploads.uploadedSizes.clear();
    }

    // 허용 목록 밖으로 보낸 multipart는 본문을 읽지 않고 415로 거절한다(M1). 지연 해석만으로는
    // @RequestParam 인자 해석(MultipartRequest.getFiles)이 GET 요청의 multipart도 해석했다.
    // 해석하면 깨진 본문은 MultipartException(500, ERROR 로그)이 된다.
    @Test
    void multipartToNonAllowlistedPath_returns415_withoutParsing() throws Exception {
        List<String[]> targets = List.of(
            new String[] {"GET", "/api/v1/exchange/rates"},
            new String[] {"GET", "/api/v1/exchange/history?startDate=2026-11-01&endDate=2026-11-20"},
            new String[] {"GET", "/api/v1/crypto/price"},
            new String[] {"GET", "/api/v1/crypto/history"},
            new String[] {"GET", "/api/v1/users/check-login-id?loginId=testuser01"},
            new String[] {"POST", "/api/v1/auth/login"},
            new String[] {"POST", "/api/v1/translation"},
            new String[] {"POST", "/api/v1/no-such-path"});
        for (String[] target : targets) {
            for (byte[] body : List.of(validBody(), brokenBody())) {
                recorder.clear();
                HttpResponse<String> response = send(target[0], target[1], null, body);

                String label = target[0] + " " + target[1];
                assertThat(recorder.accesses).as(label).isEmpty();
                assertThat(response.statusCode()).as(label).isEqualTo(415);
                assertThat(response.body()).as(label).contains("\"code\":\"UNSUPPORTED_MEDIA_TYPE\"")
                    .contains("\"status\":415").contains("\"path\":\"" + target[1].split("\\?")[0] + "\"");
            }
        }
    }

    // 허용 목록은 (메서드, 정확한 경로)로만 맞춘다. 로그인했어도 다른 메서드, 끝 '/', 대소문자가 다르면 415.
    // 정규화되지 않은 경로(//, ;, 인코딩한 /)는 그보다 앞에서 거절된다(400). 어느 쪽이든 해석하지 않는다.
    @Test
    void allowlist_matchesExactMethodAndPath_only() throws Exception {
        List<String[]> rejected = List.of(
            new String[] {"GET", "/api/v1/translation/photo"},
            new String[] {"PUT", "/api/v1/translation/photo"},
            new String[] {"POST", "/api/v1/translation/photo/"},
            new String[] {"POST", "/api/v1/Translation/photo"},
            new String[] {"POST", PROFILE_PATH},
            new String[] {"PUT", PROFILE_PATH + "/"});
        for (String[] target : rejected) {
            recorder.clear();
            HttpResponse<String> response = send(target[0], target[1], "it-token", validBody());

            assertThat(recorder.accesses).as(target[0] + " " + target[1]).isEmpty();
            assertThat(response.statusCode()).as(target[0] + " " + target[1]).isEqualTo(415);
        }
        for (String path : List.of("//api/v1/translation/photo", "/api/v1/translation/photo;x=1",
            "/api/v1/translation%2Fphoto")) {
            recorder.clear();
            HttpResponse<String> response = send("POST", path, "it-token", validBody());

            assertThat(response.statusCode()).as(path).isEqualTo(400);
            assertThat(recorder.accesses).as(path).isEmpty();
        }
        // 글자를 인코딩해도 MVC와 같은 경로로 맞춘다(같은 경로 해석 방식).
        recorder.clear();
        assertThat(send("POST", "/api/v1/translation/%70hoto", "it-token", validBody()).statusCode())
            .isEqualTo(200);
    }

    // 보안 필터가 DispatcherServlet보다 앞이라 로그인하지 않은 사진 요청은 해석 전에 401로 끝난다.
    @Test
    void photoPathWithoutLogin_returns401_withoutParsing() throws Exception {
        HttpResponse<String> response = send("/api/v1/translation/photo", null, validBody());

        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(recorder.accesses).isEmpty();
    }

    // 허용 목록의 다른 경로도 로그인하지 않으면 해석 전에 401이다.
    @Test
    void profileImageWithoutLogin_returns401_withoutParsing() throws Exception {
        HttpResponse<String> response = send("PUT", PROFILE_PATH, null, profileBody(FILE_SIZE));

        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(recorder.accesses).isEmpty();
        assertThat(recorder.bytesRead).hasValue(0);
        assertThat(profileUploads.uploadedSizes).isEmpty();
    }

    // 글자를 인코딩한 사진 경로도 보안 규칙이 같은 경로로 보므로 /translation/** permitAll로 새지 않는다.
    @Test
    void encodedPhotoPathWithoutLogin_returns401_withoutParsing() throws Exception {
        HttpResponse<String> response = send("/api/v1/translation/%70hoto", null, validBody());

        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(recorder.accesses).isEmpty();
        assertThat(recorder.bytesRead).hasValue(0);
    }

    // 대조: 파트를 받는 사진 번역 핸들러는 해석한다(기록 방법이 해석을 잡는다는 증명).
    @Test
    void photoPathWithLogin_isParsedByHandler() throws Exception {
        HttpResponse<String> response = send("/api/v1/translation/photo", "it-token", validBody());

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(recorder.accesses).isNotEmpty();
    }

    // 프로필 이미지 업로드도 지연 해석에서 그대로 동작한다: 정상 업로드 200, 파일 5MB 초과는 기존대로 400.
    @Test
    void profileImageUpload_isParsedByHandler_returns200() throws Exception {
        HttpResponse<String> response = send("PUT", PROFILE_PATH, "it-token", profileBody(FILE_SIZE));

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("\"loginId\":\"testuser01\"");
        assertThat(profileUploads.uploadedSizes).containsExactly((long) FILE_SIZE);
        assertThat(recorder.accesses).isNotEmpty();
    }

    @Test
    void profileImageUpload_overFileLimit_returns400InvalidProfileImage() throws Exception {
        HttpResponse<String> response =
            send("PUT", PROFILE_PATH, "it-token", profileBody(5 * 1024 * 1024 + 256 * 1024));

        assertThat(response.statusCode()).isEqualTo(400);
        assertThat(response.body()).contains("\"code\":\"INVALID_PROFILE_IMAGE\"").contains(PROFILE_PATH);
        assertThat(profileUploads.uploadedSizes).as("서비스를 부르지 않는다").isEmpty();
    }

    private HttpResponse<String> send(String path, String token, byte[] body)
        throws IOException, InterruptedException {
        return send("POST", path, token, body);
    }

    private HttpResponse<String> send(String method, String path, String token, byte[] body)
        throws IOException, InterruptedException {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
            .header("Content-Type", "multipart/form-data; boundary=" + BOUNDARY)
            .method(method, HttpRequest.BodyPublishers.ofByteArray(body));
        if (token != null) {
            builder.header("Authorization", "Bearer " + token);
        }
        return http.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private static byte[] validBody() throws IOException {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(("--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        byte[] image = new byte[FILE_SIZE];
        image[0] = (byte) 0xFF;
        image[1] = (byte) 0xD8;
        image[2] = (byte) 0xFF;
        body.write(image);
        body.write(("\r\n--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"request\"\r\n"
            + "Content-Type: application/json\r\n\r\n"
            + PHOTO_JSON + "\r\n--" + BOUNDARY + "--\r\n").getBytes(StandardCharsets.UTF_8));
        return body.toByteArray();
    }

    private static byte[] profileBody(int size) throws IOException {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(("--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"profile.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        body.write(new byte[size]);
        body.write(("\r\n--" + BOUNDARY + "--\r\n").getBytes(StandardCharsets.UTF_8));
        return body.toByteArray();
    }

    /** 닫는 경계 없이 끝나는 본문. 해석하면 MultipartException이 난다. */
    private static byte[] brokenBody() {
        return ("--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n"
            + "not finished").getBytes(StandardCharsets.UTF_8);
    }

    /** 프로필 이미지 서비스 대역이 받은 파일 크기. */
    static class ProfileUploads {
        final Queue<Long> uploadedSizes = new ConcurrentLinkedQueue<>();
    }

    // @SpringBootConfiguration을 붙이면 같은 패키지 아래 @WebMvcTest가 이 클래스를 설정으로 찾으므로 일반 @Configuration.
    @Configuration(proxyBeanMethods = false)
    @EnableAutoConfiguration(excludeName = "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration")
    @Import({
        ExchangeController.class,
        CryptoController.class,
        AuthController.class,
        UserController.class,
        TranslationController.class,
        GlobalExceptionHandler.class,
        SecurityConfig.class,
        CustomAuthenticationEntryPoint.class,
        CustomAccessDeniedHandler.class,
        WebConfig.class
    })
    static class App {

        @Bean
        BodyAccessRecorder bodyAccessRecorder() {
            return new BodyAccessRecorder();
        }

        // 보안 필터보다 앞에서 감싸 이후의 모든 접근(보안 필터·DispatcherServlet·핸들러)을 본다.
        @Bean
        FilterRegistrationBean<Filter> bodyAccessFilter(BodyAccessRecorder recorder) {
            Filter filter = (request, response, chain) ->
                chain.doFilter(recorder.wrap((HttpServletRequest) request), response);
            FilterRegistrationBean<Filter> registration = new FilterRegistrationBean<>(filter);
            registration.setOrder(Ordered.HIGHEST_PRECEDENCE);
            return registration;
        }

        @Bean
        PhotoTranslationService photoTranslationService() {
            PhotoTranslationService service = mock(PhotoTranslationService.class);
            when(service.translate(any(), any(), any(), any()))
                .thenReturn(new PhotoTranslationResponse("en", "ko", List.of()));
            return service;
        }

        @Bean
        ExchangeService exchangeService() {
            return mock(ExchangeService.class);
        }

        @Bean
        CryptoService cryptoService() {
            return mock(CryptoService.class);
        }

        @Bean
        TranslationService translationService() {
            return mock(TranslationService.class);
        }

        @Bean
        LineTranslationService lineTranslationService() {
            return mock(LineTranslationService.class);
        }

        @Bean
        ProfileUploads profileUploads() {
            return new ProfileUploads();
        }

        @Bean
        ProfileImageService profileImageService(ProfileUploads uploads) {
            ProfileImageService service = mock(ProfileImageService.class);
            when(service.updateProfileImage(any(), any())).thenAnswer(invocation -> {
                MultipartFile file = invocation.getArgument(1);
                uploads.uploadedSizes.add(file.getSize());
                return new UserResponse(1L, "testuser01", "여행자", null);
            });
            return service;
        }

        @Bean
        UserService userService() {
            return mock(UserService.class);
        }

        @Bean
        AccountDeletionService accountDeletionService() {
            return mock(AccountDeletionService.class);
        }

        @Bean
        AuthService authService() {
            return mock(AuthService.class);
        }

        @Bean
        FindIdVerificationService findIdVerificationService() {
            return mock(FindIdVerificationService.class);
        }

        @Bean
        PasswordResetVerificationService passwordResetVerificationService() {
            return mock(PasswordResetVerificationService.class);
        }

        @Bean
        PasswordResetService passwordResetService() {
            return mock(PasswordResetService.class);
        }

        // 아무 토큰이나 고정 사용자(1)로 받아들이는 테스트용 디코더. 프로필 API가 sub를 숫자 ID로 읽는다.
        @Bean
        JwtDecoder jwtDecoder() {
            return token -> Jwt.withTokenValue(token)
                .header("alg", "none")
                .subject("1")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60))
                .build();
        }
    }
}
