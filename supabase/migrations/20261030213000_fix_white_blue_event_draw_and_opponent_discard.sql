DO $migration$
DECLARE v_defs jsonb;
BEGIN
  SELECT definitions INTO v_defs
  FROM public.private_card_effect_catalog_v1
  WHERE catalog_id='main'
  FOR UPDATE;

  v_defs := (
    SELECT jsonb_agg(
      CASE
        WHEN d.value->>'effectId'='card-1215-on-play-detective-kid-cycle'
          THEN jsonb_set(d.value,'{steps,0,amount}','2'::jsonb,true)
        WHEN d.value->>'effectId'='card-1261-conan-vs-kid-case-effect'
          THEN jsonb_set(
            d.value,'{steps,6,when,allOf}',
            (
              SELECT jsonb_agg(cond.value ORDER BY cond.ordinality)
              FROM jsonb_array_elements(coalesce(d.value#>'{steps,6,when,allOf}','[]'::jsonb))
                   WITH ORDINALITY cond(value,ordinality)
              WHERE NOT (
                cond.value->>'fact'='vars.returned.count'
                AND cond.value->>'operator'='greater_than'
                AND cond.value->>'value'='0'
              )
            ),true
          )
        ELSE d.value
      END
      ORDER BY d.ordinality
    )
    FROM jsonb_array_elements(v_defs) WITH ORDINALITY d(value,ordinality)
  );
  UPDATE public.private_card_effect_catalog_v1
  SET definitions=v_defs, updated_at=now()
  WHERE catalog_id='main';
END
$migration$;
