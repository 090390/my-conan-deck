-- The investigate operation reveals the opponent's top card(s), waits for confirmation, and returns them to the bottom of that deck.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$
   ELSIF v_op='investigate_opponent_deck' THEN
     SELECT user_id,coalesce(deck_order,'[]'::jsonb)
       INTO v_investigate_owner,v_investigate_deck
       FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id<>v_owner
       ORDER BY seat LIMIT 1 FOR UPDATE;
     IF v_investigate_owner IS NULL THEN RAISE EXCEPTION '조사할 상대 덱을 찾을 수 없습니다.'; END IF;
     v_investigate_count:=least(greatest(0,coalesce((v_step->>'count')::integer,1)),
       jsonb_array_length(coalesce(v_investigate_deck,'[]'::jsonb)));
     SELECT coalesce(jsonb_agg(jsonb_build_object(
       'instance_id',e.value->>'instance_id','owner_user_id',v_investigate_owner,
       'zone','peek','card',e.value
     ) ORDER BY e.ordinality) FILTER(WHERE e.ordinality<=v_investigate_count),'[]'::jsonb)
       INTO v_investigate_cards
       FROM jsonb_array_elements(coalesce(v_investigate_deck,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.ordinality>v_investigate_count),'[]'::jsonb)
       INTO v_investigate_remaining
       FROM jsonb_array_elements(coalesce(v_investigate_deck,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states SET deck_order=coalesce(v_investigate_remaining,'[]'::jsonb),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_investigate_owner;
     SELECT EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_investigate_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))<=7
     ) INTO v_investigate_low;
     v_vars:=jsonb_set(v_vars,ARRAY[v_step->>'saveAs'],jsonb_build_object(
       'revealed',coalesce(v_investigate_cards,'[]'::jsonb),
       'selected','[]'::jsonb,
       'has_level_at_most_7',coalesce(v_investigate_low,false)
     ),true);
     UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;
$old$;

  v_replacement := $new$
   ELSIF v_op='investigate_opponent_deck' THEN
     SELECT user_id,coalesce(deck_order,'[]'::jsonb)
       INTO v_investigate_owner,v_investigate_deck
       FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id<>v_owner
       ORDER BY seat LIMIT 1 FOR UPDATE;
     IF v_investigate_owner IS NULL THEN RAISE EXCEPTION '조사할 상대 덱을 찾을 수 없습니다.'; END IF;
     v_investigate_count:=least(greatest(0,coalesce((v_step->>'count')::integer,1)),
       jsonb_array_length(coalesce(v_investigate_deck,'[]'::jsonb)));
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
       FILTER(WHERE e.ordinality<=v_investigate_count),'[]'::jsonb)
       INTO v_investigate_cards
       FROM jsonb_array_elements(coalesce(v_investigate_deck,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
       FILTER(WHERE e.ordinality>v_investigate_count),'[]'::jsonb)
       INTO v_investigate_remaining
       FROM jsonb_array_elements(coalesce(v_investigate_deck,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states
       SET deck_order=coalesce(v_investigate_remaining,'[]'::jsonb)||coalesce(v_investigate_cards,'[]'::jsonb),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_investigate_owner;
     SELECT EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_investigate_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(e.value)<=7
     ) INTO v_investigate_low;
     v_vars:=jsonb_set(v_vars,ARRAY[v_step->>'saveAs'],jsonb_build_object(
       'revealed',coalesce(v_investigate_cards,'[]'::jsonb),
       'selected','[]'::jsonb,
       'has_level_at_most_7',coalesce(v_investigate_low,false)
     ),true);
     IF v_investigate_count>0 THEN
       v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_investigate_owner);
       v_pending:=jsonb_build_object(
         'type','card_effect_reveal_ack','effect_id',v_effect_id,
         'source_instance_id',v_effect_source_instance_id,
         'chooser_user_id',v_investigate_owner,'source_user_id',v_owner,
         'prompt','상대 덱에서 공개된 카드를 확인한 뒤 확인 완료를 눌러 주세요.',
         'revealed_cards',coalesce(v_investigate_cards,'[]'::jsonb)
       );
       UPDATE public.private_card_effect_runs_v1
         SET variables=v_vars,waiting=v_waiting,updated_at=now()
         WHERE room_id=p_room_id;
       UPDATE public.room_match_states
         SET pending_action=v_pending,state_version=state_version+1,
             last_action_label='카드 효과: 상대 덱 조사 카드 공개 확인을 기다립니다.'
         WHERE room_id=p_room_id;
       RETURN;
     END IF;
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;
$new$;

  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN
      RAISE EXCEPTION 'investigate_opponent_deck operation anchor missing';
    END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;
  EXECUTE v_definition;
END
$migration$;
