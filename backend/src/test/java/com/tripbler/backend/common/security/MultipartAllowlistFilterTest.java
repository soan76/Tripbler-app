package com.tripbler.backend.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import tools.jackson.databind.json.JsonMapper;

/**
 * multipart 판정(대소문자 무시, 앞 공백, multipart/ 하위 형식 전부)과 multipart가 아닌 요청의 통과를 확인한다.
 * 실제 Tomcat·보안 체인 안의 동작은 MultipartPublicPathIT에서 본다.
 */
class MultipartAllowlistFilterTest {

    private final MultipartAllowlistFilter filter = new MultipartAllowlistFilter(JsonMapper.builder().build());

    @ParameterizedTest
    @ValueSource(strings = {
        "multipart/form-data; boundary=x",
        "MULTIPART/FORM-DATA; boundary=x",
        " multipart/form-data; boundary=x",
        "multipart/mixed; boundary=x"
    })
    void multipartToNonAllowlistedPath_returns415_withoutCallingChain(String contentType) throws Exception {
        MockHttpServletRequest request = request("GET", "/api/v1/exchange/rates", contentType);
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertThat(chain.getRequest()).as(contentType).isNull();
        assertThat(response.getStatus()).as(contentType).isEqualTo(415);
        assertThat(response.getContentAsString()).contains("\"code\":\"UNSUPPORTED_MEDIA_TYPE\"")
            .contains("\"path\":\"/api/v1/exchange/rates\"");
    }

    @ParameterizedTest
    @ValueSource(strings = {"multipart/form-data; boundary=x", "MULTIPART/FORM-DATA; boundary=x"})
    void multipartToAllowlistedPath_passes(String contentType) throws Exception {
        assertPasses(request("POST", "/api/v1/translation/photo", contentType));
        assertPasses(request("PUT", "/api/v1/users/me/profile-image", contentType));
    }

    @Test
    void nonMultipartRequests_passUnchanged() throws Exception {
        assertPasses(request("POST", "/api/v1/auth/login", "application/json"));
        assertPasses(request("PATCH", "/api/v1/users/me/nickname", "application/json"));
        assertPasses(request("GET", "/api/v1/exchange/rates", null));
    }

    private void assertPasses(MockHttpServletRequest request) throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        String label = request.getMethod() + " " + request.getRequestURI() + " " + request.getContentType();
        assertThat(chain.getRequest()).as(label).isSameAs(request);
        assertThat(response.getStatus()).as(label).isEqualTo(200);
        assertThat(response.getContentAsString()).as(label).isEmpty();
    }

    private static MockHttpServletRequest request(String method, String uri, String contentType) {
        MockHttpServletRequest request = new MockHttpServletRequest(method, uri);
        if (contentType != null) {
            request.setContentType(contentType);
        }
        return request;
    }
}
