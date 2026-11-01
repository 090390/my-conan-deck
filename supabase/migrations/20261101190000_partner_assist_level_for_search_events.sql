-- Partner Assist raises the effective deployment level by one. Preserve the
-- literal file-count fact for every other card effect, and expose a dedicated
-- fact only to the six level-one color-search event deployments.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$ IF p_fact='player.file.count' THEN RETURN to_jsonb(coalesce(v_board.file_count,0)); END IF;$old$;
  v_new text := $new$ IF p_fact='player.file.count' THEN RETURN to_jsonb(coalesce(v_board.file_count,0)); END IF;
 IF p_fact='player.deployable_level' THEN
   RETURN to_jsonb(coalesce(v_board.file_count,0) + CASE WHEN coalesce(v_board.partner_assist_used,false) THEN 1 ELSE 0 END);
 END IF;$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure
  ) INTO v_definition;

  IF position('player.deployable_level' IN v_definition) = 0 THEN
    IF position(v_old IN v_definition) = 0 THEN
      RAISE EXCEPTION 'player.file.count fact branch not found in private_card_effect_fact_v1.';
    END IF;
    v_definition := replace(v_definition, v_old, v_new);
    EXECUTE v_definition;
  END IF;
END
$migration$;

-- Change only the deployment-level comparison in the six color-search events.
UPDATE public.private_card_effect_catalog_v1 catalog
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN definition.value->>'effectId' IN (
        'card-0102-on-play-diminutive-detective',
        'card-0116-on-play-omamori',
        'card-0130-on-play-ladies-gentlemen',
        'card-0144-on-play-mysterious-passenger',
        'card-0158-on-play-private-eye',
        'card-0381-on-play-shadow-of-karasuma'
      )
      THEN jsonb_set(
        definition.value,
        '{steps}',
        (
          SELECT jsonb_agg(
            CASE
              WHEN step.value->>'op' = 'select_cards'
                AND jsonb_typeof(step.value#>'{filter,allOf}') = 'array'
              THEN jsonb_set(
                step.value,
                '{filter,allOf}',
                (
                  SELECT jsonb_agg(
                    CASE
                      WHEN condition.value->>'field' = 'level'
                        AND condition.value->'value'->>'fact' = 'player.file.count'
                      THEN jsonb_set(
                        condition.value,
                        '{value,fact}',
                        to_jsonb('player.deployable_level'::text),
                        true
                      )
                      ELSE condition.value
                    END
                    ORDER BY condition.ordinality
                  )
                  FROM jsonb_array_elements(step.value#>'{filter,allOf}')
                    WITH ORDINALITY condition(value, ordinality)
                ),
                true
              )
              ELSE step.value
            END
            ORDER BY step.ordinality
          )
          FROM jsonb_array_elements(definition.value->'steps')
            WITH ORDINALITY step(value, ordinality)
        ),
        true
      )
      ELSE definition.value
    END
    ORDER BY definition.ordinality
  )
  FROM jsonb_array_elements(catalog.definitions)
    WITH ORDINALITY definition(value, ordinality)
),
updated_at = now()
WHERE catalog.catalog_id = 'main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(catalog.definitions) definition(value)
    WHERE definition.value->>'effectId' IN (
      'card-0102-on-play-diminutive-detective',
      'card-0116-on-play-omamori',
      'card-0130-on-play-ladies-gentlemen',
      'card-0144-on-play-mysterious-passenger',
      'card-0158-on-play-private-eye',
      'card-0381-on-play-shadow-of-karasuma'
    )
  );
