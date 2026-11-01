DO $patch$
DECLARE
  v_definition text;
  v_old text := $old$   ELSIF v_op IN ('move_unselected_to_deck_bottom','move_unselected_to_zone') THEN$old$;
  v_new text := $new$   ELSIF v_op='move_selected_to_deck_bottom' THEN
     -- Collect every explicitly selected card from the configured variables.
     -- ID0735 selects one opponent field character and, optionally, one
     -- same-named opponent remove-area character; both must be moved together.
     v_ordered:=v_vars->'__ordered_selected';
     IF v_ordered IS NULL THEN
       v_remaining:='[]'::jsonb;
       FOR v_selected IN
         SELECT value FROM jsonb_array_elements(coalesce(v_step->'selectedVariables','[]'::jsonb))
       LOOP
         v_path:=string_to_array(replace(coalesce(v_selected #>> '{}',''),'vars.',''),'.');
         v_current:=v_vars #> v_path;
         FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_current,'[]'::jsonb)) LOOP
           v_card:=coalesce(v_item->'card',v_item);
           IF NOT EXISTS (
             SELECT 1
             FROM jsonb_array_elements(coalesce(v_remaining,'[]'::jsonb)) existing(value)
             WHERE coalesce(existing.value->>'instance_id',existing.value#>>'{card,instance_id}','')
               = coalesce(v_card->>'instance_id',v_item->>'instance_id','')
           ) THEN
             v_remaining:=v_remaining||jsonb_build_array(v_item);
           END IF;
         END LOOP;
       END LOOP;

       IF jsonb_array_length(coalesce(v_remaining,'[]'::jsonb))=0 THEN
         UPDATE public.private_card_effect_runs_v1
           SET step_index=step_index+1,updated_at=now()
           WHERE room_id=p_room_id;
         CONTINUE;
       END IF;

       IF coalesce(v_step->>'order','preserve')='player_choice'
          AND jsonb_array_length(v_remaining)>1 THEN
         v_target_owner:=v_owner;
         IF coalesce(v_step->>'chooser','self')='opponent' THEN
           SELECT user_id INTO v_target_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_owner
           ORDER BY seat LIMIT 1;
         END IF;
         v_waiting:=jsonb_build_object(
           'kind','order',
           'options',v_remaining,
           'save_as','__ordered_selected',
           'chooser_user_id',v_target_owner,
           'prompt',coalesce(v_step->>'orderPrompt','덱 아래로 보낼 카드의 순서를 정하세요.')
         );
         v_pending:=jsonb_build_object(
           'type','card_effect_order',
           'effect_id',v_effect_id,
           'chooser_user_id',v_target_owner,
           'prompt',coalesce(v_step->>'orderPrompt','덱 아래 카드의 순서를 정하세요.'),
           'options_count',jsonb_array_length(v_remaining)
         );
         UPDATE public.private_card_effect_runs_v1
           SET waiting=v_waiting,updated_at=now()
           WHERE room_id=p_room_id;
         UPDATE public.room_match_states
           SET pending_action=v_pending||jsonb_build_object(
                 'source_card',coalesce(v_effect_source_card,'{}'::jsonb),
                 'source_card_name',coalesce(v_effect_source_card->>'name','')
               ),
               state_version=state_version+1,
               last_action_label='카드 효과: 상대가 덱 아래 카드 순서를 정하기를 기다립니다.'
           WHERE room_id=p_room_id;
         RETURN;
       END IF;
       v_ordered:=v_remaining;
     END IF;

     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_ordered,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       PERFORM public.private_card_effect_move_card_v1(
         p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),
         v_card,'deck_bottom',v_target_owner
       );
     END LOOP;
     v_vars:=v_vars-'__ordered_selected';
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;

   ELSIF v_op IN ('move_unselected_to_deck_bottom','move_unselected_to_zone') THEN$new$;
  v_updated_definitions jsonb;
BEGIN
  v_definition := pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'move_unselected operation branch not found; aborting migration';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);

  SELECT jsonb_agg(
    CASE
      WHEN e.value->>'effectId'='card-0735-on-enter-opponent-field-and-same-name-remove-return' THEN
        jsonb_set(
          e.value,
          '{steps,2}',
          '{
            "op":"move_selected_to_deck_bottom",
            "selectedVariables":["field_target","remove_target"],
            "order":"player_choice",
            "chooser":"opponent",
            "orderPrompt":"상대가 선택한 두 카드를 원하는 순서대로 덱 밑으로 옮깁니다."
          }'::jsonb,
          true
        )
      ELSE e.value
    END
    ORDER BY e.ordinality
  )
  INTO v_updated_definitions
  FROM public.private_card_effect_catalog_v1 c,
       LATERAL jsonb_array_elements(c.definitions) WITH ORDINALITY e(value,ordinality)
  WHERE c.catalog_id='main';

  IF v_updated_definitions IS NULL THEN
    RAISE EXCEPTION 'main card effect catalog not found; aborting migration';
  END IF;
  UPDATE public.private_card_effect_catalog_v1
    SET definitions=v_updated_definitions,updated_at=now()
    WHERE catalog_id='main'
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(definitions) e(value)
        WHERE e.value->>'effectId'='card-0735-on-enter-opponent-field-and-same-name-remove-return'
      );
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ID0735 effect definition not found; aborting migration';
  END IF;
END
$patch$;