package com.tripbler.backend.translation.client;

import java.util.List;

/** 줄 목록을 번역하고 원문의 한글 발음을 받는다. 실패는 TranslationProviderException으로 던진다. */
public interface LineTranslationClient {

    Result translate(List<String> lines, String sourceLanguageCode, String targetLanguageCode);

    /**
     * @param detectedLanguageCode 감지한 원본 언어 코드. 모르면 null.
     * @param lines                입력과 같은 순서·개수.
     */
    record Result(String detectedLanguageCode, List<Line> lines) {
    }

    /** @param pronunciation 없으면 null. */
    record Line(String translated, String pronunciation) {
    }
}
