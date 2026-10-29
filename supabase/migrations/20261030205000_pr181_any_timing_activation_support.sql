DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_insert text;
BEGIN
  UPDATE public.private_card_effect_catalog_v1 c
  SET definitions = (
    SELECT jsonb_agg(
      CASE WHEN e.value->>'effectId'='card-0732-activated-deploy-tokyo-police-temporary-charge-return'
        THEN e.value || jsonb_build_object('activationTiming','any')
        ELSE e.value
      END ORDER BY e.ordinality
    )
    FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(value,ordinality)
  )
  WHERE c.catalog_id='main';

  SELECT pg_get_functiondef('public.get_private_card_effect_activations_v1(uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := 'OR EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND (game_over OR phase<>''playing'' OR current_turn_user_id<>v_user)) THEN';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate human activation turn guard'; END IF;
  v_definition := replace(v_definition, v_anchor,
    'OR EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND (game_over OR phase<>''playing'')) THEN');

  v_anchor := 'AND coalesce((value->>''continuous'')::boolean,false)=false';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate human ability timing filter'; END IF;
  v_definition := replace(v_definition, v_anchor,
    v_anchor || E'\n       AND (coalesce(value->>''activationTiming'','''')=''any'' OR EXISTS(\n         SELECT 1 FROM public.room_match_states m WHERE m.room_id=p_room_id\n          AND m.current_turn_user_id=v_user AND m.turn_step IN (''begin'',''file'',''main'')\n       ))');

  v_anchor := 'FOR v_card IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,''[]''::jsonb)) LOOP';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate human ability source-card loop'; END IF;
  v_definition := replace(v_definition, v_anchor,
    v_anchor || E'\n   IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;');

  v_anchor := '''label'',v_label,';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate human activation label'; END IF;
  v_definition := replace(v_definition, v_anchor,
    '''label'',v_label,''activation_timing'',coalesce(v_def->>''activationTiming'',''turn''),');

  v_anchor := 'IF v_case_id IS NOT NULL THEN';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate human case-ability phase guard'; END IF;
  v_definition := replace(v_definition, v_anchor,
    'IF v_case_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.room_match_states m WHERE m.room_id=p_room_id AND m.current_turn_user_id=v_user AND m.turn_step=''main'' AND m.pending_action IS NULL) THEN');

  v_anchor := '''label'',coalesce(v_def->>''activationLabelKo'',v_def->>''effectId''),';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate case activation label'; END IF;
  v_definition := replace(v_definition, v_anchor,
    '''label'',coalesce(v_def->>''activationLabelKo'',v_def->>''effectId''),''activation_timing'',coalesce(v_def->>''activationTiming'',''turn''),');
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := 'IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION ''자신의 턴에만 이 능력을 발동할 수 있습니다.''; END IF;';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate turn-action activation owner guard'; END IF;
  v_definition := replace(v_definition, v_anchor, '-- Turn ownership is checked after the card effect timing is loaded.');
  v_anchor := 'IF coalesce(v_match.turn_step,'''') NOT IN (''begin'',''file'',''main'') THEN RAISE EXCEPTION ''본인 턴 중 능력을 발동할 수 있는 단계가 아닙니다.''; END IF;';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate turn-action activation step guard'; END IF;
  v_definition := replace(v_definition, v_anchor, '-- Turn-step eligibility is checked after the card effect timing is loaded.');
  v_anchor := 'IF v_effect_definition IS NULL THEN RAISE EXCEPTION ''이 캐릭터에 등록된 효과를 찾을 수 없습니다.''; END IF;';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate effect-definition validation'; END IF;
  v_insert := $timing_guard$
IF NOT public.private_card_effect_is_active_v1(v_source_card) THEN
  RAISE EXCEPTION '액티브 상태의 캐릭터 능력만 발동할 수 있습니다.';
END IF;
IF coalesce(v_effect_definition->>'activationTiming','') <> 'any' THEN
  IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN
    RAISE EXCEPTION '자신의 턴에만 이 능력을 발동할 수 있습니다.';
  END IF;
  IF coalesce(v_match.turn_step,'') NOT IN ('begin','file','main') THEN
    RAISE EXCEPTION '본인 턴 중 능력을 발동할 수 있는 단계가 아닙니다.';
  END IF;
END IF;
$timing_guard$;
  v_definition := replace(v_definition, v_anchor, v_anchor || E'\n ' || v_insert);
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := ' v_turn integer;';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI activation variables'; END IF;
  v_definition := replace(v_definition, v_anchor, v_anchor || ' v_is_own_turn boolean; v_turn_step text;');

  v_anchor := 'SELECT m.turn_number INTO v_turn';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI activation turn select'; END IF;
  v_definition := replace(v_definition, v_anchor,
    'SELECT m.turn_number, m.current_turn_user_id=p_ai_user_id, m.turn_step INTO v_turn, v_is_own_turn, v_turn_step');
  v_anchor := 'AND m.current_turn_user_id = p_ai_user_id';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI activation turn-owner filter'; END IF;
  v_definition := replace(v_definition, v_anchor, '');
  v_anchor := 'AND m.turn_step IN (''file'', ''main'')';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI activation step filter'; END IF;
  v_definition := replace(v_definition, v_anchor, '');

  v_anchor := 'IF NOT FOUND OR EXISTS (';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI activation empty-state guard'; END IF;
  v_definition := replace(v_definition, v_anchor,
    'IF NOT FOUND OR (coalesce(v_is_own_turn,false) AND coalesce(v_turn_step,'''') NOT IN (''file'',''main'')) OR EXISTS (');

  v_anchor := 'WHERE d.value->''trigger''->>''event'' = ''character.activated_ability''';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI activation trigger filter'; END IF;
  v_definition := replace(v_definition, v_anchor,
    v_anchor || E'\n       AND (v_is_own_turn OR coalesce(d.value->>''activationTiming'','''')=''any'')');

  v_anchor := 'LOOP' || E'\n   FOR v_def IN';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI nested ability loop'; END IF;
  v_definition := replace(v_definition, v_anchor,
    'LOOP' || E'\n   IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;' || E'\n   FOR v_def IN');
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := 'and coalesce(v_match.pending_action ->> ''chooser_user_id'', '''') <> v_battle.ai_user_id::text then';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate AI turn-owner guard'; END IF;
  v_insert := $ai_any_timing$
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
$ai_any_timing$;
  v_definition := replace(v_definition, v_anchor,
    'and coalesce(v_match.pending_action ->> ''chooser_user_id'', '''') <> v_battle.ai_user_id::text' || E'\n    ' || v_insert);
  EXECUTE v_definition;
END
$migration$;
