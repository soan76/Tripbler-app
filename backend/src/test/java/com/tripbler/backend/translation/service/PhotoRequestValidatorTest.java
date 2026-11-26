package com.tripbler.backend.translation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;

import org.junit.jupiter.api.Test;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Box;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Paragraph;

class PhotoRequestValidatorTest {

    private static final PhotoImageInspector.Dimensions ACTUAL =
        new PhotoImageInspector.Dimensions(1536, 2048);

    private final PhotoRequestValidator validator = new PhotoRequestValidator();

    private static PhotoTranslationRequest request(int w, int h, Paragraph... paragraphs) {
        return new PhotoTranslationRequest("ja", "ko", w, h, List.of(paragraphs));
    }

    private static Paragraph paragraph(String id, String text, Box box) {
        return new Paragraph(id, text, box);
    }

    private static Box box(double left, double top, double width, double height) {
        return new Box(left, top, width, height);
    }

    private static void assertInvalid(Runnable action) {
        assertThatThrownBy(action::run)
            .isInstanceOfSatisfying(BusinessException.class,
                e -> assertThat(e.getErrorCode()).isEqualTo(ErrorCode.INVALID_REQUEST));
    }

    @Test
    void acceptsValidRequest() {
        PhotoTranslationRequest req = request(1536, 2048,
            paragraph("p1", "ラーメン", box(10, 10, 100, 50)));

        assertThatCode(() -> validator.validate(req, ACTUAL)).doesNotThrowAnyException();
    }

    @Test
    void rejectsSizeMismatch() {
        PhotoTranslationRequest req = request(1536, 2048,
            paragraph("p1", "a", box(0, 0, 10, 10)));

        assertInvalid(() -> validator.validate(req,
            new PhotoImageInspector.Dimensions(2048, 1536)));
    }

    @Test
    void rejectsDuplicateIds() {
        PhotoTranslationRequest req = request(1536, 2048,
            paragraph("p1", "a", box(0, 0, 10, 10)),
            paragraph("p1", "b", box(20, 20, 10, 10)));

        assertInvalid(() -> validator.validate(req, ACTUAL));
    }

    @Test
    void rejectsBoxOutside() {
        PhotoTranslationRequest req = request(1536, 2048,
            paragraph("p1", "a", box(0, 0, 1536 * 1.03, 10)));

        assertInvalid(() -> validator.validate(req, ACTUAL));
    }

    @Test
    void acceptsBoxWithinTolerance() {
        PhotoTranslationRequest req = request(1536, 2048,
            paragraph("p1", "a", box(0, 0, 1536 * 1.019, 10)));

        assertThatCode(() -> validator.validate(req, ACTUAL)).doesNotThrowAnyException();
    }

    @Test
    void rejectsTotalOver4000() {
        String text = "a".repeat(300);
        Paragraph[] paragraphs = new Paragraph[14];
        for (int i = 0; i < paragraphs.length; i++) {
            paragraphs[i] = paragraph("p" + i, text, box(0, i * 10, 10, 5));
        }

        assertInvalid(() -> validator.validate(request(1536, 2048, paragraphs), ACTUAL));
    }
}
