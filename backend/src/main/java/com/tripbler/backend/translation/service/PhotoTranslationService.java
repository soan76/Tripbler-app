package com.tripbler.backend.translation.service;

import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Currency;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.common.ratelimit.RateLimitBucket;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.client.PhotoTranslationClient;
import com.tripbler.backend.translation.dto.PhotoTranslationRequest;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.Price;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.TranslatedParagraph;
import com.tripbler.backend.translation.dto.PhotoTranslationResponse.TranslationSource;

/**
 * 사진 번역. 검증 → 동시 처리 자리(사용자별·전체) → 전체 호출 제한 → AI(Claude) 번역 순으로 처리하고, AI가 실패했거나 돌려주지 않은 문단은
 * 그 문단의 OCR 글자만 Google로 번역해 대신한다(translationSource OCR_TEXT, 발음 없음).
 * 가격은 AI가 확실하다고 한 것만 확정(confirmed)하고 원화로 바꾼다. 로그에는 개수와 시간만 남긴다.
 * 사용자별·IP별 호출 제한은 컨트롤러 인자 해석 전에 PhotoTranslationRateLimitInterceptor가 차감한다.
 */
@Service
public class PhotoTranslationService {

    private static final Logger log = LoggerFactory.getLogger(PhotoTranslationService.class);

    private static final String GLOBAL_KEY = "*";

    private static final List<RateLimitBucket> GLOBAL_LIMITS = List.of(
        RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_HOUR,
        RateLimitBucket.TRANSLATION_PHOTO_GLOBAL_DAY
    );

    private final PhotoTranslationSlots slots;
    private final PhotoImageInspector inspector;
    private final PhotoRequestValidator validator;
    private final PhotoTranslationClient client;
    private final LineTranslationClient fallbackClient;
    private final PriceExtractor priceExtractor;
    private final KrwPriceConverter priceConverter;
    private final AuthRateLimiter rateLimiter;
    private final TranslatedCurrencyFixer currencyFixer = new TranslatedCurrencyFixer();

    public PhotoTranslationService(
        PhotoImageInspector inspector,
        PhotoRequestValidator validator,
        @Qualifier("claudePhotoTranslationClient") PhotoTranslationClient client,
        @Qualifier("googleLineTranslationClient") LineTranslationClient fallbackClient,
        PriceExtractor priceExtractor,
        KrwPriceConverter priceConverter,
        AuthRateLimiter rateLimiter,
        PhotoTranslationSlots slots
    ) {
        this.slots = slots;
        this.inspector = inspector;
        this.validator = validator;
        this.client = client;
        this.fallbackClient = fallbackClient;
        this.priceExtractor = priceExtractor;
        this.priceConverter = priceConverter;
        this.rateLimiter = rateLimiter;
    }

    public PhotoTranslationResponse translate(
        String userId,
        byte[] image,
        String mediaType,
        PhotoTranslationRequest request
    ) {
        long startedAt = System.nanoTime();

        // 사용자별·IP별 한도는 인터셉터가 이미 차감했다(검증 실패 요청도 쓴다).
        validator.validate(request, inspector.inspect(image));

        // 사진 사본이 AI 호출·대체 번역 동안 메모리에 머무므로 사용자별·전체 동시 처리 수를 제한한다.
        // 자리가 없으면 기다리지 않고 429로 거절하며, 거절된 요청은 전체 한도를 쓰지 않는다.
        // 자리는 어떤 경우에도 try-with-resources로 돌려준다.
        try (PhotoTranslationSlots.Permit ignored = slots.acquire(userId)) {
            // 번역 제공자 호출이 실패해도 한도는 되돌리지 않는다(/lines와 같다).
            rateLimiter.acquireKeys(globalKeys());

            return process(image, mediaType, request, startedAt);
        }
    }

