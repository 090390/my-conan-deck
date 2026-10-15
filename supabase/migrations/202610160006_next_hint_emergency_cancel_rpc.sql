-- Conan TCG: expose emergency Next Hint recovery as a dedicated RPC.
-- This bypasses the legacy action dispatcher, which does not recognize custom action names.

CREATE OR REPLACE FUNCTION public.cancel_private_next_hint_v2(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $cancel_private_next_hint_v2$
DECLARE
  v_user uuid := auth.uid();
  v_match public.room_match_states%ROWTYPE;
  v_board public.room_player_turn_boards%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION '로그인한 플레이어만 넥스트 힌트를 응급 취소할 수 있습니다.';
  END IF;

  SELECT *
    INTO v_match
    FROM public.room_match_states
    WHERE room_id = p_room_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '게임 상태를 찾을 수 없습니다.';
  END IF;

  IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN
    RAISE EXCEPTION '현재 턴 플레이어만 넥스트 힌트를 응급 취소할 수 있습니다.';
  END IF;

  IF v_match.pending_action IS NOT NULL THEN
    RAISE EXCEPTION '진행 중인 응답을 먼저 완료해야 넥스트 힌트를 응급 취소할 수 있습니다.';
  END IF;

  SELECT *
    INTO v_board
    FROM public.room_player_turn_boards
    WHERE room_id = p_room_id
      AND user_id = v_user
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '플레이어의 턴 보드를 찾을 수 없습니다.';
  END IF;

  IF NOT COALESCE(v_board.next_hint_pending, false) THEN
    RAISE EXCEPTION '취소할 넥스트 힌트가 없습니다.';
  END IF;

  UPDATE public.room_player_turn_boards
    SET next_hint_pending = false,
        updated_at = now()
    WHERE room_id = p_room_id
      AND user_id = v_user;

  UPDATE public.room_match_states
    SET state_version = state_version + 1,
        last_action_label = '넥스트 힌트 응급 취소: 캐릭터 등장 의무를 해제했습니다. 가져온 파일 카드는 손패에 유지됩니다.'
    WHERE room_id = p_room_id;

  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$cancel_private_next_hint_v2$;

REVOKE ALL ON FUNCTION public.cancel_private_next_hint_v2(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_private_next_hint_v2(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.cancel_private_next_hint_v2(uuid) TO authenticated;
