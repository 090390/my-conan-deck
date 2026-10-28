# 카드 효과 DSL 초안 생성·검토 파이프라인

## 현재 체크포인트

`supabase/seed/card_effect_review_batches/20261029-matsuda-bakuchung-deck-review.json`은 공개 덱 저장소의 **💛마츠다 경시청**과 **백청덱**을 대상으로 만든 검토 배치입니다. 반복 장수와 별개로 카드 키별 정의 후보를 1회씩 기록했습니다.

- 카드 레코드: 33개 (마츠다 경시청 17개, 백청덱 16개. 파트너/사건 포함)
- 효과 후보: 34개
- 기존 DSL 명령으로 구조화한 정의 초안: 6개
- 구조 검증: 6개 모두 통과
- 서버 런타임 의미 검증과 사람 승인: 아직 완료되지 않음

초안은 서버 카탈로그에 자동으로 추가하지 않습니다. 이 배치에서 `draftStatus`가 `dsl_valid_pending_human_review`여도 이는 JSON 구조, 명령 목록, 필수 인자 및 변수 사용 순서 검사만 통과했다는 뜻입니다. 대상 소유자 해석, 발동 타이밍, 카드 공개 확인, 턴 종료 정리 등은 별도 시뮬레이션과 검토가 필요합니다. 이벤트 트리거, 변장, 히라메키, 동적 컷인, 인연/파트너 조건처럼 현재 DSL이 정확히 표현하지 못하는 규칙은 빈 정의를 억지로 채우지 않고 검토 사유로 남겼습니다.

## 로컬/CI에서 실행

```bash
npm ci
npm run validate:card-effects
npm run validate:card-effect-drafts
npm run build
```

초안 검증 명령은 기본적으로 위 샘플 배치를 검사합니다. 다른 배치를 검사하려면 `node scripts/validate-card-effect-drafts.mjs --input <경로>`를 사용합니다. 검증기는 지원하지 않는 trigger/op/operator/fact, 필수 필드 누락, 중복 source key/candidate ID, 선택 변수의 선언 순서 오류를 탐지합니다. 검증 보고는 stdout에 출력되며 원본 파일을 자동 승인하거나 서버 카탈로그를 변경하지 않습니다.

## 전체 자동화에 필요한 단계

1. **소스 정규화** — 공개 덱의 파트너/사건/메인 카드 목록을 읽고, 인쇄판 변형과 같은 카드 ID를 구분합니다. 카드 이름만으로 매칭하지 말고 내부 `ID:xxxx`와 데이터베이스 키를 함께 저장합니다.
2. **AI 해석** — 카드 원문, 기존 번역, DSL 문서, 허용 trigger/op/fact 목록을 모델에 전달합니다. 출력은 자연어가 아니라 이 배치와 동일한 JSON 스키마로 제한합니다. 원문 문장별로 발동 조건, 비용, 선택 대상, 공개 범위, 효과 순서, 지속 시간, 턴 제한을 기록하게 합니다. 해석 불가/지원하지 않는 표현은 `review_required`로 분류해야 합니다.
3. **구조 검증** — `validate:card-effect-drafts`로 JSON 구조, 허용 명령, 필수 인자, 변수 선언 순서 및 fact 경로를 검사합니다. 실패한 초안은 수정 루프로 보내고 승인 단계로 보내지 않습니다.
4. **의미/런타임 테스트** — 카드별 fixture를 준비해 조건이 참/거짓인 경우, 대상이 없는 경우, 덱에 카드가 부족한 경우, 사용자가 선택을 취소하거나 상대 ACK를 늦게 보내는 경우, 턴 종료/효과 중첩을 검사합니다. 통과 기준에는 “기대하지 않은 카드 이동이 없음”과 “대기 상태가 영구 정지하지 않음”도 포함합니다.
5. **승인 및 승격** — 구조 검증과 테스트를 통과한 뒤 사람이 원문과 대조해 `approvalStatus: approved`로 승인합니다. 승인된 정의만 `supabase/seed/card_effect_definitions.json`에 합치고 중복 `effectId`/카드 ID를 재검사합니다.
6. **서버 카탈로그 배포** — 마이그레이션/관리 RPC를 통해 `private_card_effect_catalog_v1`을 교체하고, 배포 이후 샘플 대전을 실행해 실제 런타임 동작을 확인합니다. 초안 생성기는 서비스 롤 키나 DB 권한을 갖지 않아야 합니다.

## AI 생성기를 실제 자동 실행하려면

저장소에는 **AI 초안 생성기와 검증기**가 있습니다. 생성기는 OpenAI Responses API를 호출하므로 로컬 실행 환경에 `OPENAI_API_KEY`와 `OPENAI_MODEL`을 설정해야 합니다. API 키는 프런트엔드, Git에 추적되는 파일, 커밋된 .env 파일에 저장하지 마세요.

- 카드 텍스트를 입력으로 받아 JSON 초안을 만드는 모델 호출 단계. `scripts/generate-card-effect-drafts.mjs`가 5장씩 묶어 요청하고, 배치마다 `.partial.json` 체크포인트를 저장합니다. 연결이 끊겼다면 동일한 원본/모델/출력 경로로 `--resume`을 사용합니다.
- 실행 예:
  ```bash
  OPENAI_API_KEY=... OPENAI_MODEL=... npm run generate:card-effect-drafts -- --input supabase/seed/card_effect_review_batches/20261029-matsuda-bakuchung-deck-review.json --output supabase/seed/card_effect_review_batches/20261029-matsuda-bakuchung-deck-review-ai.json
  npm run validate:card-effect-drafts -- --input supabase/seed/card_effect_review_batches/20261029-matsuda-bakuchung-deck-review-ai.json
  ```
  Windows PowerShell에서는 `$env:OPENAI_API_KEY`와 `$env:OPENAI_MODEL` 환경 변수를 먼저 설정하세요. 생성기는 결과를 별도 파일로 저장하며, 입력/활성 카탈로그를 덮어쓰지 않습니다.
- 모델 API 키를 프런트엔드나 저장소에 쓰지 않고 GitHub Actions Secret 또는 서버 측 Edge Function Secret으로 보관하는 구성.
- 입력 카드 ID, 모델/프롬프트 버전, 원문 해시, 출력, 검증 결과를 함께 보관해 동일한 입력의 결과를 재현할 수 있는 기록.
- 자동 생성 결과를 곧장 운영 카탈로그에 쓰지 않고, 검토 배치에만 추가하는 권한 분리.
- 변경된 정의에 해당하는 자동 회귀 테스트와, 실패 시 카탈로그 배포를 차단하는 CI 단계.

권장되는 자동 실행은 “AI 초안 생성 → 구조 검증 → fixture 테스트 → 사람 승인 → 별도 승격”입니다. AI가 문장을 잘 해석해도 현재 엔진에 없는 규칙을 실행할 수 있게 되는 것은 아니므로, 새 명령이 필요하면 먼저 DSL 계약, 서버 실행기, 테스트를 함께 확장해야 합니다.
