-- ID:0627 counts its own cut-in card in addition to 犯人 cards already in the remove area.
-- Jin (B03107) has an "event level" threshold that is not yet modeled by the rules engine.
-- Remove that unverified win action until the event-level rule has been confirmed.

DO $migration$
DECLARE
  v_oid oid;
  v_source text;
  v_wrong text := '2000 * greatest(coalesce(v_count,0),0)';
  v_correct text := '2000 * (greatest(coalesce(v_count,0),0) + 1)';
BEGIN
  SELECT p.oid, pg_get_functiondef(p.oid)
    INTO v_oid, v_source
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='perform_private_turn_action_v2_legacy'
  ORDER BY p.oid DESC
  LIMIT 1;

  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'ID0627 cut-in action function was not found.';
  END IF;

  IF position(v_correct IN v_source)=0 THEN
    IF position(v_wrong IN v_source)=0 THEN
      RAISE EXCEPTION 'ID0627 cut-in formula was not found in the expected form.';
    END IF;
    v_source := replace(v_source, v_wrong, v_correct);
    EXECUTE v_source;
  END IF;
END
$migration$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT coalesce(jsonb_agg(d.value ORDER BY d.ordinality), '[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
    WITH ORDINALITY d(value,ordinality)
  WHERE d.value->>'effectId' IS DISTINCT FROM 'partner-B03107-culprit-case-win'
)
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
    WHERE d.value->>'effectId'='partner-B03107-culprit-case-win'
  );
