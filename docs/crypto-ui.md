# 암호화폐 통화 행 연결

- `lib/crypto`: Tripbler 암호화폐 API, 코인/현재가 모델, 목록·선택·현재가 상태.
- `lib/presentation/exchange`: 공통 `DisplayCurrency`와 두 도메인을 화면에 연결하는 `ExchangeDisplayProvider`.
- 기존 ExchangeProvider와 환율 API에는 암호화폐 심볼을 전달하지 않는다.
- 통화 관리와 메인은 공통 모델을 사용한다. 메인의 CurrencyRow/AmountInputField를 재사용한다.

## 서버 계약

`GET /api/v1/crypto/coins`의 `symbol`, `name`으로 지원 목록을 구성한다. 7개 코인은 Flutter 제품 코드에 하드코딩하지 않는다.
`GET /api/v1/crypto/price?coin=BTC&currency=KRW`의 `symbol`, `currency`, `price`, `fetchedAt`을 사용한다.
외부 API ID/키는 Flutter에 저장하지 않는다. 기존 `TRIPBLER_API_BASE_URL` 설정을 공유한다.

## 표시와 저장

메인의 큰 숫자는 해당 코인의 환산 수량이다. 보조 문구는 1코인의 KRW 가격과 조회 시각(기기 현지 시각)이다.
기준 금액 × 기준 통화→KRW 환율 ÷ 코인 KRW 가격으로 계산하며, 코인 수량을 입력하면 역산한다.
KRW가 기준이면 연결 환율은 1이며, 다른 기준 통화일 때만 표시 계층에서 기존 법정 통화 API로 KRW 환율을 요청한다.
코인을 메인의 기준 통화로 선택하는 기능은 포함하지 않는다.

선택 코인과 마지막 성공 목록은 `crypto.selected.v1`, `crypto.catalog.v1`에 저장한다.
혼합 행 순서는 `exchange.displayOrder.v1`에 `fiat:USD`, `crypto:BTC` 형식으로 저장한다.
편집 창에서 완료를 눌러야 추가/삭제/순서가 적용되며, 창을 닫으면 초안을 버린다.
최초 목록 조회에는 서버 연결이 필요하다. 이후 서버 연결 실패 시 저장된 목록으로 편집할 수 있고, 현재가 실패는 0 대신 `—`로 표시하고 입력을 막는다.
아래로 당겨 새로고침하면 환율과 암호화폐 현재가를 다시 조회한다. 오류가 없는 이전 현재가를 재조회 중 표시할 때는 기존 조회 시각을 유지한다.

## 공통 차트와 Crypto History

- 차트 아래의 통화/암호 선택은 화면 로컬 상태이며 기본값은 통화다.
- 통화 차트는 기존 기준 통화와 기간 선택을 유지한다. 암호 차트는 추가한 코인만 카드로 넘겨 표시하며 KRW 기준으로 고정한다.
- 두 종류 모두 `MarketChartCarousel`, `MarketChartCard`, 기존 `ExchangeRateLineChart`와 축/툴팁/터치 로직을 공유한다.
- `ChartPoint`는 공통 렌더링 계약이며 기존 환율 모델은 3자리 통화 코드 검증을 유지한다. Crypto History는 별도 모델로 파싱한 뒤 표시 계층에서 `ChartSample`로 변환한다.
- 조회는 `ExchangeChartDataSource`와 `CryptoChartDataSource`로 분리한다. 암호화폐는 `/api/v1/crypto/history?coin=BTC&currency=KRW&period=1M`과 현재가 API만 사용한다.
- 기간 버튼은 7D/1M/3M/6M/1Y/2Y/5Y 모두 유지한다. 암호화폐의 2Y/5Y는 불필요한 API 호출 없이 “암호화폐 차트를 불러오지 못했습니다.”를 표시한다.
- 보이는 카드만 최초 조회한다. 종류를 전환해도 각 종류의 기간/페이지 상태를 유지하고, 기간 변경이나 카드 제거 이후의 늦은 응답은 반영하지 않는다.
- Crypto 시각은 epoch 밀리초에서 UTC로 파싱하고 기기의 현지 시각으로 표시한다. 툴팁은 시·분도 보여주며, 시간 단위 데이터는 X축 라벨 개수만 제한하고 데이터 자체는 보존한다.

## 검증 명령

```powershell
flutter test --no-pub test/crypto test/widgets/exchange
flutter analyze --no-pub
```

테스트는 모의 HTTP 응답을 사용한다. 실제 서버/CoinGecko 연결 검증은 별도다.
