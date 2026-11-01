UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN d.value->>'effectId' = 'card-0721-solution-remove-all-and-deploy-black'
      THEN jsonb_set(
        d.value,
        '{steps,2,emptyMessage}',
        to_jsonb('깡 효과: 손패에 등장 가능한 레벨 7 이하 흑색 캐릭터가 없어 추가 등장을 건너뛰었습니다.'::text),
        true
      )
      ELSE d.value
    END
    ORDER BY d.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY d(value, ordinality)
)
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(c.definitions) d(value)
    WHERE d.value->>'effectId'='card-0721-solution-remove-all-and-deploy-black'
  );

DO $patch$
DECLARE
  v_definition text;
  v_old text := $old$       IF v_to='field' THEN
         PERFORM public.private_card_effect_queue_field_entry_triggers_v1(p_room_id,v_target_owner,v_card);
       END IF;$old$;
  v_new text := $new$       IF v_to='field' THEN
         PERFORM public.private_card_effect_queue_field_entry_triggers_v1(p_room_id,v_target_owner,v_card);
         IF v_effect_id='card-0721-solution-remove-all-and-deploy-black' THEN
           UPDATE public.room_match_states
             SET state_version=state_version+1,
                 last_action_label=format(
                   '깡 효과: %s 캐릭터를 현장에 등장시켰습니다.',
                   coalesce(v_card->>'name',v_card->>'key','선택한')
                 )
           WHERE room_id=p_room_id;
         END IF;
       END IF;$new$;
BEGIN
  v_definition:=pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'move_cards field-entry hook not found; refusing to patch the runtime';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$patch$;
