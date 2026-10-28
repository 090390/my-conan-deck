-- The runtime iterates the catalog as an array, so unwrap the checked-in
-- envelope ({ schemaVersion, language, definitions }) for catalogs already seeded.
UPDATE public.private_card_effect_catalog_v1
SET definitions = definitions->'definitions',
    updated_at = now()
WHERE catalog_id = 'main'
  AND jsonb_typeof(definitions) = 'object'
  AND jsonb_typeof(definitions->'definitions') = 'array';

DO $check$
DECLARE
  v_definitions jsonb;
BEGIN
  SELECT definitions INTO v_definitions
  FROM public.private_card_effect_catalog_v1
  WHERE catalog_id = 'main';

  IF v_definitions IS NULL OR jsonb_typeof(v_definitions) <> 'array' THEN
    RAISE EXCEPTION 'Card effect catalog must be a JSON array; got %', jsonb_typeof(v_definitions);
  END IF;
END
$check$;
