update public.private_card_effect_catalog_v1 c
set definitions = (
  select jsonb_agg(
    case
      when d->>'effectId' in (
        'card-0703-activated-investigate-one',
        'card-0704-activated-opponent-evidence-and-character'
      ) then jsonb_set(d, '{oncePerTurn}', 'true'::jsonb, true)
      when d->>'effectId'='card-0732-activated-deploy-tokyo-police-temporary-charge-return'
        then jsonb_set(d, '{activationTiming}', '"turn"'::jsonb, true)
      else d
    end
    order by ordinality
  )
  from jsonb_array_elements(c.definitions) with ordinality e(d,ordinality)
),
updated_at=now()
where c.catalog_id='main'
and exists (
  select 1 from jsonb_array_elements(c.definitions) d
  where d->>'effectId' in (
    'card-0703-activated-investigate-one',
    'card-0704-activated-opponent-evidence-and-character',
    'card-0732-activated-deploy-tokyo-police-temporary-charge-return'
  )
);