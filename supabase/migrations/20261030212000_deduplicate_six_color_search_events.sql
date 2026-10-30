update public.private_card_effect_catalog_v1 c
set definitions = (
  select coalesce(jsonb_agg(e.value order by e.ordinality),'[]'::jsonb)
  from jsonb_array_elements(c.definitions) with ordinality e(value,ordinality)
  where e.value->>'effectId' not in (
    'card-0102-on-play-blue-search-deploy',
    'card-0116-on-play-green-search-deploy',
    'card-0144-on-play-red-search-deploy',
    'card-0381-on-play-black-search-deploy'
  )
),
updated_at=now()
where c.catalog_id='main'
and exists (
  select 1 from jsonb_array_elements(c.definitions) d
  where d->>'effectId' in (
    'card-0102-on-play-blue-search-deploy',
    'card-0116-on-play-green-search-deploy',
    'card-0144-on-play-red-search-deploy',
    'card-0381-on-play-black-search-deploy'
  )
);