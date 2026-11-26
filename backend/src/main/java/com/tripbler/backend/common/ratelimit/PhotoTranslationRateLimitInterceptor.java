package com.tripbler.backend.common.ratelimit;

import java.util.List;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.HandlerMapping;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 사진 번역(POST /api/v1/translation/photo)의 사용자별·IP별 호출 한도를 컨트롤러 인자 해석 전에 차감한다.
 *
 * 인자 해석(request JSON 해석, @Valid, 파트 확인)에서 실패하는 요청도 한도를 쓰게 하려고 서비스가 아니라 여기서 센다.
 * 그래서 큰 사진에 잘못된 request를 붙여 한도 없이 반복할 수 없다. multipart 해석은 DispatcherServlet이
 * 인터셉터보다 먼저 하므로(크기 초과 413 등) 그 단계에서 끝나는 요청은 한도를 쓰지 않는다.
 * 서버 전체 한도는 검증을 통과하고 동시 처리 자리를 잡은 뒤 PhotoTranslationService가 차감한다.
 *
 * 경로는 원문 URI가 아니라 Spring이 매칭한 경로 패턴으로 판단한다(AuthRateLimitInterceptor와 같은 이유).
 * IP는 접속 주소(getRemoteAddr)만 쓴다. 사용자 ID는 JWT sub이다(인증 이름, 컨트롤러의 jwt.getSubject()와 같다).
 * 거절되면 TooManyRequestsException을 던지고 GlobalExceptionHandler가 429와 Retry-After로 응답한다.
 */
public class PhotoTranslationRateLimitInterceptor implements HandlerInterceptor {

    static final String PATTERN = "/api/v1/translation/photo";

    private final AuthRateLimiter limiter;

    public PhotoTranslationRateLimitInterceptor(AuthRateLimiter limiter) {
        this.limiter = limiter;
    }

    @Override
    public boolean preHandle(
        HttpServletRequest request,
        HttpServletResponse response,
        Object handler
    ) {
        Object pattern = request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);

        if (!"POST".equals(request.getMethod()) || !PATTERN.equals(pattern)) {
            return true;
        }

        // SecurityConfig가 이 경로를 로그인 사용자로 막으므로 여기서는 항상 인증돼 있다.
        // 보안 설정이 바뀌어 인증 없이 들어오면 한도 없이 통과시키지 않고 거절한다(500).
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated() || authentication.getName() == null) {
            throw new IllegalStateException("사진 번역 요청에 인증 정보가 없습니다.");
        }

        String userId = authentication.getName();
        String clientIp = request.getRemoteAddr();

        limiter.acquireKeys(List.of(
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_USER_MINUTE, userId),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_USER_DAY, userId),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_IP_MINUTE, clientIp),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_IP_DAY, clientIp)
        ));

        return true;
    }
}
