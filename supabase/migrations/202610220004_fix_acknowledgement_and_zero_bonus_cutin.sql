-- Repair the two guards that prevented the already-implemented private actions from running.
-- 1) acknowledge_culprits_crime must pass the standard action allowlist before its handler.
-- 2) choosing a cut-in is a usage decision, not conditional on AP increase or a persisted effect string.
DO $fix_private_acknowledgement_and_zero_bonus_cutin$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'perform_private_turn_action_v2 was not found.';
  END IF;

  v_old := $old_action_guard$if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime') then$old_action_guard$;
  v_new := $new_action_guard$if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime','acknowledge_culprits_crime') then$new_action_guard$;

  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Culprits acknowledgement action guard was not found; no changes applied.';
  END IF;

  v_old := $old_cutin_guard$if v_bonus < 1 and nullif(trim(v_card ->> 'cut_in_effect'),'') is null then raise exception '컷인 효과가 기록되지 않은 카드입니다.'; end if;$old_cutin_guard$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, '');
  ELSIF position('컷인 효과가 기록되지 않은 카드입니다.' IN v_definition) > 0 THEN
    RAISE EXCEPTION 'Cut-in effect guard was present in an unexpected form; no changes applied.';
  END IF;

  EXECUTE v_definition;
  REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated;
END;
$fix_private_acknowledgement_and_zero_bonus_cutin$;
