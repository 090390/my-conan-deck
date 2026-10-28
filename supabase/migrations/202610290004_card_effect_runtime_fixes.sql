
ALTER TABLE public.room_player_turn_boards
  ADD COLUMN IF NOT EXISTS first_character_entered_this_turn text;

INSERT INTO public.private_card_effect_catalog_v1(catalog_id,schema_version,definitions)
VALUES ('main',1,$dsl_catalog${"schemaVersion":1,"language":"conan-card-effect-dsl","definitions":[{"effectId":"card-0062-on-enter","cardIds":["0062"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","operator":"less_than","value":4},"includeRemainingDeck":true,"includeRemoveArea":true,"shuffle":true},{"op":"peek_top_cards","count":4,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"filter":{"field":"color","operator":"equals","value":"red"},"prompt":"공개하여 패에 넣을 적 카드를 최대 1장 선택하세요.","saveAs":"selected_red","displayVariable":"seen"},{"op":"reveal_cards","from":"selected_red","to":["opponent"],"awaitAcknowledgement":true,"when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"selected_red","to":"hand","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_deck_bottom","from":"seen","selectedVariable":"selected_red","order":"player_choice"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"prompt":"패에 추가한 경우, 리무브할 손패 1장을 선택하세요.","saveAs":"hand_to_remove","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"hand_to_remove","to":"remove_area","when":{"fact":"vars.selected_red.count","operator":"greater_than","value":0}}]},{"effectId":"card-0110-on-enter-partner-green","cardIds":["0110"],"cardNameKo":"오키타 소지","cardNameJa":"沖田総司","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"green"}],"steps":[{"op":"grant_keyword","target":"source_character","keyword":"charge","displayNameKo":"돌격","duration":"turn_end"}]},{"effectId":"card-0011-on-enter-from-level3-effect","cardIds":["0011"],"cardNameKo":"츠부라야 미츠히코","cardNameJa":"円谷光彦","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"entry.method","operator":"in","value":["character_ability","event_effect"]},{"fact":"entry.source.card_type","operator":"in","value":["character","event"]},{"fact":"entry.source.level","operator":"greater_than_or_equal","value":3}],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"filter":{"field":"card_type","operator":"equals","value":"character"},"targetController":"any","prompt":"턴 종료 시까지 AP를 2000 올릴 캐릭터를 최대 1장 선택하세요.","saveAs":"ap_target"},{"op":"modify_stat","target":"ap_target","stat":"ap","amount":2000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0223-on-enter-ap-minus-1000","cardIds":["0223"],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"filter":{"field":"card_type","operator":"equals","value":"character"},"targetController":"any","prompt":"턴 종료 시까지 AP를 1000 낮출 캐릭터를 최대 1장 선택하세요.","saveAs":"ap_target"},{"op":"modify_stat","target":"ap_target","stat":"ap","amount":-1000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}]},{"effectId":"card-0223-mislead-passive","cardIds":["0223"],"trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"set_mislead_value","target":"source_character","value":1,"duration":"while_in_field"}],"cardNameKo":"조디 스털링","cardNameJa":"ジョディ・スターリング"},{"effectId":"card-1013-activated-remove-low-ap","cardIds":["1013"],"cardNameKo":"하기와라 켄지","cardNameJa":"萩原研二","trigger":{"event":"character.activated_ability","timing":"immediate"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"source.is_active","operator":"equals","value":true},{"fact":"player.field.has_keyword.haya","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":8000}]},"prompt":"리무브할 상대 캐릭터(AP 8000 이하)를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"질풍 조건부 슬립·리무브"},{"effectId":"card-1013-opponent-turn-field-remove","cardIds":["1013"],"cardNameKo":"하기와라 켄지","cardNameJa":"萩原研二","trigger":{"event":"character.removed_from_field","timing":"after"},"conditions":[{"fact":"turn.is_opponent_turn","operator":"equals","value":true}],"steps":[{"op":"peek_top_cards","count":3,"allowFewer":true,"saveAs":"seen"},{"op":"reveal_cards","from":"seen","to":["all"],"awaitAcknowledgement":true},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"keyword","operator":"has_keyword","value":"haya"}]},"prompt":"공개해 패에 넣을 질풍/돌격 보유 캐릭터를 최대 1장 선택하세요.","saveAs":"chosen"},{"op":"move_cards","from":"chosen","to":"hand","when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"seen","selectedVariable":"chosen","to":"remove_area","order":"preserve"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"prompt":"레벨 8 이상 카드를 패에 추가했다면, 리무브할 손패 1장을 선택하세요.","saveAs":"hand_to_remove","when":{"fact":"vars.chosen.has_level_at_least_8","operator":"equals","value":true}},{"op":"move_cards","from":"hand_to_remove","to":"remove_area","when":{"fact":"vars.chosen.has_level_at_least_8","operator":"equals","value":true}}],"afterResolve":{"note":"선택한 카드가 없으면 손패 이동과 추가 리무브는 건너뜁니다.","removeHandOnlyIfSelectedCardLevelAtLeast":8},"activationLabelKo":"상대 턴 현장 리무브 효과"},{"effectId":"card-0636-on-enter-search-shinichi","cardIds":["0636"],"cardNameKo":"모리 란","cardNameJa":"毛利蘭","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"blue"}],"steps":[{"op":"reveal_until_match","from":"deck","saveAs":"search_result","match":{"allOf":[{"field":"level","operator":"greater_than_or_equal","value":7},{"field":"card_name","operator":"name_matches","value":"工藤新一"}]},"includeMatchingCard":true,"publicReveal":true,"oneByOne":true,"awaitActorAcknowledgement":true,"whenNoMatch":"shuffle_all_back"},{"op":"move_cards","from":"search_result.matched","to":"hand","when":{"fact":"vars.search_result.matched_count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"search_result.revealed","selectedVariable":"search_result.matched","to":"deck_bottom","order":"preserve"},{"op":"shuffle_deck"}]},{"effectId":"card-0796-on-enter-partner-red-hand-check","cardIds":["0796"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"opponent.hand.count","operator":"greater_than_or_equal","value":{"fact":"player.hand.count"}}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":8}]},"prompt":"리무브할 상대 레벨 8 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"ruleTextNote":"일본어 원문은 상대 손패 수가 자신의 손패 수 이상(>=)이라고 되어 있어 원문을 우선했습니다."},{"effectId":"card-0796-activated-remove-level7","cardIds":["0796"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.activated_ability","timing":"immediate"},"oncePerTurn":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2},{"fact":"source.status","operator":"in","value":["rested","stunned"]}],"steps":[{"op":"select_cards","from":"field","min":1,"max":1,"optional":false,"filter":{"allOf":[{"field":"controller","operator":"equals","value":"self"},{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"greater_than_or_equal","value":6},{"field":"color","operator":"equals","value":"red"},{"field":"is_active","operator":"equals","value":true}]},"prompt":"비용으로 슬립시킬 레벨 6 이상 적 캐릭터 1장을 선택하세요. 효과 발동 캐릭터 자신도 선택할 수 있습니다.","saveAs":"cost_target"},{"op":"pay_cost","cost":"sleep_selected_character","targetVariable":"cost_target"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"리무브할 상대 레벨 7 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"레벨 7 이하 캐릭터 리무브"},{"effectId":"card-0501-continuous-bond-yamato-ap","cardIds":["0501"],"cardNameKo":"모로후시 타카아키","cardNameJa":"諸伏高明","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.field.has_card_name","operator":"equals","value":"大和敢助"}],"steps":[{"op":"set_continuous_stat","target":"source_character","stat":"ap","amount":2000,"modifierId":"bond-yamato-ap","duration":"while_condition_true"}]},{"effectId":"card-0501-continuous-nagano-police-charge","cardIds":["0501"],"cardNameKo":"모로후시 타카아키","cardNameJa":"諸伏高明","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"player.remove_area.count_matching_trait","operator":"greater_than_or_equal","value":2,"trait":"長野県警","cardType":"character"}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","modifierId":"nagano-police-charge","duration":"while_condition_true"}]},{"effectId":"card-0264-on-enter-attach-detective-boys","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":5,"optional":true,"uniqueBy":"card_name","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"trait","operator":"has_trait","value":"少年探偵団"}]},"prompt":"이 카드 아래에 겹칠, 카드명이 서로 다른 소년탐정단 캐릭터를 최대 5장 선택하세요.","saveAs":"attachments"},{"op":"attach_cards","from":"attachments","to":"source_character"}]},{"effectId":"card-0264-continuous-charge-from-attachments","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","modifierId":"detective-boys-charge","duration":"while_condition_true"}]},{"effectId":"card-0264-action-draw-at-three","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":3}],"steps":[{"op":"draw_cards","destination":"hand","count":1}]},{"effectId":"card-0264-action-evidence-at-five","cardIds":["0264"],"cardNameKo":"결성 소년탐정단","cardNameJa":"結成 少年探偵団","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"source.under_cards.count","operator":"greater_than_or_equal","value":5}],"steps":[{"op":"gain_evidence","count":1}]},{"effectId":"card-1010-first-entry-haya-recover","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"entry.is_first_character_this_turn","operator":"equals","value":true}],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"filter":{"anyOf":[{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6},{"field":"trait","operator":"has_trait","value":"神奈川県警"}]},{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6},{"field":"keyword","operator":"has_keyword","value":"haya"}]}]},"prompt":"패에 추가할 레벨 6 이하 가나가와현 경찰 또는 질풍 보유 캐릭터를 최대 1장 선택하세요.","saveAs":"recovered"},{"op":"move_cards","from":"recovered","to":"hand","when":{"fact":"vars.recovered.count","operator":"greater_than","value":0}},{"op":"mark_keyword_activated","keyword":"haya"}]},{"effectId":"card-1010-partner-yellow-activated-remove","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"character.activated_ability","timing":"immediate"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"},{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"source.is_active","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":9}]},"prompt":"리무브할 상대 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target"},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"파트너 황 · 슬립 리무브"},{"effectId":"card-1010-end-turn-ready-haya-users","cardIds":["1010"],"cardNameKo":"하기와라 치하야&하기와라 켄지","cardNameJa":"萩原千速&萩原研二","trigger":{"event":"player.turn_ended","timing":"after"},"steps":[{"op":"ready_cards_that_used_keyword","keyword":"haya","turn":"ending_turn","includePartnerArea":true}]}]}$dsl_catalog$::jsonb)
ON CONFLICT (catalog_id) DO UPDATE
SET schema_version=EXCLUDED.schema_version,definitions=EXCLUDED.definitions,updated_at=now();

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



