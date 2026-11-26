package com.tripbler.backend.translation.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.*;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.TooManyRequestsException;
import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.client.PhotoTranslationClient;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Box;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest.Paragraph;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.TranslatedParagraph;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.TranslationSource;

/** AI, Google, 환율, 사진 검사는 대역으로 대신한다. */
class PhotoTranslationServiceTest {

    private static final byte[] IMAGE = new byte[] {1, 2, 3};
    private static final LocalDateTime FETCHED_AT = LocalDateTime.of(2026, 11, 22, 9, 30);

    private static final class FakeAi implements PhotoTranslationClient {
        int calls;
        Result result;
        RuntimeException failure;

        @Override
        public Result translate(byte[] jpeg, String mediaType, List<PhotoTranslationRequest.Paragraph> paragraphs,
            String source, String target) {
            calls++;
            if (failure != null) throw failure;
            return result;
        }
    }

    private static final class FakeGoogle implements LineTranslationClient {
        final List<List<String>> calls = new ArrayList<>();
        RuntimeException failure;

        @Override
        public Result translate(List<String> lines, String source, String target) {
            calls.add(lines);
            if (failure != null) throw failure;
            return new Result("ja", lines.stream().map(line -> new Line("구글:" + line, null)).toList());
        }
    }

    private FakeAi ai;
    private FakeGoogle google;
    private ExchangeService exchangeService;
    private AuthRateLimiter rateLimiter;
    private PhotoImageInspector inspector;
    private PhotoRequestValidator validator;
    private KrwPriceConverter converter;
    private PhotoTranslationService service;

    @BeforeEach
    void setUp() {
        ai = new FakeAi();
        google = new FakeGoogle();
        exchangeService = mock(ExchangeService.class);
        rateLimiter = mock(AuthRateLimiter.class);
        inspector = mock(PhotoImageInspector.class);
        validator = mock(PhotoRequestValidator.class);
        when(inspector.inspect(any())).thenReturn(new PhotoImageInspector.Dimensions(1000, 800));
        converter = new KrwPriceConverter(exchangeService, Duration.ofSeconds(2));
        service = new PhotoTranslationService(inspector, validator, ai, google, new PriceExtractor(), converter,
            rateLimiter, new PhotoTranslationSlots(4, 1));
    }

    @AfterEach
    void tearDown() {
        converter.destroy();
    }

    private static Paragraph paragraph(String id, String text) {
        return new Paragraph(id, text, new Box(10, 10, 100, 30));
    }

    private static PhotoTranslationRequest request(Paragraph... paragraphs) {
        return new PhotoTranslationRequest("ja", "ko", 1000, 800, List.of(paragraphs));
    }

    private static PhotoTranslationClient.Paragraph aiParagraph(String id, String original, String translated) {
        return new PhotoTranslationClient.Paragraph(id, original, translated, false, "발음", List.of());
    }

    private static PhotoTranslationClient.Paragraph aiParagraph(String id, PhotoTranslationClient.AiPrice price) {
        return new PhotoTranslationClient.Paragraph(id, "원문", "번역", false, "발음", List.of(price));
    }

    private void aiReturns(PhotoTranslationClient.Paragraph... paragraphs) {
        ai.result = new PhotoTranslationClient.Result("ja", List.of(paragraphs));
    }

    private PhotoTranslationResponse run(PhotoTranslationRequest request) {
        return service.translate("user-1", IMAGE, "image/jpeg", request);
    }

    @Test
    void allParagraphsFromAi_markedAi() {
        aiReturns(aiParagraph("p1", "ラーメン", "라면"), aiParagraph("p2", "餃子", "교자"));

        PhotoTranslationResponse response = run(request(paragraph("p1", "ラ-メン"), paragraph("p2", "餃子")));

        assertEquals("ja", response.sourceLanguageCode());
        assertEquals("ko", response.targetLanguageCode());
        TranslatedParagraph first = response.paragraphs().get(0);
        assertEquals("ラーメン", first.original()); // AI가 고친 원문
        assertEquals("라면", first.translated());
        assertEquals("발음", first.pronunciation());
        assertEquals(TranslationSource.AI, first.translationSource());
        assertTrue(google.calls.isEmpty());
    }

    @Test
    void nullOriginalFromAi_usesRequestText() {
        aiReturns(aiParagraph("p1", null, "라면"));

        assertEquals("ラ-メン", run(request(paragraph("p1", "ラ-メン"))).paragraphs().get(0).original());
    }

