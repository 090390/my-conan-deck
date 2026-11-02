DO $migration$
DECLARE
  v_definition text;
  v_anchor text := $anchor$  if p_action = 'gain_evidence_from_deck' then$anchor$;
  v_insert text := $insert$  if p_action = 'gain_evidence_for_opponent_from_deck' then
    if v_match.pending_action is not null then
      raise exception '진행 중인 응답을 먼저 완료해 주세요.';
    end if;

    v_amount := coalesce(nullif(p_payload ->> 'count','')::integer,1);
    if v_amount < 1 or v_amount > 20 then
      raise exception '상대 증거 획득 장수는 1~20 사이로 지정해 주세요.';
    end if;

    select rp.user_id into v_other_user
      from public.room_players rp
      where rp.room_id=p_room_id and rp.user_id<>v_user
      limit 1;
    if v_other_user is null then
      raise exception '상대 플레이어를 찾을 수 없습니다.';
    end if;

    select * into v_opponent_game
      from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_other_user
      for update;
    if not found then
      raise exception '상대의 비공개 게임 상태를 찾을 수 없습니다.';
    end if;

    if jsonb_array_length(coalesce(v_opponent_game.deck_order,'[]'::jsonb)) < v_amount then
      raise exception '상대 덱에 증거로 가져올 카드가 부족합니다. 현재 %장입니다.',
        jsonb_array_length(coalesce(v_opponent_game.deck_order,'[]'::jsonb));
    end if;

    for v_i in 1..v_amount loop
      perform public.draw_private_turn_card(p_room_id,v_other_user,'evidence');
    end loop;

    update public.room_match_states m
      set state_version=state_version+1,
          last_action_label=format('수동 효과 처리: 상대가 자신의 덱 맨 위 카드 %s장을 증거 에이리어로 가져왔습니다.',v_amount)
      where m.room_id=p_room_id;

    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'gain_evidence_from_deck' then$insert$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position(v_anchor IN v_definition)=0 THEN
    RAISE EXCEPTION 'Expected evidence-draw insertion point was not found; refusing to patch an unexpected function version.';
  END IF;
  IF position('gain_evidence_for_opponent_from_deck' IN v_definition)>0 THEN
    RAISE EXCEPTION 'Opponent evidence action is already installed.';
  END IF;

  v_definition := replace(v_definition,v_anchor,v_insert);
  EXECUTE v_definition;
END;
$migration$;
