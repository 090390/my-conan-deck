-- ID0627 counts itself because using the cut-in moves this card to the remove area.
-- v_count is the number of 犯人 cards already in the remove area before the cut-in is paid.
DO $$
DECLARE
  v_oid oid;
  v_source text;
  v_old text := '2000 * greatest(coalesce(v_count,0),0)';
  v_new text := '2000 * (greatest(coalesce(v_count,0),0) + 1)';
BEGIN
  SELECT p.oid, pg_get_functiondef(p.oid)
    INTO v_oid, v_source
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prokind = 'f'
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
        AND p.prokind = 'f'
        AND p.proname = 'perform_private_turn_action_v2_legacy'
        AND pg_get_functiondef(p.oid) LIKE '%' || v_new || '%'
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'ID0627 cut-in AP formula was not found; expected current expression is missing';
  END IF;

  EXECUTE replace(v_source, v_old, v_new);
END $$;