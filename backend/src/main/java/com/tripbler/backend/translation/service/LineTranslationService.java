package com.tripbler.backend.translation.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;

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
 * 재시도 없음) + Google 대체 연결 3초·읽기 5초 + 환율 조회 대기 최대 {@link #RATE_LOOKUP_BUDGET}(5초) = 약 103초.
 * 앱의 요청 시간 제한({@code LineTranslationApiService.defaultTimeout}, 120초)은 이보다 길게 둔다.
 */
@Service
public class LineTranslationService implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(LineTranslationService.class);

    /** 한 번에 보낼 수 있는 전체 글자 수. 기존 번역 API와 같다. */
    static final int MAX_TOTAL_CHARACTERS = 5000;

    private static final String GLOBAL_KEY = "*";

    /**
     * 한 요청 안에서 환율 조회 전체를 기다리는 최대 시간. 통화마다 환율 조회는 Frankfurter(연결 3초·읽기 5초)가
     * 일시 장애면 대체 출처(연결 2초·읽기 3초)까지 이어져 한 통화에 13초 넘게 걸릴 수 있고, 가격 통화는 최대
     * 7종(JPY CNY USD EUR GBP THB VND)이다. 그래서 통화들을 동시에 묻고 모두 합쳐 이 시간까지만 기다린다.
     * 늦은 통화는 원화 없이 돌려주고(번역은 그대로), 조회는 뒤에서 끝까지 진행돼 환율 캐시를 채운다.
     */
    static final Duration RATE_LOOKUP_BUDGET = Duration.ofSeconds(5);

    // 환율 조회 스레드. 대부분 환율 캐시(5분)에서 바로 끝난다. 큐가 차면 그 통화는 원화 없이 돌려준다.
    private static final int RATE_LOOKUP_THREADS = 8;
    private static final int RATE_LOOKUP_QUEUE = 64;

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
    private final ExchangeService exchangeService;
    private final AuthRateLimiter rateLimiter;
    private final ExecutorService rateExecutor;
    private final Duration rateLookupBudget;

    @Autowired
    public LineTranslationService(
        @Qualifier("claudeLineTranslationClient") LineTranslationClient client,
        @Qualifier("googleLineTranslationClient") LineTranslationClient fallbackClient,
        PriceExtractor priceExtractor,
        ExchangeService exchangeService,
        AuthRateLimiter rateLimiter
    ) {
        this(client, fallbackClient, priceExtractor, exchangeService, rateLimiter, RATE_LOOKUP_BUDGET);
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
        this.client = client;
        this.fallbackClient = fallbackClient;
        this.priceExtractor = priceExtractor;
        this.exchangeService = exchangeService;
        this.rateLimiter = rateLimiter;
        this.rateLookupBudget = rateLookupBudget;
        this.rateExecutor = newRateExecutor();
    }

    private static ExecutorService newRateExecutor() {
        AtomicInteger threadNumber = new AtomicInteger();
        ThreadPoolExecutor executor = new ThreadPoolExecutor(
            RATE_LOOKUP_THREADS,
            RATE_LOOKUP_THREADS,
            30,
            TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(RATE_LOOKUP_QUEUE),
            runnable -> {
                Thread thread = new Thread(runnable, "line-translation-rate-" + threadNumber.incrementAndGet());
                thread.setDaemon(true);
                return thread;
            }
        );
        executor.allowCoreThreadTimeOut(true);
        return executor;
    }

    @Override
    public void destroy() {
        rateExecutor.shutdownNow();
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

        Map<String, Optional<ExchangeRateResponse>> ratesByCurrency = krwRatesFor(currencies);
        List<TranslatedLine> translatedLines = new ArrayList<>(lines.size());

        for (int index = 0; index < lines.size(); index++) {
            String original = lines.get(index);
            LineTranslationClient.Line line = result.lines().get(index);

            Price price = foundPrices.get(index)
                .map(found -> toPrice(found, ratesByCurrency))
                .orElse(null);

            translatedLines.add(new TranslatedLine(original, line.translated(), line.pronunciation(), price));
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

        Optional<ExchangeRateResponse> rates = ratesByCurrency.getOrDefault(found.currency(), Optional.empty());
        Optional<BigDecimal> rate = rates
            .map(ExchangeRateResponse::rates)
            .map(byCurrency -> byCurrency.get("KRW"));

        if (rate.isEmpty()) {
            return new Price(found.text(), found.amount(), found.currency(), null, null, null, false);
        }

        ExchangeRateResponse response = rates.get();

        return new Price(
            found.text(),
            found.amount(),
            found.currency(),
            found.amount().multiply(rate.get()).setScale(0, RoundingMode.HALF_UP),
            rate.get(),
            response.fetchedAt(),
            response.stale()
        );
    }

    /**
     * 통화마다 한 번씩(환율 서비스 캐시도 있지만 요청 안에서 줄마다 다시 부르지 않게) 동시에 묻고, 모두 합쳐
     * {@link #rateLookupBudget}까지만 기다린다. 늦거나 실패한 통화는 비어 있다(실패한 통화도 다시 묻지 않음).
     */
    private Map<String, Optional<ExchangeRateResponse>> krwRatesFor(Set<String> currencies) {
        Map<String, Optional<ExchangeRateResponse>> rates = new HashMap<>();
        Map<String, CompletableFuture<Optional<ExchangeRateResponse>>> pending = new LinkedHashMap<>();

        for (String currency : currencies) {
            try {
                pending.put(currency, CompletableFuture.supplyAsync(() -> krwRates(currency), rateExecutor));
            } catch (RejectedExecutionException exception) {
                log.info("가격 원화 환산 생략: currency={} reason=busy", currency);
                rates.put(currency, Optional.empty());
            }
        }

        long deadline = System.nanoTime() + rateLookupBudget.toNanos();

        for (Map.Entry<String, CompletableFuture<Optional<ExchangeRateResponse>>> entry : pending.entrySet()) {
            String currency = entry.getKey();
            long remaining = Math.max(0L, deadline - System.nanoTime());

            try {
                rates.put(currency, entry.getValue().get(remaining, TimeUnit.NANOSECONDS));
            } catch (TimeoutException exception) {
                // 아직 큐에서 기다리는 조회는 취소해 나중에 헛되이 실행되지 않게 한다(supplyAsync는 취소된
                // 작업을 건너뛴다). 이미 시작한 조회는 끊지 않는다(false). 끝나면 환율 캐시에 남아 다음 요청이 쓴다.
                entry.getValue().cancel(false);
                log.info("가격 원화 환산 생략: currency={} reason=timeout", currency);
                rates.put(currency, Optional.empty());
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                entry.getValue().cancel(false);
                rates.put(currency, Optional.empty());
            } catch (ExecutionException exception) {
                Throwable cause = exception.getCause();
                log.info("가격 원화 환산 생략: currency={} reason={}", currency,
                    cause == null ? "-" : cause.getClass().getSimpleName());
                rates.put(currency, Optional.empty());
            }
        }

        return rates;
    }

    private Optional<ExchangeRateResponse> krwRates(String currency) {
        try {
            return Optional.of(exchangeService.getRates(currency, "KRW"));
        } catch (RuntimeException exception) {
            // 환율 제공자가 모르는 통화(예: VND)이거나 장애면 원화 없이 번역만 돌려준다.
            log.info("가격 원화 환산 생략: currency={} reason={}", currency, exception.getClass().getSimpleName());
            return Optional.empty();
        }
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
