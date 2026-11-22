package com.tripbler.backend.translation.client;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.translation.dto.GoogleTranslationResponse;

@Component
public class GoogleTranslationClient
    implements TranslationClient {

    private static final Logger log = LoggerFactory.getLogger(GoogleTranslationClient.class);

    private static final String GOOGLE_TRANSLATION_BASE_URL =
        "https://translation.googleapis.com";

    private static final Duration CONNECT_TIMEOUT =
        Duration.ofSeconds(3);

    private static final Duration READ_TIMEOUT =
        Duration.ofSeconds(5);

    private final RestClient restClient;
    private final String apiKey;
    
    @Autowired
    public GoogleTranslationClient(
        RestClient.Builder restClientBuilder,
        @Value("${google.translation.api-key}")
        String apiKey
    ) {
        SimpleClientHttpRequestFactory requestFactory =
            new SimpleClientHttpRequestFactory();

        requestFactory.setConnectTimeout(CONNECT_TIMEOUT);
        requestFactory.setReadTimeout(READ_TIMEOUT);

        this.restClient = restClientBuilder
            .baseUrl(GOOGLE_TRANSLATION_BASE_URL)
            .requestFactory(requestFactory)
            .build();

        this.apiKey = apiKey;
    }

    GoogleTranslationClient(
        RestClient restClient,
        String apiKey
    ) {
        this.restClient = restClient;
        this.apiKey = apiKey;
    }

    @Override
    public String translate(
        String text,
        String sourceLanguageCode,
        String targetLanguageCode
    ) {
        Map<String, Object> requestBody =
            new HashMap<>();

        requestBody.put("q", text);
        requestBody.put(
            "target",
            targetLanguageCode
        );
        requestBody.put(
            "format",
            "text"
        );

        if (!"auto".equalsIgnoreCase(
            sourceLanguageCode
        )) {
            requestBody.put(
                "source",
                sourceLanguageCode
            );
        }

        try {
            GoogleTranslationResponse response =
                restClient
                    .post()
                    .uri(uriBuilder -> uriBuilder
                        .path("/language/translate/v2")
                        .queryParam("key", apiKey)
                        .build()
                    )
                    .body(requestBody)
                    .retrieve()
                    .body(
                        GoogleTranslationResponse.class
                    );

            return extractTranslatedText(
                response
            );

        } catch (RestClientException exception) {
            throw new TranslationProviderException();
        }
    }

    private String extractTranslatedText(
        GoogleTranslationResponse response
    ) {
        if (
            response == null
                || response.data() == null
                || response.data()
                    .translations() == null
                || response.data()
                    .translations()
                    .isEmpty()
        ) {
            throw new TranslationProviderException();
        }

        String translatedText =
            response.data()
                .translations()
                .get(0)
                .translatedText();

        System.out.println(
            "Google 응답 translatedText = " + translatedText
        );

        if (
            translatedText == null
                || translatedText.isBlank()
        ) {
            throw new TranslationProviderException();
        }

        return decodeHtmlEntities(
            translatedText.trim()
        );
    }

    /**
     * 여러 문장을 한 번의 요청으로 번역한다(Google v2의 q 배열, 응답은 같은 순서).
     * 찍기 모드 줄별 번역의 대체 경로가 쓴다. 번역 글자는 로그에 남기지 않는다.
     *
     * <p>번역이 비었거나 공백뿐인 항목(숫자·기호뿐인 줄 등)은 원문을 그대로 쓴다. 번역 글자가 아예 없는(null)
     * 항목과 개수가 맞지 않는 응답은 장애로 본다.
     *
     * @return 입력과 같은 개수·순서. 원본 언어를 지정하지 않았으면 항목마다 감지한 언어가 들어 있다.
     */
    public List<GoogleTranslationResponse.Translation> translateAll(
        List<String> texts,
        String sourceLanguageCode,
        String targetLanguageCode
    ) {
        Map<String, Object> requestBody = new HashMap<>();

        requestBody.put("q", texts);
        requestBody.put("target", targetLanguageCode);
        requestBody.put("format", "text");

        if (!"auto".equalsIgnoreCase(sourceLanguageCode)) {
            requestBody.put("source", sourceLanguageCode);
        }

        GoogleTranslationResponse response;

        try {
            response = restClient
                .post()
                .uri(uriBuilder -> uriBuilder
                    .path("/language/translate/v2")
                    .queryParam("key", apiKey)
                    .build()
                )
                .body(requestBody)
                .retrieve()
                .body(GoogleTranslationResponse.class);
        } catch (RestClientException exception) {
            // 예외 메시지에는 응답 본문(번역 글자)이 담길 수 있어 클래스 이름과 상태 코드만 남긴다.
            log.warn(
                "Google 일괄 번역 호출 실패: {} status={}",
                exception.getClass().getSimpleName(),
                exception instanceof RestClientResponseException responseException
                    ? responseException.getStatusCode().value()
                    : "-"
            );
            throw new TranslationProviderException();
        }

        if (
            response == null
                || response.data() == null
                || response.data().translations() == null
                || response.data().translations().size() != texts.size()
        ) {
            log.warn("Google 일괄 번역 응답 형식 오류: expected={}", texts.size());
            throw new TranslationProviderException();
        }

        List<GoogleTranslationResponse.Translation> translations = new ArrayList<>(texts.size());

        for (int index = 0; index < texts.size(); index++) {
            GoogleTranslationResponse.Translation translation = response.data().translations().get(index);

            if (translation == null || translation.translatedText() == null) {
                log.warn("Google 일괄 번역 응답에 번역이 없는 항목: index={}", index);
                throw new TranslationProviderException();
            }

            String translated = decodeHtmlEntities(translation.translatedText().trim());

            translations.add(new GoogleTranslationResponse.Translation(
                translated.isBlank() ? texts.get(index) : translated,
                translation.detectedSourceLanguage()
            ));
        }

        return translations;
    }

    // &amp;는 마지막에 푼다. 먼저 풀면 "&amp;lt;"(글자 그대로의 "&lt;")가 "<"로 두 번 풀린다.
    static String decodeHtmlEntities(
        String text
    ) {
        return text
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&");
    }
}
