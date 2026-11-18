package com.tripbler.backend.common.exception;

import com.tripbler.backend.common.cache.ProviderFailures;

public class ExchangeProviderException
    extends BusinessException {

    public ExchangeProviderException(int providerStatus) {
        super(
            ErrorCode.EXCHANGE_PROVIDER_UNAVAILABLE,
            "환율 제공 서비스 요청에 실패했습니다. "
                + "providerStatus="
                + providerStatus,
            // 429·5xx는 일시적 장애로 표시해 캐시가 마지막 성공값으로 대신 응답할 수 있게 한다.
            ProviderFailures.isTransientStatus(providerStatus)
                ? new ProviderFailures.TransientProviderFailure()
                : null
        );
    }

    public ExchangeProviderException(Throwable cause) {
        super(
            ErrorCode.EXCHANGE_PROVIDER_UNAVAILABLE,
            "환율 제공 서비스에 연결할 수 없습니다.",
            cause
        );
    }
}