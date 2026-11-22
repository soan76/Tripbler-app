package com.tripbler.backend.translation.dto;

import java.util.List;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 찍기 모드의 줄별 번역 요청. 앱이 기기에서 사진의 글자를 읽어 줄 단위로 보낸다(사진은 보내지 않는다).
 * 전체 글자 수 상한은 서비스가 따로 확인한다.
 */
public record LineTranslationRequest(
    @NotNull(message = "번역할 줄을 보내 주세요.")
    @Size(min = 1, max = 50, message = "한 번에 번역할 수 있는 줄은 1~50줄입니다.")
    List<
        @NotBlank(message = "빈 줄은 보낼 수 없습니다.")
        @Size(max = 200, message = "한 줄은 200자 이하여야 합니다.")
        String
    > lines,

    @NotBlank(message = "원본 언어 코드를 입력해 주세요.")
    @Pattern(
        regexp = "^(auto|[A-Za-z]{2,3})$",
        message = "원본 언어 코드가 올바르지 않습니다."
    )
    String sourceLanguageCode,

    @NotBlank(message = "번역 대상 언어 코드를 입력해 주세요.")
    @Pattern(
        regexp = "^[A-Za-z]{2,3}$",
        message = "번역 대상 언어 코드가 올바르지 않습니다."
    )
    String targetLanguageCode
) {
}
