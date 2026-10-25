-- Runtime field cards are intentionally compact and often omit printed-card metadata.
-- ID:0301 is represented by card keys B03046 / B03046P, so detect those exact keys
-- before relying on numeric IDs or the full metadata fallback.
DO $patch$
DECLARE
  v_definition text;
  v_anchor text := 'where coalesce(nullif(ltrim(btrim(candidate.value), ''0''), ''''), ''0'') = ''301''';
  v_start integer;
  v_replacement text;
BEGIN
  SELECT replace(
    pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure),
    chr(13),
    ''
  ) INTO v_definition;

  v_start := position(v_anchor in v_definition);
  IF v_start = 0 THEN
    RAISE EXCEPTION 'Could not find the existing ID:0301 candidate normalization check.';
  END IF;

  v_replacement :=
    'where upper(btrim(coalesce(candidate.value, ''''))) IN (''B03046'',''B03046P'',''ID:0301'',''0301'') OR '
    || substring(v_anchor from 7);

  v_definition := overlay(
    v_definition placing v_replacement
    from v_start for length(v_anchor)
  );

  EXECUTE v_definition;
END
$patch$;
