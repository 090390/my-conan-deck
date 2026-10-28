ALTER TABLE public.room_player_turn_boards ADD COLUMN IF NOT EXISTS first_character_entered_this_turn text;

INSERT INTO public.private_card_effect_catalog_v1(catalog_id,schema_version,definitions)
VALUES ('main',1,$effectdsl${"schemaVersion":1,"language":"conan-card-effect-dsl","definitions":[{"effectId":"card-0062-on-enter","cardIds":["0062"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","operator":"less_than","value":4},"includeRemainingDeck":true,"includeRemoveArea":true,"shuffle":true},{"op":"peek_top_cards","count":4,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"filter":{"field":"color","operator":"equals","value":"red"},"prompt":"공개하여 패에 넣을 적 카드를 최대 1장 선택하세요.","saveAs":"selected_red"},{"op":"reveal_cards","from":"selected_red","to":["opponent"],"awaitAcknowledgement":true,"when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"selected_red","to":"hand","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_deck_bottom","from":"seen","selectedVariable":"selected_red","order":"player_choice"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"prompt":"패에 추가한 경우, 리무브할 손패 1장을 선택하세요.","saveAs":"hand_to_remove","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"hand_to_remove","to":"remove_area","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}}]},{"effectId":"card-0110-on-enter-partner-green","cardIds":["0110"],"cardNameKo":"오키타 소지","cardNameJa":"沖田総司","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"green"}],"steps":[{"op":"grant_keyword","target":"source_character","keyword":"charge","displayNameKo":"돌격","duration":"turn_end"}]},{"effectId":"card-0011-on-enter-from-level3-effect","cardIds":["0011"],"cardNameKo":"츠부라야 미츠히코","cardNameJa":"円谷光彦","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"entry.method","operator":"in","value":["character_ability","event_effect"]},{"fact":"entry.source.card_type","operator":"in","value":["character","event"]},{"fact":"entry.source.level","operator":"greater_than_or_equal","value":3}],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"filter":{"field":"card_type","operator":"equals","value":"character"},"targetController":"any","prompt":"턴 종료 시까지 AP를 2000 올릴 캐릭터를 최대 1장 선택하세요.","saveAs":"ap_target"},{"op":"modify_stat","target":"ap_target","stat":"ap","amount":2000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0223-on-enter-ap-minus-1000","cardIds":["0223"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"filter":{"field":"card_type","operator":"equals","value":"character"},"targetController":"any","prompt":"턴 종료 시까지 AP를 1000 낮출 캐릭터를 최대 1장 선택하세요.","saveAs":"ap_target"},{"op":"modify_stat","target":"ap_target","stat":"ap","amount":-1000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0223-mislead-passive","cardIds":["0223"],"trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"set_mislead_value","target":"source_character","value":1,"duration":"while_in_field"}],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング"},{"effectId":"card-1013-activated-remove-low-ap","cardIds":["1013"],"cardNameKo":"하기와라 켄지","cardNameJa":"萩原研二","trigger":{"event":"character.activated_ability","timing":"immediate"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"source.is_active","operator":"equals","value":true},{"fact":"player.field.has_keyword.haya","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":8000}]},"prompt":"리무브할 상대 캐릭터(AP 8000 이하)를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"질풍 조건부 슬립·리무브"},{"effectId":"card-1013-opponent-turn-field-remove","cardIds":["1013"],"cardNameKo":"하기와라 켄지","cardNameJa":"萩原研二","trigger":{"event":"character.removed_from_field","timing":"after"},"conditions":[{"fact":"turn.is_opponent_turn","operator":"equals","value":true}],"steps":[{"op":"peek_top_cards","count":3,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"keyword","operator":"has_keyword","value":"haya"}]},"prompt":"공개해 패에 넣을 질풍/돌격 보유 캐릭터를 최대 1장 선택하세요.","saveAs":"chosen"},{"op":"reveal_cards","from":"chosen","to":["all"],"awaitAcknowledgement":false,"when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"chosen","to":"hand","when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"seen","selectedVariable":"chosen","to":"remove_area","order":"preserve"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"prompt":"레벨 8 이상 카드를 패에 추가했다면, 리무브할 손패 1장을 선택하세요.","saveAs":"hand_to_remove","when":{"fact":"vars.chosen.has_level_at_least_8","operator":"equals","value":true}},{"op":"move_cards","from":"hand_to_remove","to":"remove_area","when":{"fact":"vars.chosen.has_level_at_least_8","operator":"equals","value":true}}],"afterResolve":{"note":"선택한 카드가 없으면 손패 이동과 추가 리무브는 건너뜁니다.","removeHandOnlyIfSelectedCardLevelAtLeast":8},"activationLabelKo":"상대 턴 현장 리무브 효과"},{"effectId":"card-0636-on-enter-search-shinichi","cardIds":["0636"],"cardNameKo":"모리 란","cardNameJa":"毛利蘭","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"blue"}],"steps":[{"op":"reveal_until_match","from":"deck","saveAs":"search_result","match":{"allOf":[{"field":"level","operator":"greater_than_or_equal","value":7},{"field":"card_name","operator":"name_matches","value":"工藤新一"}]},"includeMatchingCard":true,"publicReveal":true,"oneByOne":true,"awaitActorAcknowledgement":true,"whenNoMatch":"shuffle_all_back"},{"op":"move_cards","from":"search_result.matched","to":"hand","when":{"fact":"vars.search_result.matched_count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"search_result.revealed","selectedVariable":"search_result.matched","to":"deck_bottom","order":"preserve"},{"op":"shuffle_deck"}]},{"effectId":"card-0796-on-enter-partner-red-hand-check","cardIds":["0796"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"opponent.hand.count","operator":"greater_than_or_equal","value":{"fact":"player.hand.count"}}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":8}]},"prompt":"리무브할 상대 레벨 8 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"ruleTextNote":"일본어 원문은 상대 손패 수가 자신의 손패 수 이상(>=)이라고 되어 있어 원문을 우선했습니다."},{"effectId":"card-0796-activated-remove-level7","cardIds":["0796"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.activated_ability","timing":"immediate"},"oncePerTurn":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2},{"fact":"source.status","operator":"in","value":["rested","stunned"]}],"steps":[{"op":"select_cards","from":"field","min":1,"max":1,"optional":false,"filter":{"allOf":[{"field":"controller","operator":"equals","value":"self"},{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"greater_than_or_equal","value":6},{"field":"color","operator":"equals","value":"red"},{"field":"is_active","operator":"equals","value":true}]},"prompt":"비용으로 슬립시킬 레벨 6 이상 적 캐릭터 1장을 선택하세요. 효과 발동 캐릭터 자신도 선택할 수 있습니다.","saveAs":"cost_target"},{"op":"pay_cost","cost":"sleep_selected_character","targetVariable":"cost_target"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"리무브할 상대 레벨 7 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"레벨 7 이하 캐릭터 리무브"},{"effectId":"card-0501-continuous-bond-yamato-ap","cardIds":["0501"],"cardNameKo":"모로후시 타카아키","cardNameJa":"諸伏高明","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.field.has_card_name","operator":"equals","value":"大和敢助"}],"steps":[{"op":"set_continuous_stat","target":"source_character","stat":"ap","amount":2000,"modifierId":"bond-yamato-ap","duration":"while_condition_true"}]},{"effectId":"card-0501-continuous-nagano-police-charge","cardIds":["0501"],"cardNameKo":"모로후시 타카아키","cardNameJa":"諸伏高明","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"player.remove_area.count_matching_trait","operator":"greater_than_or_equal","value":2,"trait":"長野県警","cardType":"character"}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","modifierId":"nagano-police-charge","duration":"while_condition_true"}]},{"effectId":"card-0264-on-enter-attach-detective-boys","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":5,"optional":true,"uniqueBy":"card_name","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"trait","operator":"has_trait","value":"少年探偵団"}]},"prompt":"이 카드 아래에 겹칠, 카드명이 서로 다른 소년탐정단 캐릭터를 최대 5장 선택하세요.","saveAs":"attachments"},{"op":"attach_cards","from":"attachments","to":"source_character"}]},{"effectId":"card-0264-continuous-charge-from-attachments","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","modifierId":"detective-boys-charge","duration":"while_condition_true"}]},{"effectId":"card-0264-action-draw-at-three","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":3}],"steps":[{"op":"draw_cards","destination":"hand","count":1}]},{"effectId":"card-0264-action-evidence-at-five","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":5}],"steps":[{"op":"gain_evidence","count":1}]},{"effectId":"card-1010-first-entry-haya-recover","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"entry.is_first_character_this_turn","operator":"equals","value":true}],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"filter":{"anyOf":[{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6},{"field":"trait","operator":"has_trait","value":"神奈川県警"}]},{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6},{"field":"keyword","operator":"has_keyword","value":"haya"}]}]},"prompt":"패에 추가할 레벨 6 이하 가나가와현 경찰 또는 질풍 보유 캐릭터를 최대 1장 선택하세요.","saveAs":"recovered"},{"op":"move_cards","from":"recovered","to":"hand","when":{"fact":"vars.recovered.count","operator":"greater_than","value":0}},{"op":"mark_keyword_activated","keyword":"haya"}]},{"effectId":"card-1010-partner-yellow-activated-remove","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"character.activated_ability","timing":"immediate"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"},{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"source.is_active","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":9}]},"prompt":"리무브할 상대 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"파트너 황 · 슬립 리무브"},{"effectId":"card-1010-end-turn-ready-haya-users","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"player.turn_ended","timing":"after"},"steps":[{"op":"ready_cards_that_used_keyword","keyword":"haya","turn":"ending_turn","includePartnerArea":true}]}]}$effectdsl$::jsonb)
ON CONFLICT (catalog_id) DO UPDATE
SET schema_version=EXCLUDED.schema_version,definitions=EXCLUDED.definitions,updated_at=now();


CREATE OR REPLACE FUNCTION public.private_card_effect_start_event_v1(
 p_room_id uuid,p_actor_user_id uuid,p_source_user_id uuid,p_source_card jsonb,
 p_trigger_event text,p_context jsonb DEFAULT '{}'::jsonb,p_only_effect_id text DEFAULT NULL,p_require_match boolean DEFAULT false
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_catalog jsonb; v_def jsonb; v_queue jsonb:='[]'::jsonb; v_context jsonb;
 v_turn integer; v_existing jsonb; v_used jsonb; v_effect_id text;
BEGIN
 IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   IF p_require_match THEN RAISE EXCEPTION '다른 카드 효과가 아직 처리 중입니다.'; END IF;
   RETURN false;
 END IF;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
 v_context:=coalesce(p_context,'{}'::jsonb)||jsonb_build_object('source_card',coalesce(p_source_card,'{}'::jsonb),'turn_number',v_turn);
 FOR v_def IN
   SELECT d.value
   FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
   WHERE d.value->'trigger'->>'event'=p_trigger_event
     AND coalesce((d.value->>'continuous')::boolean,false)=false
     AND (p_only_effect_id IS NULL OR d.value->>'effectId'=p_only_effect_id)
     AND public.private_card_effect_matches_id_v1(coalesce(p_source_card,'{}'::jsonb),coalesce(d.value->'cardIds','[]'::jsonb))
   ORDER BY d.ordinality
 LOOP
   IF NOT public.private_card_effect_conditions_match_v1(p_room_id,p_actor_user_id,p_source_user_id,
     p_source_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)) THEN
     CONTINUE;
   END IF;
   v_effect_id:=v_def->>'effectId';
   IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
     v_existing:=public.private_card_effect_get_card_v1(p_room_id,p_source_user_id,p_source_card->>'instance_id');
     v_used:=coalesce(v_existing->'dsl_effect_uses','[]'::jsonb);
     IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
       WHERE u.value->>'effect_id'=v_effect_id AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN
       CONTINUE;
     END IF;
     IF v_existing IS NULL THEN RAISE EXCEPTION '턴당 1회 효과의 원본 카드를 찾을 수 없습니다.'; END IF;
     v_used:=v_used||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'turn_number',v_turn));
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,p_source_user_id,p_source_card->>'instance_id',jsonb_build_object('dsl_effect_uses',v_used));
   END IF;
   v_queue:=v_queue||jsonb_build_array(v_def);
 END LOOP;
 IF jsonb_array_length(v_queue)=0 THEN
   IF p_require_match THEN RAISE EXCEPTION '이 카드의 효과 조건이 충족되지 않았거나 이번 턴에 이미 사용했습니다.'; END IF;
   RETURN false;
 END IF;
 INSERT INTO public.private_card_effect_runs_v1(
   room_id,actor_user_id,source_user_id,source_instance_id,trigger_event,effect_queue,
   effect_index,step_index,variables,context,waiting,created_at,updated_at
 ) VALUES (
   p_room_id,p_actor_user_id,p_source_user_id,coalesce(p_source_card->>'instance_id',''),p_trigger_event,
   v_queue,0,0,'{}'::jsonb,v_context,NULL,now(),now()
 );
 PERFORM public.private_card_effect_run_v1(p_room_id);
 RETURN true;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_continue_v1(p_room_id uuid,p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_run public.private_card_effect_runs_v1%rowtype;
 v_wait jsonb; v_pending jsonb; v_ids jsonb; v_selected jsonb:='[]'::jsonb; v_item jsonb;
 v_id text; v_save text; v_min integer; v_max integer; v_count integer; v_options jsonb;
 v_choice text; v_vars jsonb; v_ordered jsonb; v_cards jsonb; v_index integer; v_next jsonb;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_run.waiting IS NULL THEN RAISE EXCEPTION '계속 처리할 카드 효과가 없습니다.'; END IF;
 v_wait:=v_run.waiting;
 SELECT pending_action INTO v_pending FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF coalesce(v_wait->>'chooser_user_id','')<>v_user::text THEN RAISE EXCEPTION '현재 카드 효과 선택 차례가 아닙니다.'; END IF;
 v_vars:=coalesce(v_run.variables,'{}'::jsonb);

 IF v_wait->>'kind'='selection' THEN
   v_ids:=coalesce(p_payload->'selected_instance_ids','[]'::jsonb);
   IF jsonb_typeof(v_ids)<>'array' THEN RAISE EXCEPTION '선택 카드 목록 형식이 올바르지 않습니다.'; END IF;
   v_count:=jsonb_array_length(v_ids); v_min:=coalesce((v_wait->>'min')::integer,0); v_max:=coalesce((v_wait->>'max')::integer,1);
   IF v_count<v_min OR v_count>v_max THEN RAISE EXCEPTION '선택 장수가 허용 범위를 벗어났습니다. (%~%장)',v_min,v_max; END IF;
   IF (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_ids))<>v_count THEN RAISE EXCEPTION '같은 카드를 중복 선택할 수 없습니다.'; END IF;
   v_options:=coalesce(v_wait->'options','[]'::jsonb);
   FOR v_id IN SELECT value FROM jsonb_array_elements_text(v_ids) LOOP
     SELECT value INTO v_item FROM jsonb_array_elements(v_options) WHERE value->>'instance_id'=v_id LIMIT 1;
     IF v_item IS NULL THEN RAISE EXCEPTION '허용된 후보 목록에 없는 카드가 포함되어 있습니다.'; END IF;
     v_selected:=v_selected||jsonb_build_array(v_item);
   END LOOP;
   IF v_wait->>'unique_by'='card_name' AND (
      SELECT count(DISTINCT lower(public.private_card_effect_name_v1(coalesce(value->'card',value))))
      FROM jsonb_array_elements(v_selected)
   )<>jsonb_array_length(v_selected) THEN
     RAISE EXCEPTION '카드명이 서로 다른 캐릭터만 선택할 수 있습니다.';
   END IF;
   v_save:=v_wait->>'save_as';
   v_vars:=jsonb_set(v_vars,ARRAY[v_save],v_selected,true);
   UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='order' THEN
   v_ids:=coalesce(p_payload->'selected_instance_ids','[]'::jsonb);
   v_options:=coalesce(v_wait->'options','[]'::jsonb);
   v_count:=jsonb_array_length(v_ids);
   IF v_count<>jsonb_array_length(v_options) THEN RAISE EXCEPTION '덱 아래 카드의 순서를 정하려면 각 카드를 정확히 한 번 선택해야 합니다.'; END IF;
   IF (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_ids))<>v_count THEN RAISE EXCEPTION '덱 아래 순서에 중복 카드가 있습니다.'; END IF;
   FOR v_id IN SELECT value FROM jsonb_array_elements_text(v_ids) LOOP
     SELECT value INTO v_item FROM jsonb_array_elements(v_options) WHERE value->>'instance_id'=v_id LIMIT 1;
     IF v_item IS NULL THEN RAISE EXCEPTION '허용된 후보 목록에 없는 카드가 포함되어 있습니다.'; END IF;
     v_ordered:=coalesce(v_ordered,'[]'::jsonb)||jsonb_build_array(v_item);
   END LOOP;
   v_save:=coalesce(v_wait->>'save_as','__ordered_unselected');
   v_vars:=jsonb_set(v_vars,ARRAY[v_save],coalesce(v_ordered,'[]'::jsonb),true);
   UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='ack' THEN
   IF coalesce(p_payload->>'decision','acknowledge')<>'acknowledge' THEN RAISE EXCEPTION '공개 확인을 완료해 주세요.'; END IF;
   UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='sequence' THEN
   v_cards:=coalesce(v_wait->'cards','[]'::jsonb); v_index:=coalesce((v_wait->>'index')::integer,0)+1;
   IF v_index<jsonb_array_length(v_cards) THEN
     v_next:=v_cards->v_index;
     v_wait:=jsonb_set(v_wait,'{index}',to_jsonb(v_index),true);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_wait,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=jsonb_set(
       jsonb_set(coalesce(pending_action,'{}'::jsonb),'{revealed_card}',coalesce(v_next->'card',v_next),true),
       '{revealed_count}',to_jsonb(v_index+1),true
     ),state_version=state_version+1,last_action_label='카드 효과: 다음 카드를 공개했습니다.' WHERE room_id=p_room_id;
     RETURN;
   ELSE
     UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;
   END IF;

 ELSIF v_wait->>'kind'='reaction' THEN
   v_choice:=coalesce(p_payload->>'choice','');
   IF NOT (coalesce(v_wait->'choices','[]'::jsonb) @> jsonb_build_array(v_choice)) THEN RAISE EXCEPTION '허용되지 않은 반응 선택입니다.'; END IF;
   v_vars:=jsonb_set(v_vars,ARRAY[v_wait->>'save_as'],to_jsonb(v_choice),true);
   UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSE
   RAISE EXCEPTION '지원하지 않는 카드 효과 대기 단계입니다.';
 END IF;
 UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,last_action_label='카드 효과 응답을 처리했습니다.' WHERE room_id=p_room_id AND pending_action->>'type' LIKE 'card_effect_%';
 PERFORM public.private_card_effect_run_v1(p_room_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_private_card_effect_options_v1(p_room_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_user uuid:=auth.uid(); v_run public.private_card_effect_runs_v1%rowtype;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;
 IF NOT FOUND OR v_run.waiting IS NULL THEN RETURN jsonb_build_object('options','[]'::jsonb); END IF;
 IF coalesce(v_run.waiting->>'chooser_user_id','')<>v_user::text THEN
   RAISE EXCEPTION '카드 효과의 선택 후보는 지정된 선택자만 볼 수 있습니다.';
 END IF;
 RETURN jsonb_build_object('options',coalesce(v_run.waiting->'options','[]'::jsonb),
   'display_options',coalesce(v_run.waiting->'display_options','[]'::jsonb),
   'kind',v_run.waiting->>'kind','prompt',v_run.waiting->>'prompt');
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_recalculate_continuous_v1(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_catalog jsonb; v_board public.room_player_turn_boards%rowtype; v_card jsonb;
 v_def jsonb; v_step jsonb; v_ap numeric; v_old_ap numeric; v_keywords jsonb;
 v_context jsonb:='{}'::jsonb; v_vars jsonb:='{}'::jsonb; v_owner uuid; v_id text;
BEGIN
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 FOR v_board IN SELECT * FROM public.room_player_turn_boards WHERE room_id=p_room_id FOR UPDATE LOOP
   v_owner:=v_board.user_id;
   FOR v_card IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) LOOP
     IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
       WHERE coalesce((d.value->>'continuous')::boolean,false)
         AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))) THEN CONTINUE; END IF;
     v_ap:=0; v_keywords:='[]'::jsonb;
     FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) WHERE coalesce((value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb)) LOOP
       IF NOT public.private_card_effect_conditions_match_v1(p_room_id,v_owner,v_owner,v_card,v_context,v_vars,coalesce(v_def->'conditions','[]'::jsonb)) THEN CONTINUE; END IF;
       FOR v_step IN SELECT value FROM jsonb_array_elements(coalesce(v_def->'steps','[]'::jsonb)) LOOP
         IF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='ap' THEN
           v_ap:=v_ap+coalesce((v_step->>'amount')::numeric,0);
         ELSIF v_step->>'op'='set_continuous_keyword' THEN
           v_keywords:=v_keywords||jsonb_build_array(jsonb_build_object('effect_id',v_def->>'effectId','keyword',v_step->>'keyword'));
         END IF;
       END LOOP;
     END LOOP;
     v_old_ap:=coalesce(nullif(v_card->>'dsl_ap_bonus','')::numeric,0);
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_owner,v_card->>'instance_id',
       jsonb_build_object('ap_bonus',coalesce(nullif(v_card->>'ap_bonus','')::numeric,0)-v_old_ap+v_ap,
         'dsl_ap_bonus',v_ap,'dsl_continuous_keywords',v_keywords));
   END LOOP;
   v_card:=v_board.partner_mr_card;
   IF v_card IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
       WHERE coalesce((d.value->>'continuous')::boolean,false)
         AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))) THEN
     v_ap:=0; v_keywords:='[]'::jsonb;
     FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) WHERE coalesce((value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb)) LOOP
       IF NOT public.private_card_effect_conditions_match_v1(p_room_id,v_owner,v_owner,v_card,v_context,v_vars,coalesce(v_def->'conditions','[]'::jsonb)) THEN CONTINUE; END IF;
       FOR v_step IN SELECT value FROM jsonb_array_elements(coalesce(v_def->'steps','[]'::jsonb)) LOOP
         IF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='ap' THEN v_ap:=v_ap+coalesce((v_step->>'amount')::numeric,0);
         ELSIF v_step->>'op'='set_continuous_keyword' THEN
           v_keywords:=v_keywords||jsonb_build_array(jsonb_build_object('effect_id',v_def->>'effectId','keyword',v_step->>'keyword'));
         END IF;
       END LOOP;
     END LOOP;
     v_old_ap:=coalesce(nullif(v_card->>'dsl_ap_bonus','')::numeric,0);
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_owner,v_card->>'instance_id',
       jsonb_build_object('ap_bonus',coalesce(nullif(v_card->>'ap_bonus','')::numeric,0)-v_old_ap+v_ap,
         'dsl_ap_bonus',v_ap,'dsl_continuous_keywords',v_keywords));
   END IF;
 END LOOP;