CREATE OR REPLACE FUNCTION public.private_card_effect_run_v1(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_run public.private_card_effect_runs_v1%rowtype;
 v_def jsonb; v_step jsonb; v_op text; v_from text; v_to text; v_save text; v_path text[];
 v_vars jsonb; v_data jsonb; v_options jsonb; v_selected jsonb; v_remaining jsonb; v_ordered jsonb;
 v_item jsonb; v_card jsonb; v_wrapper jsonb; v_current jsonb; v_patch jsonb; v_pending jsonb; v_waiting jsonb;
 v_game public.room_player_game_states%rowtype; v_board public.room_player_turn_boards%rowtype;
 v_match public.room_match_states%rowtype; v_owner uuid; v_source_user uuid; v_target_owner uuid;
 v_i integer; v_j integer; v_n integer; v_examined integer; v_matched boolean; v_found boolean;
 v_ids text[]; v_selected_ids text[]; v_effect_id text; v_turn integer; v_amount integer; v_new_ap numeric;
 v_keyword text; v_deck jsonb; v_seen jsonb; v_match_filter jsonb; v_name text;
BEGIN
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF v_run.waiting IS NOT NULL THEN RETURN; END IF;

 LOOP
   SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND THEN RETURN; END IF;

   IF v_run.effect_index >= jsonb_array_length(coalesce(v_run.effect_queue,'[]'::jsonb)) THEN
     DELETE FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=CASE WHEN pending_action->>'type' LIKE 'card_effect_%' THEN NULL ELSE pending_action END,
           state_version=state_version+1,
           last_action_label='카드 효과 처리가 완료되었습니다.'
       WHERE room_id=p_room_id;
     RETURN;
   END IF;

   v_def:=v_run.effect_queue->v_run.effect_index;
   IF v_run.step_index >= jsonb_array_length(coalesce(v_def->'steps','[]'::jsonb)) THEN
     UPDATE public.private_card_effect_runs_v1
       SET effect_index=effect_index+1, step_index=0, variables='{}'::jsonb, waiting=NULL, updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;
   END IF;

   v_step:=v_def->'steps'->v_run.step_index;
   v_op:=v_step->>'op';
   v_vars:=coalesce(v_run.variables,'{}'::jsonb);
   v_owner:=v_run.actor_user_id;
   v_source_user:=v_run.source_user_id;
   v_effect_id:=v_def->>'effectId';
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;

   IF v_step ? 'when' AND NOT public.private_card_effect_condition_matches_v1(
     p_room_id,v_owner,v_source_user,coalesce(v_run.context->'source_card','{}'::jsonb),
     coalesce(v_run.context,'{}'::jsonb),v_vars,v_step->'when'
   ) THEN
     UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
     CONTINUE;
   END IF;

   IF v_op='refill_deck_from_remove_area' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     IF jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)) < 4 AND coalesce((v_step->>'includeRemoveArea')::boolean,false) THEN
       v_deck:=coalesce(v_game.deck_order,'[]'::jsonb)||coalesce(v_game.remove_cards,'[]'::jsonb);
       SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb) INTO v_data FROM jsonb_array_elements(v_deck) e(value);
       UPDATE public.room_player_game_states SET deck_order=v_data,remove_cards='[]'::jsonb,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET remove_count=0,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
     END IF;

   ELSIF v_op='peek_top_cards' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_n:=least(greatest(0,coalesce((v_step->>'count')::integer,0)),jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)));
     SELECT coalesce(jsonb_agg(jsonb_build_object('instance_id',e.value->>'instance_id','owner_user_id',v_owner,'zone','peek','card',e.value) ORDER BY e.ordinality)
       FILTER(WHERE e.ordinality<=v_n),'[]'::jsonb)
       INTO v_data FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.ordinality>v_n),'[]'::jsonb)
       INTO v_deck FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states SET deck_order=v_deck,updated_at=now() WHERE room_id=p_room_id AND user_id=v_owner;
     UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],v_data,true),
       step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
     CONTINUE;

   ELSIF v_op='select_cards' THEN
     v_from:=v_step->>'from';
     v_options:=public.private_card_effect_get_candidates_v1(
       p_room_id,v_owner,v_source_user,v_from,coalesce(v_step->'filter','{}'::jsonb),
       coalesce(v_step->>'targetController','self'),v_step->>'uniqueBy',v_vars
     );
     v_n:=jsonb_array_length(coalesce(v_options,'[]'::jsonb));
     IF v_n=0 AND coalesce((v_step->>'min')::integer,0)=0 THEN
       UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],'[]'::jsonb,true),
         step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     IF v_n < coalesce((v_step->>'min')::integer,0) THEN
       RAISE EXCEPTION '효과 처리에 필요한 선택 대상이 부족합니다.';
     END IF;
     v_waiting:=jsonb_build_object('kind','selection','save_as',v_step->>'saveAs','options',v_options,
       'min',coalesce((v_step->>'min')::integer,0),'max',coalesce((v_step->>'max')::integer,1),
       'unique_by',v_step->>'uniqueBy','prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'));
     IF nullif(v_step->>'displayVariable','') IS NOT NULL THEN
       v_path:=string_to_array(replace(v_step->>'displayVariable','vars.',''),'.');
       v_waiting:=v_waiting||jsonb_build_object('display_options',coalesce(v_vars #> v_path,'[]'::jsonb));
     END IF;
     v_pending:=jsonb_build_object('type','card_effect_selection','effect_id',v_effect_id,
       'source_instance_id',v_run.source_instance_id,'chooser_user_id',v_owner,
       'prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'),
       'min',coalesce((v_step->>'min')::integer,0),'max',coalesce((v_step->>'max')::integer,1),
       'optional',coalesce((v_step->>'optional')::boolean,false));
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 플레이어의 카드 선택을 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='reveal_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''), 'vars.',''),'.');
     v_data:=v_vars #> v_path;
     SELECT coalesce(jsonb_agg(coalesce(e.value->'card',e.value) ORDER BY e.ordinality),'[]'::jsonb)
       INTO v_selected FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     IF jsonb_array_length(coalesce(v_selected,'[]'::jsonb))=0 THEN
       UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     IF coalesce((v_step->>'awaitAcknowledgement')::boolean,false) IS NOT TRUE THEN
       UPDATE public.room_match_states SET state_version=state_version+1,
         last_action_label='카드 효과: 선택한 카드를 공개했습니다.' WHERE room_id=p_room_id;
       UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     v_target_owner:=v_owner;
     IF coalesce(v_step->'to','[]'::jsonb) @> '["opponent"]'::jsonb THEN
       SELECT user_id INTO v_target_owner FROM public.room_players WHERE room_id=p_room_id AND user_id<>v_owner LIMIT 1;
     END IF;
     v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_target_owner);
     v_pending:=jsonb_build_object('type','card_effect_reveal_ack','effect_id',v_effect_id,'source_instance_id',v_run.source_instance_id,
       'chooser_user_id',v_target_owner,'source_user_id',v_owner,'prompt',CASE WHEN v_target_owner<>v_owner THEN '공개된 카드를 확인한 뒤 확인 완료를 눌러 주세요.' ELSE '카드 공개를 확인하고 효과를 계속 진행하세요.' END,
       'revealed_cards',v_selected);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 카드 공개 확인을 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='move_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''), 'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_to:=coalesce(v_step->>'to','');
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),v_card,v_to,
         CASE WHEN v_to='hand' THEN v_target_owner ELSE v_target_owner END);
     END LOOP;

   ELSIF v_op IN ('move_unselected_to_deck_bottom','move_unselected_to_zone') THEN
     v_from:=v_step->>'from';
     v_path:=string_to_array(replace(coalesce(v_from,''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_path:=string_to_array(replace(coalesce(v_step->>'selectedVariable',''),'vars.',''),'.');
     v_selected:=v_vars #> v_path;
     v_selected_ids:='{}'::text[];
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_selected,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_selected_ids:=array_append(v_selected_ids,coalesce(v_card->>'instance_id',v_item->>'instance_id',''));
     END LOOP;
     v_remaining:='[]'::jsonb;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       IF NOT (coalesce(v_card->>'instance_id',v_item->>'instance_id','')=ANY(v_selected_ids)) THEN
         v_remaining:=v_remaining||jsonb_build_array(v_item);
       END IF;
     END LOOP;
     v_to:=CASE WHEN v_op='move_unselected_to_deck_bottom' THEN 'deck_bottom' ELSE v_step->>'to' END;
     IF coalesce(v_step->>'order','preserve')='player_choice' THEN
       v_ordered:=v_vars->'__ordered_unselected';
       IF v_ordered IS NULL THEN
         IF jsonb_array_length(coalesce(v_remaining,'[]'::jsonb))=0 THEN
           UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
           CONTINUE;
         END IF;
         v_waiting:=jsonb_build_object('kind','order','options',v_remaining,'save_as','__ordered_unselected',
           'chooser_user_id',v_owner,'prompt','덱 아래로 보낼 카드의 순서를 정하세요. (위에서부터 차례대로 선택)');
         v_pending:=jsonb_build_object('type','card_effect_order','effect_id',v_effect_id,'chooser_user_id',v_owner,
           'prompt','덱 아래로 보낼 카드의 순서를 정하세요.','options_count',jsonb_array_length(v_remaining));
         UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
         UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
           last_action_label='카드 효과: 덱 아래 카드 순서를 기다립니다.' WHERE room_id=p_room_id;
         RETURN;
       END IF;
       v_remaining:=v_ordered;
     END IF;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_remaining,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),v_card,v_to,v_target_owner);
     END LOOP;
     IF v_step ? 'selectedVariable' AND v_vars ? '__ordered_unselected' THEN
       v_vars:=v_vars-'__ordered_unselected';
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;

   ELSIF v_op='reveal_until_match' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_data:=coalesce(v_game.deck_order,'[]'::jsonb); v_remaining:='[]'::jsonb; v_examined:=0; v_matched:=false; v_selected:='[]'::jsonb;
     FOR v_item IN SELECT value FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality) ORDER BY ordinality LOOP
       v_examined:=v_examined+1; v_card:=v_item;
       v_wrapper:=jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_owner,'zone','peek','card',v_card);
       v_selected:=v_selected||jsonb_build_array(v_wrapper);
       IF public.private_card_effect_filter_matches_v1(p_room_id,v_card,v_owner,v_source_user,coalesce(v_step->'match','{}'::jsonb)) THEN
         v_matched:=true; EXIT;
       END IF;
     END LOOP;
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.ordinality>v_examined),'[]'::jsonb)
       INTO v_deck FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states SET deck_order=v_deck,updated_at=now() WHERE room_id=p_room_id AND user_id=v_owner;
     v_data:=jsonb_build_object('revealed',v_selected,
       'matched',CASE WHEN v_matched THEN jsonb_build_array(v_selected->(jsonb_array_length(v_selected)-1)) ELSE '[]'::jsonb END,
       'matched_count',CASE WHEN v_matched THEN 1 ELSE 0 END);
     v_vars:=jsonb_set(v_vars,ARRAY[v_step->>'saveAs'],v_data,true);
     IF jsonb_array_length(coalesce(v_selected,'[]'::jsonb))=0 THEN
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     v_waiting:=jsonb_build_object('kind','sequence','cards',v_selected,'index',0,'chooser_user_id',v_owner,'save_as',v_step->>'saveAs');
     v_pending:=jsonb_build_object('type','card_effect_reveal_sequence','effect_id',v_effect_id,'chooser_user_id',v_owner,
       'prompt','덱 위에서 한 장씩 공개합니다. 공개한 카드를 확인한 뒤 다음 카드를 진행하세요.',
       'revealed_card',coalesce(v_selected->0->'card',v_selected->0),'revealed_count',1,
       'stop_after_match',v_matched);
     UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 덱 공개를 진행 중입니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='attach_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF coalesce(v_item->>'zone','')='remove_area' THEN
         UPDATE public.room_player_game_states SET remove_cards=public.private_card_effect_remove_from_array_v1(remove_cards,v_card->>'instance_id'),updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner;
         UPDATE public.room_player_turn_boards SET remove_count=greatest(0,remove_count-1),updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner;
       END IF;
       SELECT public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id) INTO v_current;
       IF v_current IS NULL THEN RAISE EXCEPTION '겹칠 카드의 현장 원본을 찾지 못했습니다.'; END IF;
       v_patch:=jsonb_build_object('stacked_cards',coalesce(v_current->'stacked_cards',v_current->'under_cards','[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,v_patch);
     END LOOP;

   ELSIF v_op='set_mislead_value' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '미스리드 수치를 설정할 현장 카드를 찾지 못했습니다.'; END IF;
     v_amount:=coalesce(nullif(v_step->>'value','')::integer,0);
     IF v_amount<0 OR v_amount>3 THEN RAISE EXCEPTION '미스리드 수치는 0~3 범위여야 합니다.'; END IF;
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,
       jsonb_build_object('mislead_value',v_amount));

   ELSIF v_op='grant_keyword' THEN
     v_target_owner:=v_source_user; v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
     IF v_card IS NULL THEN RAISE EXCEPTION '키워드를 부여할 카드가 현장에 없습니다.'; END IF;
     v_keyword:=coalesce(v_step->>'keyword','');
     v_selected:=coalesce(v_card->'dsl_keywords','[]'::jsonb);
     IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_selected) x(value) WHERE x.value->>'effect_id'=v_effect_id AND x.value->>'keyword'=v_keyword) THEN
       v_selected:=v_selected||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'keyword',v_keyword,
         'expires_turn_number',(SELECT turn_number FROM public.room_match_states WHERE room_id=p_room_id)));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,jsonb_build_object('dsl_keywords',v_selected));
     END IF;

   ELSIF v_op='modify_stat' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path; v_amount:=coalesce((v_step->>'amount')::integer,0);
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NOT NULL AND v_step->>'stat'='ap' THEN
         v_new_ap:=coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)+v_amount;
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('ap_bonus',v_new_ap));
       END IF;
     END LOOP;

   ELSIF v_op='offer_reaction' THEN
     v_waiting:=jsonb_build_object('kind','reaction','save_as',v_step->>'saveAs',
       'choices',coalesce(v_step->'choices','[]'::jsonb),'chooser_user_id',v_owner);
     v_pending:=jsonb_build_object('type','card_effect_reaction','effect_id',v_effect_id,
       'chooser_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','효과를 발동할까요?'),
       'choices',coalesce(v_step->'choices','[]'::jsonb),'source_instance_id',v_run.source_instance_id);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 반응 여부를 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='pay_cost' THEN
     IF v_step->>'cost'='sleep_source_character' THEN
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
       IF v_current IS NULL OR NOT public.private_card_effect_is_active_v1(v_current) THEN
         RAISE EXCEPTION '비용으로 슬립시킬 효과 발동 카드가 액티브 상태가 아닙니다.';
       END IF;
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,jsonb_build_object('rested',true,'status','rested'));
     ELSIF v_step->>'cost'='sleep_selected_character' THEN
       v_path:=string_to_array(replace(coalesce(v_step->>'targetVariable',''),'vars.',''),'.');
       v_data:=v_vars #> v_path;
       v_item:=v_data->0; v_card:=coalesce(v_item->'card',v_item);
       IF v_item IS NULL OR v_card->>'instance_id' IS NULL THEN RAISE EXCEPTION '슬립 비용으로 사용할 캐릭터를 선택해 주세요.'; END IF;
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NULL OR NOT public.private_card_effect_is_active_v1(v_current) THEN RAISE EXCEPTION '슬립 비용 캐릭터는 액티브 상태여야 합니다.'; END IF;
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('rested',true,'status','rested'));
     ELSE
       RAISE EXCEPTION '지원하지 않는 카드 효과 비용입니다.';
     END IF;

   ELSIF v_op='draw_cards' THEN
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,coalesce(v_step->>'destination','hand'));
     END LOOP;

   ELSIF v_op='gain_evidence' THEN
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,'evidence');
     END LOOP;

   ELSIF v_op='mark_keyword_activated' THEN
     SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
     v_turn:=coalesce(nullif(v_run.context->>'turn_number','')::integer,v_turn);
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,
       jsonb_build_object('haya_activated_turn_number',v_turn));

   ELSIF v_op='ready_cards_that_used_keyword' THEN
     v_turn:=coalesce(nullif(v_run.context->>'ending_turn_number','')::integer,
       nullif(v_run.context->>'turn_number','')::integer,v_match.turn_number);
     UPDATE public.room_player_turn_boards b
       SET field_cards=coalesce((SELECT jsonb_agg(
         CASE WHEN coalesce(nullif(e.value->>'haya_activated_turn_number','')::integer,-1)=v_turn
           THEN e.value||jsonb_build_object('rested',false,'status','active')
           ELSE e.value END ORDER BY e.ordinality)
         FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
         partner_mr_card=CASE WHEN coalesce(nullif(b.partner_mr_card->>'haya_activated_turn_number','')::integer,-1)=v_turn
           THEN b.partner_mr_card||jsonb_build_object('rested',false,'status','active') ELSE b.partner_mr_card END,
         updated_at=now()
       WHERE b.room_id=p_room_id AND b.user_id=v_source_user;

   ELSIF v_op='shuffle_deck' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb) INTO v_data
       FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) e(value);
     UPDATE public.room_player_game_states SET deck_order=v_data,updated_at=now() WHERE room_id=p_room_id AND user_id=v_owner;

   ELSIF v_op IN ('set_continuous_stat','set_continuous_keyword') THEN
     NULL;

   ELSIF v_op='modify_lp' THEN
     RAISE EXCEPTION '현재 게임 상태에 LP 수치 저장 필드가 없어 modify_lp 명령을 실행할 수 없습니다. 기존 미스리드 규칙을 사용해 주세요.';

   ELSE
     RAISE EXCEPTION '허용되지 않은 카드 효과 실행 명령: %',coalesce(v_op,'(없음)');
   END IF;

   UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
 END LOOP;
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



