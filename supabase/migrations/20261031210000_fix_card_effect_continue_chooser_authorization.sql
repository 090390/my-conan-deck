-- Card effect continuation must authorize against the authoritative
-- chooser in room_match_states.pending_action, not the duplicated chooser
-- field in private_card_effect_runs_v1.waiting.
--
-- waiting contains the effect step and candidate list. pending_action is the
-- state machine's source of truth for who may submit the response.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$IF coalesce(v_wait->>'chooser_user_id','')<>v_user::text THEN RAISE EXCEPTION '현재 카드 효과 선택 차례가 아닙니다.'; END IF;$old$;
  v_new text := $new$IF v_pending IS NULL
    OR coalesce(v_pending->>'chooser_user_id','') IS DISTINCT FROM v_user::text THEN
   RAISE EXCEPTION '현재 카드 효과 선택 차례가 아닙니다.';
 END IF;$new$;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_continue_v1(uuid,jsonb)'::regprocedure)
    INTO v_definition;

  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION '기존 카드 효과 선택자 검사 코드를 찾을 수 없습니다.';
  END IF;

  v_definition := replace(v_definition,v_old,v_new);
  -- pg_get_functiondef omits the final PL/pgSQL block semicolon in prosrc.
  v_definition := replace(v_definition,E'END\n$function$',E'END;\n$function$');
  v_definition := v_definition || ';';
  EXECUTE v_definition;
END;
$migration$;
