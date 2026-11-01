DO $patch$
DECLARE
  v_definition text;
  v_old text := $old$     IF v_n=0 AND v_min_select=0 THEN
       UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],'[]'::jsonb,true),
         step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;$old$;
  v_new text := $new$     IF v_n=0 AND v_min_select=0 THEN
       IF nullif(v_step->>'emptyMessage','') IS NOT NULL THEN
         INSERT INTO public.private_match_action_logs(room_id,turn_number,actor_user_id,action_label)
         SELECT p_room_id,coalesce(rms.turn_number,0),v_owner,v_step->>'emptyMessage'
         FROM public.room_match_states rms
         WHERE rms.room_id=p_room_id;
       END IF;
       UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],'[]'::jsonb,true),
         step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;$new$;
BEGIN
  v_definition := pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'select_cards no-candidate branch not found; aborting migration';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$patch$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN e.value->>'effectId'='card-0735-on-enter-opponent-field-and-same-name-remove-return' THEN
        jsonb_set(
          jsonb_set(
            jsonb_set(
              e.value,
              '{steps,1,filter}',
              '{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"card_name","value":{"fact":"vars.field_target.0.card.name"},"operator":"name_matches"}]}'::jsonb,
              true
            ),
            '{steps,1,prompt}',
            to_jsonb('상대 리무브 에이리어에서 선택한 캐릭터와 카드명이 같은 캐릭터를 최대 1장 선택하세요.'::text),
            true
          ),
          '{steps,1,emptyMessage}',
          to_jsonb('상대 리무브 에이리어에 선택한 캐릭터와 카드명이 같은 캐릭터가 없어 두 번째 선택을 건너뜁니다.'::text),
          true
        )
      ELSE e.value
    END
    ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY AS e(value,ordinality)
)
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(c.definitions) e(value)
    WHERE e.value->>'effectId'='card-0735-on-enter-opponent-field-and-same-name-remove-return'
  );