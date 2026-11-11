BEGIN;
UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(
  SELECT coalesce(jsonb_agg(
    CASE
      WHEN d.value->>'effectId'='card-0894-file-five-sleep-deploy-miyano-family' THEN
        jsonb_set(
          d.value,
          '{steps,1,filter,allOf}',
          coalesce(d.value#>'{steps,1,filter,allOf}','[]'::jsonb)
            || jsonb_build_array(jsonb_build_object('field','level','operator','less_than_or_equal','value',7)),
          true
        )
      ELSE d.value
    END ORDER BY d.ordinality
  ),'[]'::jsonb)
  || CASE WHEN NOT EXISTS(
      SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) z(value)
      WHERE z.value->>'effectId'='card-1055-intrinsic-charge-character'
    )
    THEN jsonb_build_array(jsonb_build_object(
      'effectId','card-1055-intrinsic-charge-character',
      'cardIds',jsonb_build_array('1055'),
      'cardNameJa','宮野明美',
      'cardNameKo','미야노 아케미',
      'trigger',jsonb_build_object('event','continuous.recalculate','timing','continuous'),
      'continuous',true,
      'conditions','[]'::jsonb,
      'steps',jsonb_build_array(jsonb_build_object(
        'op','set_continuous_keyword','target','source_character',
        'keyword','charge_character',
        'modifierId','miyano-akemi-1055-intrinsic-charge-character',
        'duration','while_condition_true'
      ))
    ))
    ELSE '[]'::jsonb
  END
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
),
updated_at=now()
WHERE c.catalog_id='main';
COMMIT;
