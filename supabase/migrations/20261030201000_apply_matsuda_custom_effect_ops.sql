-- Apply the custom operation changes that were omitted from the original Matsuda runtime migration.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$ v_from_zone text;$old$;
  v_replacement := $new$ v_from_zone text;
 v_hand_owner uuid; v_hand_cards jsonb;
 v_investigate_owner uuid; v_investigate_deck jsonb; v_investigate_cards jsonb;
 v_investigate_remaining jsonb; v_investigate_count integer; v_investigate_low boolean;
 v_drawn_card jsonb;$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'effect runner declaration anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;

  v_anchor := $old$   ELSIF v_op='peek_top_cards' THEN$old$;
  v_replacement := $new$
   ELSIF v_op='reveal_opponent_hand' THEN
     SELECT user_id INTO v_hand_owner FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     IF v_hand_owner IS NULL THEN RAISE EXCEPTION '손패를 공개할 상대 플레이어를 찾을 수 없습니다.'; END IF;
     SELECT coalesce(hand,'[]'::jsonb) INTO v_hand_cards
       FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_hand_owner FOR UPDATE;
     v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_owner);
     v_pending:=jsonb_build_object(
       'type','card_effect_reveal_ack','effect_id',v_effect_id,
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_owner,
       'source_user_id',v_hand_owner,
       'prompt','상대의 공개된 손패를 확인한 뒤 효과를 계속 진행하세요.',
       'revealed_cards',v_hand_cards
     );
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 상대 손패 공개를 확인해 주세요.' WHERE room_id=p_room_id;
     RETURN;

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

   ELSIF v_op='peek_top_cards' THEN$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'effect runner custom-op insertion anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;

  v_anchor := $old$
   ELSIF v_op='gain_evidence' THEN
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,'evidence');
     END LOOP;
$old$;
  v_replacement := $new$
   ELSIF v_op='gain_evidence' THEN
     v_target_owner:=v_owner;
     IF v_step->>'targetOwner'='opponent' THEN
       SELECT user_id INTO v_target_owner FROM public.room_players
         WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     END IF;
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       v_drawn_card:=public.draw_private_turn_card(p_room_id,v_target_owner,'evidence');
       IF coalesce((v_step->>'faceUp')::boolean,false) AND v_drawn_card IS NOT NULL THEN
         UPDATE public.room_player_game_states gs
         SET evidence_cards=coalesce((
           SELECT jsonb_agg(
             CASE WHEN e.value->>'instance_id'=v_drawn_card->>'instance_id'
               THEN e.value||jsonb_build_object('face_up',true) ELSE e.value END
             ORDER BY e.ordinality)
           FROM jsonb_array_elements(coalesce(gs.evidence_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
         ),'[]'::jsonb),updated_at=now()
         WHERE gs.room_id=p_room_id AND gs.user_id=v_target_owner;
       END IF;
     END LOOP;
$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'gain_evidence patch anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;

  EXECUTE v_definition;
END
$migration$;