END
$function$;


CREATE OR REPLACE FUNCTION public.get_private_card_effect_activations_v1(p_room_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_catalog jsonb; v_board public.room_player_turn_boards%rowtype;
 v_card jsonb; v_def jsonb; v_used jsonb; v_turn integer; v_items jsonb:='[]'::jsonb;
 v_label text; v_context jsonb:='{}'::jsonb;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
 IF NOT FOUND THEN RAISE EXCEPTION '자신의 보드를 찾을 수 없습니다.'; END IF;
 IF EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    OR EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND (game_over OR phase<>'playing' OR current_turn_user_id<>v_user)) THEN
   RETURN jsonb_build_object('activations','[]'::jsonb);
 END IF;
 FOR v_card IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) LOOP
   FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='character.activated_ability'
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb))
       AND coalesce((value->>'continuous')::boolean,false)=false
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     IF NOT public.private_card_effect_conditions_match_v1(p_room_id,v_user,v_user,v_card,v_context,'{}'::jsonb,
       coalesce(v_def->'conditions','[]'::jsonb)) THEN CONTINUE; END IF;
     v_label:=coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과');
     v_items:=v_items||jsonb_build_array(jsonb_build_object(
       'source_instance_id',v_card->>'instance_id',
       'source_card_key',v_card->>'key',
       'source_name',public.private_card_effect_name_v1(v_card),
       'effect_id',v_def->>'effectId',
       'label',v_label
     ));
   END LOOP;
 END LOOP;
 RETURN jsonb_build_object('activations',v_items);
