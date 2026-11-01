DO $fix_case_effect_once_per_turn$
DECLARE
  v_definition text;
  v_old text := $old_block$
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_existing:=public.private_card_effect_get_card_v1(p_room_id,p_source_user_id,p_source_card->>'instance_id');
       v_used:=coalesce(v_existing->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(
         SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_effect_id
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn
       ) THEN CONTINUE; END IF;
       IF v_existing IS NULL THEN RAISE EXCEPTION '턴당 1회 효과의 원본 카드를 찾을 수 없습니다.'; END IF;
       v_used:=v_used||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'turn_number',v_turn));
       PERFORM public.private_card_effect_patch_card_v1(
         p_room_id,p_source_user_id,p_source_card->>'instance_id',jsonb_build_object('dsl_effect_uses',v_used)
       );
     END IF;
$old_block$;
  v_new text := $new_block$
     -- Case/event cards are synthetic sources (case:<event_key>) rather than
     -- field cards. Their once-per-turn use is tracked transactionally by
     -- perform_private_turn_action_v2 in room_player_turn_boards.case_effect_uses.
     -- Do not try to look them up or write dsl_effect_uses on a non-existent card.
     IF coalesce((v_def->>'oncePerTurn')::boolean,false)
        AND p_trigger_event <> 'case.activated_ability' THEN
       v_existing:=public.private_card_effect_get_card_v1(p_room_id,p_source_user_id,p_source_card->>'instance_id');
       v_used:=coalesce(v_existing->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(
         SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_effect_id
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn
       ) THEN CONTINUE; END IF;
       IF v_existing IS NULL THEN RAISE EXCEPTION '턴당 1회 효과의 원본 카드를 찾을 수 없습니다.'; END IF;
       v_used:=v_used||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'turn_number',v_turn));
       PERFORM public.private_card_effect_patch_card_v1(
         p_room_id,p_source_user_id,p_source_card->>'instance_id',jsonb_build_object('dsl_effect_uses',v_used)
       );
     END IF;
$new_block$;
BEGIN
  v_definition:=pg_get_functiondef(
    'public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean)'::regprocedure
  );
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'case once-per-turn patch anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$fix_case_effect_once_per_turn$;
