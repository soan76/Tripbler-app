package com.tripbler.backend.common.cache;

import java.net.SocketException;
import java.net.UnknownHostException;

/**
 * 외부 제공자의 일시적 장애인지 판정한다. 일시적 장애일 때만 캐시의 마지막 성공값으로 대신 응답한다.
 * 대상: 시간 초과, 연결 실패(연결 거부·끊김, 호스트 조회 실패), 제공자의 429·5xx 응답.
 * 제외: 인증 오류, 잘못된 요청, 응답 형식 오류처럼 다시 요청해도 나아지지 않는 실패.
 */
public final class ProviderFailures {
    private ProviderFailures() {}

    public static boolean isTransient(Throwable failure) {
        if (Timeouts.isTimeout(failure)) return true;
        for (int depth = 0; failure != null && depth < 20; depth++, failure = failure.getCause()) {
            if (failure instanceof TransientProviderFailure || failure instanceof SocketException ||
                failure instanceof UnknownHostException) return true;
        }
        return false;
    }

    public static boolean isTransientStatus(int status) {
        return status == 429 || (status >= 500 && status <= 599);
    }

    /** 제공자의 429·5xx 응답을 원인으로 표시한다. 외부 URL·키·본문을 담지 않는다. */
    public static final class TransientProviderFailure extends RuntimeException {
        public TransientProviderFailure() {
            super("Provider temporarily unavailable", null, false, false);
        }
    }
}
