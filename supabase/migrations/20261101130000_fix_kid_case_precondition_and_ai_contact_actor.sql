-- Fix Conan VS Kid activation precondition and preserve the effect controller
-- when a player acknowledges a public target reveal for an AI-owned effect.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  -- Apply start_contact as the effect owner, not as the player who clicked Ack.
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;
  v_old := $old$ v_min_select integer; v_max_select integer;$old$;
  v_new := $new$ v_min_select integer; v_max_select integer;
 v_old_sub text := current_setting('request.jwt.claim.sub', true);
 v_old_claims text := current_setting('request.jwt.claims', true);$new$;
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION '카드 효과 실행기의 선언부를 찾을 수 없습니다.';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);
  v_old := $old$ELSIF v_op='start_contact' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_item:=v_data->0;
     v_card:=coalesce(v_item->'card',v_item);
     v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,NULL);
     IF v_target_owner IS NULL OR v_target_owner=v_owner OR v_card IS NULL OR v_card->>'instance_id' IS NULL THEN
       RAISE EXCEPTION '컨택할 상대 캐릭터를 찾지 못했습니다.';
     END IF;
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '컨택을 시작할 현장 캐릭터를 찾지 못했습니다.'; END IF;
     -- The ability already paid its sleep cost. Temporarily satisfy the normal
     -- declare-contact validation; the action immediately rests the attacker again.
     IF coalesce((v_current->>'rested')::boolean,false) OR coalesce(v_current->>'status','active')='rested' THEN
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
         jsonb_build_object('rested',false,'status','active'));
     END IF;
     PERFORM public.perform_private_turn_action_v2(p_room_id,'declare_contact',jsonb_build_object(
       'attacker_instance_id',v_effect_source_instance_id,
       'target_instance_id',v_card->>'instance_id',
       'target_user_id',v_target_owner,
       'allow_newly_played',false,
       'allow_active_target',false
     ));$old$;
  v_new := $new$ELSIF v_op='start_contact' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_item:=v_data->0;
     v_card:=coalesce(v_item->'card',v_item);
     v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,NULL);
     IF v_target_owner IS NULL OR v_target_owner=v_owner OR v_card IS NULL OR v_card->>'instance_id' IS NULL THEN
       RAISE EXCEPTION '컨택할 상대 캐릭터를 찾지 못했습니다.';
     END IF;
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '컨택을 시작할 현장 캐릭터를 찾지 못했습니다.'; END IF;
     -- The ability already paid its sleep cost. Temporarily satisfy the normal
     -- declare-contact validation; the action immediately rests the attacker again.
     IF coalesce((v_current->>'rested')::boolean,false) OR coalesce(v_current->>'status','active')='rested' THEN
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
         jsonb_build_object('rested',false,'status','active'));
     END IF;
     -- A human may acknowledge the AI's target reveal. Continue the contact as
     -- the ability controller (v_owner), not as the acknowledging player.
     PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
     PERFORM set_config('request.jwt.claims',jsonb_build_object(
       'sub',v_owner::text,'role','authenticated'
     )::text,true);
     PERFORM public.perform_private_turn_action_v2(p_room_id,'declare_contact',jsonb_build_object(
       'attacker_instance_id',v_effect_source_instance_id,
       'target_instance_id',v_card->>'instance_id',
       'target_user_id',v_target_owner,
       'allow_newly_played',false,
       'allow_active_target',false
     ));
     PERFORM set_config('request.jwt.claim.sub',coalesce(v_old_sub,''),true);
     PERFORM set_config('request.jwt.claims',coalesce(v_old_claims,''),true);$new$;
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'start_contact 실행 코드를 찾을 수 없습니다.';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);
  v_definition := v_definition || ';';
  EXECUTE v_definition;

  -- Add a live opponent-field predicate to the condition evaluator.
  SELECT pg_get_functiondef('public.private_card_effect_condition_matches_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb)'::regprocedure)
    INTO v_definition;
  v_old := $old$ELSIF v_fact='player.remove_area.count_matching_trait' THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_trait:=coalesce(p_condition->>'trait','');
   v_typ:=coalesce(p_condition->>'cardType','character');
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value)
   WHERE (v_typ<>'character' OR public.private_card_effect_is_character_v1(e.value))
     AND public.private_card_effect_has_trait_v1(e.value,v_trait);
   v_actual:=to_jsonb(v_count);
 ELSE$old$;
  v_new := $new$ELSIF v_fact='player.remove_area.count_matching_trait' THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_trait:=coalesce(p_condition->>'trait','');
   v_typ:=coalesce(p_condition->>'cardType','character');
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value)
   WHERE (v_typ<>'character' OR public.private_card_effect_is_character_v1(e.value))
     AND public.private_card_effect_has_trait_v1(e.value,v_trait);
   v_actual:=to_jsonb(v_count);
 ELSIF v_fact='opponent.field.has_conan_vs_kid_eligible_return_target' THEN
   SELECT EXISTS(
     SELECT 1
     FROM public.room_players rp
     JOIN public.room_player_turn_boards ob
       ON ob.room_id=rp.room_id AND ob.user_id=rp.user_id
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(ob.field_cards,'[]'::jsonb)) e(value)
     WHERE rp.room_id=p_room_id
       AND rp.user_id<>p_actor
       AND public.private_card_effect_is_character_v1(e.value)
       AND (
         coalesce(e.value->>'status',
           CASE WHEN coalesce((e.value->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END)='rested'
         OR coalesce((e.value->>'rested')::boolean,false)
       )
       AND public.private_card_effect_level_v1(e.value)<=7
       AND upper(coalesce(e.value->>'rarity',e.value->>'rarity_code','')) NOT IN ('MR','MRP')
   ) INTO v_bool;
   v_actual:=to_jsonb(coalesce(v_bool,false));
 ELSE$new$;
  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION '카드 효과 조건 검사기의 삽입 위치를 찾을 수 없습니다.';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);
  v_definition := v_definition || ';';
  EXECUTE v_definition;
END;
$migration$;

-- An eligible return target is a prerequisite to activating this case ability.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE WHEN d.value->>'effectId'='card-1261-conan-vs-kid-case-effect'
      THEN jsonb_set(
        d.value,
        '{conditions}',
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM jsonb_array_elements(coalesce(d.value->'conditions','[]'::jsonb)) existing(value)
            WHERE existing.value->>'fact'='opponent.field.has_conan_vs_kid_eligible_return_target'
          ) THEN coalesce(d.value->'conditions','[]'::jsonb)
          ELSE coalesce(d.value->'conditions','[]'::jsonb) || jsonb_build_array(jsonb_build_object(
            'fact','opponent.field.has_conan_vs_kid_eligible_return_target',
            'value',true,
            'operator','equals'
          ))
        END,
        true
      )
      ELSE d.value
    END
    ORDER BY d.ordinality
  )
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
    WITH ORDINALITY d(value,ordinality)
)
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
    WHERE d.value->>'effectId'='card-1261-conan-vs-kid-case-effect'
  );
