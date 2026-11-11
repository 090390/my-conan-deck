BEGIN;

-- ID:0796 Okiya Subaru's level-7 removal ability requires the source
-- character itself to already be rested or stunned, in addition to hand <= 2.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(
  SELECT coalesce(jsonb_agg(
    CASE
      WHEN d.value->>'effectId'='card-0796-activated-remove-level7'
        THEN jsonb_set(d.value,'{requiresRestedOrStunnedSource}','true'::jsonb,true)
      ELSE d.value
    END
    ORDER BY d.ordinality
  ),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
    WITH ORDINALITY d(value,ordinality)
),
updated_at=now()
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) e(value)
    WHERE e.value->>'effectId'='card-0796-activated-remove-level7'
  );

DO $verify$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.private_card_effect_catalog_v1 c,
         LATERAL jsonb_array_elements(c.definitions) d(value)
    WHERE c.catalog_id='main'
      AND d.value->>'effectId'='card-0796-activated-remove-level7'
      AND coalesce((d.value->>'requiresRestedOrStunnedSource')::boolean,false)
  ) THEN
    RAISE EXCEPTION 'ID0796 source-state requirement was not registered';
  END IF;
END
$verify$;

COMMIT;
