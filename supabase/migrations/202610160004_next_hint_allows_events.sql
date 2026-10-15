-- Conan TCG: allow event plays during pending Next Hint without satisfying its character requirement.
-- Does not clear next_hint_pending when an event enters/resolves; the chosen character still ends Next Hint.

DO $next_hint_event_rules$
DECLARE
  v_definition text;
  v_action_block text;
  v_start integer;
  v_end integer;
  v_old_cost text := $old_cost$v_cost_limit := v_board.file_count + case when v_board.partner_assist_used then 1 else 0 end;$old_cost$;
  v_new_cost text := $new_cost$v_cost_limit := v_board.file_count
      + case when v_board.partner_assist_used then 1 else 0 end
      + case when coalesce(v_board.next_hint_pending,false) then 1 else 0 end;$new_cost$;
  v_delegate_anchor text := $delegate_anchor$v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));$delegate_anchor$;
  v_guard_anchor text := $guard_anchor$  if p_action = 'end_turn' and coalesce(v_board.next_hint_pending,false) then
    raise exception '넥스트 힌트로 가져온 캐릭터를 먼저 등장시켜야 턴을 종료할 수 있습니다.';
  end if;

  v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));$guard_anchor$;
  v_guard text := $guard$  if p_action = 'end_turn' and coalesce(v_board.next_hint_pending,false) then
    raise exception '넥스트 힌트로 가져온 캐릭터를 먼저 등장시켜야 턴을 종료할 수 있습니다.';
  end if;

  $guard$v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));$guard$;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  -- Patch event level calculation only inside the play_event block.
  v_start := position('if p_action = ''play_event'' then' in lower(v_definition));
  v_end := position('if p_action = ''finish_event'' then' in lower(v_definition));
  IF v_start = 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'next hint event migration stopped: could not isolate play_event action';
  END IF;
  v_action_block := substring(v_definition from v_start for v_end - v_start);

  IF position('case when coalesce(v_board.next_hint_pending,false) then 1 else 0 end' in lower(v_action_block)) = 0 THEN
    IF position(v_old_cost in v_action_block) = 0 THEN
      RAISE EXCEPTION 'next hint event migration stopped: event cost-limit anchor not found';
    END IF;
    v_action_block := replace(v_action_block, v_old_cost, v_new_cost);
    v_definition := substring(v_definition from 1 for v_start - 1)
      || v_action_block
      || substring(v_definition from v_end);
  END IF;

  -- End-turn must be rejected server-side until the pending Next Hint character is played.
  IF position(v_guard_anchor in v_definition) = 0 THEN
    IF position(v_delegate_anchor in v_definition) = 0 THEN
      RAISE EXCEPTION 'next hint event migration stopped: standard action delegate anchor not found';
    END IF;
    v_definition := replace(v_definition, v_delegate_anchor, v_guard);
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'next hint event migration stopped: action function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$next_hint_event_rules$;
