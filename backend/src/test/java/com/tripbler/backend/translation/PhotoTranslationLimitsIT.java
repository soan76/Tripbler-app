package com.tripbler.backend.translation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.atLeast;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;

import com.tripbler.backend.common.config.SecurityConfig;
import com.tripbler.backend.common.config.WebConfig;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.common.ratelimit.RateLimitBucket;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.client.PhotoTranslationClient;
import com.tripbler.backend.translation.controller.TranslationController;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.service.KrwPriceConverter;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PhotoImageInspector;
import com.tripbler.backend.translation.service.PhotoRequestValidator;
import com.tripbler.backend.translation.service.PhotoTranslationService;
import com.tripbler.backend.translation.service.PhotoTranslationSlots;
import com.tripbler.backend.translation.service.PriceExtractor;
import com.tripbler.backend.translation.service.TranslationService;

/**
 * 사진 번역의 호출 제한·동시 처리 상한이 실제 요청 경로(내장 Tomcat → 보안 → 인터셉터 →
 * 인자 해석(지연 multipart 해석)·@Valid → 서비스)의 어디에서 적용되는지 확인한다. 서비스·검증·제한기·WebConfig는 실제 것이고,
 * AI·Google·환율만 대역이다. DB 없이 띄운다.
 *
 * <p>접속 주소가 모두 127.0.0.1이라 IP 1분 한도(20회)를 이 클래스 전체가 함께 쓴다. 요청 수를 그 아래로 둔다.
 */
@SpringBootTest(classes = PhotoTranslationLimitsIT.App.class,
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    // 사용자별 상한은 application.properties 값(1)을 그대로 쓰고, 전체 자리만 2로 줄여 다른 사용자 수용을 본다.
    properties = "translation.photo.max-concurrent=2")
class PhotoTranslationLimitsIT {

    private static final String PATH = "/api/v1/translation/photo";
    private static final String BOUNDARY = "tripbler-limits-boundary";
    private static final String VALID_JSON = """
        {"sourceLanguageCode": "ja", "targetLanguageCode": "ko", "imageWidth": 300, "imageHeight": 200,
         "paragraphs": [{"id": "p1", "text": "abc", "box": {"left": 10, "top": 10, "width": 100, "height": 20}}]}
        """;

    private static final List<RateLimitBucket> USER_AND_IP = List.of(
        RateLimitBucket.TRANSLATION_PHOTO_USER_MINUTE, RateLimitBucket.TRANSLATION_PHOTO_USER_DAY,
        RateLimitBucket.TRANSLATION_PHOTO_IP_MINUTE, RateLimitBucket.TRANSLATION_PHOTO_IP_DAY);

    @Value("${local.server.port}")
    int port;

    @Autowired
    BlockingAi ai;

    @MockitoSpyBean
    AuthRateLimiter limiter;

    private final HttpClient http = HttpClient.newHttpClient();

    @BeforeEach
    void reset() {
        clearInvocations(limiter);
        ai.reset();
    }

    @AfterEach
    void releaseAi() {
        ai.release.countDown();
    }

    // (a)(b) 컨트롤러 인자 해석·@Valid·서비스 검증에서 실패하는 요청도 사용자·IP 한도를 쓰고, 전체 한도는 쓰지 않는다.
    @Test
    void rejectedBeforeService_consumeUserAndIp_neverGlobal() throws Exception {
        record Case(String user, byte[] body) {
        }

        String emptyParagraphs = VALID_JSON.replaceAll("\"paragraphs\": \\[.*]", "\"paragraphs\": []");
        List<Case> cases = List.of(
            // @Valid 실패(문단 0개)
            new Case("valid-fail", body(jpeg(), "application/json", emptyParagraphs)),
            // request JSON 해석 실패
            new Case("json-fail", body(jpeg(), "application/json", "{\"sourceLanguageCode\": \"ja\", ")),
            // image 파트 없음
            new Case("missing-part", body(null, "application/json", VALID_JSON)),
            // request 파트가 JSON이 아님(HttpMediaTypeNotSupportedException 400)
            new Case("not-json-part", body(jpeg(), "text/plain", VALID_JSON)),
            // 서비스 검증 실패: JPEG가 아닌 사진
            new Case("not-jpeg", body("not a jpeg".getBytes(StandardCharsets.UTF_8), "application/json", VALID_JSON))
        );

        for (Case each : cases) {
            HttpResponse<String> response = send(each.user(), each.body());

            assertThat(response.statusCode()).as(each.user()).isEqualTo(400);
            assertThat(response.body()).as(each.user()).contains("\"code\":\"INVALID_REQUEST\"");
            assertThat(consumedBy(each.user())).as(each.user() + ": 사용자·IP 한도를 한 번 쓴다")
                .containsExactly(USER_AND_IP);
        }

        assertThat(globalCalls()).as("검증에서 실패한 요청은 전체 한도를 쓰지 않는다").isZero();
        assertThat(ai.calls()).isZero();
    }

