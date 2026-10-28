
CREATE TABLE IF NOT EXISTS public.private_card_effect_catalog_v1 (
  catalog_id text PRIMARY KEY,
  schema_version integer NOT NULL,
  definitions jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.private_card_effect_catalog_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_card_effect_catalog_v1 FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.private_card_effect_runs_v1 (
  room_id uuid PRIMARY KEY REFERENCES public.rooms(id) ON DELETE CASCADE,
  actor_user_id uuid NOT NULL,
  source_user_id uuid NOT NULL,
  source_instance_id text NOT NULL,
  trigger_event text NOT NULL,
  effect_queue jsonb NOT NULL DEFAULT '[]'::jsonb,
  effect_index integer NOT NULL DEFAULT 0,
  step_index integer NOT NULL DEFAULT 0,
  variables jsonb NOT NULL DEFAULT '{}'::jsonb,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  waiting jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.private_card_effect_runs_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_card_effect_runs_v1 FROM PUBLIC, anon, authenticated;

INSERT INTO public.private_card_effect_catalog_v1(catalog_id, schema_version, definitions)
VALUES ('main', 1, ($effectdsl${"schemaVersion":1,"language":"conan-card-effect-dsl","definitions":[{"effectId":"card-0062-on-enter","cardIds":["0062"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","operator":"less_than","value":4},"includeRemainingDeck":true,"includeRemoveArea":true,"shuffle":true},{"op":"peek_top_cards","count":4,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"filter":{"field":"color","operator":"equals","value":"red"},"prompt":"공개하여 패에 넣을 적 카드를 최대 1장 선택하세요.","saveAs":"selected_red"},{"op":"reveal_cards","from":"selected_red","to":["opponent"],"awaitAcknowledgement":true,"when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"selected_red","to":"hand","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_deck_bottom","from":"seen","selectedVariable":"selected_red","order":"player_choice"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"prompt":"패에 추가한 경우, 리무브할 손패 1장을 선택하세요.","saveAs":"hand_to_remove","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"hand_to_remove","to":"remove_area","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}}]},{"effectId":"card-0110-on-enter-partner-green","cardIds":["0110"],"cardNameKo":"오키타 소지","cardNameJa":"沖田総司","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"green"}],"steps":[{"op":"grant_keyword","target":"source_character","keyword":"charge","displayNameKo":"돌격","duration":"turn_end"}]},{"effectId":"card-0011-on-enter-from-level3-effect","cardIds":["0011"],"cardNameKo":"츠부라야 미츠히코","cardNameJa":"円谷光彦","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"entry.method","operator":"in","value":["character_ability","event_effect"]},{"fact":"entry.source.card_type","operator":"in","value":["character","event"]},{"fact":"entry.source.level","operator":"greater_than_or_equal","value":3}],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"filter":{"field":"card_type","operator":"equals","value":"character"},"targetController":"any","prompt":"턴 종료 시까지 AP를 2000 올릴 캐릭터를 최대 1장 선택하세요.","saveAs":"ap_target"},{"op":"modify_stat","target":"ap_target","stat":"ap","amount":2000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0223-on-enter-ap-minus-1000","cardIds":["0223"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"filter":{"field":"card_type","operator":"equals","value":"character"},"targetController":"any","prompt":"턴 종료 시까지 AP를 1000 낮출 캐릭터를 최대 1장 선택하세요.","saveAs":"ap_target"},{"op":"modify_stat","target":"ap_target","stat":"ap","amount":-1000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0223-mislead-reaction","cardIds":["0223"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"opponent.deduction.declared","timing":"during_response_window"},"conditions":[{"fact":"source.is_active","operator":"equals","value":true},{"fact":"source.status","operator":"equals","value":"active"},{"fact":"source.rested","operator":"equals","value":false}],"steps":[{"op":"offer_reaction","reactionId":"mislead-1","actor":"source_controller","choices":["activate","pass"],"allowDuringOpponentTurn":true,"prompt":"미스리드 1을 사용해 이 카드를 슬립시키고, 상대의 추리에 LP -1을 부여할까요?","saveAs":"mislead_choice"},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.mislead_choice","operator":"equals","value":"activate"}},{"op":"modify_lp","target":"deduction_player","amount":-1,"duration":"immediate","when":{"fact":"vars.mislead_choice","operator":"equals","value":"activate"}}]},{"effectId":"card-1013-activated-remove-low-ap","cardIds":["1013"],"cardNameKo":"하기와라 켄지","cardNameJa":"萩原研二","trigger":{"event":"character.activated_ability","timing":"immediate"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"source.is_active","operator":"equals","value":true},{"fact":"player.field.has_keyword.haya","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":8000}]},"prompt":"리무브할 상대 캐릭터(AP 8000 이하)를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}]},{"effectId":"card-1013-opponent-turn-field-remove","cardIds":["1013"],"cardNameKo":"하기와라 켄지","cardNameJa":"萩原研二","trigger":{"event":"character.removed_from_field","timing":"after"},"conditions":[{"fact":"turn.is_opponent_turn","operator":"equals","value":true}],"steps":[{"op":"peek_top_cards","count":3,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"keyword","operator":"has_keyword","value":"haya"}]},"prompt":"공개해 패에 넣을 질풍/돌격 보유 캐릭터를 최대 1장 선택하세요.","saveAs":"chosen"},{"op":"reveal_cards","from":"chosen","to":["all"],"awaitAcknowledgement":false,"when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"chosen","to":"hand","when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"seen","selectedVariable":"chosen","to":"remove_area","order":"preserve"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"prompt":"레벨 8 이상 카드를 패에 추가했다면, 리무브할 손패 1장을 선택하세요.","saveAs":"hand_to_remove","when":{"fact":"vars.chosen.has_level_at_least_8","operator":"equals","value":true}},{"op":"move_cards","from":"hand_to_remove","to":"remove_area","when":{"fact":"vars.chosen.has_level_at_least_8","operator":"equals","value":true}}],"afterResolve":{"note":"선택한 카드가 없으면 손패 이동과 추가 리무브는 건너뜁니다.","removeHandOnlyIfSelectedCardLevelAtLeast":8}},{"effectId":"card-0636-on-enter-search-shinichi","cardIds":["0636"],"cardNameKo":"모리 란","cardNameJa":"毛利蘭","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"blue"}],"steps":[{"op":"reveal_until_match","from":"deck","saveAs":"search_result","match":{"allOf":[{"field":"level","operator":"greater_than_or_equal","value":7},{"field":"card_name","operator":"name_matches","value":"工藤新一"}]},"includeMatchingCard":true,"publicReveal":true,"oneByOne":true,"awaitActorAcknowledgement":true,"whenNoMatch":"shuffle_all_back"},{"op":"move_cards","from":"search_result.matched","to":"hand","when":{"fact":"vars.search_result.matched_count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"search_result.revealed","selectedVariable":"search_result.matched","to":"deck_bottom","order":"preserve"},{"op":"shuffle_deck"}]},{"effectId":"card-0796-on-enter-partner-red-hand-check","cardIds":["0796"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"opponent.hand.count","operator":"greater_than_or_equal","value":{"fact":"player.hand.count"}}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":8}]},"prompt":"리무브할 상대 레벨 8 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"ruleTextNote":"일본어 원문은 상대 손패 수가 자신의 손패 수 이상(>=)이라고 되어 있어 원문을 우선했습니다."},{"effectId":"card-0796-activated-remove-level7","cardIds":["0796"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.activated_ability","timing":"immediate"},"oncePerTurn":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2},{"fact":"source.status","operator":"in","value":["rested","stunned"]}],"steps":[{"op":"select_cards","from":"field","min":1,"max":1,"optional":false,"filter":{"allOf":[{"field":"controller","operator":"equals","value":"self"},{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"greater_than_or_equal","value":6},{"field":"color","operator":"equals","value":"red"},{"field":"is_active","operator":"equals","value":true}]},"prompt":"비용으로 슬립시킬 레벨 6 이상 적 캐릭터 1장을 선택하세요. 효과 발동 캐릭터 자신도 선택할 수 있습니다.","saveAs":"cost_target"},{"op":"pay_cost","cost":"sleep_selected_character","targetVariable":"cost_target"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"리무브할 상대 레벨 7 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0501-continuous-bond-yamato-ap","cardIds":["0501"],"cardNameKo":"모로후시 타카아키","cardNameJa":"諸伏高明","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.field.has_card_name","operator":"equals","value":"大和敢助"}],"steps":[{"op":"set_continuous_stat","target":"source_character","stat":"ap","amount":2000,"modifierId":"bond-yamato-ap","duration":"while_condition_true"}]},{"effectId":"card-0501-continuous-nagano-police-charge","cardIds":["0501"],"cardNameKo":"모로후시 타카아키","cardNameJa":"諸伏高明","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"player.remove_area.count_matching_trait","operator":"greater_than_or_equal","value":2,"trait":"長野県警","cardType":"character"}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","modifierId":"nagano-police-charge","duration":"while_condition_true"}]},{"effectId":"card-0264-on-enter-attach-detective-boys","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":5,"optional":true,"uniqueBy":"card_name","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"trait","operator":"has_trait","value":"少年探偵団"}]},"prompt":"이 카드 아래에 겹칠, 카드명이 서로 다른 소년탐정단 캐릭터를 최대 5장 선택하세요.","saveAs":"attachments"},{"op":"attach_cards","from":"attachments","to":"source_character"}]},{"effectId":"card-0264-continuous-charge-from-attachments","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","modifierId":"detective-boys-charge","duration":"while_condition_true"}]},{"effectId":"card-0264-action-draw-at-three","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":3}],"steps":[{"op":"draw_cards","destination":"hand","count":1}]},{"effectId":"card-0264-action-evidence-at-five","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":5}],"steps":[{"op":"gain_evidence","count":1}]},{"effectId":"card-1010-first-entry-haya-recover","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"entry.is_first_character_this_turn","operator":"equals","value":true}],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"filter":{"anyOf":[{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6},{"field":"trait","operator":"has_trait","value":"神奈川県警"}]},{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6},{"field":"keyword","operator":"has_keyword","value":"haya"}]}]},"prompt":"패에 추가할 레벨 6 이하 가나가와현 경찰 또는 질풍 보유 캐릭터를 최대 1장 선택하세요.","saveAs":"recovered"},{"op":"move_cards","from":"recovered","to":"hand","when":{"fact":"vars.recovered.count","operator":"greater_than","value":0}},{"op":"mark_keyword_activated","keyword":"haya"}]},{"effectId":"card-1010-partner-yellow-activated-remove","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"character.activated_ability","timing":"immediate"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"},{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"source.is_active","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":9}]},"prompt":"리무브할 상대 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}]},{"effectId":"card-1010-end-turn-ready-haya-users","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"player.turn_ended","timing":"after"},"steps":[{"op":"ready_cards_that_used_keyword","keyword":"haya","turn":"ending_turn","includePartnerArea":true}]}]}$effectdsl$::jsonb)->'definitions')
ON CONFLICT (catalog_id) DO UPDATE
SET schema_version = EXCLUDED.schema_version,
    definitions = EXCLUDED.definitions,
    updated_at = now();

CREATE OR REPLACE FUNCTION public.private_card_effect_normalize_id_v1(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT CASE
    WHEN v ~ '^[0-9]+$' THEN coalesce(nullif(ltrim(v, '0'), ''), '0')
    ELSE v
  END
  FROM (SELECT regexp_replace(upper(trim(coalesce(p_value, ''))), '^ID[[:space:]]*:[[:space:]]*', '') AS v) n
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_matches_id_v1(p_card jsonb, p_card_ids jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(coalesce(p_card_ids, '[]'::jsonb)) ids(id)
    CROSS JOIN LATERAL unnest(ARRAY[
      p_card ->> 'databaseId', p_card ->> 'database_id', p_card ->> 'databaseID',
      p_card ->> 'cardId', p_card ->> 'card_id', p_card ->> 'cardNum', p_card ->> 'card_num',
      p_card ->> 'id', p_card ->> 'key',
      p_card #>> '{sourceData,databaseId}', p_card #>> '{sourceData,database_id}',
      p_card #>> '{sourceData,cardId}', p_card #>> '{sourceData,card_id}',
      p_card #>> '{sourceData,id}', p_card #>> '{raw,databaseId}',
      p_card #>> '{raw,database_id}', p_card #>> '{raw,cardId}', p_card #>> '{raw,card_id}',
      p_card #>> '{raw,id}'
    ]) vals(val)
    WHERE public.private_card_effect_normalize_id_v1(vals.val)
        = public.private_card_effect_normalize_id_v1(ids.id)
  )
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_level_v1(p_card jsonb)
RETURNS integer LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT coalesce(
    nullif(regexp_replace(coalesce(p_card ->> 'level', p_card ->> 'cost',
      p_card ->> 'level_number', p_card #>> '{sourceData,level}',
      p_card #>> '{sourceData,cost}', p_card #>> '{raw,level}', p_card #>> '{raw,cost}', ''), '[^0-9-]', '', 'g'), '')::integer,
    0
  )
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_color_v1(p_card jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE v text;
BEGIN
  v := lower(coalesce(p_card ->> 'color', p_card ->> 'color_key', p_card ->> 'colorKey',
    p_card #>> '{sourceData,color}', p_card #>> '{raw,color}', ''));
  IF v IN ('red','赤','적') OR position('赤' in v)>0 OR position('적' in v)>0 OR v LIKE '%red%' THEN RETURN 'red'; END IF;
  IF v IN ('blue','青','청') OR position('青' in v)>0 OR position('청' in v)>0 OR v LIKE '%blue%' THEN RETURN 'blue'; END IF;
  IF v IN ('green','緑','녹') OR position('緑' in v)>0 OR position('녹' in v)>0 OR v LIKE '%green%' THEN RETURN 'green'; END IF;
  IF v IN ('yellow','黄','황') OR position('黄' in v)>0 OR position('황' in v)>0 OR v LIKE '%yellow%' THEN RETURN 'yellow'; END IF;
  RETURN nullif(v,'');
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_name_v1(p_card jsonb)
RETURNS text LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT coalesce(
    nullif(p_card ->> 'name', ''), nullif(p_card ->> 'name_ja', ''),
    nullif(p_card ->> 'nameJa', ''), nullif(p_card ->> 'card_name', ''),
    nullif(p_card ->> 'title', ''), nullif(p_card #>> '{sourceData,name}', ''),
    nullif(p_card #>> '{sourceData,name_ja}', ''), nullif(p_card #>> '{raw,name}', ''),
    nullif(p_card #>> '{raw,name_ja}', ''), ''
  )
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_name_matches_v1(p_card jsonb, p_expected text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE v text := lower(coalesce(p_expected, '')); j text := lower(coalesce(p_card, '{}'::jsonb)::text);
BEGIN
  IF v = '' THEN RETURN false; END IF;
  IF position(v in j)>0 THEN RETURN true; END IF;
  IF v IN ('工藤新一','쿠도 신이치','쿠도신이치','kudo shinichi','kudou shinichi','shinichi kudo') THEN
    RETURN position('工藤新一' in j)>0 OR position('쿠도 신이치' in j)>0
      OR position('kudo shinichi' in j)>0 OR position('kudou shinichi' in j)>0;
  END IF;
  IF v IN ('大和敢助','야마토 칸스케','야마토칸스케','yamato kansuke') THEN
    RETURN position('大和敢助' in j)>0 OR position('야마토 칸스케' in j)>0 OR position('yamato kansuke' in j)>0;
  END IF;
  RETURN false;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_has_keyword_v1(p_card jsonb, p_keyword text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE j text := lower(coalesce(p_card, '{}'::jsonb)::text); k text := lower(coalesce(p_keyword,''));
BEGIN
  IF k IN ('haya','gale','질풍','疾風') THEN
    RETURN position('疾風' in j)>0 OR position('질풍' in j)>0 OR position('haya' in j)>0 OR position('gale' in j)>0
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_card->'dsl_keywords','[]'::jsonb)) x(value)
                 WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}','')) IN ('haya','gale','질풍','疾風'));
  ELSIF k IN ('charge','돌격','突撃') THEN
    RETURN position('突撃' in j)>0 OR position('돌격' in j)>0 OR position('charge' in j)>0
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_card->'dsl_keywords','[]'::jsonb)) x(value)
                 WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}','')) IN ('charge','돌격','突撃'))
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_card->'dsl_continuous_keywords','[]'::jsonb)) x(value)
                 WHERE lower(coalesce(x.value->>'keyword','')) IN ('charge','돌격','突撃'));
  END IF;
  RETURN position(k in j)>0;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_has_trait_v1(p_card jsonb, p_trait text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE j text := lower(coalesce(p_card, '{}'::jsonb)::text); t text := lower(coalesce(p_trait,''));
BEGIN
  IF t IN ('少年探偵団','소년탐정단','detective boys') THEN
    RETURN position('少年探偵団' in j)>0 OR position('소년탐정단' in j)>0 OR position('detective boys' in j)>0;
  ELSIF t IN ('神奈川県警','가나가와현 경찰','가나가와현경','kanagawa prefectural police') THEN
    RETURN position('神奈川県警' in j)>0 OR position('가나가와현 경찰' in j)>0 OR position('가나가와현경' in j)>0;
  ELSIF t IN ('長野県警','나가노현 경찰','나가노현경','nagano prefectural police') THEN
    RETURN position('長野県警' in j)>0 OR position('나가노현 경찰' in j)>0 OR position('나가노현경' in j)>0;
  END IF;
  RETURN position(t in j)>0;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_is_character_v1(p_card jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE t text := lower(coalesce(p_card->>'card_type', p_card->>'type', p_card->>'originalType', p_card#>>'{sourceData,card_type}', p_card#>>'{raw,type}', ''));
BEGIN
  RETURN t IN ('character','キャラ','キャラクター','캐릭터') OR position('character' in t)>0 OR position('キャラ' in t)>0 OR position('캐릭터' in t)>0;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_is_active_v1(p_card jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT coalesce((p_card->>'rested')::boolean,false)=false
    AND lower(coalesce(p_card->>'status','active')) NOT IN ('rested','stunned','sleep','slumber','슬립','스턴','sleeping')
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_partner_color_v1(p_room_id uuid, p_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_key text; v_card jsonb; v_board public.room_player_turn_boards%rowtype; v_deck jsonb;
BEGIN
  SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_user_id;
  v_key := v_board.partner_key;
  IF v_board.partner_mr_card IS NOT NULL AND (v_board.partner_mr_card->>'key')=v_key THEN
    RETURN public.private_card_effect_color_v1(v_board.partner_mr_card);
  END IF;
  SELECT e.value INTO v_card FROM jsonb_array_elements(coalesce(v_board.partner_non_mr_cards,'[]'::jsonb)) e(value)
   WHERE e.value->>'key'=v_key OR e.value->>'instance_id'=v_key LIMIT 1;
  IF v_card IS NOT NULL THEN RETURN public.private_card_effect_color_v1(v_card); END IF;
  SELECT e.value INTO v_card FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
   WHERE e.value->>'key'=v_key LIMIT 1;
  IF v_card IS NOT NULL THEN RETURN public.private_card_effect_color_v1(v_card); END IF;
  SELECT coalesce(main_deck,'[]'::jsonb) INTO v_deck FROM public.room_player_decks WHERE room_id=p_room_id AND user_id=p_user_id;
  SELECT e.value INTO v_card FROM jsonb_array_elements(coalesce(v_deck,'[]'::jsonb)) e(value)
   WHERE e.value->>'key'=v_key LIMIT 1;
  RETURN public.private_card_effect_color_v1(v_card);
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_fact_v1(
 p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb,
 p_context jsonb, p_vars jsonb, p_fact text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_match public.room_match_states%rowtype; v_game public.room_player_game_states%rowtype;
 v_board public.room_player_turn_boards%rowtype; v_other_game public.room_player_game_states%rowtype;
 v_cards jsonb; v_result jsonb; v_kw text; v_path text[]; v_bool boolean;
BEGIN
 SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_other_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id<>p_actor ORDER BY seat LIMIT 1;
 IF p_fact='player.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='opponent.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_other_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.deck.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb))); END IF;
 IF p_fact='player.partner.color' THEN RETURN to_jsonb(public.private_card_effect_partner_color_v1(p_room_id,p_actor)); END IF;
 IF p_fact='turn.is_source_controller_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id=p_source_user); END IF;
 IF p_fact='turn.is_opponent_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id IS DISTINCT FROM p_source_user); END IF;
 IF p_fact='entry.method' THEN RETURN coalesce(p_context#>'{entry,method}','null'::jsonb); END IF;
 IF p_fact='entry.is_first_character_this_turn' THEN RETURN coalesce(p_context#>'{entry,is_first_character_this_turn}','false'::jsonb); END IF;
 IF p_fact='entry.source.level' THEN RETURN to_jsonb(public.private_card_effect_level_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb))); END IF;
 IF p_fact='entry.source.card_type' THEN RETURN coalesce(p_context#>'{entry,source,card_type}',p_context#>'{entry,source,type}','null'::jsonb); END IF;
 IF p_fact='source.status' THEN
   RETURN to_jsonb(coalesce(p_source_card->>'status',CASE WHEN coalesce((p_source_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END));
 END IF;
 IF p_fact='source.is_active' THEN RETURN to_jsonb(public.private_card_effect_is_active_v1(p_source_card)); END IF;
 IF p_fact='source.under_cards.count' THEN
   RETURN to_jsonb(jsonb_array_length(coalesce(p_source_card->'stacked_cards',p_source_card->'under_cards','[]'::jsonb)));
 END IF;
 IF p_fact='player.field.has_card_name' THEN RETURN 'null'::jsonb; END IF;
 IF p_fact='player.remove_area.count_matching_trait' THEN RETURN 'null'::jsonb; END IF;
 IF p_fact LIKE 'player.field.has_keyword.%' THEN
   v_kw := substr(p_fact,length('player.field.has_keyword.')+1);
   SELECT EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     WHERE public.private_card_effect_has_keyword_v1(e.value,v_kw)
   ) INTO v_bool;
   RETURN to_jsonb(v_bool);
 END IF;
 IF p_fact LIKE 'vars.%' THEN
   v_path := string_to_array(substr(p_fact,6),'.');
   IF array_length(v_path,1)>1 AND v_path[array_length(v_path,1)]='count' THEN
     v_path := v_path[1:array_length(v_path,1)-1];
     v_result := p_vars #> v_path;
     IF jsonb_typeof(v_result)='array' THEN RETURN to_jsonb(jsonb_array_length(v_result)); END IF;
     IF jsonb_typeof(v_result)='object' THEN RETURN to_jsonb((SELECT count(*) FROM jsonb_object_keys(v_result))); END IF;
     RETURN to_jsonb(0);
   END IF;
   IF p_fact LIKE 'vars.%.has_level_at_least_8' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     RETURN to_jsonb(EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))>=8));
   END IF;
   RETURN coalesce(p_vars #> v_path,'null'::jsonb);
 END IF;
 RETURN 'null'::jsonb;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_condition_matches_v1(
 p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb,
 p_context jsonb, p_vars jsonb, p_condition jsonb
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_fact text:=p_condition->>'fact'; v_op text:=p_condition->>'operator';
 v_actual jsonb; v_expected jsonb; v_match public.room_match_states%rowtype; v_bool boolean;
 v_board public.room_player_turn_boards%rowtype; v_game public.room_player_game_states%rowtype;
 v_count integer; v_expected_name text; v_card jsonb; v_trait text; v_typ text;
BEGIN
 IF p_condition IS NULL OR jsonb_typeof(p_condition)<>'object' THEN RETURN false; END IF;
 v_expected:=p_condition->'value';
 IF jsonb_typeof(v_expected)='object' AND v_expected ? 'fact' THEN
   v_expected:=public.private_card_effect_fact_v1(p_room_id,p_actor,p_source_user,p_source_card,p_context,p_vars,v_expected->>'fact');
 END IF;
 IF v_fact='player.field.has_card_name' THEN
   SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
   SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      WHERE public.private_card_effect_name_matches_v1(e.value,trim(both '"' from v_expected::text))) INTO v_bool;
   v_actual:=to_jsonb(v_bool);
 ELSIF v_fact='player.remove_area.count_matching_trait' THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_trait:=coalesce(p_condition->>'trait','');
   v_typ:=coalesce(p_condition->>'cardType','character');
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value)
   WHERE (v_typ<>'character' OR public.private_card_effect_is_character_v1(e.value))
     AND public.private_card_effect_has_trait_v1(e.value,v_trait);
   v_actual:=to_jsonb(v_count);
 ELSE
   v_actual:=public.private_card_effect_fact_v1(p_room_id,p_actor,p_source_user,p_source_card,p_context,p_vars,v_fact);
 END IF;
 IF v_actual IS NULL OR v_actual='null'::jsonb THEN
   IF v_op='equals' THEN RETURN v_expected='null'::jsonb; END IF;
   RETURN false;
 END IF;
 CASE v_op
  WHEN 'equals' THEN RETURN v_actual=v_expected;
  WHEN 'in' THEN RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_expected,'[]'::jsonb)) e(value) WHERE e.value=v_actual);
  WHEN 'less_than' THEN RETURN (v_actual #>> '{}')::numeric < (v_expected #>> '{}')::numeric;
  WHEN 'less_than_or_equal' THEN RETURN (v_actual #>> '{}')::numeric <= (v_expected #>> '{}')::numeric;
  WHEN 'greater_than' THEN RETURN (v_actual #>> '{}')::numeric > (v_expected #>> '{}')::numeric;
  WHEN 'greater_than_or_equal' THEN RETURN (v_actual #>> '{}')::numeric >= (v_expected #>> '{}')::numeric;
  ELSE RETURN false;
 END CASE;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RETURN false;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_conditions_match_v1(
 p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb,
 p_context jsonb, p_vars jsonb, p_conditions jsonb
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE c jsonb;
BEGIN
 FOR c IN SELECT value FROM jsonb_array_elements(coalesce(p_conditions,'[]'::jsonb)) LOOP
   IF NOT public.private_card_effect_condition_matches_v1(p_room_id,p_actor,p_source_user,p_source_card,p_context,p_vars,c) THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_filter_matches_v1(
 p_room_id uuid, p_card jsonb, p_owner_user uuid, p_source_user uuid, p_filter jsonb
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE part jsonb; f text; op text; expected jsonb; actual jsonb; v_num numeric;
BEGIN
 IF p_filter IS NULL OR jsonb_typeof(p_filter)<>'object' THEN RETURN true; END IF;
 IF p_filter ? 'allOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'allOf') LOOP
    IF NOT public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,part) THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
 END IF;
 IF p_filter ? 'anyOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'anyOf') LOOP
    IF public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,part) THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
 END IF;
 f:=p_filter->>'field'; op:=p_filter->>'operator'; expected:=p_filter->'value'; actual:='null'::jsonb;
 CASE f
  WHEN 'card_type' THEN actual:=to_jsonb(CASE WHEN public.private_card_effect_is_character_v1(p_card) THEN 'character' ELSE lower(coalesce(p_card->>'card_type',p_card->>'type','')) END);
  WHEN 'level' THEN actual:=to_jsonb(public.private_card_effect_level_v1(p_card));
  WHEN 'color' THEN actual:=to_jsonb(public.private_card_effect_color_v1(p_card));
  WHEN 'card_name' THEN
    IF op='name_matches' THEN RETURN public.private_card_effect_name_matches_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_name_v1(p_card));
  WHEN 'trait' THEN
    IF op='has_trait' THEN RETURN public.private_card_effect_has_trait_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_has_trait_v1(p_card,trim(both '"' from expected::text)));
  WHEN 'keyword' THEN
    IF op='has_keyword' THEN RETURN public.private_card_effect_has_keyword_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_has_keyword_v1(p_card,trim(both '"' from expected::text)));
  WHEN 'ap_current' THEN actual:=to_jsonb(coalesce(nullif(p_card->>'ap','')::numeric,0)+coalesce(nullif(p_card->>'ap_bonus','')::numeric,0));
  WHEN 'is_active' THEN actual:=to_jsonb(public.private_card_effect_is_active_v1(p_card));
  WHEN 'status' THEN actual:=to_jsonb(coalesce(p_card->>'status',CASE WHEN coalesce((p_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END));
  WHEN 'controller' THEN actual:=to_jsonb(CASE WHEN p_owner_user=p_source_user THEN 'self' ELSE 'opponent' END);
  ELSE actual:=coalesce(p_card->f,'null'::jsonb);
 END CASE;
 IF op='equals' THEN RETURN actual=expected; END IF;
 IF op='in' THEN RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(expected,'[]'::jsonb)) e(value) WHERE e.value=actual); END IF;
 IF op='less_than' THEN RETURN (actual#>>'{}')::numeric < (expected#>>'{}')::numeric; END IF;
 IF op='less_than_or_equal' THEN RETURN (actual#>>'{}')::numeric <= (expected#>>'{}')::numeric; END IF;
 IF op='greater_than' THEN RETURN (actual#>>'{}')::numeric > (expected#>>'{}')::numeric; END IF;
 IF op='greater_than_or_equal' THEN RETURN (actual#>>'{}')::numeric >= (expected#>>'{}')::numeric; END IF;
 RETURN false;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN false;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_get_card_v1(p_room_id uuid,p_user_id uuid,p_instance_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_card jsonb; v_board public.room_player_turn_boards%rowtype; v_game public.room_player_game_states%rowtype;
BEGIN
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_user_id;
 SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_user_id;
 SELECT value INTO v_card FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) WHERE value->>'instance_id'=p_instance_id LIMIT 1;
 IF v_card IS NOT NULL THEN RETURN v_card; END IF;
 IF v_board.partner_mr_card->>'instance_id'=p_instance_id THEN RETURN v_board.partner_mr_card; END IF;
 SELECT value INTO v_card FROM jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) WHERE value->>'instance_id'=p_instance_id LIMIT 1;
 IF v_card IS NOT NULL THEN RETURN v_card; END IF;
 SELECT value INTO v_card FROM jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) WHERE value->>'instance_id'=p_instance_id LIMIT 1;
 IF v_card IS NOT NULL THEN RETURN v_card; END IF;
 SELECT value INTO v_card FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WHERE value->>'instance_id'=p_instance_id LIMIT 1;
 RETURN v_card;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_patch_card_v1(p_room_id uuid,p_user_id uuid,p_instance_id text,p_patch jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_board public.room_player_turn_boards%rowtype; v_found boolean:=false;
BEGIN
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION '카드 효과 대상 보드를 찾지 못했습니다.'; END IF;
 IF v_board.partner_mr_card->>'instance_id'=p_instance_id THEN
   UPDATE public.room_player_turn_boards SET partner_mr_card=partner_mr_card || p_patch,updated_at=now() WHERE room_id=p_room_id AND user_id=p_user_id;
   RETURN;
 END IF;
 SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=p_instance_id) INTO v_found;
 IF v_found THEN
   UPDATE public.room_player_turn_boards b SET field_cards=(
     SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'instance_id'=p_instance_id THEN e.value || p_patch ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb)
     FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
   ),updated_at=now() WHERE b.room_id=p_room_id AND b.user_id=p_user_id;
   RETURN;
 END IF;
 RAISE EXCEPTION '카드 효과로 변경할 현장 카드를 찾지 못했습니다.';
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_remove_from_array_v1(p_array jsonb,p_instance_id text)
RETURNS jsonb LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality),'[]'::jsonb)
 FROM jsonb_array_elements(coalesce(p_array,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
 WHERE e.value->>'instance_id' IS DISTINCT FROM p_instance_id
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_move_card_v1(
 p_room_id uuid,p_owner_user uuid,p_from_zone text,p_card jsonb,p_to_zone text,p_target_user uuid DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_source_user uuid:=p_owner_user; v_target_user uuid:=coalesce(p_target_user,p_owner_user);
 v_id text:=p_card->>'instance_id'; v_card jsonb:=p_card;
 v_game public.room_player_game_states%rowtype; v_board public.room_player_turn_boards%rowtype;
 v_old_partner jsonb; v_rarity text;
BEGIN
 IF v_id IS NULL OR v_id='' THEN RAISE EXCEPTION '카드 효과 이동에 instance_id가 없습니다.'; END IF;
 IF p_from_zone NOT IN ('peek','variable','') THEN
   IF p_from_zone='field' THEN
     SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF NOT FOUND THEN RAISE EXCEPTION '카드 이동 원본 현장을 찾을 수 없습니다.'; END IF;
     UPDATE public.room_player_turn_boards SET field_cards=public.private_card_effect_remove_from_array_v1(field_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='hand' THEN
     UPDATE public.room_player_game_states SET hand=public.private_card_effect_remove_from_array_v1(hand,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='remove_area' THEN
     UPDATE public.room_player_game_states SET remove_cards=public.private_card_effect_remove_from_array_v1(remove_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
     UPDATE public.room_player_turn_boards SET remove_count=greatest(0,remove_count-1),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='deck' THEN
     UPDATE public.room_player_game_states SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='evidence_area' THEN
     UPDATE public.room_player_game_states SET evidence_cards=public.private_card_effect_remove_from_array_v1(evidence_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
     UPDATE public.room_player_turn_boards SET evidence_count=greatest(0,evidence_count-1),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   END IF;
 END IF;

 v_card:=v_card-'zone'-'owner_user_id'-'resolving';
 IF p_to_zone='hand' THEN
   UPDATE public.room_player_game_states SET hand=coalesce(hand,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSIF p_to_zone='remove_area' THEN
   v_rarity:=upper(coalesce(v_card->>'rarity',v_card->>'rarity_code',v_card#>>'{sourceData,rarity}',v_card#>>'{raw,rarity}',''));
   IF p_from_zone='field' AND v_rarity IN ('MR','MRP') THEN
     SELECT partner_mr_card INTO v_old_partner FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF v_old_partner IS NOT NULL AND v_old_partner->>'instance_id' IS DISTINCT FROM v_id THEN
       UPDATE public.room_player_game_states SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_old_partner-'rested'-'status'-'ap_bonus'-'summoned_this_turn'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
       UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now() WHERE room_id=p_room_id AND user_id=v_source_user;
     END IF;
     UPDATE public.room_player_turn_boards SET partner_mr_card=v_card||jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',false),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSE
     UPDATE public.room_player_game_states SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
     UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
   END IF;
 ELSIF p_to_zone='deck_bottom' THEN
   UPDATE public.room_player_game_states SET deck_order=coalesce(deck_order,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSIF p_to_zone='field' THEN
   UPDATE public.room_player_turn_boards SET field_cards=coalesce(field_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('rested',false,'status','active','summoned_this_turn',true,'ap_bonus',0,'entry_method','event_effect')),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSE
   RAISE EXCEPTION '카드 효과 이동 목적지 %는 아직 지원하지 않습니다.',p_to_zone;
 END IF;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_get_candidates_v1(
 p_room_id uuid,p_actor uuid,p_source_user uuid,p_from text,p_filter jsonb,p_target_controller text,p_unique_by text,p_vars jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_out jsonb:='[]'::jsonb; v_data jsonb; v_wrapped jsonb; v_card jsonb; v_owner uuid; v_zone text;
 v_board public.room_player_turn_boards%rowtype; v_game public.room_player_game_states%rowtype;
 v_rp record; e record; v_name text; v_seen_names text[]:='{}'::text[]; v_path text[];
BEGIN
 IF p_from IN ('deck','hand','remove_area','evidence_area') THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_data:=CASE p_from WHEN 'deck' THEN coalesce(v_game.deck_order,'[]'::jsonb) WHEN 'hand' THEN coalesce(v_game.hand,'[]'::jsonb)
     WHEN 'remove_area' THEN coalesce(v_game.remove_cards,'[]'::jsonb) ELSE coalesce(v_game.evidence_cards,'[]'::jsonb) END;
   v_owner:=p_actor; v_zone:=p_from;
   FOR e IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
     v_card:=e.value;
     IF public.private_card_effect_filter_matches_v1(p_room_id,v_card,v_owner,p_source_user,p_filter) THEN
       v_name:=lower(public.private_card_effect_name_v1(v_card));
       IF p_unique_by IS NULL OR NOT(v_name=ANY(v_seen_names)) THEN
         v_out:=v_out||jsonb_build_array(jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_owner,'zone',v_zone,'card',v_card));
         IF p_unique_by='card_name' THEN v_seen_names:=array_append(v_seen_names,v_name); END IF;
       END IF;
     END IF;
   END LOOP;
   RETURN v_out;
 END IF;
 IF p_from LIKE 'vars.%' OR p_from NOT IN ('field','opponent_field','partner_area','source_character') THEN
   v_path:=string_to_array(CASE WHEN p_from LIKE 'vars.%' THEN substr(p_from,6) ELSE p_from END,'.');
   v_data:=p_vars #> v_path;
   FOR e IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
     v_card:=coalesce(e.value->'card',e.value);
     v_owner:=coalesce(nullif(e.value->>'owner_user_id','')::uuid,p_actor);
     v_zone:=coalesce(e.value->>'zone','variable');
     IF public.private_card_effect_filter_matches_v1(p_room_id,v_card,v_owner,p_source_user,p_filter) THEN
       v_name:=lower(public.private_card_effect_name_v1(v_card));
       IF p_unique_by IS NULL OR NOT(v_name=ANY(v_seen_names)) THEN
         v_out:=v_out||jsonb_build_array(jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_owner,'zone',v_zone,'card',v_card));
         IF p_unique_by='card_name' THEN v_seen_names:=array_append(v_seen_names,v_name); END IF;
       END IF;
     END IF;
   END LOOP;
   RETURN v_out;
 END IF;

 FOR v_rp IN SELECT user_id FROM public.room_players WHERE room_id=p_room_id
 LOOP
   IF p_from='opponent_field' AND v_rp.user_id=p_actor THEN CONTINUE; END IF;
   IF p_from='field' AND p_target_controller IS DISTINCT FROM 'any' AND v_rp.user_id<>p_actor THEN CONTINUE; END IF;
   SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_rp.user_id;
   IF p_from='partner_area' THEN
     IF v_board.partner_mr_card IS NOT NULL THEN
       v_card:=v_board.partner_mr_card;
       IF public.private_card_effect_filter_matches_v1(p_room_id,v_card,v_rp.user_id,p_source_user,p_filter) THEN
         v_out:=v_out||jsonb_build_array(jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_rp.user_id,'zone','partner_area','card',v_card));
       END IF;
     END IF;
     CONTINUE;
   END IF;
   FOR e IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) LOOP
     v_card:=e.value;
     IF public.private_card_effect_filter_matches_v1(p_room_id,v_card,v_rp.user_id,p_source_user,p_filter) THEN
       v_name:=lower(public.private_card_effect_name_v1(v_card));
       IF p_unique_by IS NULL OR NOT(v_name=ANY(v_seen_names)) THEN
         v_out:=v_out||jsonb_build_array(jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_rp.user_id,'zone','field','card',v_card));
         IF p_unique_by='card_name' THEN v_seen_names:=array_append(v_seen_names,v_name); END IF;
       END IF;
     END IF;
   END LOOP;
 END LOOP;
 RETURN v_out;
END
$function$;

REVOKE ALL ON FUNCTION public.private_card_effect_normalize_id_v1(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_matches_id_v1(jsonb,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_level_v1(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_color_v1(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_name_v1(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_name_matches_v1(jsonb,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_has_keyword_v1(jsonb,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_has_trait_v1(jsonb,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_is_character_v1(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_is_active_v1(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_partner_color_v1(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_condition_matches_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_conditions_match_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_filter_matches_v1(uuid,jsonb,uuid,uuid,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_get_card_v1(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_patch_card_v1(uuid,uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_remove_from_array_v1(jsonb,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_move_card_v1(uuid,uuid,text,jsonb,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_get_candidates_v1(uuid,uuid,uuid,text,jsonb,text,text,jsonb) FROM PUBLIC, anon, authenticated;
