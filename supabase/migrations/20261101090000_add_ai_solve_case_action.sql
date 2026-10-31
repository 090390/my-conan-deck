-- Add solve_case support to the v2 action handler used by both human and AI battles.
-- Generic cases require 7 evidence for the first player and 6 for the second.
-- Conan vs Kid keeps its case-specific 8/7 evidence threshold.
DO $patch$
DECLARE
  v_definition text;
  v_anchor text := ' IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION ''이 방의 참가자가 아닙니다.'';
 END IF;

 IF p_action=''activate_case_effect'' THEN';
  v_insertion text := ' IF p_action=''solve_case'' THEN
   SELECT * INTO v_match
   FROM public.room_match_states
   WHERE room_id=p_room_id
   FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>''playing'' OR v_match.game_over THEN
     RAISE EXCEPTION ''진행 중인 게임에서만 사건을 해결할 수 있습니다.'';
   END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user
      OR coalesce(v_match.turn_step,'''')<>''main'' THEN
     RAISE EXCEPTION ''자신의 메인 단계에서만 사건을 해결할 수 있습니다.'';
   END IF;
   IF v_match.pending_action IS NOT NULL
      OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION ''진행 중인 선택/응답을 먼저 완료해 주세요.'';
   END IF;
   SELECT * INTO v_new_board
   FROM public.room_player_turn_boards
   WHERE room_id=p_room_id AND user_id=v_user
   FOR UPDATE;
   IF NOT FOUND THEN
     RAISE EXCEPTION ''자신의 보드를 찾을 수 없습니다.'';
   END IF;
   IF coalesce(v_new_board.case_phase,v_match.case_phase,''incident'')<>''solution'' THEN
     RAISE EXCEPTION ''해결편에서만 사건을 해결할 수 있습니다.'';
   END IF;
   v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''''),''[^A-Za-z0-9]'','''',''g''));
   IF v_case_key IN (''B11098'',''B11098P'',''1261'')
      OR coalesce(v_new_board.event_rule_code,'''')=''conan_vs_kid_1261'' THEN
     IF v_match.first_player_user_id=v_user THEN
       IF coalesce(v_new_board.evidence_count,0)<8 THEN
         RAISE EXCEPTION ''이 사건의 해결에는 증거 8장이 필요합니다. 현재 %장입니다.'',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     ELSE
       IF coalesce(v_new_board.evidence_count,0)<7 THEN
         RAISE EXCEPTION ''이 사건의 해결에는 증거 7장이 필요합니다. 현재 %장입니다.'',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     END IF;
   ELSE
     IF v_match.first_player_user_id=v_user THEN
       IF coalesce(v_new_board.evidence_count,0)<7 THEN
         RAISE EXCEPTION ''사건 해결에는 증거 7장이 필요합니다. 현재 %장입니다.'',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     ELSE
       IF coalesce(v_new_board.evidence_count,0)<6 THEN
         RAISE EXCEPTION ''사건 해결에는 증거 6장이 필요합니다. 현재 %장입니다.'',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     END IF;
   END IF;
   UPDATE public.room_match_states
   SET game_over=true,
       winner_user_id=v_user,
       winner_turn_number=v_match.turn_number,
       last_action_label=''사건 해결 성공! 승리 선언이 완료되었습니다.'',
       state_version=state_version+1
   WHERE room_id=p_room_id;
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

';
  v_target text := ' IF p_action=''activate_case_effect'' THEN';
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='perform_private_turn_action_v2'
    AND pg_get_function_identity_arguments(p.oid)='p_room_id uuid, p_action text, p_payload jsonb';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'perform_private_turn_action_v2를 찾을 수 없습니다.';
  END IF;
  IF position(' IF p_action=''solve_case'' THEN' in v_definition)>0 THEN
    RAISE NOTICE 'perform_private_turn_action_v2 already supports solve_case.';
    RETURN;
  END IF;
  IF position(v_anchor in v_definition)=0 THEN
    RAISE EXCEPTION 'solve_case 패치 기준 구문을 찾지 못했습니다.';
  END IF;
  IF length(v_definition)-length(replace(v_definition,v_anchor,'')) <> length(v_anchor) THEN
    RAISE EXCEPTION 'solve_case 패치 기준 구문이 중복되어 있습니다.';
  END IF;

  v_definition:=replace(v_definition,v_anchor,
    replace(v_anchor,v_target,'') || v_insertion || v_target);
  EXECUTE v_definition;
END
$patch$;
