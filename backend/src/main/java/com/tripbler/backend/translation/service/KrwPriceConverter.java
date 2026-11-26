package com.tripbler.backend.translation.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.LinkedHashMap;
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
import org.springframework.stereotype.Component;

import com.tripbler.backend.exchange.dto.ExchangeRateResponse;
import com.tripbler.backend.exchange.service.ExchangeService;

/**
 * 번역에서 찾은 가격을 오늘 환율로 원화로 바꾼다(찍기 모드 줄별 번역, 사진 번역이 함께 쓴다).
 * 환율을 받지 못한 통화는 원화 없이 둔다(번역은 실패시키지 않음).
 */
@Component
public class KrwPriceConverter implements DisposableBean {

    private static final Logger log = LoggerFactory.getLogger(KrwPriceConverter.class);

    /**
     * 한 번에 환율 조회 전체를 기다리는 최대 시간. 통화마다 환율 조회는 Frankfurter(연결 3초·읽기 5초)가
     * 일시 장애면 대체 출처(연결 2초·읽기 3초)까지 이어져 한 통화에 13초 넘게 걸릴 수 있고, 가격 통화는 최대
     * 7종(JPY CNY USD EUR GBP THB VND)이다. 그래서 통화들을 동시에 묻고 모두 합쳐 이 시간까지만 기다린다.
     * 늦은 통화는 원화 없이 돌려주고(번역은 그대로), 조회는 뒤에서 끝까지 진행돼 환율 캐시를 채운다.
     */
    static final Duration RATE_LOOKUP_BUDGET = Duration.ofSeconds(5);

    // 환율 조회 스레드. 대부분 환율 캐시(5분)에서 바로 끝난다. 큐가 차면 그 통화는 원화 없이 돌려준다.
    private static final int RATE_LOOKUP_THREADS = 8;
    private static final int RATE_LOOKUP_QUEUE = 64;

    /** 원화 환산 결과. */
    public record KrwConversion(BigDecimal krwAmount, BigDecimal krwRate, LocalDateTime fetchedAt, boolean stale) {
    }

    private final ExchangeService exchangeService;
    private final Duration rateLookupBudget;
    private final ExecutorService rateExecutor;

    @Autowired
    public KrwPriceConverter(ExchangeService exchangeService) {
        this(exchangeService, RATE_LOOKUP_BUDGET);
    }

    /** 테스트에서 환율 대기 시간을 줄일 때 쓴다. */
    KrwPriceConverter(ExchangeService exchangeService, Duration rateLookupBudget) {
        this.exchangeService = exchangeService;
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

    /** 원화이거나 환율이 없으면 비어 있다. 금액은 소수 없이 반올림(HALF_UP)한다. */
    public Optional<KrwConversion> convert(
        BigDecimal amount,
        String currency,
        Map<String, Optional<ExchangeRateResponse>> rates
    ) {
        if ("KRW".equals(currency)) {
            return Optional.empty();
        }

        Optional<ExchangeRateResponse> response = rates.getOrDefault(currency, Optional.empty());
        Optional<BigDecimal> rate = response
            .map(ExchangeRateResponse::rates)
            .map(byCurrency -> byCurrency.get("KRW"));

        if (rate.isEmpty()) {
            return Optional.empty();
        }

        return Optional.of(new KrwConversion(
            amount.multiply(rate.get()).setScale(0, RoundingMode.HALF_UP),
            rate.get(),
            response.get().fetchedAt(),
            response.get().stale()
        ));
    }

    /**
     * 통화마다 한 번씩(환율 서비스 캐시도 있지만 요청 안에서 줄마다 다시 부르지 않게) 동시에 묻고, 모두 합쳐
     * {@link #rateLookupBudget}까지만 기다린다. 늦거나 실패한 통화는 비어 있다(실패한 통화도 다시 묻지 않음).
     */
    public Map<String, Optional<ExchangeRateResponse>> ratesFor(Set<String> currencies) {
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
}
