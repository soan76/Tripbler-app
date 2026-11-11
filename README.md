# Tripbler

여행할 때 자주 쓰는 도구인 **환율, 지도, 번역**을 한 앱에 모은 Flutter 앱입니다.

환율, 암호화폐 시세, 장소 검색, 번역 요청은 Tripbler 서버의 `/api/v1/...`를 거치며, 이 외부 서비스의 API 키는 서버에만 있습니다. 지도 표시용 Google Maps SDK 키만 앱에서 별도로 설정합니다(아래 실행 방법 참고).

- 백엔드(Spring Boot): [soan76/Tripbler-backend](https://github.com/soan76/Tripbler-backend)

## 주요 기능

### 환율
- 국가 통화와 암호화폐(비트코인, 이더리움 등)를 한 목록에서 보여주고, 금액을 입력하면 바로 환산합니다.
- 표시할 통화를 고르고 순서를 바꿀 수 있습니다. 지원 코인 목록은 서버에서 받습니다.
- 기간별 시세 차트(7일~1년), 두 통화 바꾸기, 차트에서 고른 날의 환율과 증감, 금액 환산.
- 저장해 둔 값을 먼저 보여주고 다시 조회합니다(stale-while-revalidate). 갱신에 실패하면 마지막 성공값과 원래 갱신 시각을 유지하고 오래된 값임을 알립니다.

### 지도
- Google 지도, 현재 위치와 나침반 방향, 축척 표시.
- 장소 검색(로그인 필요): 검색 버튼을 누른 순간의 지도 중심을 기준으로 검색하고, 결과를 목록과 마커로 보여줍니다. 결과를 고르면 그 장소로 이동하고 상세 카드가 열립니다.

### 번역
- 카메라로 찍거나 갤러리에서 고른 사진의 글자를 기기에서 인식(OCR)하고, 인식한 텍스트만 서버로 보내 번역합니다.
- 원본 언어와 대상 언어를 고르고 서로 바꿀 수 있습니다.

### 계정
- 아이디·비밀번호 회원가입과 로그인, Google 계정 연동·해제.
- 이메일 인증 코드로 아이디 찾기와 비밀번호 재설정.
- 닉네임·비밀번호 변경, 프로필 이미지 변경, 회원 탈퇴.
- 로그인 없이도 환율과 번역은 쓸 수 있습니다. 장소 검색처럼 로그인이 필요한 기능은 그 자리에서 로그인을 안내합니다.

## 기술 스택

| 구분 | 사용 기술 |
| --- | --- |
| 프레임워크 | Flutter (Dart SDK ^3.9.2) |
| 상태 관리 | Provider |
| 네트워크 | `http` |
| 지도 / 위치 | `google_maps_flutter`, `geolocator`, `flutter_compass` |
| 번역 입력 | `camera`, `image_picker`, `google_mlkit_text_recognition`(기기 내 OCR) |
| 차트 | `fl_chart` |
| 인증 / 저장 | `google_sign_in`, `flutter_secure_storage`(토큰), `shared_preferences` |

## 프로젝트 구조

```
lib
├── main.dart          # MultiProvider로 Provider 연결, AuthGate
├── core               # API 설정(api_config.dart), 네트워크, 테마
├── screens            # 환율, 지도, 번역, 설정, 인증, 사용자 화면
├── widgets            # 화면별 위젯
├── providers          # 상태 관리 (Auth, Exchange, Map, Translation, Tab 등)
├── repositories       # 인증 (토큰 재발급, 세션 관리)
├── services           # HTTP, 캐시, 위치, OCR 등
├── domain/exchange    # 환율 계산
├── presentation       # 차트 데이터 변환
├── crypto             # 암호화폐 기능 모듈 (models / providers / services)
├── models
└── utils
```

- 계층: 화면 → Provider(상태) → Repository / Service(HTTP, 저장소, OCR).
- 하단 탭 3개(환율 / 지도 / 번역)는 `TabProvider`가 관리합니다.
- 서버 API 경로: 환율·인증·회원·장소는 `lib/core/config/api_config.dart`, 번역은 `lib/services/translation_service.dart`, 암호화폐는 `lib/crypto/services/crypto_api_service.dart`에서 확인할 수 있습니다.
- 인증 요청은 `Authorization` 헤더를 붙여 보내고, 액세스 토큰이 만료되면 Refresh Token으로 재발급을 시도합니다. 요청 도중 다른 계정으로 바뀌면 이전 요청의 결과는 버립니다.
- 암호화폐 서버 계약과 저장 키는 [docs/crypto-ui.md](docs/crypto-ui.md)에 있습니다.

## 실행 방법

### 준비물

- Flutter SDK
- 실행 중인 [Tripbler 백엔드](https://github.com/soan76/Tripbler-backend) 서버
- Google Maps API 키, Google OAuth 서버 클라이언트 ID

### 설정

**Google Maps 키** (저장소에 포함되지 않음, `.gitignore` 대상)

- Android: `android/local.properties`

  ```properties
  GOOGLE_MAPS_ANDROID_API_KEY=<your-key>
  ```

- iOS: `ios/Flutter/Secrets.xcconfig`

  ```properties
  GOOGLE_MAPS_IOS_API_KEY=<your-key>
  ```

**서버 주소**: `--dart-define=TRIPBLER_API_BASE_URL`로 넘깁니다. 넘기지 않으면 다음 기본값을 씁니다.

- Android: `http://10.0.2.2:8080`. 에뮬레이터에서 개발 PC에 접속할 때 쓰는 주소입니다. 실기기에서는 `TRIPBLER_API_BASE_URL`에 기기에서 접근할 수 있는 서버 주소를 지정하세요.
- iOS, 웹, 데스크톱: `http://localhost:8080`

### 명령어

```bash
flutter pub get
```

```bash
flutter run --dart-define=TRIPBLER_API_BASE_URL=http://<host>:8080 --dart-define=GOOGLE_OAUTH_SERVER_CLIENT_ID=<client-id>
```

```bash
flutter test
```

- 실기기에서 실행할 때는 `<host>`에 서버가 돌아가는 PC의 IP를 넣습니다.
- `google_maps_flutter` 계열 패키지는 `dependency_overrides`로 `packages/`에 내려받아 수정해 씁니다.

## 앞으로의 계획

현재 홈은 안내 문구만 표시하는 임시 화면입니다. 아래 항목은 향후 개발 계획입니다.

- 장소 상세 패널과 길찾기 연결
- 별도 AI 채팅 화면 대신, 어느 화면에서든 음성·텍스트로 요청하면 결과가 지도·번역·환율·일정 화면에 바로 반영되는 여행 에이전트
- 사용자의 여행 취향을 분석해 개인화된 추천을 제공하는 기능
- 여행 일정 기능
