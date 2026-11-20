# 느린 외부 응답과 History 전송 최적화

| 데이터 | 정상 TTL | TTL 만료 후 일시적 장애 fallback 허용 기간 |
|---|---|---|
| Crypto 현재가 | 60초 | 10분 |
| Crypto History | 15분 | 24시간 |
| 국가 통화 환율 | 5분 | 3일 |
| 국가 통화 History | 1시간 | 7일 |

Crypto 설정은 `crypto.cache.price-ttl`, `history-ttl`, `price-stale-window`, `history-stale-window`로 변경한다.
캐시는 서버 인스턴스 메모리에 저장한다. 재시작 시 비워지며 서버 간 공유되지 않는다.
국가 통화는 현재가 256개/History 512개, Crypto는 각각 최대 64개 키로 제한한다.

일시적 장애만 fallback 대상이다(`common/cache/ProviderFailures.isTransient`).
- 대상: 시간 초과, 연결 실패(연결 거부·끊김 등 `SocketException`, 호스트 조회 실패 `UnknownHostException`), 제공자의 429·5xx 응답.
- 제외: 그 밖의 4xx(인증 오류, 잘못된 통화·날짜 등), 잘못된 응답 본문, 유효성 오류, TLS 오류. 다시 요청해도 나아지지 않으므로 성공으로 바꾸지 않는다.
- 429·5xx는 클라이언트가 예외 원인에 `ProviderFailures.TransientProviderFailure` 표시를 붙여 알린다(Frankfurter는 `ExchangeProviderException(int)`, CoinGecko는 클라이언트 안에서).
CoinGecko 장애는 안전한 종류 정보(시간 초과는 `SocketTimeoutException`, 그 밖의 일시적 장애는 `TransientProviderFailure`)만 보존하고 외부 URL/키/본문이 포함될 수 있는 원본 예외는 전달하지 않는다.
캐시에 값이 없거나 허용 기간이 지났으면 일시적 장애라도 원래 오류를 그대로 돌려준다.
fallback 응답은 `stale: true`, 정상 응답은 `stale: false`이며, 원래 `fetchedAt`을 보존한다.

## 국가 통화 최신 환율의 대체 출처

Frankfurter가 일시적으로 실패하면(위와 같은 기준) 캐시보다 먼저 대체 출처 fawazahmed0 currency-api
(`exchange/client/CurrencyApiExchangeRateClient`, 키 없음, 하루 1회 갱신)에서 최신 환율을 받는다.
- 순서: Frankfurter → 대체 출처 → 캐시의 마지막 성공값(`stale: true`) → 원래 오류. 대체 출처가 실패하면 Frankfurter의 원래 예외로 캐시 fallback 여부를 정한다.
- 일시적 장애가 아닌 Frankfurter 실패(4xx 등)와 기간별 시세는 대체 출처를 쓰지 않는다.
- 요청: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{오늘 UTC 날짜}/v1/currencies/{소문자 기준 통화}.json`. 404면 전날 날짜로 한 번 더 요청한다(`@latest`는 CDN 캐시로 하루 늦을 수 있어 쓰지 않는다). 배포 주소마다 값이 조금 달라 한 주소만 쓴다.
- 요청한 통화가 하나라도 없거나 값이 0 이하·숫자가 아니면 실패로 본다. 응답 `date`가 전날~오늘(UTC)을 벗어나도(미래이거나 이틀 이상 지남) 실패로 본다. 이런 실패는 일시적 장애가 아니다.
- 시간 제한: 연결 2초, 응답 3초(Frankfurter를 이미 기다린 뒤라 더 짧게).
- 응답의 `source` 필드: 평소 `FRANKFURTER`, 대체 출처 값이면 `CURRENCY_API`(stale로 돌려줄 때도 원래 출처 유지). 두 출처는 기준이 달라 값이 조금 다를 수 있다. 필드 추가라 기존 앱은 무시한다.
- 배포 환경에 나가는 통신 제한이 있으면 `cdn.jsdelivr.net`을 허용해야 한다.
- 대체 출처 값도 같은 캐시 키에 저장되지만 TTL은 1분이다(Frankfurter 값은 5분). Frankfurter가 복구되면 1분 안에 돌아간다. stale 허용 기간(3일)은 각 값의 만료 시각부터 센다(`TimeoutFallbackCache`의 값별 TTL `get`).
- 캐시된 마지막 값(만료됐어도)의 `rateDate`가 대체 값의 `rateDate`보다 뒤면 대체 값을 버리고 Frankfurter의 원래 예외로 처리한다. 그래서 캐시가 그 값을 `stale: true`로 돌려준다(허용 기간이 지났으면 원래 오류). 갱신 시각만 최신이고 기준일은 더 과거인 응답을 막기 위한 규칙이다. 기준일이 같거나 대체 값이 더 최근이면 대체 값을 쓴다.
fallback 후 15초 동안 같은 키의 재시도 폭주를 억제한다. 이 기간은 원래 만료/fallback 기한을 연장하지 않는다.
캐시 키에는 코인/통화 또는 기준·대상 통화/기간(법정 통화는 시작·종료일)이 포함된다.

## History 응답 축소

두 History 엔드포인트에 `maxPoints`(기본 300, 허용 16~1000)를 추가했다.
원본 조회/캐시 데이터는 유지하고 REST 응답에서만 샘플링한다.
첫/마지막 점과 구간별 최저·최고점을 보존한다. 값이나 타임스탬프를 만들어내지 않으며 반환 순서는 오름차순이다.
축소된 데이터는 표시용이며 원본의 모든 중간 포인트를 포함하지 않는다.

## 압축

`server.compression.enabled=true`, JSON MIME 타입, 최소 1024바이트로 설정했다.
클라이언트가 gzip을 허용할 때만 압축하고, 표준 HTTP 클라이언트의 자동 해제를 사용한다.
`CompressionTest`는 외부 API/DB 없이 실제 embedded HTTP 서버를 띄워 gzip 헤더, 압축 크기, 해제한 본문의 동일성을 검증한다.

```powershell
.\gradlew.bat test --tests "com.tripbler.backend.crypto.*" --tests "com.tripbler.backend.exchange.*" --tests "com.tripbler.backend.common.cache.*" --tests "com.tripbler.backend.common.chart.*"
```

외부 CoinGecko/Frankfurter 실통신이나 배포된 프록시의 압축 설정까지 검증하는 테스트는 아니다.
