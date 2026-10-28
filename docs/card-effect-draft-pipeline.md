# 카드 효과 DSL 초안 생성·검토 파이프라인

## 현재 체크포인트

`supabase/seed/card_effect_review_batches/card-effect-review-20261029-attempt-01.json`은 테스트 목적으로 선정한 카드별 검토 배치입니다. 덱 이름, 편성자, 원본 덱 식별자는 기록하지 않고 카드 키별 정의 후보만 저장합니다.

- 카드 레코드: 33개 (파트너·사건 카드 포함)
- 효과 후보: 34개
- 기존 DSL 명령으로 구조화한 정의 초안: 6개
- 구조 검증: 6개 모두 통과
- 서버 런타임 의미 검증과 사람 승인: 아직 완료되지 않음

초안은 서버 카탈로그에 자동으로 추가하지 않습니다. 구조 검사 통과는 JSON 구조, 명령 목록, 필수 인자 및 변수 사용 순서 검사만 통과했다는 뜻입니다. 대상 소유자 해석, 발동 타이밍, 카드 공개 확인, 턴 종료 정리 등은 별도 시뮬레이션과 검토가 필요합니다. 이벤트 트리거, 변장, 히라메키, 동적 컷인, 인연/파트너 조건처럼 현재 DSL이 정확히 표현하지 못하는 규칙은 빈 정의를 억지로 채우지 않고 검토 사유로 남겼습니다.

## 로컬/CI에서 실행

```bash
npm ci
npm run validate:card-effects
npm run validate:card-effect-drafts
npm run build
```

초안 검증 명령은 기본적으로 위 샘플 배치를 검사합니다. 다른 배치를 검사하려면 `node scripts/validate-card-effect-drafts.mjs --input <경로>`를 사용합니다. 검증기는 지원하지 않는 trigger/op/operator/fact, 필수 필드 누락, 중복 source key/candidate ID, 선택 변수의 선언 순서 오류를 탐지합니다. 검증 보고는 stdout에 출력되며 원본 파일을 자동 승인하거나 서버 카탈로그를 변경하지 않습니다.

## 전체 자동화에 필요한 단계

1. **소스 정규화** — 카드 키 및 내부 `ID:xxxx`를 이용해 인쇄판 변형을 구분합니다. 카드 이름만으로 매칭하지 말고 내부 ID와 데이터베이스 키를 함께 저장합니다.
2. **AI 해석** — 카드 원문, 기존 번역, DSL 문서, 허용 trigger/op/fact 목록을 모델에 전달합니다. 출력은 자연어가 아니라 이 배치와 동일한 JSON 스키마로 제한합니다. 원문 문장별로 발동 조건, 비용, 선택 대상, 공개 범위, 효과 순서, 지속 시간, 턴 제한을 기록하게 합니다. 해석 불가/지원하지 않는 표현은 `review_required`로 분류해야 합니다.
3. **구조 검증** — `validate:card-effect-drafts`로 JSON 구조, 허용 명령, 필수 인자, 변수 선언 순서 및 fact 경로를 검사합니다. 실패한 초안은 수정 루프로 보내고 승인 단계로 보내지 않습니다.
4. **의미/런타임 테스트** — 카드별 fixture를 준비해 조건이 참/거짓인 경우, 대상이 없는 경우, 덱에 카드가 부족한 경우, 사용자가 선택을 취소하거나 상대 ACK를 늦게 보내는 경우, 턴 종료/효과 중첩을 검사합니다.
5. **승인 및 승격** — 구조 검증과 테스트를 통과한 뒤 사람이 원문과 대조해 `approvalStatus: approved`로 승인합니다. 승인된 정의만 `supabase/seed/card_effect_definitions.json`에 합치고 중복 `effectId`/카드 ID를 재검사합니다.
6. **서버 카탈로그 배포** — 마이그레이션/관리 RPC를 통해 `private_card_effect_catalog_v1`을 교체하고, 배포 이후 샘플 대전을 실행해 실제 런타임 동작을 확인합니다. 초안 생성기는 서비스 롤 키나 DB 권한을 갖지 않아야 합니다.

## AI 생성기 사용법

저장소의 초안 생성기는 OpenAI Responses API를 호출합니다. 처음 한 번 `.env.api.example`을 복사해 `.env.api.local`을 만들고, 그 파일 안에 `OPENAI_API_KEY`와 `OPENAI_MODEL`을 입력하면 됩니다. `.env.api.local`은 현재 `.gitignore`의 `.env.*.local` 패턴에 따라 Git 추적에서 제외됩니다. 이 파일을 GitHub에 올리거나 채팅으로 키를 보내지 마세요. OpenAI API 사용 요금은 ChatGPT 구독 요금과 별도로 청구되므로, API 플랫폼에서 결제 설정과 사용 한도도 먼저 확인하세요.

설정 예시 파일: `.env.api.example`. 다음 내용을 복사해 만든 `.env.api.local`에서 키 값을 직접 입력하세요. `OPENAI_MODEL`에는 API 플랫폼에서 현재 사용 가능한 모델 ID를 넣습니다. 예시의 `gpt-4.1-mini`는 시작용 예시일 뿐이며, 계정에서 사용할 수 있는 모델인지 확인해야 합니다.

기본 생성 명령은 카드 5장씩 요청하고 배치마다 `.partial.json` 체크포인트를 저장합니다. 연결이 끊겼다면 동일한 원본/모델/출력 경로로 `--resume`을 사용합니다.

```powershell
Copy-Item .env.api.example .env.api.local
notepad .env.api.local
npm run generate:card-effect-drafts -- --input supabase/seed/card_effect_review_batches/card-effect-review-20261029-attempt-01.json --output supabase/seed/card_effect_review_batches/card-effect-review-20261029-attempt-01-ai.json
npm run validate:card-effect-drafts -- --input supabase/seed/card_effect_review_batches/card-effect-review-20261029-attempt-01-ai.json
```

생성기는 결과를 별도 파일로 저장하며, 입력/활성 카탈로그를 덮어쓰지 않습니다.

## 안전한 자동화 원칙

- API 키는 로컬 환경 변수, GitHub Actions Secret 또는 서버 측 Secret으로 보관합니다.
- 입력 카드 ID, 모델/프롬프트 버전, 원문 해시, 출력, 검증 결과를 함께 기록해 결과를 재현 가능하게 만듭니다.
- 자동 생성 결과를 운영 카탈로그에 곧장 쓰지 않고 검토 배치에만 추가합니다.
- 새 명령이 필요하면 DSL 계약, 서버 실행기, 테스트를 함께 확장합니다.

권장 파이프라인은 “AI 초안 생성 → 구조 검증 → fixture 테스트 → 사람 승인 → 별도 승격”입니다. AI가 문장을 잘 해석해도 현재 엔진에 없는 규칙을 실행할 수 있게 되는 것은 아니므로, 지원하지 않는 규칙을 임의로 변환하면 안 됩니다.
