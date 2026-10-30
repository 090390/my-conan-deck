-- D11007 Matsuda Jinpei's contact-start discard/AP boost is once per turn.
update public.private_card_effect_catalog_v1 c
set definitions = (
  select jsonb_agg(
    case when d->>'effectId'='card-0938-contact-start-discard-for-ap-3000'
      then jsonb_set(d,'{oncePerTurn}','true'::jsonb,true)
      else d end
    order by ordinality
  )
  from jsonb_array_elements(c.definitions) with ordinality e(d,ordinality)
),
updated_at=now()
where c.catalog_id='main'
and exists (
 select 1 from jsonb_array_elements(c.definitions) d
 where d->>'effectId'='card-0938-contact-start-discard-for-ap-3000'
);
