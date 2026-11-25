package com.tripbler.backend.translation.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/** 사진 번역 응답. 문단 순서와 ID는 요청과 같다. */
public record PhotoTranslationResponse(
    String sourceLanguageCode,
    String targetLanguageCode,
    List<TranslatedParagraph> paragraphs
) {

    /** 사진에서 글자를 읽을 수 없을 때 번역문 자리에 넣는 표시. */
    public static final String UNREADABLE_MARKER = "[읽을 수 없음]";

    public enum TranslationSource {
        AI,
        OCR_TEXT
    }

    public record TranslatedParagraph(
        String id,
        String original,
        String translated,
        boolean uncertain,
        TranslationSource translationSource,
        String pronunciation,
        List<Price> prices
    ) {
    }

    public record Price(
        String text,
        BigDecimal amount,
        String currency,
        boolean confirmed,
        BigDecimal krwAmount,
        BigDecimal krwRate,
        LocalDateTime rateFetchedAt,
        boolean rateStale
    ) {
    }
}
