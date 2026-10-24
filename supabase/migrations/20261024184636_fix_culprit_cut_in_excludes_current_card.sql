-- Count only the culprit cards already in the Remove area.
DO $patch$
DECLARE
  v_definition text;
  v_old text := 'v_bonus := 2000 * (greatest(coalesce(v_count,0),0) + 1);';
  v_new text := 'v_bonus := 2000 * greatest(coalesce(v_count,0),0);';
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
  INTO v_definition;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected AP bonus expression was not found.';
  END IF;
  EXECUTE v_definition;
END
$patch$;
