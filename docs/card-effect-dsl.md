# 카드 효과 DSL (초안 v1)

이 문서는 `supabase/seed/card_effect_definitions.json`에 쓰는 카드 효과 데이터 형식과 각 실행 명령의 의미를 정의합니다. 카드의 한국어 표시 문구는 기존 `public/card-translations.ko.json`에 계속 두고, 이 파일에는 **규칙 엔진이 읽을 조건과 명령만** 넣습니다.

## 중요한 실행 경계

이 커밋은 정의 형식·검증기·대표 카드 정의를 준비합니다. 현재 대전의 권위 있는 상태 변경은 PostgreSQL의 `perform_private_turn_action_v2`에서 이뤄지므로, 이 JSON만 추가한다고 실전 대전에서 효과가 자동 발동하는 것은 아닙니다. 정의를 실제 대전에 적용하려면 서버 측 효과 실행기를 연결하고, 아래의 대기/선택 단계와 턴 종료 정리를 서버 트랜잭션에 연결해야 합니다. 브라우저에서 JSON을 직접 실행해 게임 상태를 바꾸지 않습니다.

## 최상위 형식

- `schemaVersion`: 이 DSL의 버전. 현재 `1`.
- `language`: 고정 식별자 `conan-card-effect-dsl`.
- `definitions`: 효과 목록. 카드 하나에 등장 효과와 반응 효과가 함께 있으면 별도의 정의로 나눕니다.

각 효과 정의는 다음 필드를 사용합니다.

- `effectId`: 프로젝트 전체에서 유일한 효과 ID.
- `cardIds`: 기존 카드 데이터의 `ID:xxxx` 번호를 네 자리 문자열로 저장합니다. 인쇄판 코드와 한국어 별명은 여기에 넣지 않습니다.
- `trigger`: 발동 이벤트와 타이밍.
- `conditions`: 모두 참이어야 하는 조건 배열. 비어 있으면 조건이 없습니다.
- `steps`: 위에서 아래 순서로 실행할 명령 배열.
- `saveAs`: 선택/반응 결과를 저장할 변수명. 후속 명령은 `vars.변수명.count` 또는 `vars.변수명`으로 결과를 참조합니다.
- `when`: 각 명령의 실행 조건. 거짓이면 해당 명령만 건너뛰고 다음 명령으로 진행합니다.

## 이벤트와 조건

현재 정의된 이벤트:

- `character.entered_field`: 캐릭터가 현장에 들어온 직후.
- `opponent.deduction.declared`: 상대가 추리를 선언하고 반응을 받을 수 있는 시점.

조건의 `fact`는 서버 이벤트 문맥에서 읽는 경로입니다. 예: `player.partner.color`, `entry.method`, `entry.source.level`, `source.is_active`, `vars.selected_red.count`.

지원 조건 연산자:

- `equals`: 값이 같은지 확인.
- `in`: 왼쪽 값이 `value` 배열에 포함되는지 확인.
- `less_than`, `greater_than`, `greater_than_or_equal`: 숫자 비교.

`entry.method` 값은 `character_ability` 또는 `event_effect`처럼 진입을 발생시킨 규칙 원인을 나타냅니다. 일반적인 기본 등장에는 이 조건이 일치하지 않아야 합니다.

## 실행 명령 목록

명령은 서버 실행기가 허용 목록에 있는 것만 실행해야 합니다. 임의의 함수 이름이나 SQL, JavaScript 코드를 JSON에 담아 실행해서는 안 됩니다.

