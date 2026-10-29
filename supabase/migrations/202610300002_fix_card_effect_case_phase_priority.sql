-- Case phase is player-specific in this game, so prefer the acting player's board value.
DO $patch_case_phase_fact$
DECLARE
  v_definition text;
  v_old text := $old$coalesce(v_match.case_phase,v_board.case_phase,'incident')$old$;
  v_new text := $new$coalesce(v_board.case_phase,v_match.case_phase,'incident')$new$;
BEGIN
  v_definition := pg_get_functiondef(
    'public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure
  );
  IF position(v_old in v_definition)>0 THEN
    v_definition := replace(v_definition,v_old,v_new);
    EXECUTE v_definition;
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'case phase fact anchor not found';
  END IF;
END
$patch_case_phase_fact$;
