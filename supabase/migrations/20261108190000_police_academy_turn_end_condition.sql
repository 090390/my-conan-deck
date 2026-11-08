UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN e.value->>'effectId' = 'card-1121-bond-furuya-end-turn-recover-police'
       AND NOT coalesce(e.value->'conditions','[]'::jsonb) @>
          '[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true}]'::jsonb
      THEN jsonb_set(
        e.value,
        '{conditions}',
        coalesce(e.value->'conditions','[]'::jsonb)
          || '[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true}]'::jsonb,
        true
      )
      ELSE e.value
    END
    ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
       WITH ORDINALITY e(value,ordinality)
),
updated_at = now()
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
    WHERE d.value->>'effectId'='card-1121-bond-furuya-end-turn-recover-police'
  );