| 명령 | 의미와 필수 인자 |
|---|---|
| `refill_deck_from_remove_area` | 덱 카드 수가 조건보다 적으면 남은 덱과 리무브 에이리어를 합쳐 덱을 만들고 섞습니다. `includeRemainingDeck`, `includeRemoveArea`, `shuffle` 사용. |
| `peek_top_cards` | 덱 위에서 최대 `count`장 확인하고 `saveAs`에 카드 인스턴스를 기록합니다. `allowFewer: true`이면 부족한 수만큼 확인합니다. |
| `select_cards` | `from` 영역/변수에서 `min`~`max`장을 선택합니다. `filter`, `targetController`, `optional`, `saveAs`를 지원합니다. 최대 0장은 선택하지 않는 선택을 허용합니다. |
| `reveal_cards` | `from` 결과를 `to` 대상에게 공개합니다. `awaitAcknowledgement: true`이면 상대 확인 응답 전에는 다음 단계로 넘어가지 않습니다. |
| `move_cards` | 카드 인스턴스를 `from`에서 `to` 영역으로 이동합니다. |
| `move_unselected_to_deck_bottom` | 확인한 카드 중 `selectedVariable`에 포함되지 않은 카드를 덱 아래로 옮깁니다. `order: player_choice`는 사용자가 순서를 정한다는 뜻입니다. |
| `grant_keyword` | 카드에 임시 키워드를 부여합니다. `target`, `keyword`, `duration`을 사용합니다. 지속 키워드는 턴 종료 때 만료되어야 합니다. |
| `modify_stat` | 대상 카드의 수치를 바꿉니다. `stat`, `amount`, `duration`, `stacking`을 사용합니다. 기존 기본 AP를 덮어쓰지 말고 임시 보정으로 저장합니다. |
| `offer_reaction` | 반응 선택 창을 만들고 플레이어 선택까지 실행을 일시 정지합니다. 선택 결과는 `saveAs`에 저장합니다. |
| `pay_cost` | 선택된 반응의 비용을 결제합니다. 현재 명령 `sleep_source_character`는 발동한 캐릭터를 슬립 상태로 만듭니다. |
| `set_mislead_value` | 카드가 현장에 있는 동안 기존 추리 응답 규칙에서 사용할 `mislead_value`를 설정합니다. `value`는 0~3, `duration`은 `while_in_field`입니다. Conan TCG의 LP는 생명력이 아니라 추리로 얻는 증거 장수이므로, 미스리드는 기존 증거 획득량 감소 처리에 연결합니다. |

### 실행기 계약

1. 트리거 발생 시 `cardIds`와 `trigger.event`가 일치하는 정의를 찾습니다.
2. 모든 `conditions`를 서버 문맥에서 평가합니다.
3. `steps`를 순서대로 실행합니다. 선택·상대 확인·반응 응답이 필요하면 실행 위치와 문맥을 보존한 대기 상태를 저장하고, 응답 후 그 단계 다음부터 이어갑니다.
4. 효과 실행은 서버 권위 상태에만 적용합니다. 공개되어도 되는 카드만 상대에게 노출합니다.
5. `duration: turn_end` 보정은 턴 종료 처리에서 만료시킵니다. 원래 카드의 AP나 영구 키워드를 수정하지 않습니다.
6. 발동 이벤트 ID와 카드 인스턴스 ID로 중복 발동을 막고, 플레이어가 아직 응답하지 않은 효과가 있으면 다음 행동으로 건너뛰지 못하게 합니다.

## 예시 해석 메모

- **ID:0062**: 덱이 4장 미만이면 리무브 에이리어와 남은 덱을 합쳐 섞습니다. 이후 최대 4장을 확인하고, 선택한 적 카드를 상대가 확인한 다음 패에 넣습니다. 미선택 카드는 원하는 순서로 덱 아래에 놓고, 실제로 패에 추가한 경우에만 손패 1장을 리무브합니다.
- **ID:0110**: 파트너의 색이 녹색일 때 이번 턴 동안 자신에게 `charge`(한국어 표시명: 돌격)를 부여합니다.
- **ID:0011**: 다른 캐릭터 능력 또는 이벤트 효과로 등장했고, 그 효과의 원본 카드 레벨이 3 이상인 경우에만 캐릭터 최대 1장의 AP를 턴 종료까지 2000 올립니다.
- **ID:0223**: 등장 시 캐릭터 최대 1장의 AP를 턴 종료까지 1000 내립니다. 별도 반응 정의는 상대 추리 중 액티브 상태일 때만 제안되며, 발동 선택 시 이 카드를 슬립시키고 상대 추리에 LP -1을 적용합니다.

## 검증

저장소 루트에서 다음 명령으로 구조와 명령 인자, 변수의 사용 순서를 확인합니다.

```bash
npm run validate:card-effects
```

검증 통과는 데이터 형식의 일관성을 뜻할 뿐, 효과가 실제 온라인 대전에서 이미 활성화됐다는 뜻은 아닙니다.
