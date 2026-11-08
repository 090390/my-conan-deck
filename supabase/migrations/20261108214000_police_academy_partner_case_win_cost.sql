-- The partner's 【事件解決】【スリープ】 ability consumes the partner
-- when it declares the winning case. Keep the same state transition as other
-- native partner actions, and reject it when already rested (guard is in prior migration).
DO $migration$
DECLARE
  v_function_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure
  ) INTO v_function_definition;

  v_old := $old$
   UPDATE public.room_match_states
   SET game_over=true,
       winner_user_id=v_user,
       winner_turn_number=v_match.turn_number,
       last_action_label='사건 해결 성공! 승리 선언이 완료되었습니다.',
       state_version=state_version+1
   WHERE room_id=p_room_id;
$old$;

  v_new := $new$
   -- P081's case-solving ability has a partner sleep cost. Record that cost
   -- before marking the match as won, just like partner assist/deduction.
   UPDATE public.room_player_turn_boards
      SET partner_rested=true, updated_at=now()
    WHERE room_id=p_room_id AND user_id=v_user;

   UPDATE public.room_match_states
   SET game_over=true,
       winner_user_id=v_user,
       winner_turn_number=v_match.turn_number,
       last_action_label='사건 해결 성공! 파트너를 슬립시키고 승리 선언이 완료되었습니다.',
       state_version=state_version+1
   WHERE room_id=p_room_id;
$new$;

  IF position(v_old IN v_function_definition) > 0 THEN
    v_function_definition := replace(v_function_definition, v_old, v_new);
    EXECUTE v_function_definition;
  ELSIF position('파트너를 슬립시키고 승리 선언이 완료되었습니다.' IN v_function_definition) = 0 THEN
    RAISE EXCEPTION 'solve_case 승리 처리의 파트너 슬립 반영 위치를 찾지 못했습니다.';
  END IF;
END
$migration$;
