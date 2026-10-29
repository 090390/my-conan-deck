-- Extend common DSL context and timing support without promoting unapproved card definitions.
ALTER TABLE public.room_player_decks
  ADD COLUMN IF NOT EXISTS event_has_non_blue_color boolean;

CREATE OR REPLACE FUNCTION public.set_private_room_event_has_non_blue_color_v1(
  p_room_id uuid,
  p_has_non_blue_color boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF p_has_non_blue_color IS NULL THEN RAISE EXCEPTION '사건 색상 판정값이 필요합니다.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players rp
    WHERE rp.room_id=p_room_id AND rp.user_id=v_user
  ) THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  UPDATE public.room_player_decks
    SET event_has_non_blue_color=p_has_non_blue_color
    WHERE room_id=p_room_id AND user_id=v_user;
  IF NOT FOUND THEN RAISE EXCEPTION '제출된 덱에서 사건 카드를 찾을 수 없습니다.'; END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.set_private_room_event_has_non_blue_color_v1(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_private_room_event_has_non_blue_color_v1(uuid,boolean) TO authenticated;

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
 IF p_fact='player.file.count' THEN RETURN to_jsonb(coalesce(v_board.file_count,0)); END IF;
 IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_match.case_phase,v_board.case_phase,'incident'));
 END IF;
 IF p_fact='player.event.has_non_blue_color' THEN
   SELECT d.event_has_non_blue_color INTO v_bool
   FROM public.room_player_decks d
   WHERE d.room_id=p_room_id AND d.user_id=p_actor;
   RETURN coalesce(to_jsonb(v_bool),'null'::jsonb);
 END IF;
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
 v_actual jsonb; v_expected jsonb; v_bool boolean;
 v_board public.room_player_turn_boards%rowtype; v_game public.room_player_game_states%rowtype;
 v_count integer; v_trait text; v_typ text;
BEGIN
 IF p_condition IS NULL OR jsonb_typeof(p_condition)<>'object' THEN RETURN false; END IF;
 v_expected:=p_condition->'value';
 IF jsonb_typeof(v_expected)='object' AND v_expected ? 'fact' THEN
   v_expected:=public.private_card_effect_fact_v1(p_room_id,p_actor,p_source_user,p_source_card,p_context,p_vars,v_expected->>'fact');
 END IF;

 IF v_fact='player.field.has_card_name' THEN
   SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
   SELECT EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     WHERE public.private_card_effect_name_matches_v1(e.value,trim(both '"' from v_expected::text))
   ) INTO v_bool;
   IF v_op='name_matches' THEN RETURN coalesce(v_bool,false); END IF;
   -- Backward compatibility: existing catalog definitions use equals + a card-name string.
   IF jsonb_typeof(v_expected)<>'boolean' THEN RETURN coalesce(v_bool,false); END IF;
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
  WHEN 'name_matches' THEN RETURN false;
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

-- Recalculate continuous modifiers by source definition, allowing a definition to affect
-- each own field character except its source (used by PR274's non-blue event rule).
CREATE OR REPLACE FUNCTION public.private_card_effect_recalculate_continuous_v1(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_catalog jsonb; v_board public.room_player_turn_boards%rowtype;
 v_target_wrap jsonb; v_source_wrap jsonb; v_target_card jsonb; v_source_card jsonb;
 v_def jsonb; v_step jsonb; v_ap numeric; v_old_ap numeric; v_keywords jsonb;
 v_context jsonb:='{}'::jsonb; v_vars jsonb:='{}'::jsonb; v_owner uuid;
 v_target_id text; v_source_id text; v_target_is_partner boolean; v_current jsonb;
BEGIN
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 FOR v_board IN SELECT * FROM public.room_player_turn_boards WHERE room_id=p_room_id FOR UPDATE LOOP
   v_owner:=v_board.user_id;
   FOR v_target_wrap IN
     SELECT jsonb_build_object('card',e.value,'is_partner',false) FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     UNION ALL
     SELECT jsonb_build_object('card',v_board.partner_mr_card,'is_partner',true) WHERE v_board.partner_mr_card IS NOT NULL
   LOOP
     v_target_card:=v_target_wrap->'card';
     v_target_id:=v_target_card->>'instance_id';
     v_target_is_partner:=coalesce((v_target_wrap->>'is_partner')::boolean,false);
     v_ap:=0; v_keywords:='[]'::jsonb;

     FOR v_source_wrap IN
       SELECT jsonb_build_object('card',e.value) FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
       UNION ALL
       SELECT jsonb_build_object('card',v_board.partner_mr_card) WHERE v_board.partner_mr_card IS NOT NULL
     LOOP
       v_source_card:=v_source_wrap->'card';
       v_source_id:=v_source_card->>'instance_id';
       FOR v_def IN
         SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
         WHERE coalesce((d.value->>'continuous')::boolean,false)
           AND public.private_card_effect_matches_id_v1(v_source_card,coalesce(d.value->'cardIds','[]'::jsonb))
       LOOP
         IF NOT public.private_card_effect_conditions_match_v1(
           p_room_id,v_owner,v_owner,v_source_card,v_context,v_vars,coalesce(v_def->'conditions','[]'::jsonb)
         ) THEN CONTINUE; END IF;

         FOR v_step IN SELECT value FROM jsonb_array_elements(coalesce(v_def->'steps','[]'::jsonb)) LOOP
           IF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='ap' THEN
             IF coalesce(v_step->>'target','source_character')='source_character' AND v_target_id=v_source_id THEN
               v_ap:=v_ap+coalesce((v_step->>'amount')::numeric,0);
             ELSIF v_step->>'target'='own_field_characters_except_source'
               AND NOT v_target_is_partner AND v_target_id IS DISTINCT FROM v_source_id THEN
               v_ap:=v_ap+coalesce((v_step->>'amount')::numeric,0);
             END IF;
           ELSIF v_step->>'op'='set_continuous_keyword'
             AND coalesce(v_step->>'target','source_character')='source_character'
             AND v_target_id=v_source_id THEN
             v_keywords:=v_keywords||jsonb_build_array(jsonb_build_object(
               'effect_id',v_def->>'effectId','keyword',v_step->>'keyword'
             ));
           END IF;
         END LOOP;
       END LOOP;
     END LOOP;

     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_owner,v_target_id);
     IF v_current IS NULL THEN CONTINUE; END IF;
     v_old_ap:=coalesce(nullif(v_current->>'dsl_ap_bonus','')::numeric,0);
     PERFORM public.private_card_effect_patch_card_v1(
       p_room_id,v_owner,v_target_id,
       jsonb_build_object(
         'ap_bonus',coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)-v_old_ap+v_ap,
         'dsl_ap_bonus',v_ap,
         'dsl_continuous_keywords',v_keywords
       )
     );
   END LOOP;
 END LOOP;
