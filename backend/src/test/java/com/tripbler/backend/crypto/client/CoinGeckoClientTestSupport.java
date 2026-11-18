package com.tripbler.backend.crypto.client;

import org.springframework.web.client.RestClient;

import com.tripbler.backend.crypto.config.CoinGeckoProperties;

/** 다른 패키지의 테스트가 가짜 RestClient를 연결한 실제 클라이언트를 만들 수 있게 한다. */
public final class CoinGeckoClientTestSupport {
    private CoinGeckoClientTestSupport() {}

    public static CoinGeckoCryptoMarketClient create(RestClient restClient, CoinGeckoProperties properties) {
        return new CoinGeckoCryptoMarketClient(restClient, properties);
    }
}