    private PhotoTranslationResponse process(
        byte[] image,
        String mediaType,
        PhotoTranslationRequest request,
        long startedAt
    ) {
        String source = request.sourceLanguageCode().toLowerCase(Locale.ROOT);
        String target = request.targetLanguageCode().toLowerCase(Locale.ROOT);
        List<PhotoTranslationRequest.Paragraph> paragraphs = request.paragraphs();

        String aiDetected = null;
        Map<String, PhotoTranslationClient.Paragraph> aiById = new HashMap<>();

        try {
            PhotoTranslationClient.Result result = client.translate(image, mediaType, paragraphs, source, target);
            aiDetected = result.detectedLanguageCode();
            Set<String> requested = new HashSet<>();
            paragraphs.forEach(paragraph -> requested.add(paragraph.id()));

            for (PhotoTranslationClient.Paragraph each : result.paragraphs()) {
                // 모르는 ID는 버리고, 중복 ID는 처음 것만 쓴다.
                if (each != null && requested.contains(each.id())) {
                    aiById.putIfAbsent(each.id(), each);
                }
            }
        } catch (TranslationProviderException exception) {
            // 실패 원인은 AI 클라이언트가 이미 남겼다.
            log.info("사진 번역 AI 실패, 전체 대체: paragraphs={}", paragraphs.size());
        }

        List<PhotoTranslationRequest.Paragraph> fallbackParagraphs = paragraphs.stream()
            .filter(paragraph -> !aiById.containsKey(paragraph.id()))
            .toList();

        Map<String, String> fallbackTranslated = new HashMap<>();
        String fallbackDetected = null;

        if (!fallbackParagraphs.isEmpty()) {
            log.info("사진 번역을 Google로 대체: paragraphs={} fallback={}", paragraphs.size(),
                fallbackParagraphs.size());
            LineTranslationClient.Result fallback = translateFallback(fallbackParagraphs, source, target);
            fallbackDetected = fallback.detectedLanguageCode();

            for (int index = 0; index < fallbackParagraphs.size(); index++) {
                fallbackTranslated.put(fallbackParagraphs.get(index).id(), fallback.lines().get(index).translated());
            }
        }

        String detectedSource = "auto".equals(source)
            ? firstNonNull(aiDetected, fallbackDetected, "auto")
            : source;

        Map<String, Optional<PriceExtractor.Found>> fallbackPrices = new HashMap<>();
        for (PhotoTranslationRequest.Paragraph paragraph : fallbackParagraphs) {
            fallbackPrices.put(paragraph.id(), priceExtractor.find(paragraph.text(), detectedSource));
        }

        // 환산할 통화를 모아 환율을 한 번에 조회한다.
        Set<String> currencies = new LinkedHashSet<>();
        aiById.values().forEach(each -> each.prices().stream()
            .filter(price -> isConfirmable(price) && !"KRW".equals(price.currency()))
            .forEach(price -> currencies.add(price.currency())));

        Map<String, Optional<ExchangeRateResponse>> rates =
            currencies.isEmpty() ? Map.of() : priceConverter.ratesFor(currencies);

        List<TranslatedParagraph> translated = new ArrayList<>(paragraphs.size());

        for (PhotoTranslationRequest.Paragraph paragraph : paragraphs) {
            PhotoTranslationClient.Paragraph ai = aiById.get(paragraph.id());

            translated.add(ai != null
                ? fromAi(paragraph, ai, rates)
                : fromFallback(paragraph, fallbackTranslated.get(paragraph.id()),
                    fallbackPrices.get(paragraph.id()), target));
        }

        log.info("사진 번역 완료: paragraphs={} fallback={} elapsedMs={}", paragraphs.size(),
            fallbackParagraphs.size(), (System.nanoTime() - startedAt) / 1_000_000);

        return new PhotoTranslationResponse(detectedSource, target, List.copyOf(translated));
    }

