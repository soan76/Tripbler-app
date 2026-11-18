package com.tripbler.backend.exchange.client;

import org.springframework.web.client.RestClient;

/** 다른 패키지의 테스트가 가짜 RestClient를 연결한 실제 클라이언트를 만들 수 있게 한다. */
public final class FrankfurterClientTestSupport {
    private FrankfurterClientTestSupport() {}

    public static FrankfurterExchangeRateClient create(RestClient restClient) {
        return new FrankfurterExchangeRateClient(restClient);
    }
}
