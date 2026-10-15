-- Conan TCG: emergency recovery when a player declares Next Hint but cannot play a character.
-- This is not a normal game action. It only clears the forced character-play requirement:
-- the file card already taken stays in hand, Next Hint remains used, and prior actions are not rolled back.

DO $next_hint_emergency_cancel$
DECLARE
  v_definition text;
  v_delegate_anchor text := $delegate_anchor$v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));$delegate_anchor$;
  v_cancel_marker text := $cancel_marker$if p_action = 'cancel_next_hint' then$cancel_marker$;
  v_cancel_block text := $cancel_block$  if p_action = 'cancel_next_hint' then
    if v_match.pending_action is not null then
      raise exception '진행 중인 응답을 먼저 완료해야 넥스트 힌트를 응급 취소할 수 있습니다.';
    end if;
    if not coalesce(v_board.next_hint_pending,false) then
      raise exception '취소할 넥스트 힌트가 없습니다.';
    end if;

    update public.room_player_turn_boards b
      set next_hint_pending=false, updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;
    if not found then
      raise exception '넥스트 힌트 상태를 갱신하지 못했습니다.';
    end if;

    update public.room_match_states m
      set state_version=state_version+1,
          last_action_label='넥스트 힌트 응급 취소: 캐릭터 등장 의무를 해제했습니다. 가져온 파일 카드는 손패에 유지됩니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

$cancel_block$;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  IF position(lower(v_cancel_marker) in lower(v_definition)) = 0 THEN
    IF position(v_delegate_anchor in v_definition) = 0 THEN
      RAISE EXCEPTION 'next hint emergency cancel migration stopped: standard action delegate anchor not found';
    END IF;
    v_definition := replace(v_definition, v_delegate_anchor, v_cancel_block || v_delegate_anchor);
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'next hint emergency cancel migration stopped: action function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$next_hint_emergency_cancel$;
