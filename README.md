# CONAN CARD LAB — 코난 TCG 개인용 카드 도감 & 덱 빌더

React + Vite로 만든 개인용 카드 도감/덱 빌더입니다. 카드 도감은 `public/cards.json`을 자동으로 읽기 때문에 수집을 마치면 브라우저에서 파일을 따로 업로드할 필요가 없습니다.

## 기능

- 공식 카드 목록의 카드별 `data` JSON과 이미지 주소를 브라우저 자동화로 추출
- 카드 종류, ID, 카드 번호, 레어리티, 색상, 레벨/코스트, AP, LP, 수록처, 특징, 능력 텍스트 추출
- 카드 이미지를 로컬 `public/card-images/` 폴더에 저장하거나 공식 이미지 URL을 참조
- 카드 ID/이름/능력 검색, 종류·색상·레어리티·레벨·LP·수록처 필터
- 카드 상세에서 한국어 번역과 일본어 원문 확인
- 한국어 카드명·수록처·특징·능력의 일괄 번역 및 중단 후 이어하기
- 메인 덱 40장 + 파트너 1장 + 사건 1장 편집
- 덱 저장/불러오기/삭제/JSON 내보내기
- PC 및 모바일 반응형 UI

## 처음 한 번만 설정하기

필요한 환경은 **Node.js 20.19 이상**입니다.

```bash
npm install
npm run setup:scraper
```

두 번째 명령은 Playwright가 사용할 Chromium 브라우저를 설치합니다.

## 1단계: 카드 2,292장 자동 수집

```bash
npm run scrape:cards
```

기본 설정은 공식 카드 목록을 열어 카드 JSON과 이미지 URL을 파싱하고, 페이지를 순회한 뒤 카드 데이터를 `public/cards.json`에 저장하는 것입니다. 2,292장의 이미지 파일을 전부 다운로드하면 저장 공간이 많이 필요할 수 있어, 기본값은 공식 이미지 URL을 참조합니다.

사이트를 다시 실행하거나 새로고침하면 `cards.json`을 자동으로 읽습니다. 원문을 수집한 다음 번역까지 연속 실행하려면 `.env`에 번역 API 키를 설정한 뒤 `npm run sync:cards`를 실행하세요. 이미지도 사이트 폴더에 로컬로 보관하고 싶을 때만 아래 명령을 실행하세요.

```bash
npm run scrape:cards:local-images
```

로컬 이미지 파일은 `public/card-images/`에 저장되고, 다운로드에 실패한 이미지는 원본 URL로 남습니다. 기존 이미지 파일은 재다운로드하지 않습니다.

브라우저 창을 직접 보며 수집 과정을 확인하려면 다음과 같이 실행할 수 있습니다.

```bash
npm run scrape:cards -- --headed
```

스크립트는 카드 수를 목록의 `data-total`과 비교합니다. 페이지네이션 구조가 바뀌어 전체 수집이 완료되지 않으면 완성본을 덮어쓰지 않고 진단용 `data/cards.partial.json`을 남기며 오류 메시지를 출력합니다.

## 2단계: 한국어 번역 생성

자동 번역을 한 번에 생성하려면 Google Cloud Translation API 키가 필요합니다. API 사용료 및 할당량은 Google Cloud 계정 설정에 따라 달라질 수 있습니다.

1. `.env.example`을 복사해 프로젝트 루트에 `.env` 파일을 만듭니다.
2. `.env`에 다음 값을 입력합니다.

```env
GOOGLE_TRANSLATE_API_KEY=여기에_본인_API_키
```

3. 번역을 실행합니다.

```bash
npm run translate:cards
```

카드명, 수록처, 특징, 능력 텍스트에서 아직 한국어 값이 없는 고유 문자열만 묶음 단위로 번역합니다. 번역이 끝날 때마다 카드 데이터와 번역 캐시를 저장하므로 오류나 중단이 발생해도 완료한 번역을 다시 요청하지 않도록 설계했습니다. 원본 일본어 필드는 유지됩니다.

기계 번역은 카드 게임 고유 용어, 키워드, 조건문을 잘못 옮길 수 있으므로 룰 판정이 필요한 문구는 일본어 원문과 대조하세요.

## 3단계: 실행

```bash
npm run dev
```

터미널에 표시되는 로컬 주소를 PC 브라우저에서 엽니다.

### 같은 Wi-Fi에 연결된 휴대전화에서도 보기

```bash
npm run dev -- --host 0.0.0.0
```

PC와 휴대전화가 같은 Wi-Fi에 연결되어 있어야 합니다. PC에서 `ipconfig`를 실행해 로컬 IPv4 주소를 확인한 뒤, 휴대전화 브라우저에서 `http://PC의-IPv4-주소:5173`으로 접속합니다. Windows 방화벽이 요청하면 개인 네트워크에 한해 허용해야 할 수 있습니다.