END
$function$;

-- Allow DECLARE/SLEEP abilities at any non-blocked timing within the source owner's turn.
DO $patch_activation_timing$
DECLARE
 v_definition text;
 v_old text := $old$IF v_match.turn_step IS DISTINCT FROM 'main' THEN RAISE EXCEPTION '파일 배치가 끝난 뒤 메인 단계에서 능력을 발동할 수 있습니다.'; END IF;$old$;
 v_new text := $new$IF coalesce(v_match.turn_step,'') NOT IN ('begin','file','main') THEN RAISE EXCEPTION '본인 턴 중 능력을 발동할 수 있는 단계가 아닙니다.'; END IF;$new$;
BEGIN
 v_definition:=pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
 IF position(v_old in v_definition)>0 THEN
   v_definition:=replace(v_definition,v_old,v_new);
   EXECUTE v_definition;
 ELSIF position(v_new in v_definition)=0 THEN
   RAISE EXCEPTION 'ability timing gate anchor not found';
 END IF;
END
$patch_activation_timing$;

-- Permit the AI worker to activate DSL abilities that it has evaluated as worthwhile.
DO $patch_ai_activation_allowlist$
DECLARE
 v_definition text;
 v_old text := $old$'shuffle_deck','card_effect_continue'$old$;
 v_new text := $new$'shuffle_deck','card_effect_continue','activate_card_effect'$new$;
BEGIN
 v_definition:=pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure);
 IF position('activate_card_effect' in v_definition)=0 THEN
   IF position(v_old in v_definition)=0 THEN RAISE EXCEPTION 'AI action allow-list anchor not found'; END IF;
   v_definition:=replace(v_definition,v_old,v_new);
   EXECUTE v_definition;
 END IF;
END
$patch_ai_activation_allowlist$;

-- Service-role-only list of actually eligible activated definitions for the AI planner.
CREATE OR REPLACE FUNCTION public.get_private_ai_card_effect_activations_v1(
 p_room_id uuid,p_ai_user_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_catalog jsonb; v_board public.room_player_turn_boards%rowtype; v_card jsonb; v_def jsonb;
 v_used jsonb; v_turn integer; v_items jsonb:='[]'::jsonb; v_context jsonb:='{}'::jsonb;
BEGIN
 IF coalesce(current_setting('request.jwt.claim.role',true),'') <> 'service_role' THEN
   RAISE EXCEPTION 'AI 능력 목록은 서버에서만 조회할 수 있습니다.';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.private_ai_battles b
   WHERE b.room_id=p_room_id AND b.ai_user_id=p_ai_user_id
 ) THEN RAISE EXCEPTION 'AI 대전 정보를 찾을 수 없습니다.'; END IF;
 SELECT m.turn_number INTO v_turn FROM public.room_match_states m
 WHERE m.room_id=p_room_id AND m.current_turn_user_id=p_ai_user_id
   AND m.phase='playing' AND NOT m.game_over AND m.turn_step='main'
   AND m.pending_action IS NULL;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 r WHERE r.room_id=p_room_id) THEN
   RETURN jsonb_build_object('activations','[]'::jsonb);
 END IF;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_ai_user_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('activations','[]'::jsonb); END IF;
 FOR v_card IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) LOOP
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='character.activated_ability'
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN CONTINUE; END IF;
     v_items:=v_items||jsonb_build_array(jsonb_build_object(
       'source_instance_id',v_card->>'instance_id',
       'effect_id',v_def->>'effectId',
       'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
       'definition',v_def
     ));
   END LOOP;
 END LOOP;
 RETURN jsonb_build_object('activations',v_items);
END
$function$;

REVOKE ALL ON FUNCTION public.get_private_card_effect_activations_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_private_card_effect_activations_v1(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_private_ai_card_effect_activations_v1(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_private_ai_card_effect_activations_v1(uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_condition_matches_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_recalculate_continuous_v1(uuid) FROM PUBLIC,anon,authenticated;
