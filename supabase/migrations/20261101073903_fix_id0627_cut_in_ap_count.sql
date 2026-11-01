-- ID:0627's cut-in AP is 2000 per 犯人 card already in the remove area.
-- The cut-in card itself is still in hand while its effect is calculated, so it
-- must not be counted as an additional removed card.
DO $$
DECLARE
  v_oid oid;
  v_source text;
  v_old text := '2000 * (greatest(coalesce(v_count,0),0) + 1)';
  v_new text := '2000 * greatest(coalesce(v_count,0),0)';
BEGIN
  SELECT p.oid, pg_get_functiondef(p.oid)
    INTO v_oid, v_source
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'perform_private_turn_action_v2_legacy'
    AND pg_get_functiondef(p.oid) LIKE '%' || v_old || '%'
  ORDER BY p.oid DESC
  LIMIT 1;

  IF v_oid IS NULL THEN
    IF EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'perform_private_turn_action_v2_legacy'
        AND pg_get_functiondef(p.oid) LIKE '%' || v_new || '%'
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'ID0627 cut-in formula not found';
  END IF;

  EXECUTE replace(v_source, v_old, v_new);
END $$;