### 집 밖에서도 비공개로 접속하기: Tailscale Serve 권장

공개 GitHub 저장소나 공개 정적 호스팅에 카드 데이터를 올리지 않고 집 밖에서도 보려면, PC를 개인 서버로 두고 Tailscale Serve로 해당 PC의 웹서버를 **내 Tailscale 네트워크에 속한 기기에서만** 접속하도록 할 수 있습니다. Tailscale은 Serve를 tailnet 안에서만 서비스하는 기능으로 설명합니다. (문서: https://tailscale.com/docs/features/tailscale-serve)

1. PC와 휴대전화에 [Tailscale](https://tailscale.com/download)을 설치하고 같은 계정으로 로그인합니다.
2. 카드 수집과 일괄 번역을 마친 PC에서 아래 명령을 실행합니다.

```bash
npm run build
npm run preview -- --host 127.0.0.1
```

3. 별도의 터미널 창에서 다음 명령을 실행합니다.

```bash
tailscale serve 4173
```

4. 터미널에 표시되는 `https://...ts.net` 주소를 휴대전화에서 열면 됩니다. 휴대전화에서도 Tailscale 연결을 켜 둡니다. HTTPS 설정을 요구하면 Tailscale 안내를 따라 활성화하세요.

이 방법은 PC가 켜져 있고 미리보기 서버와 Tailscale Serve가 실행 중일 때만 사용할 수 있습니다. 서버를 중지하면 접속도 끝납니다.

**GitHub 저장소를 비공개로 바꾸는 것만으로 배포 URL까지 비공개가 되는 것은 아닙니다.** 정적 사이트에 클라이언트 쪽 비밀번호만 추가하는 것도 실제 접근 제어가 되지 않습니다.

카드 이미지와 `public/cards.json`은 `.gitignore`에 등록되어 기본적으로 Git에 추가되지 않도록 했습니다. 이는 실수로 공개 저장소에 개인용 수집 데이터가 올라가는 것을 방지하기 위한 설정이며, 로컬 실행과 로컬 빌드에는 영향을 주지 않습니다. 수집 데이터는 기본적으로 프로젝트 폴더 안에 남으며, 이 도구는 데이터를 ChatGPT나 제3자 서버로 전송하지 않습니다. 단, 일괄 번역을 실행하면 입력한 텍스트가 선택한 번역 API 제공자에게 전송됩니다.

카드 데이터 파일은 여러 기기에서 같은 주소로 제공할 수 있지만, 현재 덱 저장은 브라우저별 `localStorage` 방식입니다. 따라서 PC에서 저장한 덱이 휴대전화에 자동으로 동기화되지는 않습니다. 여러 기기 간 덱 자동 동기화에는 인증된 데이터베이스/서버 기능을 추가해야 합니다.

## 데이터 필드

`public/cards.json`의 각 카드에는 앱에서 쓰는 필드(`id`, `cardId`, `cardNumber`, `nameJp`, `type`, `rarity`, `color`, `cost`, `ap`, `lp`, `set`, `traits`, `abilityJp`, `imageUrl`)와 한국어 번역 필드(`nameKo`, `setKo`, `traitsKo`, `abilityKo`)가 저장됩니다. `id`는 인쇄 버전마다 구분할 수 있는 내부 고유 ID이고, `cardId`는 카드 상세의 ID 표시용 값입니다.

## 문제 해결

- `playwright install` 또는 Chromium 실행 오류: `npm run setup:scraper`를 다시 실행하세요.
- 일부 카드만 수집됨: 출력된 오류와 `data/cards.partial.json`을 확인하세요. 사이트의 페이지 이동 구조가 바뀐 경우 스크립트 수정이 필요할 수 있습니다.
- 이미지 일부가 저장되지 않음: 해당 카드만 원본 URL로 남겨 두어 화면에서 계속 표시되도록 했습니다.
- 번역 API 오류: `.env` 키, Google Cloud Translation API 활성화 상태, 결제 및 할당량을 확인하세요. `npm run translate:cards`를 다시 실행하면 캐시에 없는 문자열부터 이어갑니다. 수집과 번역을 연속 실행하려면 `npm run sync:cards`를 사용하세요.
- 새로 수집한 데이터가 화면에 보이지 않음: 도감의 **기본 데이터 새로고침** 버튼을 누르세요. 이전에 브라우저 `localStorage`에 카드 목록이 저장되어도 새 `cards.json`을 다시 읽습니다.

## 공식 출처

- https://www.takaratomy.co.jp/products/conan-cardgame/cardlist/

타카라토미 사이트는 이미지 및 텍스트 등의 데이터 무단 전재를 금지한다고 안내합니다. 개인용으로 데이터를 추출하는 것과 이를 제3자에게 배포하거나 공개 사이트에 복제하는 것은 별개입니다. 이미지·텍스트를 외부에 공유하거나 배포하기 전에는 권리자 이용 조건을 확인하세요.
