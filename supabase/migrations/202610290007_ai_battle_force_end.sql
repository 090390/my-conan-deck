-- Allow the human player in an AI battle to end it immediately,
-- even while a modal or pending response would block normal turn actions.
CREATE OR REPLACE FUNCTION public.force_end_private_ai_battle_v1(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_force_ended boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  SELECT * INTO v_battle
  FROM public.private_ai_battles
  WHERE room_id = p_room_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI 대전 정보를 찾을 수 없습니다.';
  END IF;
  IF v_battle.human_user_id IS DISTINCT FROM v_user THEN
    RAISE EXCEPTION '이 AI 대전을 강제 종료할 권한이 없습니다.';
  END IF;

  SELECT * INTO v_match
  FROM public.room_match_states
  WHERE room_id = p_room_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI 대전 상태를 찾을 수 없습니다.';
  END IF;

  IF NOT v_match.game_over THEN
    UPDATE public.room_match_states
    SET game_over = true,
        winner_user_id = NULL,
        pending_action = NULL,
        cancel_requested_by = '{}'::uuid[],
        current_turn_user_id = NULL,
        state_version = state_version + 1,
        last_action_label = '모의전 취소 완료: AI 대전을 강제 종료하고 로비로 돌아갔습니다.'
    WHERE room_id = p_room_id;
    v_force_ended := true;
  END IF;

  -- Do not let a stale worker lock delay another attempt or keep an abandoned match busy.
  UPDATE public.private_ai_battles
  SET worker_locked_until = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object(
    'room_id', p_room_id,
    'game_over', true,
    'force_ended', v_force_ended,
    'already_ended', NOT v_force_ended
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.force_end_private_ai_battle_v1(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.force_end_private_ai_battle_v1(uuid) TO authenticated;
