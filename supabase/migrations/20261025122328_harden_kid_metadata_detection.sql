-- Harden the ID:0301 metadata fallback when a card row lacks translated/original name fields
-- and when CT-P03 appears in either localized or original product metadata.
DO $patch$
DECLARE
  v_definition text;
  v_condition_start integer;
  v_condition_end integer;
  v_condition_length integer;
  v_new_condition text := $kid$or (
               (
                 NOT EXISTS (
                   SELECT 1
                   FROM unnest(ARRAY[
                     other_card.value ->> 'name',
                     other_card.value ->> 'nameKo',
                     other_card.value ->> 'name_ko',
                     other_card.value ->> 'originalName',
                     other_card.value ->> 'original_name',
                     other_card.value ->> 'translatedName',
                     other_card.value ->> 'cardName',
                     other_card.value ->> 'card_name',
                     other_card.value ->> 'title',
                     other_card.value #>> '{sourceData,name}',
                     other_card.value #>> '{sourceData,originalName}'
                   ]) AS kid_names(value)
                   WHERE nullif(trim(kid_names.value),'') IS NOT NULL
                 )
                 OR EXISTS (
                   SELECT 1
                   FROM unnest(ARRAY[
                     other_card.value ->> 'name',
                     other_card.value ->> 'nameKo',
                     other_card.value ->> 'name_ko',
                     other_card.value ->> 'originalName',
                     other_card.value ->> 'original_name',
                     other_card.value ->> 'translatedName',
                     other_card.value ->> 'cardName',
                     other_card.value ->> 'card_name',
                     other_card.value ->> 'title',
                     other_card.value #>> '{sourceData,name}',
                     other_card.value #>> '{sourceData,originalName}'
                   ]) AS kid_names(value)
                   WHERE regexp_replace(lower(coalesce(kid_names.value,'')), '[[:space:]]', '', 'g')
                     IN ('괴도키드','怪盗キッド')
                 )
               )
               AND lower(coalesce(other_card.value ->> 'card_type', other_card.value ->> 'type', 'character'))
                 IN ('character','캐릭터','キャラクター')
               AND upper(coalesce(other_card.value ->> 'rarity', other_card.value ->> 'rarity_code', '')) = 'SR'
               AND coalesce(nullif(other_card.value ->> 'cost','')::numeric, -1) = 8
               AND coalesce(nullif(other_card.value ->> 'ap','')::numeric, -1) = 7000
               AND coalesce(nullif(other_card.value ->> 'lp','')::numeric, -1) = 2
               AND EXISTS (
                 SELECT 1
                 FROM unnest(ARRAY[
                   other_card.value ->> 'color',
                   other_card.value ->> 'originalColor',
                   other_card.value ->> 'original_color',
                   other_card.value ->> 'colorJp',
                   other_card.value ->> 'colorKo'
                 ]) AS kid_colors(value)
                 WHERE upper(trim(coalesce(kid_colors.value,''))) IN ('백','白','白色','WHITE')
               )
               AND upper(concat_ws(' ',
                 other_card.value ->> 'set',
                 other_card.value ->> 'originalSet',
                 other_card.value ->> 'original_set',
                 other_card.value ->> 'product',
                 other_card.value ->> 'package'
               )) LIKE '%CT-P03%'$kid$;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;
  v_condition_start := position('or (' || E'\n               regexp_replace(lower(coalesce(' IN v_definition);
  IF v_condition_start = 0 THEN RAISE EXCEPTION 'Could not find the existing ID:0301 attribute fallback.'; END IF;
  v_condition_end := position('like ''%CT-P03%''' IN substring(v_definition from v_condition_start));
  IF v_condition_end = 0 THEN RAISE EXCEPTION 'Could not find the CT-P03 product check.'; END IF;
  v_condition_length := v_condition_end + length('like ''%CT-P03%''') - 1;
  v_definition := overlay(v_definition placing v_new_condition from v_condition_start for v_condition_length);
  EXECUTE v_definition;
END
$patch$;
