package com.tripbler.backend.translation.client;

import java.math.BigDecimal;
import java.util.List;

import com.tripbler.backend.translation.dto.PhotoTranslationRequest;

/**
 * 사진 한 장과 기기에서 읽은 문단 목록을 AI로 번역한다. 실패는 TranslationProviderException으로 던진다.
 *
 * <p>응답 문단의 ID는 걸러 내지 않고 그대로 돌려준다. 모르는 ID·중복 ID·빠진 ID 처리는 서비스가 맡는다.
 */
public interface PhotoTranslationClient {

    Result translate(
        byte[] jpeg,
        String mediaType,
        List<PhotoTranslationRequest.Paragraph> paragraphs,
        String source,
        String target
    );

    /**
     * @param detectedLanguageCode 감지한 원본 언어 코드. 모르면 null.
     * @param paragraphs           AI가 돌려준 순서 그대로의 문단.
     */
    record Result(String detectedLanguageCode, List<Paragraph> paragraphs) {
    }

    /**
     * @param original      AI가 사진과 대조해 보정한 원문. 비었거나 너무 길면 요청에서 같은 ID의 OCR 글자,
     *                      그것도 없으면(요청에 없는 ID) null.
     * @param uncertain     읽을 수 없는 부분이 있거나 확실하지 않은 번역이면 true.
     * @param pronunciation 원문의 한글 발음. 없으면 null.
     */
    record Paragraph(
        String id,
        String original,
        String translated,
        boolean uncertain,
        String pronunciation,
        List<AiPrice> prices
    ) {
    }

    /**
     * @param amount    금액. 읽지 못했으면 null.
     * @param currency  ISO 4217 통화 코드. 모르면 null.
     * @param uncertain 금액·통화가 확실하지 않으면 true.
     */
    record AiPrice(String text, BigDecimal amount, String currency, boolean uncertain) {
    }
}