    // multipart는 인자 해석 때 지연 해석한다(resolve-lazily). 그래서 크기 초과 413도 인터셉터 뒤에 나며
    // 사용자·IP 한도를 쓴다. 응답 형식(413 PAYLOAD_TOO_LARGE)은 그대로고, 전체 한도는 쓰지 않는다.
    @Test
    void oversizeUpload_failsAfterInterceptor_consumesUserAndIp() throws Exception {
        byte[] oversize = Arrays.copyOf(jpeg(), 5 * 1024 * 1024 + 256 * 1024);

        HttpResponse<String> response = send("oversize", body(oversize, "application/json", VALID_JSON));

        assertThat(response.statusCode()).isEqualTo(413);
        assertThat(response.body()).contains("\"code\":\"PAYLOAD_TOO_LARGE\"").contains(PATH);
        assertThat(consumedBy("oversize")).containsExactly(USER_AND_IP);
        assertThat(globalCalls()).isZero();
        assertThat(ai.calls()).isZero();
    }

    // 경계가 닫히지 않은 multipart 본문은 인자 해석 중 MultipartException이 되고 이 경로에서는 400이다.
    @Test
    void brokenMultipart_returns400_afterInterceptor() throws Exception {
        byte[] broken = ("--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\nnot finished").getBytes(StandardCharsets.UTF_8);

        HttpResponse<String> response = send("broken", broken);

        assertThat(response.statusCode()).isEqualTo(400);
        assertThat(response.body()).contains("\"code\":\"INVALID_REQUEST\"").contains(PATH)
            .doesNotContain("not finished");
        assertThat(consumedBy("broken")).containsExactly(USER_AND_IP);
        assertThat(globalCalls()).isZero();
    }

    // (c)(d) 같은 사용자의 두 번째 동시 요청은 사용자 상한으로, 전체 자리가 차면 다른 사용자도 429 + Retry-After: 3.
    @Test
    void perUserAndGlobalConcurrency_overHttp() throws Exception {
        CompletableFuture<HttpResponse<String>> firstOfA = sendAsync("user-a");
        assertThat(ai.entered.tryAcquire(1, 10, TimeUnit.SECONDS)).isTrue();

        HttpResponse<String> secondOfA = send("user-a", body(jpeg(), "application/json", VALID_JSON));
        assertThat(secondOfA.statusCode()).as("같은 사용자 두 번째 요청").isEqualTo(429);
        assertThat(secondOfA.headers().firstValue("Retry-After")).hasValue("3");

        // 전체 자리는 2개라 다른 사용자는 받아진다(자리 2개 동시 처리).
        CompletableFuture<HttpResponse<String>> firstOfB = sendAsync("user-b");
        assertThat(ai.entered.tryAcquire(1, 10, TimeUnit.SECONDS)).as("다른 사용자 요청이 AI까지 간다").isTrue();

        HttpResponse<String> firstOfC = send("user-c", body(jpeg(), "application/json", VALID_JSON));
        assertThat(firstOfC.statusCode()).as("전체 자리 부족").isEqualTo(429);
        assertThat(firstOfC.headers().firstValue("Retry-After")).hasValue("3");
        assertThat(firstOfC.body()).contains("\"code\":\"TOO_MANY_REQUESTS\"");

        ai.release.countDown();
        assertThat(firstOfA.get(10, TimeUnit.SECONDS).statusCode()).isEqualTo(200);
        assertThat(firstOfB.get(10, TimeUnit.SECONDS).statusCode()).isEqualTo(200);

        // 자리 부족으로 거절된 두 요청도 사용자·IP 한도는 썼고(인터셉터), 전체 한도는 받아진 두 요청만 썼다.
        assertThat(consumedBy("user-a")).containsExactly(USER_AND_IP, USER_AND_IP);
        assertThat(consumedBy("user-c")).containsExactly(USER_AND_IP);
        assertThat(globalCalls()).isEqualTo(2);
    }

    /** 이 사용자 키로 차감을 시도한 호출마다 그 호출의 묶음 목록. */
    @SuppressWarnings("unchecked")
    private List<List<RateLimitBucket>> consumedBy(String user) {
        ArgumentCaptor<List<AuthRateLimiter.Key>> captor = ArgumentCaptor.forClass(List.class);
        verify(limiter, atLeast(0)).acquireKeys(captor.capture());
        List<List<RateLimitBucket>> result = new ArrayList<>();
        for (List<AuthRateLimiter.Key> keys : captor.getAllValues()) {
            if (keys.stream().anyMatch(key -> key.value().equals(user))) {
                result.add(keys.stream().map(AuthRateLimiter.Key::bucket).toList());
            }
        }
        return result;
    }

