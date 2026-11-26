package com.tripbler.backend.translation.service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import com.tripbler.backend.common.exception.BusinessException;
import com.tripbler.backend.common.exception.ErrorCode;
import com.tripbler.backend.common.exception.TranslationProviderException;
import com.tripbler.backend.common.ratelimit.AuthRateLimiter;
import com.tripbler.backend.common.ratelimit.RateLimitBucket;
import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.exchange.service.ExchangeService;
import com.tripbler.backend.translation.client.LineTranslationClient;
import com.tripbler.backend.translation.dto.LineTranslationRequest;
import com.tripbler.backend.translation.dto.LineTranslationResponse;
import com.tripbler.backend.translation.dto.LineTranslationResponse.Price;
import com.tripbler.backend.translation.dto.LineTranslationResponse.TranslatedLine;

/**
 * 찍기 모드의 줄별 번역. 사용자별·IP별·전체 호출 제한을 확인한 뒤 줄 목록을 번역하고, 줄에서 찾은 가격을
 * 오늘 환율로 원화로 바꿔 함께 돌려준다. 환율을 받지 못한 가격은 원화 없이 둔다(번역은 실패시키지 않음).
 * Claude를 쓸 수 없으면(키·크레딧 없음, 장애, 거절 등) Google 번역으로 대체한다. 이때 발음은 없다.
 *
 * <p>요청 하나의 최악 처리 시간(외부 호출 기준): Claude 최대 90초({@code ClaudeLineTranslationClient.MAX_TIMEOUT},
 * 재시도 없음) + Google 대체 연결 3초·읽기 5초 + 환율 조회 대기 최대 {@link KrwPriceConverter#RATE_LOOKUP_BUDGET}(5초) = 약 103초.
 * 앱의 요청 시간 제한({@code LineTranslationApiService.defaultTimeout}, 120초)은 이보다 길게 둔다.
 */
