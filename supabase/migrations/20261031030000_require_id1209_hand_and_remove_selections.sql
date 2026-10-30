-- ID 1209: require one hand selection and one different Remove selection.
UPDATE public.private_card_effect_catalog_v1 AS catalog
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN definition.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove' THEN
        jsonb_set(
          definition.value,
          '{steps}',
          (
            SELECT jsonb_agg(
              CASE step.ordinality
                WHEN 4 THEN step.value || jsonb_build_object(
                  'min', 1,
                  'max', 1,
                  'optional', false,
                  'prompt', '공개한 카드 3장 중 손패에 넣을 카드 1장을 반드시 선택하세요.'
                )
                WHEN 6 THEN step.value || jsonb_build_object(
                  'min', 1,
                  'max', 1,
                  'optional', false,
                  'prompt', '손패에 넣은 카드와 다른 카드 1장을 리무브 에이리어로 반드시 선택하세요.'
                )
                ELSE step.value
              END
              ORDER BY step.ordinality
            )
            FROM jsonb_array_elements(definition.value->'steps') WITH ORDINALITY AS step(value, ordinality)
          ),
          true
        )
      ELSE definition.value
    END
    ORDER BY definition.ordinality
  )
  FROM jsonb_array_elements(catalog.definitions) WITH ORDINALITY AS definition(value, ordinality)
),
updated_at = now()
WHERE catalog.catalog_id = 'main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(catalog.definitions) candidate(value)
    WHERE candidate.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove'
  );

DO $$
DECLARE
  v_definition jsonb;
  v_count integer;
BEGIN
  SELECT d.value INTO v_definition
  FROM public.private_card_effect_catalog_v1 c
  CROSS JOIN LATERAL jsonb_array_elements(c.definitions) d(value)
  WHERE c.catalog_id = 'main'
    AND d.value->>'effectId' = 'card-1209-on-enter-reveal-three-hand-remove';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'ID 1209 effect definition not found';
  END IF;

  IF (v_definition#>>'{steps,3,min}')::integer <> 1
     OR (v_definition#>>'{steps,3,max}')::integer <> 1
     OR coalesce((v_definition#>>'{steps,3,optional}')::boolean, true)
     OR (v_definition#>>'{steps,5,min}')::integer <> 1
     OR (v_definition#>>'{steps,5,max}')::integer <> 1
     OR coalesce((v_definition#>>'{steps,5,optional}')::boolean, true) THEN
    RAISE EXCEPTION 'ID 1209 mandatory hand/remove selection validation failed';
  END IF;

  SELECT jsonb_array_length(v_definition->'steps') INTO v_count;
  IF v_count <> 10 THEN
    RAISE EXCEPTION 'ID 1209 effect step count changed unexpectedly: %', v_count;
  END IF;
END $$;
