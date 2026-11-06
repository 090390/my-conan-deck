-- Restore the fact used by the six level-1 color-search event deployment filters.
-- The effective cap is FILE count, plus one when Partner Assist was used.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text := $anchor$ SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;$anchor$;
  v_replacement text := $body$ SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
 IF p_fact='player.file.count' THEN
   RETURN to_jsonb(coalesce(v_board.file_count,0));
 END IF;
 IF p_fact='player.deployable_level' THEN
   RETURN to_jsonb(coalesce(v_board.file_count,0) + CASE WHEN coalesce(v_board.partner_assist_used,false) THEN 1 ELSE 0 END);
 END IF;$body$;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure
  ) INTO v_definition;

  IF position('player.deployable_level' IN v_definition)=0 THEN
    IF position(v_anchor IN v_definition)=0 THEN
      RAISE EXCEPTION 'Could not locate board lookup in private_card_effect_fact_v1';
    END IF;
    v_definition := replace(v_definition,v_anchor,v_replacement);
    EXECUTE v_definition;
  END IF;

  IF position('player.deployable_level' IN pg_get_functiondef(
    'public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure
  ))=0 THEN
    RAISE EXCEPTION 'player.deployable_level fact was not installed';
  END IF;
END
$migration$;

-- Keep the catalog prompt aligned with the calculated cap: FILE count + 1
-- only when Partner Assist has been used. The actual selection is enforced
-- by the player.deployable_level filter, not by the prompt text.
UPDATE public.private_card_effect_catalog_v1 catalog
SET definitions = (
  SELECT coalesce(jsonb_agg(
    CASE
      WHEN definition.value->>'effectId' IN (
        'card-0144-on-play-mysterious-passenger',
        'card-0158-on-play-private-eye',
        'card-0102-on-play-diminutive-detective',
        'card-0116-on-play-omamori',
        'card-0130-on-play-ladies-gentlemen',
        'card-0381-on-play-shadow-of-karasuma'
      )
      THEN jsonb_set(
        definition.value,
        '{steps}',
        (
          SELECT coalesce(jsonb_agg(
            CASE
              WHEN step.value->>'op'='select_cards'
                AND step.value->>'saveAs'='deployment'
              THEN jsonb_set(
                step.value,
                '{prompt}',
                to_jsonb(CASE definition.value->>'effectId'
                  WHEN 'card-0144-on-play-mysterious-passenger' THEN '현재 등장 가능 레벨(파일 수 + 어시스트 보정) 이하의 적 캐릭터를 최대 1장 등장시킬 수 있습니다.'
                  WHEN 'card-0158-on-play-private-eye' THEN '현재 등장 가능 레벨(파일 수 + 어시스트 보정) 이하의 황 캐릭터를 최대 1장 등장시킬 수 있습니다.'
                  WHEN 'card-0102-on-play-diminutive-detective' THEN '현재 등장 가능 레벨(파일 수 + 어시스트 보정) 이하의 청 캐릭터를 최대 1장 등장시킬 수 있습니다.'
                  WHEN 'card-0116-on-play-omamori' THEN '현재 등장 가능 레벨(파일 수 + 어시스트 보정) 이하의 녹 캐릭터를 최대 1장 등장시킬 수 있습니다.'
                  WHEN 'card-0130-on-play-ladies-gentlemen' THEN '현재 등장 가능 레벨(파일 수 + 어시스트 보정) 이하의 백 캐릭터를 최대 1장 등장시킬 수 있습니다.'
                  ELSE '현재 등장 가능 레벨(파일 수 + 어시스트 보정) 이하의 흑 캐릭터를 최대 1장 등장시킬 수 있습니다.'
                END),
                true
              )
              ELSE step.value
            END
            ORDER BY step.ordinality
          ),'[]'::jsonb)
          FROM jsonb_array_elements(definition.value->'steps')
            WITH ORDINALITY step(value,ordinality)
        ),
        true
      )
      ELSE definition.value
    END
    ORDER BY definition.ordinality
  ),catalog.definitions)
  FROM jsonb_array_elements(catalog.definitions)
    WITH ORDINALITY definition(value,ordinality)
),
updated_at=now()
WHERE catalog.catalog_id='main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(catalog.definitions) definition(value)
    WHERE definition.value->>'effectId' IN (
      'card-0144-on-play-mysterious-passenger',
      'card-0158-on-play-private-eye',
      'card-0102-on-play-diminutive-detective',
      'card-0116-on-play-omamori',
      'card-0130-on-play-ladies-gentlemen',
      'card-0381-on-play-shadow-of-karasuma'
    )
  );

DO $validation$
DECLARE
  v_invalid_count integer;
BEGIN
  SELECT count(*) INTO v_invalid_count
  FROM public.private_card_effect_catalog_v1 c
  CROSS JOIN LATERAL jsonb_array_elements(c.definitions) d
  WHERE c.catalog_id='main'
    AND d->>'effectId' IN (
      'card-0144-on-play-mysterious-passenger',
      'card-0158-on-play-private-eye',
      'card-0102-on-play-diminutive-detective',
      'card-0116-on-play-omamori',
      'card-0130-on-play-ladies-gentlemen',
      'card-0381-on-play-shadow-of-karasuma'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(d->'steps') step
      WHERE step->>'op'='select_cards'
        AND step->>'saveAs'='deployment'
        AND step#>>'{filter,allOf,2,value,fact}'='player.deployable_level'
        AND step->>'max'='1'
        AND step->>'from'='hand'
    );

  IF v_invalid_count<>0 THEN
    RAISE EXCEPTION 'Search-event deployment filter validation failed for % event(s)',v_invalid_count;
  END IF;
END
$validation$;
