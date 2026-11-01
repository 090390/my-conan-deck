-- B03107 (Jin) has a win ability requiring evidence at least equal to the event level.
-- The current effect DSL does not yet model the event-level threshold, so leave
-- this effect unregistered rather than allowing an unconditional win.

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