    @Test
    void unknownAndDuplicateIdsFromAi_ignored() {
        aiReturns(aiParagraph("p9", "x", "모르는 ID"), aiParagraph("p1", "a", "첫째"), aiParagraph("p1", "a", "둘째"));

        PhotoTranslationResponse response = run(request(paragraph("p1", "a")));

        assertEquals(1, response.paragraphs().size());
        assertEquals("첫째", response.paragraphs().get(0).translated());
        assertTrue(google.calls.isEmpty());
    }

    @Test
    void missingIdFromAi_fallsBackForThatParagraphOnly() {
        aiReturns(aiParagraph("p1", "a", "번역1"), aiParagraph("p3", "c", "번역3"));

        PhotoTranslationResponse response = run(request(paragraph("p1", "a"), paragraph("p2", "b"), paragraph("p3", "c")));

        assertEquals(List.of(List.of("b")), google.calls);
        assertEquals(TranslationSource.AI, response.paragraphs().get(0).translationSource());
        TranslatedParagraph second = response.paragraphs().get(1);
        assertEquals(TranslationSource.OCR_TEXT, second.translationSource());
        assertEquals("구글:b", second.translated());
        assertEquals("b", second.original());
        assertNull(second.pronunciation());
        assertEquals(TranslationSource.AI, response.paragraphs().get(2).translationSource());
    }

    @Test
    void aiFailure_allParagraphsFallBack() {
        ai.failure = new TranslationProviderException();

        PhotoTranslationResponse response = run(request(paragraph("p1", "a"), paragraph("p2", "b")));

        assertEquals(List.of(List.of("a", "b")), google.calls);
        assertTrue(response.paragraphs().stream().allMatch(p -> p.translationSource() == TranslationSource.OCR_TEXT));
    }

    @Test
    void aiAndFallbackFailure_throws503() {
        ai.failure = new TranslationProviderException();
        google.failure = new TranslationProviderException();

        BusinessException exception = assertThrows(BusinessException.class, () -> run(request(paragraph("p1", "a"))));

        assertEquals(ErrorCode.TRANSLATION_PROVIDER_UNAVAILABLE, exception.getErrorCode());
    }

    @Test
    void uncertainParagraph_keepsMarkerText() {
        aiReturns(new PhotoTranslationClient.Paragraph("p1", "???", PhotoTranslationResponse.UNREADABLE_MARKER,
            true, null, List.of()));

        TranslatedParagraph paragraph = run(request(paragraph("p1", "???"))).paragraphs().get(0);

        assertEquals(PhotoTranslationResponse.UNREADABLE_MARKER, paragraph.translated());
        assertTrue(paragraph.uncertain());
    }

    @Test
    void correctedOriginalWithMarker_returnedAsOriginal() {
        String corrected = "ラーメン " + PhotoTranslationResponse.UNREADABLE_MARKER;
        aiReturns(new PhotoTranslationClient.Paragraph("p1", corrected,
            "라멘 " + PhotoTranslationResponse.UNREADABLE_MARKER, true, null, List.of()));

        TranslatedParagraph paragraph = run(request(paragraph("p1", "ラ-メン 9?0"))).paragraphs().get(0);

        assertEquals(corrected, paragraph.original());
        assertEquals(TranslationSource.AI, paragraph.translationSource());
        assertTrue(paragraph.uncertain());
    }

