-- Public card reveals always pause for the opponent to inspect and explicitly acknowledge.
DO $patch_public_reveal_ack$
DECLARE
  v_definition text;
  v_old_skip text := $old$
     IF coalesce((v_step->>'awaitAcknowledgement')::boolean,false) IS NOT TRUE THEN
       UPDATE public.room_match_states SET state_version=state_version+1,
         last_action_label='카드 효과: 선택한 카드를 공개했습니다.' WHERE room_id=p_room_id;
       UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
$old$;
  v_new_skip text := $new$
     IF coalesce((v_step->>'awaitAcknowledgement')::boolean,false) IS NOT TRUE
        AND NOT (
          coalesce(v_step->'to','[]'::jsonb) @> '["opponent"]'::jsonb
          OR coalesce(v_step->'to','[]'::jsonb) @> '["all"]'::jsonb
        ) THEN
       UPDATE public.room_match_states SET state_version=state_version+1,
         last_action_label='카드 효과: 선택한 카드를 공개했습니다.' WHERE room_id=p_room_id;
       UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
$new$;
  v_old_target text := $old$     IF coalesce(v_step->'to','[]'::jsonb) @> '["opponent"]'::jsonb THEN$old$;
  v_new_target text := $new$     IF coalesce(v_step->'to','[]'::jsonb) @> '["opponent"]'::jsonb
        OR coalesce(v_step->'to','[]'::jsonb) @> '["all"]'::jsonb THEN$new$;
BEGIN
  v_definition := pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  IF position(v_old_skip in v_definition)>0 THEN
    v_definition := replace(v_definition,v_old_skip,v_new_skip);
  ELSIF position('coalesce(v_step->''awaitAcknowledgement'')::boolean,false)' in v_definition)=0 THEN
    RAISE EXCEPTION 'public reveal acknowledgement skip block not found';
  END IF;
  IF position(v_old_target in v_definition)>0 THEN
    v_definition := replace(v_definition,v_old_target,v_new_target);
  ELSIF position('OR coalesce(v_step->''to'',''[]''::jsonb) @> ''["all"]''::jsonb' in v_definition)=0 THEN
    RAISE EXCEPTION 'public reveal recipient block not found';
  END IF;
  EXECUTE v_definition;
END
$patch_public_reveal_ack$;
