package com.tripbler.backend.translation.dto;

import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

/**
 * 사진 번역 요청. 앱이 정규화한 JPEG 사진과 함께, 기기에서 읽은 문단(글자와 사진 픽셀 좌표 상자)을 보낸다.
 * 사진 크기, 문단 상자의 범위, 전체 글자 수는 PhotoRequestValidator가 따로 확인한다.
 */
public record PhotoTranslationRequest(
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
    String targetLanguageCode,

    @Positive(message = "사진 너비가 올바르지 않습니다.")
    @Max(value = 8192, message = "사진 너비는 8192 이하여야 합니다.")
    int imageWidth,

    @Positive(message = "사진 높이가 올바르지 않습니다.")
    @Max(value = 8192, message = "사진 높이는 8192 이하여야 합니다.")
    int imageHeight,

    @NotNull(message = "번역할 문단을 보내 주세요.")
    // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
    @Size(min = 1, max = 50, message = "한 번에 번역할 수 있는 문단은 1~50개입니다.")
    List<@NotNull(message = "문단이 비어 있습니다.") @Valid Paragraph> paragraphs
) {

    public record Paragraph(
        @NotNull(message = "문단 ID를 보내 주세요.")
        @Pattern(regexp = "^p[0-9]{1,3}$", message = "문단 ID가 올바르지 않습니다.")
        String id,

        @NotBlank(message = "빈 문단은 보낼 수 없습니다.")
        // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
        @Size(max = 300, message = "한 문단은 300자 이하여야 합니다.")
        String text,

        @NotNull(message = "문단 위치를 보내 주세요.")
        @Valid
        Box box
    ) {
    }

    /** 사진 픽셀 좌표 기준 문단 상자. */
    public record Box(
        @PositiveOrZero(message = "상자 위치가 올바르지 않습니다.") double left,
        @PositiveOrZero(message = "상자 위치가 올바르지 않습니다.") double top,
        @Positive(message = "상자 크기가 올바르지 않습니다.") double width,
        @Positive(message = "상자 크기가 올바르지 않습니다.") double height
    ) {
    }
}
