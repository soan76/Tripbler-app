package com.tripbler.backend.translation.dto;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.Test;

import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Box;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Paragraph;

import jakarta.validation.Validation;
import jakarta.validation.Validator;

class PhotoTranslationRequestValidationTest {

    private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

    private static PhotoTranslationRequest request(List<Paragraph> paragraphs) {
        return new PhotoTranslationRequest("ja", "ko", 100, 100, paragraphs);
    }

    @Test
    void acceptsValidRequest() {
        var req = request(List.of(new Paragraph("p1", "a", new Box(0, 0, 10, 10))));

        assertThat(validator.validate(req)).isEmpty();
    }

    @Test
    void rejectsNullParagraphId() {
        var req = request(List.of(new Paragraph(null, "a", new Box(0, 0, 10, 10))));

        assertThat(validator.validate(req)).isNotEmpty();
    }

    @Test
    void rejectsNullParagraphElement() {
        var req = request(Arrays.asList((Paragraph) null));

        assertThat(validator.validate(req)).isNotEmpty();
    }
}
