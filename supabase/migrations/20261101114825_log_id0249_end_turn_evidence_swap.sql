DO $patch$
DECLARE
  v_definition text;
  v_old text := $old$ELSIF v_op='remove_top_evidence_silently' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_data:=coalesce(v_game.evidence_cards,'[]'::jsonb);
     v_n:=jsonb_array_length(v_data);
     IF v_n>0 THEN
       v_card:=v_data->(v_n-1);
       SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
         FILTER (WHERE e.ordinality<v_n),'[]'::jsonb)
         INTO v_remaining FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality);
       UPDATE public.room_player_game_states SET
         evidence_cards=v_remaining,
         remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('face_up',true)),
         updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET
         evidence_count=greatest(0,evidence_count-1),
         remove_count=remove_count+1,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
     END IF;

   ELSIF v_op='move_source_to_remove_area' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_source_user,'field',v_current,'remove_area',v_source_user);
     END IF;

   ELSIF v_op='move_source_to_faceup_evidence' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_source_user,'field',v_current,'evidence_area',v_source_user);
     END IF;$old$;
  v_new text := $new$ELSIF v_op='remove_top_evidence_silently' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_data:=coalesce(v_game.evidence_cards,'[]'::jsonb);
     v_n:=jsonb_array_length(v_data);
     IF v_n>0 THEN
       v_card:=v_data->(v_n-1);
       SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
         FILTER (WHERE e.ordinality<v_n),'[]'::jsonb)
         INTO v_remaining FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality);
       UPDATE public.room_player_game_states SET
         evidence_cards=v_remaining,
         remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('face_up',true)),
         updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET
         evidence_count=greatest(0,evidence_count-1),
         remove_count=remove_count+1,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       IF v_effect_id='card-0249-end-turn-swap-evidence' THEN
         UPDATE public.room_match_states
           SET state_version=state_version+1,
               last_action_label=format(
                 'ID:0249 효과: 증거 맨 위 카드 %s를 리무브했습니다.',
                 coalesce(v_card->>'key','카드')
               )
         WHERE room_id=p_room_id;
       END IF;
     ELSIF v_effect_id='card-0249-end-turn-swap-evidence' THEN
       UPDATE public.room_match_states
         SET state_version=state_version+1,
             last_action_label='ID:0249 효과: 증거 에이리어가 비어 있어 리무브를 건너뛰었습니다.'
       WHERE room_id=p_room_id;
     END IF;

   ELSIF v_op='move_source_to_remove_area' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_source_user,'field',v_current,'remove_area',v_source_user);
     END IF;

   ELSIF v_op='move_source_to_faceup_evidence' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_source_user,'field',v_current,'evidence_area',v_source_user);
       IF v_effect_id='card-0249-end-turn-swap-evidence' THEN
         UPDATE public.room_match_states
           SET state_version=state_version+1,
               last_action_label='ID:0249 효과: 발동한 범인 카드를 앞면 증거로 이동했습니다.'
         WHERE room_id=p_room_id;
       END IF;
     END IF;$new$;
BEGIN
  v_definition:=pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'ID0249 evidence swap steps not found; refusing to patch runtime';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$patch$;
