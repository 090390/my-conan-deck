-- Use the canonical four-digit Conan card ID for rules-engine lookups.
-- Detailed printing IDs (B06084, PR237, etc.), DB row IDs, card numbers and keys
-- remain metadata and must never be interpreted as effect identity.

CREATE OR REPLACE FUNCTION public.private_card_effect_internal_id_v1(p_card jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT candidate.canonical_id
  FROM unnest(ARRAY[
    p_card ->> 'internal_card_id', p_card ->> 'internalCardId',
    p_card ->> 'id_code', p_card ->> 'idCode', p_card ->> 'cardId',
    p_card #>> '{sourceData,internal_card_id}', p_card #>> '{sourceData,internalCardId}',
    p_card #>> '{sourceData,id_code}', p_card #>> '{sourceData,idCode}',
    p_card #>> '{sourceData,card_id}', p_card #>> '{sourceData,cardId}',
    p_card #>> '{raw,internal_card_id}', p_card #>> '{raw,internalCardId}',
    p_card #>> '{raw,id_code}', p_card #>> '{raw,idCode}', p_card #>> '{raw,cardId}',
    p_card #>> '{raw,sourceData,internal_card_id}', p_card #>> '{raw,sourceData,internalCardId}',
    p_card #>> '{raw,sourceData,card_id}', p_card #>> '{raw,sourceData,cardId}'
  ]) WITH ORDINALITY AS candidate(value, ordinality)
  CROSS JOIN LATERAL (
    SELECT regexp_replace(upper(trim(coalesce(candidate.value, ''))),
      '^ID[[:space:]]*:[[:space:]]*', '') AS canonical_id
  ) normalized
  WHERE normalized.canonical_id ~ '^[0-9]{4}$'
  ORDER BY candidate.ordinality
  LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_matches_id_v1(p_card jsonb, p_card_ids jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(coalesce(p_card_ids, '[]'::jsonb)) ids(id)
    WHERE ids.id ~ '^[0-9]{4}$'
      AND public.private_card_effect_internal_id_v1(p_card) = ids.id
  )
$function$;

CREATE OR REPLACE FUNCTION public.enrich_turn_card_instances(p_cards jsonb, p_main_deck jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT coalesce(jsonb_agg(
    c.card || jsonb_strip_nulls(jsonb_build_object(
      'card_type', coalesce(nullif(d.value ->> 'card_type', ''), nullif(c.card ->> 'card_type', ''), 'unknown'),
      'internal_card_id', coalesce(
        public.private_card_effect_internal_id_v1(c.card),
        public.private_card_effect_internal_id_v1(d.value)
      ),
      'card_id', coalesce(nullif(c.card ->> 'card_id', ''), nullif(d.value ->> 'card_id', '')),
      'card_num', coalesce(nullif(c.card ->> 'card_num', ''), nullif(d.value ->> 'card_num', '')),
      'database_id', coalesce(nullif(c.card ->> 'database_id', ''), nullif(d.value ->> 'database_id', '')),
      'name', coalesce(nullif(c.card ->> 'name', ''), nullif(d.value ->> 'name', '')),
      'name_ja', coalesce(nullif(c.card ->> 'name_ja', ''), nullif(d.value ->> 'name_ja', '')),
      'color', coalesce(nullif(c.card ->> 'color', ''), nullif(d.value ->> 'color', '')),
      'rarity', coalesce(nullif(c.card ->> 'rarity', ''), nullif(d.value ->> 'rarity', '')),
      'cost', case when coalesce(d.value ->> 'cost', '') ~ '^-?[0-9]+([.][0-9]+)?$' then (d.value ->> 'cost')::numeric else coalesce(nullif(c.card ->> 'cost','')::numeric,0) end,
      'ap', case when coalesce(d.value ->> 'ap', '') ~ '^-?[0-9]+([.][0-9]+)?$' then (d.value ->> 'ap')::numeric else coalesce(nullif(c.card ->> 'ap','')::numeric,0) end,
      'lp', case when coalesce(d.value ->> 'lp', '') ~ '^-?[0-9]+([.][0-9]+)?$' then (d.value ->> 'lp')::numeric else coalesce(nullif(c.card ->> 'lp','')::numeric,0) end,
      'cut_in_bonus', case when coalesce(d.value ->> 'cut_in_bonus', '') ~ '^[0-9]+$' then (d.value ->> 'cut_in_bonus')::integer else coalesce(nullif(c.card ->> 'cut_in_bonus','')::integer,0) end,
      'cut_in_effect', coalesce(nullif(c.card ->> 'cut_in_effect',''), nullif(d.value ->> 'cut_in_effect','')),
      'traits', case when jsonb_typeof(d.value -> 'traits') = 'array' then d.value -> 'traits' else coalesce(c.card -> 'traits','[]'::jsonb) end,
      'category1', coalesce(nullif(d.value ->> 'category1',''), c.card ->> 'category1',''),
      'category2', coalesce(nullif(d.value ->> 'category2',''), c.card ->> 'category2',''),
      'category3', coalesce(nullif(d.value ->> 'category3',''), c.card ->> 'category3','')
    )) order by c.ordinality
  ), '[]'::jsonb)
  FROM jsonb_array_elements(coalesce(p_cards, '[]'::jsonb)) WITH ORDINALITY AS c(card, ordinality)
  LEFT JOIN LATERAL (
    SELECT entry.value
    FROM jsonb_array_elements(coalesce(p_main_deck, '[]'::jsonb)) AS entry(value)
    WHERE entry.value ->> 'key' = c.card ->> 'key'
    LIMIT 1
  ) d ON true;
$function$;

REVOKE ALL ON FUNCTION public.private_card_effect_internal_id_v1(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.private_card_effect_matches_id_v1(jsonb,jsonb) FROM PUBLIC, anon, authenticated;