    @SuppressWarnings("unchecked")
    private long globalCalls() {
        ArgumentCaptor<List<AuthRateLimiter.Key>> captor = ArgumentCaptor.forClass(List.class);
        verify(limiter, atLeast(0)).acquireKeys(captor.capture());
        return captor.getAllValues().stream()
            .filter(keys -> keys.stream().anyMatch(key -> key.bucket() == RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_HOUR))
            .count();
    }

    private CompletableFuture<HttpResponse<String>> sendAsync(String user) throws IOException {
        return http.sendAsync(request(user, body(jpeg(), "application/json", VALID_JSON)),
            HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> send(String user, byte[] body) throws IOException, InterruptedException {
        return http.send(request(user, body), HttpResponse.BodyHandlers.ofString());
    }

    // 테스트 디코더는 토큰 값을 그대로 사용자 ID(sub)로 쓴다.
    private HttpRequest request(String user, byte[] body) {
        return HttpRequest.newBuilder(URI.create("http://localhost:" + port + PATH))
            .header("Authorization", "Bearer " + user)
            .header("Content-Type", "multipart/form-data; boundary=" + BOUNDARY)
            .POST(HttpRequest.BodyPublishers.ofByteArray(body))
            .build();
    }

    /** image가 null이면 image 파트를 넣지 않는다. */
    private static byte[] body(byte[] image, String requestType, String json) throws IOException {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        if (image != null) {
            body.write(("--" + BOUNDARY + "\r\n"
                + "Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n"
                + "Content-Type: image/jpeg\r\n\r\n").getBytes(StandardCharsets.UTF_8));
            body.write(image);
            body.write("\r\n".getBytes(StandardCharsets.UTF_8));
        }
        body.write(("--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"request\"\r\n"
            + "Content-Type: " + requestType + "\r\n\r\n"
            + json + "\r\n--" + BOUNDARY + "--\r\n").getBytes(StandardCharsets.UTF_8));
        return body.toByteArray();
    }

    private static byte[] jpeg() throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(300, 200, BufferedImage.TYPE_INT_RGB), "jpg", out);
        return out.toByteArray();
    }

    /** 호출이 들어오면 entered에 하나 올리고 release가 열릴 때까지 붙잡는 AI 대역. */
    static class BlockingAi implements PhotoTranslationClient {
        final Semaphore entered = new Semaphore(0);
        volatile CountDownLatch release = new CountDownLatch(1);
        private final AtomicInteger calls = new AtomicInteger();

        void reset() {
            entered.drainPermits();
            release = new CountDownLatch(1);
            calls.set(0);
        }

        int calls() {
            return calls.get();
        }

        @Override
        public Result translate(byte[] jpeg, String mediaType, List<PhotoTranslationRequest.Paragraph> paragraphs,
            String source, String target) {
            calls.incrementAndGet();
            CountDownLatch gate = release;
            entered.release();
            try {
                gate.await(10, TimeUnit.SECONDS);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
            }
            return new Result("ja", List.of(new Paragraph("p1", "abc", "번역", false, null, List.of())));
        }
    }

    // @SpringBootConfiguration을 붙이면 같은 패키지 아래 @WebMvcTest가 이 클래스를 설정으로 찾으므로 일반 @Configuration.
    @Configuration(proxyBeanMethods = false)
    @EnableAutoConfiguration(excludeName = "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration")
    @Import({
        TranslationController.class,
        GlobalExceptionHandler.class,
        SecurityConfig.class,
        CustomAuthenticationEntryPoint.class,
        CustomAccessDeniedHandler.class,
        WebConfig.class,
        PhotoTranslationService.class,
        PhotoTranslationSlots.class,
        PhotoImageInspector.class,
        PhotoRequestValidator.class,
        PriceExtractor.class,
        KrwPriceConverter.class
    })
    static class App {

        @Bean
        BlockingAi claudePhotoTranslationClient() {
            return new BlockingAi();
        }

        @Bean
        LineTranslationClient googleLineTranslationClient() {
            return (lines, source, target) -> new LineTranslationClient.Result("ja",
                lines.stream().map(line -> new LineTranslationClient.Line("구글", null)).toList());
        }

        @Bean
        ExchangeService exchangeService() {
            return mock(ExchangeService.class);
        }

        @Bean
        TranslationService translationService() {
            return mock(TranslationService.class);
        }

        @Bean
        LineTranslationService lineTranslationService() {
            return mock(LineTranslationService.class);
        }

        // 토큰 값을 그대로 사용자 ID로 쓰는 테스트용 디코더.
        @Bean
        JwtDecoder jwtDecoder() {
            return token -> Jwt.withTokenValue(token)
                .header("alg", "none")
                .subject(token)
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60))
                .build();
        }
    }
}
