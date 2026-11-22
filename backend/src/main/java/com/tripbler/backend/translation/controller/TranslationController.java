package com.tripbler.backend.translation.controller;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.tripbler.backend.translation.dto.LineTranslationRequest;
import com.tripbler.backend.translation.dto.LineTranslationResponse;
import com.tripbler.backend.translation.dto.TranslationRequest;
import com.tripbler.backend.translation.dto.TranslationResponse;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.TranslationService;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/translation")
public class TranslationController {

    private final TranslationService translationService;
    private final LineTranslationService lineTranslationService;

    public TranslationController(
        TranslationService translationService,
        LineTranslationService lineTranslationService
    ) {
        this.translationService =
            translationService;
        this.lineTranslationService = lineTranslationService;
    }

    @PostMapping(
        produces = "application/json;charset=UTF-8"
    )
    public TranslationResponse translate(
        @Valid
        @RequestBody
        TranslationRequest request
    ) {
        return translationService.translate(
            request
        );
    }

    // 찍기 모드의 줄별 번역·한글 발음·가격 원화. 유료 Claude 호출이라 로그인 사용자만 쓰고
    // 사용자별·IP별·전체 호출 제한을 둔다(SecurityConfig, LineTranslationService).
    // IP는 인증 API 제한(AuthRateLimitInterceptor)과 같이 접속 주소(getRemoteAddr)만 쓴다.
    @PostMapping(
        path = "/lines",
        produces = "application/json;charset=UTF-8"
    )
    public LineTranslationResponse translateLines(
        @AuthenticationPrincipal Jwt jwt,
        @Valid
        @RequestBody
        LineTranslationRequest request,
        HttpServletRequest httpRequest
    ) {
        return lineTranslationService.translate(jwt.getSubject(), httpRequest.getRemoteAddr(), request);
    }
}
