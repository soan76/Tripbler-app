package com.tripbler.backend.common.security;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher;
import org.springframework.security.web.util.matcher.RequestMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.ErrorResponse;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import tools.jackson.databind.ObjectMapper;

/**
 * multipart 본문은 파트를 받는 두 핸들러(사진 번역, 프로필 이미지)로 가는 요청만 통과시키고, 나머지는 본문을
 * 읽지 않고 415로 거절한다(보안 지적 M1/N1).
 *
 * <p>multipart 판단(Content-Type이 "multipart/"로 시작)은 HTTP 메서드를 보지 않는다. 그래서 지연 해석에서도
 * GET 요청의 @RequestParam 인자 해석(MultipartRequest.getFiles)이 본문 전체를 메모리(file-size-threshold
 * 6MB 아래)로 해석했다. 로그인 없이 열린 환율·암호화폐 조회에 6MB multipart를 몰아 보내면 힙이 차고, 깨진
 * 본문은 500과 ERROR 로그를 냈다. 경로마다 consumes를 다는 방식은 빠지기 쉬워 여기서 한 번에 막는다.
 *
 * <p>SecurityConfig가 Spring Security 필터 체인 안(Bearer 토큰 인증보다 앞)에 둔다. 정규화되지 않은 경로
 * (//, ;, 인코딩한 / 등)는 Tomcat이나 체인 맨 앞의 방화벽(StrictHttpFirewall)이 먼저 400으로 거절하고, 허용 경로는
 * 보안 설정과 같은 경로 해석(PathPatternRequestMatcher, MVC 핸들러 매핑과 같은 방식)으로 (메서드, 경로)가
 * 정확히 같을 때만 통과한다. 끝 '/', 대소문자가 다르면 허용하지 않는다. 허용 경로는 이어서 인증(401)을 받는다.
 *
 * <p>오류 응답은 GlobalExceptionHandler를 거치지 않으므로 같은 ErrorResponse 형식을 직접 쓴다
 * (CustomAuthenticationEntryPoint와 같은 방식). 로그는 DEBUG로 사유 종류만 남긴다(경로·본문 없음).
 */
public class MultipartAllowlistFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(MultipartAllowlistFilter.class);

    private static final List<RequestMatcher> ALLOWED = List.of(
        PathPatternRequestMatcher.pathPattern(HttpMethod.POST, "/api/v1/translation/photo"),
        PathPatternRequestMatcher.pathPattern(HttpMethod.PUT, "/api/v1/users/me/profile-image")
    );

    private final ObjectMapper objectMapper;

    public MultipartAllowlistFilter(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(
        HttpServletRequest request,
        HttpServletResponse response,
        FilterChain filterChain
    ) throws ServletException, IOException {
        if (!isMultipart(request) || isAllowed(request)) {
            filterChain.doFilter(request, response);
            return;
        }

        log.debug("Rejected multipart request: reason=path-not-allowlisted");

        ErrorCode errorCode = ErrorCode.UNSUPPORTED_MEDIA_TYPE;
        response.setStatus(errorCode.getStatus().value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        objectMapper.writeValue(
            response.getWriter(),
            ErrorResponse.of(errorCode, request.getRequestURI())
        );
    }

    // StandardServletMultipartResolver.isMultipart와 같은 기준(메서드 무관, 대소문자 무시)에 앞 공백도 본다.
    private static boolean isMultipart(HttpServletRequest request) {
        String contentType = request.getContentType();
        return contentType != null
            && contentType.strip().regionMatches(true, 0, "multipart/", 0, "multipart/".length());
    }

    private static boolean isAllowed(HttpServletRequest request) {
        for (RequestMatcher matcher : ALLOWED) {
            if (matcher.matches(request)) {
                return true;
            }
        }
        return false;
    }
}