    /** 대체 목록을 Google로 한 번에 번역한다. 실패하거나 개수가 맞지 않으면 503. */
    private LineTranslationClient.Result translateFallback(
        List<PhotoTranslationRequest.Paragraph> paragraphs,
        String source,
        String target
    ) {
        try {
            LineTranslationClient.Result result = fallbackClient.translate(
                paragraphs.stream().map(PhotoTranslationRequest.Paragraph::text).toList(), source, target);

            if (result.lines().size() != paragraphs.size()) {
                throw new TranslationProviderException();
            }

            return result;
        } catch (TranslationProviderException exception) {
            throw new BusinessException(ErrorCode.TRANSLATION_PROVIDER_UNAVAILABLE);
        }
    }

    private TranslatedParagraph fromAi(
        PhotoTranslationRequest.Paragraph requested,
        PhotoTranslationClient.Paragraph ai,
        Map<String, Optional<ExchangeRateResponse>> rates
    ) {
        String original = ai.original() != null ? ai.original() : requested.text();
        List<Price> prices = ai.prices() == null
            ? List.of()
            : ai.prices().stream().map(price -> toAiPrice(price, rates)).toList();

        return new TranslatedParagraph(requested.id(), original, ai.translated(), ai.uncertain(),
            TranslationSource.AI, ai.pronunciation(), prices);
    }

    private Price toAiPrice(PhotoTranslationClient.AiPrice price, Map<String, Optional<ExchangeRateResponse>> rates) {
        Price unconfirmed = new Price(price.text(), price.amount(), price.currency(), false, null, null, null, false);

        if (!isConfirmable(price)) {
            return unconfirmed;
        }

        if ("KRW".equals(price.currency())) {
            return new Price(price.text(), price.amount(), "KRW", true,
                price.amount().setScale(0, RoundingMode.HALF_UP), null, null, false);
        }

        // confirmed는 가격이 확실한지만 뜻한다. 환율을 받지 못하면 원화 없이 확정으로 돌려준다.
        return priceConverter.convert(price.amount(), price.currency(), rates)
            .map(krw -> new Price(price.text(), price.amount(), price.currency(), true,
                krw.krwAmount(), krw.krwRate(), krw.fetchedAt(), krw.stale()))
            .orElseGet(() -> new Price(price.text(), price.amount(), price.currency(), true,
                null, null, null, false));
    }

    private static boolean isConfirmable(PhotoTranslationClient.AiPrice price) {
        return !price.uncertain() && price.amount() != null && isIsoCurrency(price.currency());
    }

    /** ISO 4217에 있는 통화 코드인지. 형식만 맞는 모르는 코드(예: XYZ)는 통화를 모르는 것으로 본다. */
    private static boolean isIsoCurrency(String code) {
        if (code == null || code.isBlank()) {
            return false;
        }

        try {
            Currency.getInstance(code);
            return true;
        } catch (IllegalArgumentException exception) {
            return false;
        }
    }

    private TranslatedParagraph fromFallback(
        PhotoTranslationRequest.Paragraph requested,
        String translated,
        Optional<PriceExtractor.Found> found,
        String target
    ) {
        // 번역기가 가격의 통화를 잘못 옮긴 경우(예: 중국어 ¥38 → "38엔") 원문 통화에 맞춘다.
        String fixed = found
            .map(each -> currencyFixer.fix(translated, each.amount(), each.currency(), target))
            .orElse(translated);
        List<Price> prices = found
            .map(each -> List.of(
                new Price(each.text(), each.amount(), each.currency(), false, null, null, null, false)))
            .orElse(List.of());

        return new TranslatedParagraph(requested.id(), requested.text(), fixed, false,
            TranslationSource.OCR_TEXT, null, prices);
    }

    private static String firstNonNull(String first, String second, String otherwise) {
        return first != null ? first : second != null ? second : otherwise;
    }

    private static List<AuthRateLimiter.Key> globalKeys() {
        List<AuthRateLimiter.Key> keys = new ArrayList<>(GLOBAL_LIMITS.size());

        for (RateLimitBucket bucket : GLOBAL_LIMITS) {
            keys.add(new AuthRateLimiter.Key(bucket, GLOBAL_KEY));
        }

        return keys;
    }
}
