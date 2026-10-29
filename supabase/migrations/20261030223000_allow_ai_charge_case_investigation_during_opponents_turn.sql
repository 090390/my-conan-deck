DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := '''shuffle_deck'',''card_effect_continue'',''activate_card_effect'',''activate_case_effect''';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI action allowlist'; END IF;
  v_definition:=replace(v_definition,v_anchor,
    '''shuffle_deck'',''card_effect_continue'',''activate_card_effect'',''activate_case_effect'',''investigate''');

  v_anchor := $owner_guard$
and NOT (
  p_action='activate_card_effect'
  AND EXISTS (
    SELECT 1
    FROM public.private_card_effect_catalog_v1 c
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
    JOIN public.room_player_turn_boards b ON b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
    WHERE c.catalog_id='main'
      AND d.value->>'effectId'=p_payload->>'effect_id'
      AND d.value->>'activationTiming'='any'
      AND e.value->>'instance_id'=p_payload->>'source_instance_id'
      AND public.private_card_effect_matches_id_v1(e.value,coalesce(d.value->'cardIds','[]'::jsonb))
      AND public.private_card_effect_is_active_v1(e.value)
  )
) then
$owner_guard$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI cross-turn guard'; END IF;
  v_replacement := $owner_guard$
and NOT (
  (
    p_action='activate_card_effect'
    AND EXISTS (
      SELECT 1
      FROM public.private_card_effect_catalog_v1 c
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
      JOIN public.room_player_turn_boards b ON b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
      WHERE c.catalog_id='main'
        AND d.value->>'effectId'=p_payload->>'effect_id'
        AND d.value->>'activationTiming'='any'
        AND e.value->>'instance_id'=p_payload->>'source_instance_id'
        AND public.private_card_effect_matches_id_v1(e.value,coalesce(d.value->'cardIds','[]'::jsonb))
        AND public.private_card_effect_is_active_v1(e.value)
    )
  )
  OR (
    p_action='investigate'
    AND EXISTS (
      SELECT 1
      FROM public.room_player_turn_boards b
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
      WHERE b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
        AND e.value->>'instance_id'=p_payload->>'instance_id'
        AND public.private_card_effect_is_active_v1(e.value)
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(
            coalesce(e.value->'dsl_keywords','[]'::jsonb)
            || coalesce(e.value->'dsl_continuous_keywords','[]'::jsonb)
          ) k(value)
          WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
            IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')
        )
    )
  )
) then
$owner_guard$;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;
END
$migration$;
