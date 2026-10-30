-- Field-watch effects may react to evidence.card_removed as well as character entry.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$     IF p_trigger_event<>'character.entered_field' THEN CONTINUE; END IF;$old$;
  v_replacement := $new$     IF p_trigger_event NOT IN ('character.entered_field','evidence.card_removed') THEN CONTINUE; END IF;$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'field-watch trigger event guard anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;
  EXECUTE v_definition;
END
$migration$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE WHEN d->>'effectId' IN (
      'card-0704-hirameki-rest-character',
      'card-1134-hirameki-draw-one'
    ) THEN
      jsonb_set(
        d,
        '{trigger,scope}',
        to_jsonb('field_watch'::text),
        true
      )
    ELSE d END
    ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(d,ordinality)
)
WHERE c.catalog_id='main'
AND EXISTS (
  SELECT 1 FROM jsonb_array_elements(c.definitions) d
  WHERE d->>'effectId' IN (
    'card-0704-hirameki-rest-character',
    'card-1134-hirameki-draw-one'
  )
);
