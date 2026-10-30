-- ID 1209: require the hand and remove selections before returning the remaining card(s) to deck bottom.
UPDATE public.private_card_effect_catalog_v1 AS catalog
SET definitions = (
  SELECT jsonb_agg(
    CASE WHEN definition.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove' THEN
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(definition.value, '{steps,3,min}', '1'::jsonb, true),
            '{steps,3,max}', '1'::jsonb, true
          ),
          '{steps,3,optional}', 'false'::jsonb, true
        ),
        '{steps,5,min}', '1'::jsonb, true
      ) || jsonb_build_object(
        'steps',
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(definition.value->'steps', '{3,min}', '1'::jsonb, true),
              '{3,max}', '1'::jsonb, true
            ),
            '{3,optional}', 'false'::jsonb, true
          ),
          '{3,prompt}', to_jsonb('공개한 카드 3장 중 손패에 넣을 카드 1장을 반드시 선택하세요.'::text), true
        )
      )
    ELSE definition.value END
    ORDER BY definition.ordinality
  )
  FROM jsonb_array_elements(catalog.definitions) WITH ORDINALITY AS definition(value, ordinality)
)
, updated_at = now()
WHERE catalog.catalog_id = 'main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(catalog.definitions) candidate(value)
    WHERE candidate.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove'
  );

-- Apply the second mandatory one-card removal step separately, preserving the rest of the definition.
UPDATE public.private_card_effect_catalog_v1 AS catalog
SET definitions = (
  SELECT jsonb_agg(
    CASE WHEN definition.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove' THEN
      jsonb_set(
        jsonb_set(
          jsonb_set(definition.value, '{steps,5,min}', '1'::jsonb, true),
          '{steps,5,max}', '1'::jsonb, true
        ),
        '{steps,5,optional}', 'false'::jsonb, true
      ) || jsonb_build_object(
        'steps',
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
                jsonb_set(definition.value->'steps', '{3,min}', '1'::jsonb, true),
                '{3,max}', '1'::jsonb, true
              ),
              '{3,optional}', 'false'::jsonb, true
            ),
            '{5,min}', '1'::jsonb, true
          ),
          '{5,max}', '1'::jsonb, true
        )
      )
    ELSE definition.value END
    ORDER BY definition.ordinality
  )
  FROM jsonb_array_elements(catalog.definitions) WITH ORDINALITY AS definition(value, ordinality)
)
, updated_at = now()
WHERE catalog.catalog_id = 'main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(catalog.definitions) candidate(value)
    WHERE candidate.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove'
  );

DO $$
DECLARE v_definition jsonb;
BEGIN
  SELECT value INTO v_definition
  FROM public.private_card_effect_catalog_v1 c,
       jsonb_array_elements(c.definitions) d(value)
  WHERE c.catalog_id='main'
    AND d.value->>'effectId'='card-1209-on-enter-reveal-three-hand-remove';

  IF v_definition IS NULL
     OR (v_definition#>>'{steps,3,min}')::integer <> 1
     OR (v_definition#>>'{steps,3,max}')::integer <> 1
     OR coalesce((v_definition#>>'{steps,3,optional}')::boolean,true)
     OR (v_definition#>>'{steps,5,min}')::integer <> 1
     OR (v_definition#>>'{steps,5,max}')::integer <> 1
     OR coalesce((v_definition#>>'{steps,5,optional}')::boolean,true) THEN
    RAISE EXCEPTION 'ID 1209 mandatory hand/remove selection validation failed';
  END IF;
END $$;
