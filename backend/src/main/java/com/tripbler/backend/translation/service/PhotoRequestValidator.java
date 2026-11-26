package com.tripbler.backend.translation.service;

import java.util.HashSet;
import java.util.Set;

import org.springframework.stereotype.Component;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Box;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Paragraph;

/**
 * 어노테이션으로 못 하는 사진 번역 요청 검증: 사진 크기 일치, ID 중복, 상자 범위, 전체 글자 수.
 * 오류 메시지에 문단 글자를 넣지 않는다.
 */
@Component
public class PhotoRequestValidator {

    // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
    static final int MAX_TOTAL_CHARACTERS = 4000;

    private static final double BOX_TOLERANCE = 0.02;

    public void validate(PhotoTranslationRequest request, PhotoImageInspector.Dimensions actual) {
        if (request.imageWidth() != actual.width() || request.imageHeight() != actual.height()) {
            throw invalid("사진 크기가 요청한 크기와 다릅니다.");
        }
        double maxRight = actual.width() * (1 + BOX_TOLERANCE);
        double maxBottom = actual.height() * (1 + BOX_TOLERANCE);
        Set<String> ids = new HashSet<>();
        int total = 0;
        for (Paragraph paragraph : request.paragraphs()) {
            if (!ids.add(paragraph.id())) {
                throw invalid("문단 ID가 중복되었습니다.");
            }
            Box box = paragraph.box();
            if (box.left() + box.width() > maxRight || box.top() + box.height() > maxBottom) {
                throw invalid("문단 위치가 사진 밖에 있습니다.");
            }
            total += paragraph.text().length();
        }
        if (total > MAX_TOTAL_CHARACTERS) {
            throw invalid("번역할 글자가 너무 많습니다. 전체 " + MAX_TOTAL_CHARACTERS + "자 이하여야 합니다.");
        }
    }

    private static BusinessException invalid(String message) {
        return new BusinessException(ErrorCode.INVALID_REQUEST, message);
    }
}
