BEGIN;

-- Any selector feeding rest_cards must target an active character.
-- Keep existing card-type/trait/controller filters and add is_active=true.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb)) r(value)
        JOIN jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb)) s(value)
          ON s.value->>'op'='select_cards'
         AND s.value->>'saveAs'=regexp_replace(coalesce(r.value->>'target',''), '^vars\.', '')
        WHERE r.value->>'op'='rest_cards'
          AND s.value->>'from' IN ('field','own_field','self_field','opponent_field','both_fields')
          AND NOT (
            coalesce(s.value->'filter'->'allOf','[]'::jsonb)
              @> '[{"field":"is_active","operator":"equals","value":true}]'::jsonb
            OR (
              s.value->'filter'->>'field'='is_active'
              AND s.value->'filter'->>'operator'='equals'
              AND s.value->'filter'->>'value'='true'
            )
          )
      ) THEN jsonb_set(
        e.value,
        '{steps}',
        (
          SELECT jsonb_agg(
            CASE
              WHEN s.value->>'op'='select_cards'
               AND s.value->>'from' IN ('field','own_field','self_field','opponent_field','both_fields')
               AND EXISTS (
                 SELECT 1
                 FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb)) r(value)
                 WHERE r.value->>'op'='rest_cards'
                   AND regexp_replace(coalesce(r.value->>'target',''), '^vars\.', '')=coalesce(s.value->>'saveAs','')
               )
               AND NOT (
                 coalesce(s.value->'filter'->'allOf','[]'::jsonb)
                   @> '[{"field":"is_active","operator":"equals","value":true}]'::jsonb
                 OR (
                   s.value->'filter'->>'field'='is_active'
                   AND s.value->'filter'->>'operator'='equals'
                   AND s.value->'filter'->>'value'='true'
                 )
               )
              THEN
                CASE
                  WHEN jsonb_typeof(s.value->'filter'->'allOf')='array'
                  THEN jsonb_set(
                    s.value,
                    '{filter,allOf}',
                    coalesce(s.value->'filter'->'allOf','[]'::jsonb)
                      || jsonb_build_array(jsonb_build_object('field','is_active','operator','equals','value',true)),
                    true
                  )
                  ELSE jsonb_set(
                    s.value,
                    '{filter}',
                    jsonb_build_object(
                      'allOf',
                      jsonb_build_array(
                        coalesce(s.value->'filter','{}'::jsonb),
                        jsonb_build_object('field','is_active','operator','equals','value',true)
                      )
                    ),
                    true
                  )
                END
              ELSE s.value
            END ORDER BY s.ordinality
          )
          FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb))
            WITH ORDINALITY s(value,ordinality)
        ),
        true
      )
      ELSE e.value
    END ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(value,ordinality)
)
WHERE c.catalog_id='main';

COMMIT;
