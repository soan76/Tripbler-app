package com.tripbler.backend.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.assertj.core.api.SoftAssertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * 실제 내장 Tomcat에서 로그인 없이 보낸 urlencoded 본문을 읽는지 확인한다(보안 지적 H1).
 *
 * <p>Spring Boot가 기본으로 등록하는 FormContentFilter(순서 -9900, Spring Security보다 앞)는 PUT·PATCH·DELETE이고
 * Content-Type이 application/x-www-form-urlencoded이면 경로와 로그인 여부와 상관없이 본문 전체를 크기 제한 없이
 * 문자열로 읽는다. 이 앱에는 그 파라미터를 쓰는 핸들러가 없어 spring.mvc.formcontent.filter.enabled=false로 끈다.
 *
 * <p>관찰: MultipartPublicPathIT와 같은 서버 구성에서, 가장 앞(FormContentFilter보다 앞)의 서블릿 필터가 요청을
 * 감싸 본문 스트림 접근과 읽은 바이트 수를 기록한다(BodyAccessRecorder). 대조로 JSON을 받는 핸들러는 본문을
 * 읽는 것이 기록되는지 본다.
 */
@SpringBootTest(classes = MultipartPublicPathIT.App.class,
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class FormBodyPublicPathIT {

    // 제한된 크기. Tomcat max-swallow-size(2MB)보다 작아 읽지 않고 응답해도 연결이 끊기지 않는다.
    private static final int BODY_SIZE = 256 * 1024;

    @Value("${local.server.port}")
    int port;

    @Autowired
    BodyAccessRecorder recorder;

    private final HttpClient http = HttpClient.newHttpClient();

    @BeforeEach
    void reset() {
        recorder.clear();
    }

    // 공개 경로, 없는 경로, 로그인이 필요한 경로 모두 로그인 없이 보낸 form 본문을 읽지 않는다.
    // 로그인이 필요한 경로는 401이다(인증 전에 본문을 읽지 않음).
    @Test
    void formBodyWithoutLogin_isNotRead() throws Exception {
        List<String> paths = List.of("/api/v1/auth/login", "/api/v1/no-such-path", "/api/v1/users/me/nickname");
        List<String> observed = new ArrayList<>();
        SoftAssertions softly = new SoftAssertions();
        for (String method : List.of("PUT", "PATCH", "DELETE")) {
            for (String path : paths) {
                recorder.clear();
                HttpResponse<String> response = send(method, path, null,
                    "application/x-www-form-urlencoded", formBody());

                String label = method + " " + path + " -> " + response.statusCode()
                    + ", read " + recorder.bytesRead.get() + " bytes, " + recorder.accesses;
                observed.add(label);
                softly.assertThat(recorder.accesses).as(label).isEmpty();
                softly.assertThat(recorder.bytesRead.get()).as(label).isZero();
                if (path.startsWith("/api/v1/users/me")) {
                    softly.assertThat(response.statusCode()).as(label).isEqualTo(401);
                }
            }
        }
        System.out.println("[H1] " + String.join("\n[H1] ", observed));
        softly.assertAll();
    }

    // 대조: JSON 본문을 받는 핸들러는 본문을 읽고, 그 읽기가 기록된다(기록 방법이 본문 읽기를 잡는다는 증명).
    // 폼 필터를 꺼도 앱이 쓰는 JSON PATCH(닉네임 200, 비밀번호 204)는 그대로 동작한다.
    @Test
    void jsonBodyWithLogin_isReadByHandler() throws Exception {
        String[][] targets = {
            {"/api/v1/users/me/nickname", "{\"nickname\":\"traveler\"}", "200"},
            {"/api/v1/users/me/password", "{\"currentPassword\":\"old-pass-1\",\"newPassword\":\"new-pass-1\"}", "204"}
        };
        for (String[] target : targets) {
            recorder.clear();
            byte[] body = target[1].getBytes(StandardCharsets.UTF_8);
            HttpResponse<String> response = send("PATCH", target[0], "it-token", "application/json", body);

            assertThat(response.statusCode()).as(target[0]).isEqualTo(Integer.parseInt(target[2]));
            assertThat(recorder.accesses).as(target[0]).anyMatch(access -> access.startsWith("getInputStream"));
            assertThat(recorder.bytesRead).as(target[0]).hasValue(body.length);
        }
    }

    // 본문 없는 DELETE(프로필 이미지 삭제, 회원 탈퇴)도 그대로 동작한다.
    @Test
    void deleteWithoutBody_withLogin_stillWorks() throws Exception {
        assertThat(send("DELETE", "/api/v1/users/me/profile-image", "it-token", "application/json", new byte[0])
            .statusCode()).isEqualTo(204);
        assertThat(send("DELETE", "/api/v1/users/me", "it-token", "application/json", new byte[0])
            .statusCode()).isEqualTo(204);
    }

    private HttpResponse<String> send(String method, String path, String token, String contentType, byte[] body)
        throws IOException, InterruptedException {
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
            .header("Content-Type", contentType)
            .method(method, HttpRequest.BodyPublishers.ofByteArray(body));
        if (token != null) {
            builder.header("Authorization", "Bearer " + token);
        }
        return http.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private static byte[] formBody() {
        byte[] body = new byte[BODY_SIZE];
        Arrays.fill(body, (byte) 'a');
        body[0] = 'd';
        body[1] = '=';
        return body;
    }
}
