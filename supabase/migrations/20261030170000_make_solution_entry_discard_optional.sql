-- Optional hand discard on solution entry must not block the entire turn when the hand is empty.
update public.private_card_effect_catalog_v1 c
set definitions = (
  select jsonb_agg(
    case when d->>'effectId' in (
      'card-1139-case-solution-discard-hand',
      'card-1261-case-solution-discard-hand'
    ) then
      jsonb_set(
        jsonb_set(d, '{steps,0,min}', '0'::jsonb, true),
        '{steps,0,optional}', 'true'::jsonb, true
      )
    else d end
    order by ordinality
  )
  from jsonb_array_elements(c.definitions) with ordinality e(d, ordinality)
),
updated_at = now()
where c.catalog_id = 'main'
  and exists (
    select 1 from jsonb_array_elements(c.definitions) d
    where d->>'effectId' in (
      'card-1139-case-solution-discard-hand',
      'card-1261-case-solution-discard-hand'
    )
  );