@Service
public class LineTranslationService implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(LineTranslationService.class);

    /** 한 번에 보낼 수 있는 전체 글자 수. 기존 번역 API와 같다. */
    static final int MAX_TOTAL_CHARACTERS = 5000;

    private static final String GLOBAL_KEY = "*";

    private static final List<RateLimitBucket> USER_LIMITS = List.of(
        RateLimitBucket.TRANSLATION_LINES_USER_MINUTE,
        RateLimitBucket.TRANSLATION_LINES_USER_DAY
    );

    private static final List<RateLimitBucket> IP_LIMITS = List.of(
        RateLimitBucket.TRANSLATION_LINES_IP_MINUTE,
        RateLimitBucket.TRANSLATION_LINES_IP_DAY
    );

    private static final List<RateLimitBucket> GLOBAL_LIMITS = List.of(
        RateLimitBucket.TRANSLATION_LINES_GLOBAL_HOUR,
        RateLimitBucket.TRANSLATION_LINES_GLOBAL_DAY
    );

    private final LineTranslationClient client;
    private final LineTranslationClient fallbackClient;
    private final PriceExtractor priceExtractor;
    private final KrwPriceConverter priceConverter;
    private final AuthRateLimiter rateLimiter;
    private final boolean ownsPriceConverter;
    private final TranslatedCurrencyFixer currencyFixer = new TranslatedCurrencyFixer();

    @Autowired
    public LineTranslationService(
        @Qualifier("claudeLineTranslationClient") LineTranslationClient client,
        @Qualifier("googleLineTranslationClient") LineTranslationClient fallbackClient,
        PriceExtractor priceExtractor,
        KrwPriceConverter priceConverter,
        AuthRateLimiter rateLimiter
    ) {
        this(client, fallbackClient, priceExtractor, priceConverter, rateLimiter, false);
    }

    private LineTranslationService(
        LineTranslationClient client,
        LineTranslationClient fallbackClient,
        PriceExtractor priceExtractor,
        KrwPriceConverter priceConverter,
        AuthRateLimiter rateLimiter,
        boolean ownsPriceConverter
    ) {
        this.ownsPriceConverter = ownsPriceConverter;
        this.client = client;
        this.fallbackClient = fallbackClient;
        this.priceExtractor = priceExtractor;
        this.priceConverter = priceConverter;
        this.rateLimiter = rateLimiter;
    }

    /** 테스트에서 환율 서비스 대역을 바로 넘길 때 쓴다. */
    LineTranslationService(
        LineTranslationClient client,
        LineTranslationClient fallbackClient,
        PriceExtractor priceExtractor,
        ExchangeService exchangeService,
        AuthRateLimiter rateLimiter
    ) {
        this(client, fallbackClient, priceExtractor, new KrwPriceConverter(exchangeService), rateLimiter, true);
    }

    /** 테스트에서 환율 대기 시간을 줄일 때 쓴다. */
    LineTranslationService(
        LineTranslationClient client,
        LineTranslationClient fallbackClient,
        PriceExtractor priceExtractor,
        ExchangeService exchangeService,
        AuthRateLimiter rateLimiter,
        Duration rateLookupBudget
    ) {
        this(client, fallbackClient, priceExtractor, new KrwPriceConverter(exchangeService, rateLookupBudget),
            rateLimiter, true);
    }

    /** 테스트 생성자가 직접 만든 환율 조회기만 닫는다(Spring이 주입한 것은 컨테이너가 닫는다). */
    @Override
    public void destroy() {
        if (ownsPriceConverter) {
            priceConverter.destroy();
        }
    }

    /**
     * @param clientIp 접속 주소(컨트롤러가 getRemoteAddr로 넘긴다). IP별 한도의 키.
     */
    public LineTranslationResponse translate(String userId, String clientIp, LineTranslationRequest request) {
        List<String> lines = request.lines().stream().map(String::trim).toList();

        int totalCharacters = lines.stream().mapToInt(String::length).sum();

        if (totalCharacters > MAX_TOTAL_CHARACTERS) {
            throw new BusinessException(
                ErrorCode.INVALID_REQUEST,
                "한 번에 번역할 수 있는 글자는 모두 합쳐 5000자 이하입니다."
            );
        }

        String source = request.sourceLanguageCode().toLowerCase(Locale.ROOT);
        String target = request.targetLanguageCode().toLowerCase(Locale.ROOT);

        // 검증을 통과한 요청만 한도를 쓴다.
        // 번역 제공자 호출이 실패해도 한도는 되돌리지 않는다(실패를 반복해 비용을 쓰는 것도 막는다).
        rateLimiter.acquireKeys(limitsFor(userId, clientIp));

        LineTranslationClient.Result result = translateLines(lines, source, target);

        String detectedSource = "auto".equals(source)
            ? Optional.ofNullable(result.detectedLanguageCode()).orElse("auto")
            : source;

        List<Optional<PriceExtractor.Found>> foundPrices = lines.stream()
            .map(original -> priceExtractor.find(original, detectedSource))
            .toList();

        Set<String> currencies = new LinkedHashSet<>();
        foundPrices.forEach(found -> found
            .map(PriceExtractor.Found::currency)
            .filter(currency -> !"KRW".equals(currency))
            .ifPresent(currencies::add));

        Map<String, Optional<ExchangeRateResponse>> ratesByCurrency = priceConverter.ratesFor(currencies);
        List<TranslatedLine> translatedLines = new ArrayList<>(lines.size());

        for (int index = 0; index < lines.size(); index++) {
            String original = lines.get(index);
            LineTranslationClient.Line line = result.lines().get(index);

            Optional<PriceExtractor.Found> found = foundPrices.get(index);

            Price price = found
                .map(each -> toPrice(each, ratesByCurrency))
                .orElse(null);

            // 번역기가 가격의 통화를 잘못 옮긴 경우(예: 중국어 ¥38 → "38엔") 원문 통화에 맞춘다.
            String translated = found
                .map(each -> currencyFixer.fix(line.translated(), each.amount(), each.currency(), target))
                .orElse(line.translated());

            translatedLines.add(new TranslatedLine(original, translated, line.pronunciation(), price));
        }

        return new LineTranslationResponse(detectedSource, target, List.copyOf(translatedLines));
    }

    /** Claude로 번역하고, 실패하면 Google로 한 번 더 시도한다. 둘 다 실패하면 503. */
    private LineTranslationClient.Result translateLines(List<String> lines, String source, String target) {
        try {
            return client.translate(lines, source, target);
        } catch (TranslationProviderException exception) {
            // 실패 원인은 Claude 클라이언트가 이미 남겼다. 여기서는 대체했다는 사실만 남긴다.
            log.info("줄별 번역을 Google로 대체: lines={}", lines.size());
            return fallbackClient.translate(lines, source, target);
        }
    }

    private Price toPrice(PriceExtractor.Found found, Map<String, Optional<ExchangeRateResponse>> ratesByCurrency) {
        if ("KRW".equals(found.currency())) {
            return new Price(found.text(), found.amount(), "KRW", null, null, null, false);
        }

        return priceConverter.convert(found.amount(), found.currency(), ratesByCurrency)
            .map(krw -> new Price(found.text(), found.amount(), found.currency(),
                krw.krwAmount(), krw.krwRate(), krw.fetchedAt(), krw.stale()))
            .orElseGet(() -> new Price(found.text(), found.amount(), found.currency(), null, null, null, false));
    }

    private static List<AuthRateLimiter.Key> limitsFor(String userId, String clientIp) {
        List<AuthRateLimiter.Key> keys =
            new ArrayList<>(USER_LIMITS.size() + IP_LIMITS.size() + GLOBAL_LIMITS.size());

        for (RateLimitBucket bucket : USER_LIMITS) {
            keys.add(new AuthRateLimiter.Key(bucket, userId));
        }

        for (RateLimitBucket bucket : IP_LIMITS) {
            keys.add(new AuthRateLimiter.Key(bucket, clientIp));
        }

        for (RateLimitBucket bucket : GLOBAL_LIMITS) {
            keys.add(new AuthRateLimiter.Key(bucket, GLOBAL_KEY));
        }

        return keys;
    }
}
