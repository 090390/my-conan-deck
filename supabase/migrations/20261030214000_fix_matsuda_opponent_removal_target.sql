update public.private_card_effect_catalog_v1 c
set definitions = (
  select jsonb_agg(
    case
      when d->>'effectId'='card-0808-activated-partner-yellow-file5-police-bottom-remove'
      then jsonb_set(
        d,
        '{steps,3,from}',
        '"opponent_field"'::jsonb,
        true
      )
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
  where d->>'effectId'='card-0808-activated-partner-yellow-file5-police-bottom-remove'
);