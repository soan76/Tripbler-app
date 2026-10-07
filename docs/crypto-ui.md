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
최초 목록 조회에는 서버 연결이 필요하다. 이후 서버 연결 실패 시 저장된 목록으로 편집할 수 있다. 현재가 갱신에 실패하면 마지막 성공값과 조회 시각을 유지하고 저장값임을 표시한다. 성공값도 없으면 `—`로 표시하고 입력을 막는다.
아래로 당겨 새로고침하면 환율과 암호화폐 현재가를 다시 조회한다. 오류가 없는 이전 현재가를 재조회 중 표시할 때는 기존 조회 시각을 유지한다.

## 공통 차트와 Crypto History

- 차트 아래의 통화/암호 선택은 화면 로컬 상태이며 기본값은 통화다.
- 통화 차트는 기존 기준 통화와 기간 선택을 유지한다. 암호 차트는 추가한 코인만 카드로 넘겨 표시하며 KRW 기준으로 고정한다.
- 두 종류 모두 `MarketChartCarousel`, `MarketChartCard`, 기존 `ExchangeRateLineChart`와 축/툴팁/터치 로직을 공유한다.
- `ChartPoint`는 공통 렌더링 계약이며 기존 환율 모델은 3자리 통화 코드 검증을 유지한다. Crypto History는 별도 모델로 파싱한 뒤 표시 계층에서 `ChartSample`로 변환한다.
- 조회는 `ExchangeChartDataSource`와 `CryptoChartDataSource`로 분리한다. 암호화폐는 `/api/v1/crypto/history?coin=BTC&currency=KRW&period=1M`과 현재가 API만 사용한다.
- 기간 버튼은 7D/1M/3M/6M/1Y/2Y/5Y 모두 유지한다. 암호화폐의 2Y/5Y는 불필요한 API 호출 없이 “암호화폐 차트를 불러오지 못했습니다.”를 표시한다.
- 보이는 카드만 최초 조회한다. 종류를 전환해도 각 종류의 기간/페이지 상태를 유지하고, 기간 변경이나 카드 제거 이후의 늦은 응답은 반영하지 않는다.
- Crypto 시각은 epoch 밀리초에서 UTC로 파싱하고 기기의 현지 시각으로 표시한다. 툴팁은 시·분도 보여준다. 서버는 History를 기본 최대 300점으로 축소하며 각 구간의 최저/최고점 및 첫/마지막 점을 보존한다.

## 느린 네트워크 처리

- 초기화는 로컬 복원 완료 후 반환한다. 저장된 목록과 가격을 먼저 표시하고, 네트워크 갱신은 백그라운드에서 진행한다.
- 코인 목록과 선택 코인 가격은 병렬 조회한다. 차트의 현재가와 History도 병렬 조회하며 현재가만 실패하면 History는 표시하고 금액을 `최근 기록`으로 명시한다.
- 법정 통화 환율은 기존 저장소, 코인 현재가와 차트는 `MarketSnapshotStore`에 마지막 성공 응답을 저장한다. 후자는 최대 64개 항목이며 저장 실패가 화면의 성공 응답을 없애지 않는다.
- 앱 시작 시 복원 허용 나이: 법정 환율/KRW 연결 환율 3일, 코인 현재가 15분, 법정 History 7일, Crypto History 1일. `fetchedAt`으로 판단하며 재저장 시 시간을 갱신하지 않는다.
- 갱신 중에도 차트와 가격을 유지한다. 실패하면 마지막 성공 데이터 표시를 안내하며, 성공 시 최신 값으로 교체한다. 기준 통화/코인/기간별 캐시를 분리한다.
- 서버 타임아웃 fallback은 `stale: true`와 기존 `fetchedAt`을 반환한다. 프론트는 이를 저장값/갱신 지연 상태로 표시한다.
- 서버 JSON 압축은 `Accept-Encoding: gzip`을 지원하는 클라이언트에 1KB 이상 응답부터 적용된다.

## 검증 명령

```powershell
flutter test --no-pub test/crypto test/widgets/exchange test/providers/exchange_swr_test.dart
flutter analyze --no-pub
```

테스트는 모의 HTTP 응답을 사용한다. 실제 서버/CoinGecko 연결 검증은 별도다.
