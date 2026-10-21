-- If the public Culprits' Crime verification finds fewer than 8 culprit-trait evidence cards,
-- resolve the attempted effect as a refresh instead of leaving the player with an empty deck.
DO $restore_failed_culprits_refresh$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_old := $old_block$else
      update public.room_match_states m set
        pending_action=null,state_version=state_version+1,
        last_action_label=format('범인들의 범행 확인 결과 특징 [범인] 증거가 %s장으로 8장 미만입니다. 게임을 계속합니다.',v_culprit_count)
      where m.room_id=p_room_id;
    end if;$old_block$;

  v_new := $new_block$else
      -- Rebuild the declarer's deck from the current remove pile after the failed check.
      select * into v_game
        from public.room_player_game_states gs
        where gs.room_id=p_room_id and gs.user_id=v_owner_id
        for update;
      if not found then raise exception '범인들의 범행 리프레시: 선언 플레이어의 카드 영역을 찾을 수 없습니다.'; end if;

      select coalesce(jsonb_agg(e.value order by random()),'[]'::jsonb)
        into v_deck_new
        from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value);
      update public.room_player_game_states gs
        set deck_order=coalesce(v_deck_new,'[]'::jsonb),
            remove_cards='[]'::jsonb,
            updated_at=now()
        where gs.room_id=p_room_id and gs.user_id=v_owner_id;
      update public.room_player_turn_boards b
        set remove_count=0,updated_at=now()
        where b.room_id=p_room_id and b.user_id=v_owner_id;

      -- Preserve the refresh side effect: the opponent receives the new top card as evidence.
      select rp.user_id into v_other_user
        from public.room_players rp
        where rp.room_id=p_room_id and rp.user_id<>v_owner_id
        limit 1;
      if v_other_user is not null then
        select * into v_opponent_game
          from public.room_player_game_states gs
          where gs.room_id=p_room_id and gs.user_id=v_other_user
          for update;
        if jsonb_array_length(coalesce(v_opponent_game.deck_order,'[]'::jsonb))>0 then
          v_card := v_opponent_game.deck_order -> 0;
          select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.ordinality>1),'[]'::jsonb)
            into v_deck_new
            from jsonb_array_elements(v_opponent_game.deck_order) with ordinality e(value,ordinality);
          update public.room_player_game_states gs
            set deck_order=coalesce(v_deck_new,'[]'::jsonb),
                evidence_cards=coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card),
                updated_at=now()
            where gs.room_id=p_room_id and gs.user_id=v_other_user;
          update public.room_player_turn_boards b
            set evidence_count=jsonb_array_length(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb))+1,
                updated_at=now()
            where b.room_id=p_room_id and b.user_id=v_other_user;
        end if;
      end if;

      update public.room_match_states m set
        pending_action=null,state_version=state_version+1,
        last_action_label=format('범인들의 범행 확인 결과 특징 [범인] 증거는 %s장으로 8장 미만입니다. 게임을 계속하며 리프레시했습니다.',v_culprit_count)
      where m.room_id=p_room_id;
    end if;$new_block$;

  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'Failed culprit refresh patch stopped: expected failed-verification block not found.';
  END IF;
  v_definition := replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
  REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated;
END;
$restore_failed_culprits_refresh$;