    @Test
    void confirmedPrice_hasKrw() {
        when(exchangeService.getRates("JPY", "KRW")).thenReturn(new ExchangeRateResponse("JPY",
            Map.of("KRW", new BigDecimal("9.29")), LocalDate.of(2026, 11, 21), FETCHED_AT, false));
        aiReturns(aiParagraph("p1", new PhotoTranslationClient.AiPrice("980円", new BigDecimal("980"), "JPY", false)));

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "980円"))).paragraphs().get(0).prices().get(0);

        assertTrue(price.confirmed());
        assertEquals(new BigDecimal("9104"), price.krwAmount());
        assertEquals(new BigDecimal("9.29"), price.krwRate());
        assertEquals(FETCHED_AT, price.rateFetchedAt());
    }

    @Test
    void confirmedPrice_rateUnavailable_confirmedWithoutKrw() {
        when(exchangeService.getRates("JPY", "KRW")).thenThrow(new TranslationProviderException());
        aiReturns(aiParagraph("p1", new PhotoTranslationClient.AiPrice("980円", new BigDecimal("980"), "JPY", false)));

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "980円"))).paragraphs().get(0).prices().get(0);

        assertTrue(price.confirmed());
        assertNull(price.krwAmount());
        assertNull(price.krwRate());
        assertNull(price.rateFetchedAt());
    }

    @Test
    void krwPrice_confirmedWithoutRateLookup() {
        aiReturns(aiParagraph("p1", new PhotoTranslationClient.AiPrice("5,000원", new BigDecimal("5000"), "KRW", false)));

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "5,000원"))).paragraphs().get(0).prices().get(0);

        assertTrue(price.confirmed());
        assertEquals(new BigDecimal("5000"), price.krwAmount());
        verifyNoInteractions(exchangeService);
    }

    @Test
    void fallbackResultCountMismatch_throws503() {
        ai.failure = new TranslationProviderException();
        LineTranslationClient shortGoogle = (lines, source, target) ->
            new LineTranslationClient.Result("ja", List.of(new LineTranslationClient.Line("하나", null)));
        service = new PhotoTranslationService(inspector, validator, ai, shortGoogle, new PriceExtractor(), converter,
            rateLimiter, new PhotoTranslationSlots(4, 1));

        BusinessException exception = assertThrows(BusinessException.class,
            () -> run(request(paragraph("p1", "a"), paragraph("p2", "b"))));

        assertEquals(ErrorCode.TRANSLATION_PROVIDER_UNAVAILABLE, exception.getErrorCode());
    }

    @Test
    void uncertainPrice_notConfirmedNoKrw() {
        aiReturns(aiParagraph("p1", new PhotoTranslationClient.AiPrice("980円", new BigDecimal("980"), "JPY", true)));

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "980円"))).paragraphs().get(0).prices().get(0);

        assertFalse(price.confirmed());
        assertNull(price.krwAmount());
        verifyNoInteractions(exchangeService);
    }

    @Test
    void unknownCurrencyPrice_notConfirmed() {
        aiReturns(aiParagraph("p1", new PhotoTranslationClient.AiPrice("980", new BigDecimal("980"), null, false)));

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "980"))).paragraphs().get(0).prices().get(0);

        assertFalse(price.confirmed());
        assertNull(price.krwAmount());
    }

    @Test
    void unrecognizedCurrencyCode_notConfirmed() {
        aiReturns(aiParagraph("p1", new PhotoTranslationClient.AiPrice("980 XYZ", new BigDecimal("980"), "XYZ", false)));

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "980 XYZ"))).paragraphs().get(0).prices().get(0);

        assertFalse(price.confirmed());
        assertNull(price.krwAmount());
        verifyNoInteractions(exchangeService);
    }

    @Test
    void fallbackParagraphPrice_extractedButNotConfirmed() {
        ai.failure = new TranslationProviderException();

        PhotoTranslationResponse.Price price = run(request(paragraph("p1", "ラーメン 980円"))).paragraphs().get(0)
            .prices().get(0);

        assertEquals("JPY", price.currency());
        assertEquals(new BigDecimal("980"), price.amount());
        assertFalse(price.confirmed());
        assertNull(price.krwAmount());
        verifyNoInteractions(exchangeService);
    }

    @Test
    void validationFailure_consumesNoGlobalLimit() {
        doThrow(new BusinessException(ErrorCode.INVALID_REQUEST, "사진 크기가 요청한 크기와 다릅니다."))
            .when(validator).validate(any(), any());

        assertThrows(BusinessException.class, () -> run(request(paragraph("p1", "a"))));

        // 사용자·IP 한도는 인터셉터가 차감하고, 서비스는 검증을 통과한 뒤에만 전체 한도를 차감한다.
        verifyNoInteractions(rateLimiter);
        assertEquals(0, ai.calls);
    }

    @Test
    void rateLimitExceeded_throws429BeforeCallingAi() {
        doThrow(new TooManyRequestsException(30)).when(rateLimiter).acquireKeys(anyList());

        assertThrows(TooManyRequestsException.class, () -> run(request(paragraph("p1", "a"))));

        assertEquals(0, ai.calls);
        assertTrue(google.calls.isEmpty());
    }

    @Test
    void responseOrderFollowsRequest() {
        aiReturns(aiParagraph("p3", "c", "3"), aiParagraph("p1", "a", "1"), aiParagraph("p2", "b", "2"));

        PhotoTranslationResponse response = run(request(paragraph("p1", "a"), paragraph("p2", "b"), paragraph("p3", "c")));

        assertEquals(List.of("p1", "p2", "p3"), response.paragraphs().stream().map(TranslatedParagraph::id).toList());
    }
}
