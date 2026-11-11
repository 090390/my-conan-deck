
BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_has_original_ability_v1(p_card jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT length(regexp_replace(concat_ws('',
    nullif(btrim(p_card->>'abilityJp'),''), nullif(btrim(p_card->>'abilityKo'),''),
    nullif(btrim(p_card->>'ability'),''), nullif(btrim(p_card->>'feature'),''),
    nullif(btrim(p_card->>'ability_text'),''), nullif(btrim(p_card#>>'{sourceData,feature}'),''),
    nullif(btrim(p_card#>>'{sourceData,ability}'),''), nullif(btrim(p_card#>>'{raw,feature}'),''),
    nullif(btrim(p_card#>>'{raw,ability}'),''), nullif(btrim(p_card#>>'{raw,sourceData,feature}'),'')),
    '[[:space:]]','','g'))>0
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_effective_level_for_rules_v1(
  p_room_id uuid,p_owner_user uuid,p_card jsonb
) RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_phase text; v_turn_user uuid; v_level integer; v_existing_continuous integer;
BEGIN
  SELECT coalesce(case_phase,'incident') INTO v_phase
    FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_owner_user;
  SELECT current_turn_user_id INTO v_turn_user
    FROM public.room_match_states WHERE room_id=p_room_id;
  v_existing_continuous:=coalesce(nullif(p_card->>'dsl_continuous_level_bonus','')::integer,0);
  v_level:=public.private_card_effect_level_v1(p_card)-v_existing_continuous;
  IF v_phase='solution' THEN
    IF public.private_card_effect_matches_id_v1(p_card,'["1055"]'::jsonb) THEN v_level:=v_level+2;
    ELSIF public.private_card_effect_matches_id_v1(p_card,'["0888"]'::jsonb) THEN v_level:=v_level+3;
    ELSIF public.private_card_effect_matches_id_v1(p_card,'["1227"]'::jsonb) THEN v_level:=v_level+1;
    ELSIF v_turn_user=p_owner_user AND public.private_card_effect_matches_id_v1(p_card,'["1217"]'::jsonb) THEN v_level:=v_level-2;
    ELSIF v_turn_user=p_owner_user AND public.private_card_effect_matches_id_v1(p_card,'["1228"]'::jsonb) THEN v_level:=v_level-1;
    END IF;
  END IF;
  RETURN v_level;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_variable_ap_fact_v1(p_vars jsonb,p_fact text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE v_path text[]; v_value jsonb; v_card jsonb; v_ap numeric;
BEGIN
  IF p_fact IS NULL OR p_fact NOT LIKE 'vars.%.ap_current' THEN RETURN 'null'::jsonb; END IF;
  v_path:=string_to_array(substr(p_fact,6),'.');
  IF array_length(v_path,1)<3 OR v_path[array_length(v_path,1)]<>'ap_current' THEN RETURN 'null'::jsonb; END IF;
  v_path:=v_path[1:array_length(v_path,1)-1];
  v_value:=coalesce(p_vars,'{}'::jsonb)#>v_path;
  v_card:=coalesce(v_value->'card',v_value,'{}'::jsonb);
  v_ap:=coalesce(nullif(v_card->>'ap','')::numeric,nullif(v_card#>>'{sourceData,ap}','')::numeric,0)
       +coalesce(nullif(v_card->>'ap_bonus','')::numeric,0);
  RETURN to_jsonb(v_ap);
END
$function$;

REVOKE ALL ON FUNCTION public.private_card_effect_has_original_ability_v1(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_effective_level_for_rules_v1(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_variable_ap_fact_v1(jsonb,text) FROM PUBLIC,anon,authenticated;

DO $patch_conditions$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_condition_matches_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb)'::regprocedure) INTO v_source;
  v_old:=$old$IF v_fact='player.field.has_card_id' THEN$old$;
  v_new:=$new$IF v_fact='player.field.has_original_abilityless_character' THEN
    SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
    SELECT EXISTS(
      SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      WHERE public.private_card_effect_is_character_v1(e.value)
        AND NOT public.private_card_effect_has_original_ability_v1(e.value)
    ) INTO v_bool;
    v_actual:=to_jsonb(coalesce(v_bool,false));
  ELSIF v_fact='entry.source.has_original_abilityless_character' THEN
    v_actual:=to_jsonb(NOT public.private_card_effect_has_original_ability_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb)));
  ELSIF v_fact='player.field.count_level_7' THEN
    SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
    SELECT count(*)::integer INTO v_count
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE public.private_card_effect_is_character_v1(e.value)
      AND public.private_card_effect_effective_level_for_rules_v1(p_room_id,p_actor,e.value)=7;
    v_actual:=to_jsonb(coalesce(v_count,0));
  ELSIF v_fact='player.field.count_level_7_active_or_rested' THEN
    SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
    SELECT count(*)::integer INTO v_count
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE public.private_card_effect_is_character_v1(e.value)
      AND public.private_card_effect_effective_level_for_rules_v1(p_room_id,p_actor,e.value)=7
      AND NOT (coalesce((e.value->>'stunned')::boolean,false) OR coalesce((e.value->>'stun')::boolean,false)
        OR coalesce((e.value->>'is_stunned')::boolean,false)
        OR lower(coalesce(e.value->>'status','')) IN ('stunned','stun','スタン','ス��','스턴'));
    v_actual:=to_jsonb(coalesce(v_count,0));
  ELSIF v_fact='player.field.count_level_7_active' THEN
    SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
    SELECT count(*)::integer INTO v_count
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE public.private_card_effect_is_character_v1(e.value)
      AND public.private_card_effect_effective_level_for_rules_v1(p_room_id,p_actor,e.value)=7
      AND public.private_card_effect_is_active_v1(e.value);
    v_actual:=to_jsonb(coalesce(v_count,0));
  ELSIF v_fact='player.field.has_stunned_character' THEN
    SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
    SELECT EXISTS(
      SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      WHERE public.private_card_effect_is_character_v1(e.value)
        AND (coalesce((e.value->>'stunned')::boolean,false) OR coalesce((e.value->>'stun')::boolean,false)
          OR coalesce((e.value->>'is_stunned')::boolean,false)
          OR lower(coalesce(e.value->>'status','')) IN ('stunned','stun','スタン','ス��','스턴'))
    ) INTO v_bool;
    v_actual:=to_jsonb(coalesce(v_bool,false));
  ELSIF v_fact='vars.selected.is_miyano_search_exempt' THEN
    v_card:=coalesce(p_vars#>'{selected,0,card}',p_vars#>'{selected,0}','{}'::jsonb);
    v_bool:=public.private_card_effect_name_matches_v1(v_card,'諸星大')
      OR public.private_card_effect_name_matches_v1(v_card,'宮野志保')
      OR public.private_card_effect_name_matches_v1(v_card,'宮野エレーナ')
      OR public.private_card_effect_name_matches_v1(v_card,'宮野厚司');
    v_actual:=to_jsonb(coalesce(v_bool,false));
  ELSIF v_fact='player.field.has_card_id' THEN$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'Miyano DSL condition insertion point not found'; END IF;
  EXECUTE replace(v_source,v_old,v_new);
END
$patch_conditions$;

DO $patch_filter$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_filter_matches_with_vars_v1(uuid,jsonb,uuid,uuid,jsonb,jsonb)'::regprocedure) INTO v_source;
  v_old:=$old$IF jsonb_typeof(expected)='object' AND expected ? 'fact' THEN
   expected:=public.private_card_effect_fact_v1(p_room_id,p_owner_user,p_source_user,p_card,'{}'::jsonb,coalesce(p_vars,'{}'::jsonb),expected->>'fact');
 END IF;$old$;
  v_new:=$new$IF jsonb_typeof(expected)='object' AND expected ? 'fact' THEN
   IF expected->>'fact' LIKE 'vars.%.ap_current' THEN
     expected:=public.private_card_effect_variable_ap_fact_v1(coalesce(p_vars,'{}'::jsonb),expected->>'fact');
   ELSE
     expected:=public.private_card_effect_fact_v1(p_room_id,p_owner_user,p_source_user,p_card,'{}'::jsonb,coalesce(p_vars,'{}'::jsonb),expected->>'fact');
   END IF;
 END IF;$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'Miyano AP filter insertion point not found'; END IF;
  EXECUTE replace(v_source,v_old,v_new);
END
$patch_filter$;

DO $patch_continuous$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_recalculate_continuous_v1(uuid)'::regprocedure) INTO v_source;
  v_old:=$old$ELSIF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='level'
             AND v_step->>'target'='opponent_field_characters'
             AND v_target_owner<>v_owner AND NOT v_target_is_partner THEN
             v_level:=v_level+coalesce((v_step->>'amount')::numeric,0);$old$;
  v_new:=$new$ELSIF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='level'
             AND coalesce(v_step->>'target','source_character')='source_character'
             AND v_target_owner=v_owner AND v_target_id=v_source_id THEN
             v_level:=v_level+coalesce((v_step->>'amount')::numeric,0);
           ELSIF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='level'
             AND v_step->>'target'='opponent_field_characters'
             AND v_target_owner<>v_owner AND NOT v_target_is_partner THEN
             v_level:=v_level+coalesce((v_step->>'amount')::numeric,0);$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'Miyano continuous-level insertion point not found'; END IF;
  EXECUTE replace(v_source,v_old,v_new);
END
$patch_continuous$;

CREATE OR REPLACE FUNCTION public.private_card_effect_prepare_miyano_cutin_v1(
  p_room_id uuid,p_user uuid,p_payload jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_match public.room_match_states%rowtype; v_game public.room_player_game_states%rowtype;
  v_card jsonb; v_cost_card jsonb; v_hand jsonb; v_new_hand jsonb;
  v_instance text:=nullif(p_payload->>'instance_id',''); v_cost_instance text:=nullif(p_payload->>'cost_instance_id','');
  v_card_code text; v_partner_color text; v_hand_count integer; v_bonus integer:=0; v_ap numeric;
BEGIN
  SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '컷인 사용자의 손패를 찾을 수 없습니다.'; END IF;
  v_hand:=coalesce(v_game.hand,'[]'::jsonb);
  SELECT e.value INTO v_card FROM jsonb_array_elements(v_hand) e(value)
    WHERE e.value->>'instance_id'=v_instance LIMIT 1;
  IF v_card IS NULL THEN RAISE EXCEPTION '손패에서 컷인 카드를 찾을 수 없습니다.'; END IF;

  IF public.private_card_effect_matches_id_v1(v_card,'["1117"]'::jsonb) THEN
    v_card_code:=upper(coalesce(v_card->>'key',v_card->>'card_num',v_card->>'cardNum',v_card->>'cardNumber',
      v_card#>>'{sourceData,card_num}',v_card#>>'{sourceData,cardNumber}',''));
    v_partner_color:=public.private_card_effect_partner_color_v1(p_room_id,p_user);
    v_hand_count:=jsonb_array_length(v_hand);
    IF v_card_code='B10058' THEN v_hand_count:=greatest(0,v_hand_count-1); END IF;
    IF v_partner_color='red' THEN v_bonus:=CASE WHEN v_hand_count<=2 THEN 3000 ELSE 1000 END; END IF;
    SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'instance_id'=v_instance
      THEN e.value||jsonb_build_object('cut_in_bonus',v_bonus) ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb)
      INTO v_new_hand FROM jsonb_array_elements(v_hand) WITH ORDINALITY e(value,ordinality);
    UPDATE public.room_player_game_states SET hand=v_new_hand,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_user;

  ELSIF public.private_card_effect_matches_id_v1(v_card,'["0893"]'::jsonb) THEN
    IF v_match.current_turn_user_id=p_user AND v_cost_instance IS NOT NULL THEN
      SELECT e.value INTO v_cost_card FROM jsonb_array_elements(v_hand) e(value)
        WHERE e.value->>'instance_id'=v_cost_instance AND e.value->>'instance_id'<>v_instance LIMIT 1;
      IF v_cost_card IS NULL OR NOT public.private_card_effect_is_character_v1(v_cost_card) THEN
        RAISE EXCEPTION '미야노 히데미 컷인 비용은 컷인 카드 이외의 손패 캐릭터 1장이어야 합니다.';
      END IF;
      v_ap:=coalesce(nullif(v_cost_card->>'ap','')::numeric,nullif(v_cost_card#>>'{sourceData,ap}','')::numeric,0)
        +coalesce(nullif(v_cost_card->>'ap_bonus','')::numeric,0);
      IF v_ap<1000 THEN RAISE EXCEPTION '미야노 히데미 컷인 비용 캐릭터의 AP가 1000 미만입니다.'; END IF;
      v_bonus:=floor(v_ap/1000)::integer*1000;
      SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.value->>'instance_id'<>v_cost_instance),'[]'::jsonb)
        INTO v_new_hand FROM jsonb_array_elements(v_hand) WITH ORDINALITY e(value,ordinality);
      UPDATE public.room_player_game_states SET hand=v_new_hand,
        remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_cost_card),updated_at=now()
        WHERE room_id=p_room_id AND user_id=p_user;
      UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
        WHERE room_id=p_room_id AND user_id=p_user;
    END IF;
    SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'instance_id'=v_instance
      THEN e.value||jsonb_build_object('cut_in_bonus',v_bonus) ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb)
      INTO v_new_hand FROM jsonb_array_elements(coalesce(
        (SELECT hand FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_user),'[]'::jsonb
      )) WITH ORDINALITY e(value,ordinality);
    UPDATE public.room_player_game_states SET hand=v_new_hand,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_user;
  END IF;
END
$function$;
REVOKE ALL ON FUNCTION public.private_card_effect_prepare_miyano_cutin_v1(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;

DO $patch_turn_action$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure) INTO v_source;
  v_old:=$old$v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));$old$;
  v_new:=$new$IF p_action='contact_use_cutin' THEN
    PERFORM public.private_card_effect_prepare_miyano_cutin_v1(p_room_id,v_user,coalesce(p_payload,'{}'::jsonb));
  END IF;
  v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'Miyano cut-in turn-action insertion point not found'; END IF;
  EXECUTE replace(v_source,v_old,v_new);
END
$patch_turn_action$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(
  SELECT coalesce(jsonb_agg(d.value ORDER BY d.ordinality),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
  WHERE d.value->>'effectId' NOT IN (
    SELECT x.value->>'effectId'
    FROM jsonb_array_elements($miyano_defs$[{"steps":[{"op":"draw_cards","count":1,"destination":"hand"}],"cardIds":["1111"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-1111-end-turn-draw-if-original-abilityless-character","conditions":[{"fact":"player.field.has_original_abilityless_character","value":true,"operator":"equals"}],"oncePerTurn":true},{"steps":[{"op":"select_cards","max":1,"min":0,"from":"opponent_field","filter":{"field":"card_type","value":"character","operator":"equals"},"prompt":"턴 종료 시까지 레벨을 1 낮출 상대 캐릭터를 최대 1장 선택하세요.","saveAs":"level_target","optional":true},{"op":"modify_stat","stat":"level","when":{"fact":"vars.level_target.count","value":0,"operator":"greater_than"},"amount":-1,"target":"vars.level_target","duration":"turn_end"}],"cardIds":["1111"],"trigger":{"event":"character.entered_field","scope":"field_watch","timing":"after"},"effectId":"card-1111-own-turn-abilityless-entry-opponent-level-minus-one","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"entry.controller_is_source_controller","value":true,"operator":"equals"},{"fact":"entry.source.has_original_abilityless_character","value":true,"operator":"equals"}]},{"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","max":1,"min":1,"from":"hand","prompt":"비용으로 손패 1장을 선택해 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost"},{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":9,"operator":"less_than_or_equal"}]},"prompt":"리무브할 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target","optional":true},{"op":"move_cards","to":"remove_area","from":"target","when":{"fact":"vars.target.count","value":0,"operator":"greater_than"}}],"cardIds":["1111"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1111-activated-discard-hand-remove-level-nine-character","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"player.hand.count","value":1,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"슬립 · 손패 1장 리무브 · 레벨 9 이하 캐릭터 리무브"},{"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","max":1,"min":0,"from":"hand","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"anyOf":[{"field":"card_name","value":"宮野エレーナ","operator":"name_matches"},{"field":"card_name","value":"宮野志保","operator":"name_matches"},{"field":"card_name","value":"宮野明美","operator":"name_matches"}]}]},"prompt":"손패에서 미야노 엘레나, 미야노 시호, 미야노 아케미 중 1장까지 선택해 등장시킬 수 있습니다.","saveAs":"deployment","optional":true},{"op":"calculate_switch_count","saveAs":"switch_needed","deploymentVariable":"vars.deployment"},{"op":"select_cards","max":0,"min":0,"from":"field","when":{"fact":"vars.switch_needed","value":0,"operator":"greater_than"},"filter":{"field":"card_type","value":"character","operator":"equals"},"prompt":"현장이 가득 찼습니다. 등장 자리를 만들기 위해 자신의 현장 캐릭터를 리무브하세요.","saveAs":"switch_targets","maxFrom":"vars.switch_needed","minFrom":"vars.switch_needed","optional":true},{"op":"move_cards","to":"remove_area","from":"switch_targets","when":{"fact":"vars.switch_targets.count","value":0,"operator":"greater_than"}},{"op":"move_cards","to":"field","from":"deployment","when":{"fact":"vars.deployment.count","value":0,"operator":"greater_than"},"entryMethod":"character_ability"}],"cardIds":["0894"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-0894-file-five-sleep-deploy-miyano-family","conditions":[{"fact":"player.file.count","value":5,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"FILE5 · 슬립 · 손패의 미야노 가족 등장"},{"steps":[{"op":"draw_cards","count":1,"destination":"hand"},{"op":"select_cards","max":1,"min":0,"from":"opponent_field","filter":{"field":"card_type","value":"character","operator":"equals"},"prompt":"스턴시킬 상대 캐릭터를 최대 1장 선택하세요.","saveAs":"stun_target","optional":true},{"op":"stun_cards","when":{"fact":"vars.stun_target.count","value":0,"operator":"greater_than"},"target":"vars.stun_target"}],"cardIds":["0896"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-0896-end-turn-level-seven-three-draw-stun","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"player.field.count_level_7","value":3,"operator":"greater_than_or_equal"}],"oncePerTurn":true},{"steps":[{"op":"offer_reaction","actor":"controller","prompt":"이 캐릭터를 슬립시키고 손패 1장과 FILE 맨 위의 일반 카드 1장을 리무브해도 될까요? 그렇게 하면 슬립/스턴 상태이며 레벨 8 이하인 캐릭터를 덱 맨 아래로 옮깁니다.","saveAs":"file8_choice","choices":["yes","no"],"reactionId":"card-0896-file8-on-enter-cost"},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"}},{"op":"select_cards","max":1,"min":1,"from":"hand","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"},"prompt":"비용으로 손패 1장을 선택해 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"}},{"op":"move_top_file_cards","to":"remove_area","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"},"count":1},{"op":"select_cards","max":1,"min":0,"from":"both_fields","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"},"filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":8,"operator":"less_than_or_equal"},{"anyOf":[{"field":"status","value":"rested","operator":"equals"},{"field":"status","value":"stunned","operator":"equals"}]}]},"prompt":"덱 맨 아래로 옮길, 레벨 8 이하의 슬립 또는 스턴 상태 캐릭터를 최대 1장 선택하세요.","saveAs":"bottom_target","optional":true},{"op":"move_cards","to":"deck_bottom","from":"bottom_target","when":{"allOf":[{"fact":"vars.file8_choice","value":"yes","operator":"equals"},{"fact":"vars.bottom_target.count","value":0,"operator":"greater_than"}]}}],"cardIds":["0896"],"trigger":{"event":"character.entered_field","timing":"after"},"effectId":"card-0896-file-eight-on-enter-sleep-discard-return-stunned-or-rested","conditions":[{"fact":"player.file.count","value":8,"operator":"greater_than_or_equal"},{"fact":"player.hand.count","value":1,"operator":"greater_than_or_equal"},{"fact":"source.is_active","value":true,"operator":"equals"}]},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":2,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-akemi-1055-solution-level-plus-two"}],"cardIds":["1055"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1055-solution-continuous-level-plus-two","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"}],"continuous":true},{"steps":[{"op":"grant_keyword","target":"source_character","keyword":"charge_case","duration":"turn_end","displayNameKo":"돌격[사건]"}],"cardIds":["1055"],"trigger":{"event":"character.entered_field","timing":"after"},"effectId":"card-1055-on-enter-level-seven-three-grant-charge-case","conditions":[{"fact":"player.field.count_level_7","value":3,"operator":"greater_than_or_equal"}]},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":3,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-akemi-0888-solution-level-plus-three"}],"cardIds":["0888"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-0888-solution-continuous-level-plus-three","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"}],"continuous":true},{"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","prompt":"공개하여 패에 넣을 카드 1장을 선택할 수 있습니다. 선택하지 않으면 공개한 카드는 전부 리무브 에이리어로 이동합니다.","saveAs":"selected","optional":true,"displayVariable":"seen"},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_zone","to":"remove_area","from":"seen","selectedVariable":"selected"},{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","value":4,"operator":"less_than"},"shuffle":true,"includeRemoveArea":true,"includeRemainingDeck":true},{"op":"select_cards","max":1,"min":1,"from":"hand","when":{"allOf":[{"fact":"vars.selected.count","value":0,"operator":"greater_than"},{"fact":"vars.selected.is_miyano_search_exempt","value":false,"operator":"equals"}]},"prompt":"모로호시 다이/미야노 시호/미야노 엘레나/미야노 아츠시 이외의 카드를 패에 추가했으므로, 손패 1장을 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost","when":{"allOf":[{"fact":"vars.selected.count","value":0,"operator":"greater_than"},{"fact":"vars.selected.is_miyano_search_exempt","value":false,"operator":"equals"}]}}],"cardIds":["0888"],"trigger":{"event":"character.entered_field","timing":"after"},"effectId":"card-0888-on-enter-look-three-add-one-remove-rest-and-discard-if-not-family"},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":-2,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-shiho-akemi-1217-solution-level-minus-two"}],"cardIds":["1217"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1217-solution-own-turn-continuous-level-minus-two","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"}],"continuous":true},{"steps":[{"op":"select_cards","max":1,"min":1,"from":"field","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":7,"operator":"equals"},{"anyOf":[{"field":"status","value":"active","operator":"equals"},{"field":"status","value":"rested","operator":"equals"}]}]},"prompt":"자신의 현장에서 레벨 7의 액티브 또는 슬립 상태 캐릭터 1장을 선택해 스턴시키세요.","saveAs":"stun_cost","optional":false,"targetController":"self"},{"op":"stun_cards","target":"vars.stun_cost"},{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":9,"operator":"less_than_or_equal"}]},"prompt":"리무브할 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"remove_target","optional":true},{"op":"move_cards","to":"remove_area","from":"remove_target","when":{"fact":"vars.remove_target.count","value":0,"operator":"greater_than"}}],"cardIds":["1217"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1217-partner-red-activated-stun-level-seven-then-remove-level-nine","conditions":[{"fact":"player.partner.color","value":"red","operator":"equals"},{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"player.field.count_level_7_active_or_rested","value":1,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"레벨 7 캐릭터 스턴 · 레벨 9 이하 캐릭터 리무브"},{"steps":[{"op":"draw_cards","count":2,"destination":"hand"},{"op":"select_cards","max":1,"min":1,"from":"hand","prompt":"손패 1장을 선택해 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost"}],"cardIds":["1217"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-1217-end-turn-if-own-stunned-draw-two-discard-one","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"player.field.has_stunned_character","value":true,"operator":"equals"}],"oncePerTurn":true,"allowPartnerArea":true},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":1,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-elena-1227-solution-level-plus-one"}],"cardIds":["1227"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1227-solution-continuous-level-plus-one","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"}],"continuous":true},{"steps":[{"op":"select_cards","max":1,"min":1,"from":"field","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":7,"operator":"equals"},{"field":"status","value":"active","operator":"equals"}]},"prompt":"자신의 현장에서 레벨 7의 액티브 상태 캐릭터 1장을 선택해 스턴시키세요.","saveAs":"stun_cost","optional":false,"targetController":"self"},{"op":"stun_cards","target":"vars.stun_cost"},{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"ap_current","value":{"fact":"vars.stun_cost.0.card.ap_current"},"operator":"less_than_or_equal"}]},"prompt":"방금 스턴시킨 캐릭터의 현재 AP 이하인 캐릭터를 최대 1장 선택해 리무브하세요.","saveAs":"remove_target","optional":true},{"op":"move_cards","to":"remove_area","from":"remove_target","when":{"fact":"vars.remove_target.count","value":0,"operator":"greater_than"}}],"cardIds":["1227"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1227-partner-red-solution-stun-active-level-seven-remove-at-most-equal-ap","conditions":[{"fact":"player.partner.color","value":"red","operator":"equals"},{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"player.field.count_level_7_active","value":1,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"레벨 7 액티브 캐릭터 스턴 · 그 캐릭터 이하 AP 리무브"},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":-1,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-atsushi-1228-solution-level-minus-one"}],"cardIds":["1228"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1228-solution-own-turn-continuous-level-minus-one","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"}],"continuous":true},{"steps":[{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"ap_current","value":8000,"operator":"less_than_or_equal"}]},"prompt":"리무브할 AP 8000 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"remove_target","optional":true},{"op":"move_cards","to":"remove_area","from":"remove_target","when":{"fact":"vars.remove_target.count","value":0,"operator":"greater_than"}}],"cardIds":["1228"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1228-activated-remove-ap-eight-thousand-rested-or-stunned-source","oncePerTurn":true,"activationTiming":"any","activationLabelKo":"AP 8000 이하 캐릭터 리무브","allowRestedSource":true,"allowStunnedSource":true},{"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"anyOf":[{"field":"card_name","value":"宮野エレーナ","operator":"name_matches"},{"field":"card_name","value":"宮野明美","operator":"name_matches"},{"field":"card_name","value":"宮野志保","operator":"name_matches"}]}]},"prompt":"공개하여 패에 추가할 미야노 엘레나/미야노 아케미/미야노 시호 중 1장까지 선택하세요.","saveAs":"selected","optional":true,"displayVariable":"seen"},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_zone","to":"remove_area","from":"seen","selectedVariable":"selected"},{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","value":4,"operator":"less_than"},"shuffle":true,"includeRemoveArea":true,"includeRemainingDeck":true}],"cardIds":["1228"],"trigger":{"event":"character.removed_from_field","timing":"after"},"effectId":"card-1228-partner-red-opponent-turn-removed-look-three-miyano-recover","conditions":[{"fact":"player.partner.color","value":"red","operator":"equals"},{"fact":"turn.is_opponent_turn","value":true,"operator":"equals"}]}]$miyano_defs$::jsonb) x(value)
  )
) || $miyano_defs$[{"steps":[{"op":"draw_cards","count":1,"destination":"hand"}],"cardIds":["1111"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-1111-end-turn-draw-if-original-abilityless-character","conditions":[{"fact":"player.field.has_original_abilityless_character","value":true,"operator":"equals"}],"oncePerTurn":true},{"steps":[{"op":"select_cards","max":1,"min":0,"from":"opponent_field","filter":{"field":"card_type","value":"character","operator":"equals"},"prompt":"턴 종료 시까지 레벨을 1 낮출 상대 캐릭터를 최대 1장 선택하세요.","saveAs":"level_target","optional":true},{"op":"modify_stat","stat":"level","when":{"fact":"vars.level_target.count","value":0,"operator":"greater_than"},"amount":-1,"target":"vars.level_target","duration":"turn_end"}],"cardIds":["1111"],"trigger":{"event":"character.entered_field","scope":"field_watch","timing":"after"},"effectId":"card-1111-own-turn-abilityless-entry-opponent-level-minus-one","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"entry.controller_is_source_controller","value":true,"operator":"equals"},{"fact":"entry.source.has_original_abilityless_character","value":true,"operator":"equals"}]},{"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","max":1,"min":1,"from":"hand","prompt":"비용으로 손패 1장을 선택해 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost"},{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":9,"operator":"less_than_or_equal"}]},"prompt":"리무브할 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"target","optional":true},{"op":"move_cards","to":"remove_area","from":"target","when":{"fact":"vars.target.count","value":0,"operator":"greater_than"}}],"cardIds":["1111"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1111-activated-discard-hand-remove-level-nine-character","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"player.hand.count","value":1,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"슬립 · 손패 1장 리무브 · 레벨 9 이하 캐릭터 리무브"},{"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","max":1,"min":0,"from":"hand","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"anyOf":[{"field":"card_name","value":"宮野エレーナ","operator":"name_matches"},{"field":"card_name","value":"宮野志保","operator":"name_matches"},{"field":"card_name","value":"宮野明美","operator":"name_matches"}]}]},"prompt":"손패에서 미야노 엘레나, 미야노 시호, 미야노 아케미 중 1장까지 선택해 등장시킬 수 있습니다.","saveAs":"deployment","optional":true},{"op":"calculate_switch_count","saveAs":"switch_needed","deploymentVariable":"vars.deployment"},{"op":"select_cards","max":0,"min":0,"from":"field","when":{"fact":"vars.switch_needed","value":0,"operator":"greater_than"},"filter":{"field":"card_type","value":"character","operator":"equals"},"prompt":"현장이 가득 찼습니다. 등장 자리를 만들기 위해 자신의 현장 캐릭터를 리무브하세요.","saveAs":"switch_targets","maxFrom":"vars.switch_needed","minFrom":"vars.switch_needed","optional":true},{"op":"move_cards","to":"remove_area","from":"switch_targets","when":{"fact":"vars.switch_targets.count","value":0,"operator":"greater_than"}},{"op":"move_cards","to":"field","from":"deployment","when":{"fact":"vars.deployment.count","value":0,"operator":"greater_than"},"entryMethod":"character_ability"}],"cardIds":["0894"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-0894-file-five-sleep-deploy-miyano-family","conditions":[{"fact":"player.file.count","value":5,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"FILE5 · 슬립 · 손패의 미야노 가족 등장"},{"steps":[{"op":"draw_cards","count":1,"destination":"hand"},{"op":"select_cards","max":1,"min":0,"from":"opponent_field","filter":{"field":"card_type","value":"character","operator":"equals"},"prompt":"스턴시킬 상대 캐릭터를 최대 1장 선택하세요.","saveAs":"stun_target","optional":true},{"op":"stun_cards","when":{"fact":"vars.stun_target.count","value":0,"operator":"greater_than"},"target":"vars.stun_target"}],"cardIds":["0896"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-0896-end-turn-level-seven-three-draw-stun","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"player.field.count_level_7","value":3,"operator":"greater_than_or_equal"}],"oncePerTurn":true},{"steps":[{"op":"offer_reaction","actor":"controller","prompt":"이 캐릭터를 슬립시키고 손패 1장과 FILE 맨 위의 일반 카드 1장을 리무브해도 될까요? 그렇게 하면 슬립/스턴 상태이며 레벨 8 이하인 캐릭터를 덱 맨 아래로 옮깁니다.","saveAs":"file8_choice","choices":["yes","no"],"reactionId":"card-0896-file8-on-enter-cost"},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"}},{"op":"select_cards","max":1,"min":1,"from":"hand","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"},"prompt":"비용으로 손패 1장을 선택해 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"}},{"op":"move_top_file_cards","to":"remove_area","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"},"count":1},{"op":"select_cards","max":1,"min":0,"from":"both_fields","when":{"fact":"vars.file8_choice","value":"yes","operator":"equals"},"filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":8,"operator":"less_than_or_equal"},{"anyOf":[{"field":"status","value":"rested","operator":"equals"},{"field":"status","value":"stunned","operator":"equals"}]}]},"prompt":"덱 맨 아래로 옮길, 레벨 8 이하의 슬립 또는 스턴 상태 캐릭터를 최대 1장 선택하세요.","saveAs":"bottom_target","optional":true},{"op":"move_cards","to":"deck_bottom","from":"bottom_target","when":{"allOf":[{"fact":"vars.file8_choice","value":"yes","operator":"equals"},{"fact":"vars.bottom_target.count","value":0,"operator":"greater_than"}]}}],"cardIds":["0896"],"trigger":{"event":"character.entered_field","timing":"after"},"effectId":"card-0896-file-eight-on-enter-sleep-discard-return-stunned-or-rested","conditions":[{"fact":"player.file.count","value":8,"operator":"greater_than_or_equal"},{"fact":"player.hand.count","value":1,"operator":"greater_than_or_equal"},{"fact":"source.is_active","value":true,"operator":"equals"}]},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":2,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-akemi-1055-solution-level-plus-two"}],"cardIds":["1055"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1055-solution-continuous-level-plus-two","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"}],"continuous":true},{"steps":[{"op":"grant_keyword","target":"source_character","keyword":"charge_case","duration":"turn_end","displayNameKo":"돌격[사건]"}],"cardIds":["1055"],"trigger":{"event":"character.entered_field","timing":"after"},"effectId":"card-1055-on-enter-level-seven-three-grant-charge-case","conditions":[{"fact":"player.field.count_level_7","value":3,"operator":"greater_than_or_equal"}]},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":3,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-akemi-0888-solution-level-plus-three"}],"cardIds":["0888"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-0888-solution-continuous-level-plus-three","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"}],"continuous":true},{"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","prompt":"공개하여 패에 넣을 카드 1장을 선택할 수 있습니다. 선택하지 않으면 공개한 카드는 전부 리무브 에이리어로 이동합니다.","saveAs":"selected","optional":true,"displayVariable":"seen"},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_zone","to":"remove_area","from":"seen","selectedVariable":"selected"},{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","value":4,"operator":"less_than"},"shuffle":true,"includeRemoveArea":true,"includeRemainingDeck":true},{"op":"select_cards","max":1,"min":1,"from":"hand","when":{"allOf":[{"fact":"vars.selected.count","value":0,"operator":"greater_than"},{"fact":"vars.selected.is_miyano_search_exempt","value":false,"operator":"equals"}]},"prompt":"모로호시 다이/미야노 시호/미야노 엘레나/미야노 아츠시 이외의 카드를 패에 추가했으므로, 손패 1장을 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost","when":{"allOf":[{"fact":"vars.selected.count","value":0,"operator":"greater_than"},{"fact":"vars.selected.is_miyano_search_exempt","value":false,"operator":"equals"}]}}],"cardIds":["0888"],"trigger":{"event":"character.entered_field","timing":"after"},"effectId":"card-0888-on-enter-look-three-add-one-remove-rest-and-discard-if-not-family"},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":-2,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-shiho-akemi-1217-solution-level-minus-two"}],"cardIds":["1217"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1217-solution-own-turn-continuous-level-minus-two","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"}],"continuous":true},{"steps":[{"op":"select_cards","max":1,"min":1,"from":"field","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":7,"operator":"equals"},{"anyOf":[{"field":"status","value":"active","operator":"equals"},{"field":"status","value":"rested","operator":"equals"}]}]},"prompt":"자신의 현장에서 레벨 7의 액티브 또는 슬립 상태 캐릭터 1장을 선택해 스턴시키세요.","saveAs":"stun_cost","optional":false,"targetController":"self"},{"op":"stun_cards","target":"vars.stun_cost"},{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":9,"operator":"less_than_or_equal"}]},"prompt":"리무브할 레벨 9 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"remove_target","optional":true},{"op":"move_cards","to":"remove_area","from":"remove_target","when":{"fact":"vars.remove_target.count","value":0,"operator":"greater_than"}}],"cardIds":["1217"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1217-partner-red-activated-stun-level-seven-then-remove-level-nine","conditions":[{"fact":"player.partner.color","value":"red","operator":"equals"},{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"player.field.count_level_7_active_or_rested","value":1,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"레벨 7 캐릭터 스턴 · 레벨 9 이하 캐릭터 리무브"},{"steps":[{"op":"draw_cards","count":2,"destination":"hand"},{"op":"select_cards","max":1,"min":1,"from":"hand","prompt":"손패 1장을 선택해 리무브하세요.","saveAs":"hand_cost","optional":false},{"op":"move_cards","to":"remove_area","from":"hand_cost"}],"cardIds":["1217"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-1217-end-turn-if-own-stunned-draw-two-discard-one","conditions":[{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"},{"fact":"player.field.has_stunned_character","value":true,"operator":"equals"}],"oncePerTurn":true,"allowPartnerArea":true},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":1,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-elena-1227-solution-level-plus-one"}],"cardIds":["1227"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1227-solution-continuous-level-plus-one","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"}],"continuous":true},{"steps":[{"op":"select_cards","max":1,"min":1,"from":"field","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"level","value":7,"operator":"equals"},{"field":"status","value":"active","operator":"equals"}]},"prompt":"자신의 현장에서 레벨 7의 액티브 상태 캐릭터 1장을 선택해 스턴시키세요.","saveAs":"stun_cost","optional":false,"targetController":"self"},{"op":"stun_cards","target":"vars.stun_cost"},{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"ap_current","value":{"fact":"vars.stun_cost.0.card.ap_current"},"operator":"less_than_or_equal"}]},"prompt":"방금 스턴시킨 캐릭터의 현재 AP 이하인 캐릭터를 최대 1장 선택해 리무브하세요.","saveAs":"remove_target","optional":true},{"op":"move_cards","to":"remove_area","from":"remove_target","when":{"fact":"vars.remove_target.count","value":0,"operator":"greater_than"}}],"cardIds":["1227"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1227-partner-red-solution-stun-active-level-seven-remove-at-most-equal-ap","conditions":[{"fact":"player.partner.color","value":"red","operator":"equals"},{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"player.field.count_level_7_active","value":1,"operator":"greater_than_or_equal"}],"oncePerTurn":true,"activationLabelKo":"레벨 7 액티브 캐릭터 스턴 · 그 캐릭터 이하 AP 리무브"},{"steps":[{"op":"set_continuous_stat","stat":"level","amount":-1,"target":"source_character","duration":"while_condition_true","modifierId":"miyano-atsushi-1228-solution-level-minus-one"}],"cardIds":["1228"],"trigger":{"event":"continuous.recalculate","timing":"continuous"},"effectId":"card-1228-solution-own-turn-continuous-level-minus-one","conditions":[{"fact":"player.case_phase","value":"solution","operator":"equals"},{"fact":"turn.is_source_controller_turn","value":true,"operator":"equals"}],"continuous":true},{"steps":[{"op":"select_cards","max":1,"min":0,"from":"both_fields","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"ap_current","value":8000,"operator":"less_than_or_equal"}]},"prompt":"리무브할 AP 8000 이하 캐릭터를 최대 1장 선택하세요.","saveAs":"remove_target","optional":true},{"op":"move_cards","to":"remove_area","from":"remove_target","when":{"fact":"vars.remove_target.count","value":0,"operator":"greater_than"}}],"cardIds":["1228"],"trigger":{"event":"character.activated_ability","timing":"after"},"effectId":"card-1228-activated-remove-ap-eight-thousand-rested-or-stunned-source","oncePerTurn":true,"activationTiming":"any","activationLabelKo":"AP 8000 이하 캐릭터 리무브","allowRestedSource":true,"allowStunnedSource":true},{"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"anyOf":[{"field":"card_name","value":"宮野エレーナ","operator":"name_matches"},{"field":"card_name","value":"宮野明美","operator":"name_matches"},{"field":"card_name","value":"宮野志保","operator":"name_matches"}]}]},"prompt":"공개하여 패에 추가할 미야노 엘레나/미야노 아케미/미야노 시호 중 1장까지 선택하세요.","saveAs":"selected","optional":true,"displayVariable":"seen"},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_zone","to":"remove_area","from":"seen","selectedVariable":"selected"},{"op":"refill_deck_from_remove_area","when":{"fact":"player.deck.count","value":4,"operator":"less_than"},"shuffle":true,"includeRemoveArea":true,"includeRemainingDeck":true}],"cardIds":["1228"],"trigger":{"event":"character.removed_from_field","timing":"after"},"effectId":"card-1228-partner-red-opponent-turn-removed-look-three-miyano-recover","conditions":[{"fact":"player.partner.color","value":"red","operator":"equals"},{"fact":"turn.is_opponent_turn","value":true,"operator":"equals"}]}]$miyano_defs$::jsonb,
updated_at=now()
WHERE c.catalog_id='main';

COMMIT;
