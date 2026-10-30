-- Evidence removal inside a running effect must trigger matching field-watch cards on the other player's field.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$ v_drawn_card jsonb;$old$;
  v_replacement := $new$ v_drawn_card jsonb;
 v_trigger_owner uuid; v_watch_card jsonb;$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'effect runner evidence watcher declarations missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;

  v_anchor := $old$
       ELSIF v_to='remove_area' AND v_from_zone='evidence_area' THEN
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'evidence_removed_instance_id',v_card->>'instance_id');
         v_child_queue:='[]'::jsonb;
         FOR v_child_def IN
           SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
           WHERE d.value->'trigger'->>'event'='evidence.card_removed'
             AND NOT coalesce((d.value->>'continuous')::boolean,false)
             AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
             AND public.private_card_effect_conditions_match_v1(p_room_id,v_target_owner,v_target_owner,v_card,
               v_child_context,'{}'::jsonb,coalesce(d.value->'conditions','[]'::jsonb))
         LOOP
           v_child_queue:=v_child_queue||jsonb_build_array(jsonb_build_object(
             '__definition',v_child_def,'__actor_user_id',v_target_owner,'__source_user_id',v_target_owner,
             '__source_instance_id',v_card->>'instance_id','__source_card',v_card,'__context',v_child_context
           ));
         END LOOP;
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1 SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;

       ELSIF v_to='remove_area' AND v_from_zone='evidence_area' THEN
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'evidence_removed_instance_id',v_card->>'instance_id');
         v_child_queue:='[]'::jsonb;
         FOR v_child_def IN
           SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
           WHERE d.value->'trigger'->>'event'='evidence.card_removed'
             AND NOT coalesce((d.value->>'continuous')::boolean,false)
             AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
             AND public.private_card_effect_conditions_match_v1(p_room_id,v_target_owner,v_target_owner,v_card,
               v_child_context,'{}'::jsonb,coalesce(d.value->'conditions','[]'::jsonb))
         LOOP
           v_child_queue:=v_child_queue||jsonb_build_array(jsonb_build_object(
             '__definition',v_child_def,'__actor_user_id',v_target_owner,'__source_user_id',v_target_owner,
             '__source_instance_id',v_card->>'instance_id','__source_card',v_card,'__context',v_child_context
           ));
         END LOOP;
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1 SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;

       ELSIF v_to='field' AND public.private_card_effect_is_character_v1(v_card) THEN
$old$;
  v_replacement := $new$
       ELSIF v_to='remove_area' AND v_from_zone='evidence_area' THEN
         SELECT user_id INTO v_trigger_owner
         FROM public.room_players
         WHERE room_id=p_room_id AND user_id<>v_target_owner
         ORDER BY seat LIMIT 1;
         v_child_queue:='[]'::jsonb;
         IF v_trigger_owner IS NOT NULL THEN
           SELECT * INTO v_board FROM public.room_player_turn_boards
           WHERE room_id=p_room_id AND user_id=v_trigger_owner;
           FOR v_watch_card IN
             SELECT e.value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
           LOOP
             v_child_context:=jsonb_build_object(
               'source_card',v_watch_card,
               'turn_number',v_match.turn_number,
               'evidence_removed_instance_id',v_card->>'instance_id',
               'evidence_owner_user_id',v_target_owner::text,
               'removed_evidence_card',v_card
             );
             FOR v_child_def IN
               SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
               WHERE d.value->'trigger'->>'event'='evidence.card_removed'
                 AND d.value->'trigger'->>'scope'='field_watch'
                 AND NOT coalesce((d.value->>'continuous')::boolean,false)
                 AND public.private_card_effect_matches_id_v1(v_watch_card,coalesce(d.value->'cardIds','[]'::jsonb))
                 AND public.private_card_effect_conditions_match_v1(
                   p_room_id,v_trigger_owner,v_trigger_owner,v_watch_card,
                   v_child_context,'{}'::jsonb,coalesce(d.value->'conditions','[]'::jsonb)
                 )
             LOOP
               v_child_queue:=v_child_queue||jsonb_build_array(jsonb_build_object(
                 '__definition',v_child_def,
                 '__actor_user_id',v_trigger_owner,
                 '__source_user_id',v_trigger_owner,
                 '__source_instance_id',v_watch_card->>'instance_id',
                 '__source_card',v_watch_card,
                 '__context',v_child_context
               ));
             END LOOP;
           END LOOP;
         END IF;
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1
           SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;

       ELSIF v_to='field' AND public.private_card_effect_is_character_v1(v_card) THEN
$new$;

  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'effect runner evidence field-watch branch anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;
  EXECUTE v_definition;
END
$migration$;