END
$function$;

REVOKE ALL ON FUNCTION public.get_private_card_effect_activations_v1(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_private_card_effect_activations_v1(uuid) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_private_card_effect_options_for_ai_v1(p_room_id uuid,p_ai_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_run public.private_card_effect_runs_v1%rowtype; v_battle public.private_ai_battles%rowtype;
BEGIN
 SELECT * INTO v_battle FROM public.private_ai_battles WHERE room_id=p_room_id;
 IF NOT FOUND OR v_battle.ai_user_id IS DISTINCT FROM p_ai_user_id THEN
   RAISE EXCEPTION 'AI 대전에서 효과 선택 권한을 확인할 수 없습니다.';
 END IF;
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;
 IF NOT FOUND OR v_run.waiting IS NULL OR coalesce(v_run.waiting->>'chooser_user_id','')<>p_ai_user_id::text THEN
   RAISE EXCEPTION 'AI가 처리할 카드 효과 선택이 없습니다.';
 END IF;
 RETURN jsonb_build_object('options',coalesce(v_run.waiting->'options','[]'::jsonb),
   'kind',v_run.waiting->>'kind','prompt',v_run.waiting->>'prompt');
END
$function$;
REVOKE ALL ON FUNCTION public.get_private_card_effect_options_for_ai_v1(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_private_card_effect_options_for_ai_v1(uuid,uuid) TO service_role;

DO $rename$
BEGIN
 IF to_regprocedure('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)') IS NULL
    AND to_regprocedure('public.perform_private_turn_action_v2(uuid,text,jsonb)') IS NOT NULL THEN
   ALTER FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) RENAME TO perform_private_turn_action_v2_legacy;
 END IF;
END
$rename$;

CREATE OR REPLACE FUNCTION public.perform_private_turn_action_v2(p_room_id uuid,p_action text,p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_match public.room_match_states%rowtype; v_before_match public.room_match_states%rowtype;
 v_before_boards jsonb; v_before_board jsonb; v_new_board public.room_player_turn_boards%rowtype;
 v_before_pending jsonb; v_result jsonb; v_source_card jsonb; v_old_card jsonb; v_new_card jsonb;
 v_owner uuid; v_instance_id text; v_first_entry boolean; v_turn integer; v_old_field jsonb;
 v_old_board jsonb; v_old_entry jsonb; v_current_field jsonb; v_current_remove jsonb; v_removed boolean;
 v_before_base_character_played boolean:=false; v_first_entry_already boolean:=false;
 v_pending_actor uuid; v_context jsonb; v_event_source_user uuid;
 v_old_action text:=p_action;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;

 IF p_action='card_effect_continue' THEN
   PERFORM public.private_card_effect_continue_v1(p_room_id,coalesce(p_payload,'{}'::jsonb));
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='activate_card_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 효과를 발동할 수 있습니다.'; END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION '자신의 턴에만 이 능력을 발동할 수 있습니다.'; END IF;
   IF v_match.turn_step IS DISTINCT FROM 'main' THEN RAISE EXCEPTION '파일 배치가 끝난 뒤 메인 단계에서 능력을 발동할 수 있습니다.'; END IF;
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1 FOR UPDATE;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 캐릭터를 찾을 수 없습니다.'; END IF;
   PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
     'character.activated_ability',jsonb_build_object('turn_number',v_match.turn_number),
     p_payload->>'effect_id',true);
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 SELECT * INTO v_before_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_before_match.phase<>'playing' OR v_before_match.game_over THEN
   RAISE EXCEPTION '진행 중인 게임이 아닙니다.';
 END IF;
 v_before_pending:=v_before_match.pending_action;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',b.user_id,'field_cards',coalesce(b.field_cards,'[]'::jsonb),'partner_mr_card',b.partner_mr_card)
   ORDER BY b.seat),'[]'::jsonb) INTO v_before_boards
 FROM public.room_player_turn_boards b WHERE b.room_id=p_room_id;
 v_turn:=v_before_match.turn_number;
 SELECT coalesce(base_character_played_this_turn,false), first_character_entered_this_turn IS NOT NULL
   INTO v_before_base_character_played, v_first_entry_already
   FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;

 v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));

 IF p_action='begin_turn' THEN
   UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=NULL, updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
 END IF;

 IF p_action='play_character' THEN
   v_instance_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
   IF v_source_card IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     SELECT value INTO v_before_board FROM jsonb_array_elements(v_before_boards) WHERE value->>'user_id'=v_user::text LIMIT 1;
     v_old_field:=coalesce(v_before_board->'field_cards','[]'::jsonb);
     v_first_entry:=NOT v_first_entry_already;
     IF v_first_entry THEN
       UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=v_instance_id,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_user AND first_character_entered_this_turn IS NULL;
     END IF;
     v_context:=jsonb_build_object('entry',jsonb_build_object(
       'method','manual','is_first_character_this_turn',v_first_entry,'source',v_source_card),
       'turn_number',v_turn);
     PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
       'character.entered_field',v_context,NULL,false);
   END IF;
 END IF;

 IF p_action IN ('investigate','attack_character','attack_evidence','declare_contact') THEN
   IF NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
      AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     v_instance_id:=coalesce(nullif(p_payload->>'instance_id',''),nullif(p_payload->>'attacker_instance_id',''));
     IF v_instance_id IS NOT NULL THEN
       SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
         CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
         WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
       IF v_source_card IS NOT NULL THEN
         PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
           'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
       END IF;
     END IF;
   END IF;
 END IF;

 IF p_action IN ('pass_mislead','resolve_mislead') AND v_before_pending->>'type'='mislead_response'
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'investigator_user_id','')::uuid;
   v_instance_id:=v_before_pending->>'investigator_instance_id';
   IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_event_source_user,v_event_source_user,v_source_card,
         'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
     END IF;
   END IF;
 END IF;

 IF p_action IN ('contact_pass_cutin','contact_use_cutin','contact_use_disguise','resolve_character_contact')
    AND v_before_pending IS NOT NULL
    AND v_before_pending->>'type' IN ('character_contact','character_contact_guard')
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
   v_instance_id:=coalesce(v_before_pending->>'attacker_instance_id',v_before_pending->>'attacker_id');
   IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_event_source_user,v_event_source_user,v_source_card,
         'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
     END IF;
   END IF;
 END IF;

 IF p_action='end_turn' THEN
   UPDATE public.room_player_turn_boards b
    SET field_cards=coalesce((SELECT jsonb_agg(
       e.value||jsonb_build_object('ap_bonus',0,'dsl_ap_bonus',0,
         'dsl_keywords',coalesce((SELECT jsonb_agg(k.value) FROM jsonb_array_elements(coalesce(e.value->'dsl_keywords','[]'::jsonb)) k(value)
          WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>v_turn),'[]'::jsonb))
       ORDER BY e.ordinality)
      FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
       partner_mr_card=CASE WHEN b.partner_mr_card IS NULL THEN NULL ELSE b.partner_mr_card||jsonb_build_object('ap_bonus',0,'dsl_ap_bonus',0,
         'dsl_keywords',coalesce((SELECT jsonb_agg(k.value) FROM jsonb_array_elements(coalesce(b.partner_mr_card->'dsl_keywords','[]'::jsonb)) k(value)
          WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>v_turn),'[]'::jsonb)) END,
       updated_at=now()
    WHERE b.room_id=p_room_id AND b.user_id=v_user;

   IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     SELECT field_cards,partner_mr_card INTO v_current_field,v_old_card FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
     FOR v_new_card IN SELECT value FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) UNION ALL
       SELECT v_old_card WHERE v_old_card IS NOT NULL LOOP
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_new_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn),NULL,false);
       IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
     END LOOP;
   END IF;
 END IF;

 -- Detect field cards that actually entered an owner's remove area during this action.
 IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL) THEN
   FOR v_old_board IN SELECT value FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb)) LOOP
     v_owner:=nullif(v_old_board->>'user_id','')::uuid;
     FOR v_old_card IN SELECT value FROM jsonb_array_elements(coalesce(v_old_board->'field_cards','[]'::jsonb)) LOOP
       v_instance_id:=v_old_card->>'instance_id';
       IF v_instance_id IS NULL OR v_instance_id='' THEN CONTINUE; END IF;
       SELECT coalesce(field_cards,'[]'::jsonb) INTO v_current_field FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_owner;
       SELECT coalesce(remove_cards,'[]'::jsonb) INTO v_current_remove FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner;
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_instance_id)
         AND (
           EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_instance_id)
           OR EXISTS(SELECT 1 FROM public.room_player_turn_boards pb WHERE pb.room_id=p_room_id AND pb.user_id=v_owner AND pb.partner_mr_card->>'instance_id'=v_instance_id)
         ) THEN
         PERFORM public.private_card_effect_start_event_v1(p_room_id,v_owner,v_owner,v_old_card,
           'character.removed_from_field',jsonb_build_object('turn_number',v_turn,'removed_on_turn_user_id',v_before_match.current_turn_user_id),NULL,false);
         IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
       END IF;
     END LOOP;
     IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
   END LOOP;
 END IF;

 PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
 RETURN public.get_private_turn_state_v2(p_room_id);
