package com.tripbler.backend.translation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import com.tripbler.backend.common.config.SecurityConfig;
import com.tripbler.backend.common.exception.GlobalExceptionHandler;
import com.tripbler.backend.common.security.CustomAccessDeniedHandler;
import com.tripbler.backend.common.security.CustomAuthenticationEntryPoint;
import com.tripbler.backend.translation.controller.TranslationController;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PhotoTranslationService;
import com.tripbler.backend.translation.service.TranslationService;

/**
 * 실제 내장 Tomcat의 multipart 해석으로, 사진 업로드가 임시 파일을 디스크에 쓰지 않는지 확인한다.
 * DB 없이 띄우려고 컨트롤러·보안·예외 처리만 올리고 서비스는 대역으로 둔다. multipart 설정은
 * application.properties 값(파일 5MB, 요청 6MB, file-size-threshold)을 그대로 쓰고 임시 폴더만 바꾼다.
 * 임시 파일은 요청이 끝나면 지워지므로, 서비스 대역이 처리 도중(파트가 살아 있는 동안) 폴더를 본다.
 */
@SpringBootTest(classes = PhotoTranslationNoStorageIT.App.class,
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PhotoTranslationNoStorageIT {

    private static final String PATH = "/api/v1/translation/photo";
    private static final String BOUNDARY = "tripbler-it-boundary";

    @TempDir
    static Path uploadDir;

    @TempDir
    Path controlDir;

    @Value("${local.server.port}")
    int port;

    @Autowired
    TempDirProbe probe;

    private final HttpClient http = HttpClient.newHttpClient();

    @DynamicPropertySource
    static void multipartLocation(DynamicPropertyRegistry registry) {
        registry.add("spring.servlet.multipart.location", () -> uploadDir.toString());
    }

    @BeforeEach
    void resetProbe() {
        probe.seen.set(null);
    }

    @Test
    void photoUpload_writesNoTempFile() throws Exception {
        HttpResponse<String> response = upload(port, jpegOfSize(4 * 1024 * 1024));

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(probe.seen.get()).as("처리 도중 임시 폴더").isEmpty();
        assertThat(listFiles(uploadDir)).as("요청 뒤 임시 폴더").isEmpty();
    }

    @Test
    void returns413OverFileLimit() throws Exception {
        HttpResponse<String> response = upload(port, jpegOfSize(5 * 1024 * 1024 + 256 * 1024));

        assertThat(response.statusCode()).isEqualTo(413);
        assertThat(response.body()).contains("\"code\":\"PAYLOAD_TOO_LARGE\"").contains(PATH);
        assertThat(probe.seen.get()).as("서비스를 부르지 않는다").isNull();
    }

    // 대조: threshold를 0으로 두면 같은 측정으로 임시 파일이 잡힌다(측정 방법이 파일 생성을 잡는다는 증명).
    @Test
    void thresholdZero_wouldWriteTempFile() throws Exception {
        try (ConfigurableApplicationContext context = new SpringApplicationBuilder(App.class)
            .web(WebApplicationType.SERVLET)
            // properties()는 application.properties보다 우선순위가 낮아 명령줄 인자로 넘긴다.
            .run(
                "--server.port=0",
                "--spring.servlet.multipart.file-size-threshold=0",
                "--spring.servlet.multipart.location=" + controlDir
            )) {
            int controlPort = Integer.parseInt(context.getEnvironment().getProperty("local.server.port"));
            TempDirProbe controlProbe = context.getBean(TempDirProbe.class);

            HttpResponse<String> response = upload(controlPort, jpegOfSize(4 * 1024 * 1024));

            assertThat(response.statusCode()).isEqualTo(200);
            assertThat(controlProbe.seen.get()).as("처리 도중 임시 폴더").isNotEmpty();
        }
    }

    private HttpResponse<String> upload(int targetPort, byte[] image) throws IOException, InterruptedException {
        String json = """
            {"sourceLanguageCode": "auto", "targetLanguageCode": "ko", "imageWidth": 16, "imageHeight": 16,
             "paragraphs": [{"id": "p1", "text": "abc", "box": {"left": 0, "top": 0, "width": 8, "height": 8}}]}
            """;
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        body.write(("--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n"
            + "Content-Type: image/jpeg\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        body.write(image);
        body.write(("\r\n--" + BOUNDARY + "\r\n"
            + "Content-Disposition: form-data; name=\"request\"\r\n"
            + "Content-Type: application/json\r\n\r\n"
            + json + "\r\n--" + BOUNDARY + "--\r\n").getBytes(StandardCharsets.UTF_8));

        HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + targetPort + PATH))
            .header("Authorization", "Bearer it-token")
            .header("Content-Type", "multipart/form-data; boundary=" + BOUNDARY)
            .POST(HttpRequest.BodyPublishers.ofByteArray(body.toByteArray()))
            .build();

        return http.send(request, HttpResponse.BodyHandlers.ofString());
    }

    /** JPEG 머리로 시작하고 뒤를 채워 원하는 크기로 만든 바이트(서비스가 대역이라 내용은 읽지 않는다). */
    private static byte[] jpegOfSize(int size) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(16, 16, BufferedImage.TYPE_INT_RGB), "jpg", out);
        return Arrays.copyOf(out.toByteArray(), size);
    }

    private static List<String> listFiles(Path dir) throws IOException {
        try (Stream<Path> files = Files.walk(dir)) {
            return files.filter(Files::isRegularFile).map(Path::toString).toList();
        }
    }

    static class TempDirProbe {
        final AtomicReference<List<String>> seen = new AtomicReference<>();
    }

    // @SpringBootConfiguration을 붙이면 같은 패키지 아래 @WebMvcTest(translation.controller)가 이 클래스를
    // 설정으로 찾아 쓰므로 일반 @Configuration으로 둔다.
    @Configuration(proxyBeanMethods = false)
    @EnableAutoConfiguration(excludeName = "org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration")
    @Import({
        TranslationController.class,
        GlobalExceptionHandler.class,
        SecurityConfig.class,
        CustomAuthenticationEntryPoint.class,
        CustomAccessDeniedHandler.class
    })
    static class App {

        @Bean
        TempDirProbe tempDirProbe() {
            return new TempDirProbe();
        }

        @Bean
        PhotoTranslationService photoTranslationService(
            TempDirProbe probe,
            @Value("${spring.servlet.multipart.location}") String location
        ) {
            PhotoTranslationService service = mock(PhotoTranslationService.class);
            when(service.translate(any(), any(), any(), any(), any())).thenAnswer(invocation -> {
                probe.seen.set(listFiles(Path.of(location)));
                return new PhotoTranslationResponse("en", "ko", List.of());
            });
            return service;
        }

        @Bean
        TranslationService translationService() {
            return mock(TranslationService.class);
        }

        @Bean
        LineTranslationService lineTranslationService() {
            return mock(LineTranslationService.class);
        }

        // 아무 토큰이나 고정 사용자로 받아들이는 테스트용 디코더.
        @Bean
        JwtDecoder jwtDecoder() {
            return token -> Jwt.withTokenValue(token)
                .header("alg", "none")
                .subject("it-user")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60))
                .build();
        }
    }
}
