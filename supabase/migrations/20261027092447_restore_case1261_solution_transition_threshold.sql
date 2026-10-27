DO $patch$
DECLARE
  v_definition text;
  v_solve_pos integer;
  v_before text;
  v_after text;
  v_simple_threshold text := $threshold$v_count := case when v_match.first_player_user_id=v_user then 7 else 6 end;$threshold$;
  v_special_threshold text := $threshold$v_count := case
      when coalesce(v_board.event_rule_code, '') = 'conan_vs_kid_1261'
        or coalesce(nullif(ltrim(v_culprit_key, '0'), ''), '0') in ('1261','11098')
        then case when v_match.first_player_user_id=v_user then 8 else 7 end
      else case when v_match.first_player_user_id=v_user then 7 else 6 end
    end;$threshold$;
BEGIN
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  v_solve_pos := position('if p_action = ''solve_case'' then' in v_definition);
  IF v_solve_pos = 0 THEN RAISE EXCEPTION 'solve_case block not found'; END IF;
  v_before := substring(v_definition from 1 for v_solve_pos - 1);
  v_after := substring(v_definition from v_solve_pos);
  IF position(v_special_threshold in v_before) = 0 THEN
    RAISE EXCEPTION 'special threshold not found in the pre-solve transition block';
  END IF;
  IF position(v_special_threshold in v_after) = 0 THEN
    RAISE EXCEPTION 'special solve threshold not found after solve_case';
  END IF;
  v_before := replace(v_before, v_special_threshold, v_simple_threshold);
  v_definition := v_before || v_after;
  EXECUTE v_definition;
END;
$patch$;