END
$function$;



DO $patch_ai$
DECLARE v_definition text;
BEGIN
  IF to_regprocedure('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)') IS NULL THEN RETURN; END IF;
  v_definition := pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure);
  IF position('card_effect_continue' in v_definition)=0 THEN
    IF position('shuffle_deck' in v_definition)=0 THEN
      RAISE EXCEPTION 'AI action allow-list tail not found; refusing partial card effect integration';
    END IF;
    v_definition := replace(v_definition, '''shuffle_deck''', '''shuffle_deck'',''card_effect_continue''');
    IF position('chooser_user_id' in v_definition)=0 THEN
      v_definition := replace(v_definition,
        'and coalesce(v_match.pending_action ->> ''initiator_user_id'', '''') <> v_battle.ai_user_id::text then',
        'and coalesce(v_match.pending_action ->> ''initiator_user_id'', '''') <> v_battle.ai_user_id::text and coalesce(v_match.pending_action ->> ''chooser_user_id'', '''') <> v_battle.ai_user_id::text then');
    END IF;
  END IF;
  EXECUTE v_definition;
END
$patch_ai$;

REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2_legacy(uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_continue_v1(uuid,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_recalculate_continuous_v1(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_private_card_effect_options_v1(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_private_card_effect_options_v1(uuid) TO authenticated;
