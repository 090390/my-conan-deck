-- Add the evidence face-down count fact used by PR320's case ability.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure)
    INTO v_definition;
  v_old := $old$ IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_board.case_phase,'incident'));
 END IF;$old$;
  v_new := $new$ IF p_fact='player.evidence.facedown_count' THEN
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) e(value)
   WHERE NOT coalesce(nullif(e.value->>'face_up','')::boolean,false);
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_board.case_phase,'incident'));
 END IF;$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('player.evidence.facedown_count' IN v_definition)=0 THEN
      RAISE EXCEPTION 'Evidence facedown-count fact insertion point was not found.';
    END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;
  EXECUTE v_definition;
END
$migration$;
