package com.tripbler.backend.translation.service;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.tripbler.backend.common.exception.TooManyRequestsException;

/**
 * 사진 번역 동시 처리 자리. 요청마다 사진 사본이 AI 호출·대체 번역 동안 메모리에 머물므로 서버 전체 자리 수와
 * 사용자별 자리 수를 함께 제한한다. 사용자별 자리가 없으면 계정 하나가 서버 전체 자리를 모두 차지할 수 있다.
 * 자리가 없으면 기다리지 않고 429(Retry-After 3초)로 거절한다. 사용자 자리를 먼저 잡아, 같은 사용자의 두 번째
 * 요청이 전체 자리를 잠깐이라도 쓰지 않게 한다. 받은 {@link Permit}은 반드시 닫는다(try-with-resources).
 */
@Component
public class PhotoTranslationSlots {

    private static final Logger log = LoggerFactory.getLogger(PhotoTranslationSlots.class);

    // 자리가 없어 거절할 때 알리는 재시도 대기 시간(초). 임시값.
    static final long BUSY_RETRY_AFTER_SECONDS = 3;

    private final int capacity;
    private final int perUserCapacity;
    private final Semaphore global;
    // 처리 중인 요청이 있는 사용자만 둔다. 0이 되면 항목을 지워 사용자 수만큼 쌓이지 않게 한다.
    private final ConcurrentHashMap<String, Integer> inFlightByUser = new ConcurrentHashMap<>();

    public PhotoTranslationSlots(
        // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
        @Value("${translation.photo.max-concurrent:4}") int maxConcurrent,
        // 임시값: 실제 Claude 측정(작업 14) 뒤 확정
        @Value("${translation.photo.max-concurrent-per-user:1}") int maxConcurrentPerUser
    ) {
        this.capacity = Math.max(1, maxConcurrent);
        this.perUserCapacity = Math.max(1, maxConcurrentPerUser);
        this.global = new Semaphore(capacity);
    }

    /** 사용자 자리와 전체 자리를 잡는다. 둘 중 하나라도 없으면 아무것도 잡지 않고 429. */
    public Permit acquire(String userId) {
        // 사용자 ID는 로그에 남기지 않는다.
        if (!tryAcquireUser(userId)) {
            log.info("사진 번역 사용자별 동시 처리 상한 도달");
            throw new TooManyRequestsException(BUSY_RETRY_AFTER_SECONDS);
        }

        if (!global.tryAcquire()) {
            releaseUser(userId);
            log.info("사진 번역 전체 동시 처리 상한 도달");
            throw new TooManyRequestsException(BUSY_RETRY_AFTER_SECONDS);
        }

        return new Permit(userId);
    }

    public int capacity() {
        return capacity;
    }

    public int perUserCapacity() {
        return perUserCapacity;
    }

    /** 지금 처리 중인 요청이 있는 사용자 수(테스트·점검용). */
    int trackedUsers() {
        return inFlightByUser.size();
    }

    private boolean tryAcquireUser(String userId) {
        boolean[] acquired = {false};
        // compute는 키 단위로 원자적이다.
        inFlightByUser.compute(userId, (key, count) -> {
            int current = count == null ? 0 : count;
            if (current >= perUserCapacity) {
                return count;
            }
            acquired[0] = true;
            return current + 1;
        });
        return acquired[0];
    }

    private void releaseUser(String userId) {
        // null을 돌려주면 항목이 지워진다.
        inFlightByUser.computeIfPresent(userId, (key, count) -> count <= 1 ? null : count - 1);
    }

    /** 잡은 자리. 닫으면 전체 자리와 사용자 자리를 돌려준다. 두 번 닫아도 한 번만 돌려준다. */
    public final class Permit implements AutoCloseable {

        private final String userId;
        private boolean closed;

        private Permit(String userId) {
            this.userId = userId;
        }

        @Override
        public synchronized void close() {
            if (closed) {
                return;
            }
            closed = true;
            global.release();
            releaseUser(userId);
        }
    }
}
