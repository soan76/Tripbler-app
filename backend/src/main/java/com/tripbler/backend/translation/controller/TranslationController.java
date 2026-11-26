package com.tripbler.backend.translation.controller;

import java.io.IOException;

import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.tripbler.backend.translation.dto.LineTranslationRequest;
import com.tripbler.backend.translation.dto.LineTranslationResponse;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse;
import com.tripbler.backend.translation.dto.TranslationRequest;
import com.tripbler.backend.translation.dto.TranslationResponse;
import com.tripbler.backend.translation.service.LineTranslationService;
import com.tripbler.backend.translation.service.PhotoTranslationService;
import com.tripbler.backend.translation.service.TranslationService;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/translation")
public class TranslationController {

    private final TranslationService translationService;
    private final LineTranslationService lineTranslationService;
    private final PhotoTranslationService photoTranslationService;

    public TranslationController(
        TranslationService translationService,
        LineTranslationService lineTranslationService,
        PhotoTranslationService photoTranslationService
    ) {
        this.translationService =
            translationService;
        this.lineTranslationService = lineTranslationService;
        this.photoTranslationService = photoTranslationService;
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

    // 사진 번역. 사진(JPEG)과 기기에서 읽은 문단을 multipart로 받는다. /lines와 같이 로그인·호출 제한을 둔다.
    // 사용자별·IP별 한도는 이 메서드의 인자 해석(@Valid 등) 전에 PhotoTranslationRateLimitInterceptor가 차감한다.
    // 사진은 메모리에서만 다룬다(multipart file-size-threshold를 요청 한도 이상으로 두어 임시 파일을 쓰지 않음).
    // JPEG 여부는 서비스가 바이트로 확인하므로, 클라이언트가 보낸 Content-Type은 믿지 않고 image/jpeg로 넘긴다.
    @PostMapping(
        path = "/photo",
        consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
        produces = "application/json;charset=UTF-8"
    )
    public PhotoTranslationResponse translatePhoto(
        @AuthenticationPrincipal Jwt jwt,
        @RequestPart("image") MultipartFile image,
        @Valid
        @RequestPart("request")
        PhotoTranslationRequest request
    ) throws IOException {
        return photoTranslationService.translate(jwt.getSubject(), image.getBytes(), MediaType.IMAGE_JPEG_VALUE,
            request);
    }
}
