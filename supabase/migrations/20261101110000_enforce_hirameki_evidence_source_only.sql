-- Hirameki effects are intrinsic to the card while it is in the Evidence Area.
-- They trigger only when that same card leaves Evidence for the Remove Area.
-- A card in the Field must never watch another card's evidence removal.

DO $migration$
DECLARE
  v_definition text;
  v_old text := '   v_scope:=coalesce(v_def->''trigger''->>''scope'',''source'');';
  v_new text := '   v_scope:=CASE WHEN p_trigger_event=''evidence.card_removed'' THEN ''source'' ELSE coalesce(v_def->''trigger''->>''scope'',''source'') END;';
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean)'::regprocedure
  ) INTO v_definition;

  IF position(v_new IN v_definition) = 0 THEN
    IF position(v_old IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not find effect trigger scope selection';
    END IF;
    v_definition := replace(v_definition, v_old, v_new);
    EXECUTE v_definition;
  END IF;

  UPDATE public.private_card_effect_catalog_v1
  SET definitions = (
    SELECT jsonb_agg(
      CASE
        WHEN e.value->'trigger'->>'event'='evidence.card_removed'
          THEN jsonb_set(e.value, '{trigger}', (e.value->'trigger') - 'scope')
        ELSE e.value
      END
      ORDER BY e.ordinality
    )
    FROM jsonb_array_elements(definitions) WITH ORDINALITY e(value, ordinality)
  ),
  updated_at = now()
  WHERE catalog_id = 'main'
    AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(definitions) e(value)
      WHERE e.value->'trigger'->>'event'='evidence.card_removed'
        AND e.value->'trigger' ? 'scope'
    );
END
$migration$;
