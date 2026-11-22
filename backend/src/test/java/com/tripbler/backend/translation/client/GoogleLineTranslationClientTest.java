package com.tripbler.backend.translation.client;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.util.List;

import org.hamcrest.Matchers;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import com.tripbler.backend.common.exception.TranslationProviderException;

/** 줄별 번역 대체 경로: Google v2 배열 요청(translateAll)과 줄별 결과 변환. Google은 대역 서버로 대신한다. */
class GoogleLineTranslationClientTest {

    private static final String URL = "https://translation.googleapis.com/language/translate/v2?key=test-api-key";

    private MockRestServiceServer mockServer;
    private GoogleLineTranslationClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder().baseUrl("https://translation.googleapis.com");
        mockServer = MockRestServiceServer.bindTo(builder).build();
        client = new GoogleLineTranslationClient(new GoogleTranslationClient(builder.build(), "test-api-key"));
    }

    private void respond(String json) {
        mockServer.expect(requestTo(URL))
            .andExpect(method(HttpMethod.POST))
            .andRespond(withSuccess(json, MediaType.APPLICATION_JSON));
    }

    @Test
    void 줄을_한_번에_보내고_같은_순서로_번역을_돌려주며_발음은_없다() {
        mockServer.expect(requestTo(URL))
            .andExpect(method(HttpMethod.POST))
            .andExpect(jsonPath("$.q", Matchers.contains("醤油ラーメン 980円", "食券")))
            .andExpect(jsonPath("$.target").value("ko"))
            .andExpect(jsonPath("$.format").value("text"))
            .andExpect(jsonPath("$.source").doesNotExist())
            .andRespond(withSuccess("""
                {"data":{"translations":[
                  {"translatedText":" 간장 라멘 980엔 ","detectedSourceLanguage":"ja"},
                  {"translatedText":"식권 &amp; 발매기","detectedSourceLanguage":"ja"}
                ]}}
                """, MediaType.APPLICATION_JSON));

        LineTranslationClient.Result result = client.translate(List.of("醤油ラーメン 980円", "食券"), "auto", "ko");

        assertEquals("ja", result.detectedLanguageCode());
        assertEquals(List.of(
            new LineTranslationClient.Line("간장 라멘 980엔", null),
            new LineTranslationClient.Line("식권 & 발매기", null)
        ), result.lines());
        mockServer.verify();
    }

    @Test
    void 원본_언어를_정하면_source를_보낸다() {
        mockServer.expect(requestTo(URL))
            .andExpect(jsonPath("$.source").value("ja"))
            .andRespond(withSuccess("""
                {"data":{"translations":[{"translatedText":"라멘"}]}}
                """, MediaType.APPLICATION_JSON));

        LineTranslationClient.Result result = client.translate(List.of("ラーメン"), "ja", "ko");

        assertNull(result.detectedLanguageCode());
        assertEquals("라멘", result.lines().get(0).translated());
        mockServer.verify();
    }

    @Test
    void 감지_언어는_가장_많은_것을_쓰고_지역_표기는_뗀다() {
        respond("""
            {"data":{"translations":[
              {"translatedText":"a","detectedSourceLanguage":"en"},
              {"translatedText":"b","detectedSourceLanguage":"zh-CN"},
              {"translatedText":"c","detectedSourceLanguage":"zh-TW"}
            ]}}
            """);

        LineTranslationClient.Result result = client.translate(List.of("x", "y", "z"), "auto", "ko");

        assertEquals("zh", result.detectedLanguageCode());
    }

    @Test
    void 번역_개수가_줄_수와_다르면_503_예외() {
        respond("""
            {"data":{"translations":[{"translatedText":"하나"}]}}
            """);

        assertThrows(TranslationProviderException.class,
            () -> client.translate(List.of("one", "two"), "en", "ko"));
    }

    @Test
    void 번역_글자가_없는_항목이_있으면_503_예외() {
        respond("""
            {"data":{"translations":[{"translatedText":"하나"},{"detectedSourceLanguage":"en"}]}}
            """);

        assertThrows(TranslationProviderException.class,
            () -> client.translate(List.of("one", "two"), "en", "ko"));
    }

    @Test
    void 번역이_비었거나_공백뿐인_줄은_원문을_그대로_쓴다() {
        respond("""
            {"data":{"translations":[
              {"translatedText":"","detectedSourceLanguage":"ja"},
              {"translatedText":"   ","detectedSourceLanguage":"ja"},
              {"translatedText":"라멘","detectedSourceLanguage":"ja"}
            ]}}
            """);

        LineTranslationClient.Result result = client.translate(List.of("980", "★☆", "ラーメン"), "auto", "ko");

        assertEquals(List.of(
            new LineTranslationClient.Line("980", null),
            new LineTranslationClient.Line("★☆", null),
            new LineTranslationClient.Line("라멘", null)
        ), result.lines());
    }

    @Test
    void 번역_항목이_null이면_503_예외() {
        respond("""
            {"data":{"translations":[{"translatedText":"하나"},null]}}
            """);

        assertThrows(TranslationProviderException.class,
            () -> client.translate(List.of("one", "two"), "en", "ko"));
    }

    @Test
    void 응답에_data가_없으면_503_예외() {
        respond("""
            {"data":null}
            """);

        assertThrows(TranslationProviderException.class,
            () -> client.translate(List.of("one"), "en", "ko"));
    }

    @Test
    void 번역_글자의_HTML_엔티티는_한_번만_푼다() {
        respond("""
            {"data":{"translations":[{"translatedText":"a &amp;lt;b&amp;gt; &lt;c&gt; &quot;d&quot; &#39;e&#39; &amp;"}]}}
            """);

        LineTranslationClient.Result result = client.translate(List.of("x"), "en", "ko");

        assertEquals("a &lt;b&gt; <c> \"d\" 'e' &", result.lines().get(0).translated());
    }

    @Test
    void Google이_실패하면_503_예외() {
        mockServer.expect(requestTo(URL)).andRespond(withServerError());

        assertThrows(TranslationProviderException.class,
            () -> client.translate(List.of("one"), "en", "ko"));
    }
}
