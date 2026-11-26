package com.tripbler.backend.common.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.servlet.HandlerMapping;

import com.tripbler.backend.common.exception.TooManyRequestsException;

class PhotoTranslationRateLimitInterceptorTest {

    private final AuthRateLimiter limiter = mock(AuthRateLimiter.class);
    private final PhotoTranslationRateLimitInterceptor interceptor = new PhotoTranslationRateLimitInterceptor(limiter);

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    private static MockHttpServletRequest request(String method, String pattern) {
        MockHttpServletRequest request = new MockHttpServletRequest(method, "/ignored");
        request.setAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE, pattern);
        request.setRemoteAddr("203.0.113.7");
        return request;
    }

    private static void signIn(String user) {
        TestingAuthenticationToken authentication = new TestingAuthenticationToken(user, null, "ROLE_USER");
        SecurityContextHolder.getContext().setAuthentication(authentication);
    }

    @Test
    void photoPath_consumesUserAndIpTogether() {
        signIn("user-1");

        assertThat(interceptor.preHandle(request("POST", "/api/v1/translation/photo"),
            new MockHttpServletResponse(), new Object())).isTrue();

        verify(limiter).acquireKeys(List.of(
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_USER_MINUTE, "user-1"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_USER_DAY, "user-1"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_IP_MINUTE, "203.0.113.7"),
            new AuthRateLimiter.Key(RateLimitBucket.TRANSLATION_PHOTO_IP_DAY, "203.0.113.7")));
    }

    @Test
    void otherPathsOrMethods_notCounted() {
        signIn("user-1");

        interceptor.preHandle(request("POST", "/api/v1/translation/lines"), new MockHttpServletResponse(), null);
        interceptor.preHandle(request("GET", "/api/v1/translation/photo"), new MockHttpServletResponse(), null);
        interceptor.preHandle(request("POST", null), new MockHttpServletResponse(), null);

        verifyNoInteractions(limiter);
    }

    @Test
    void limitExceeded_propagates429() {
        signIn("user-1");
        doThrow(new TooManyRequestsException(12)).when(limiter).acquireKeys(anyList());

        assertThatThrownBy(() -> interceptor.preHandle(request("POST", "/api/v1/translation/photo"),
            new MockHttpServletResponse(), null)).isInstanceOf(TooManyRequestsException.class);
    }

    @Test
    void missingAuthentication_rejectedWithoutCounting() {
        assertThatThrownBy(() -> interceptor.preHandle(request("POST", "/api/v1/translation/photo"),
            new MockHttpServletResponse(), null)).isInstanceOf(IllegalStateException.class);

        verifyNoInteractions(limiter);
    }
}
