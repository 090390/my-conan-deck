DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_insertion text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_condition_matches_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := ' ELSIF v_fact=''player.remove_area.count_matching_trait'' THEN';
  IF position(v_anchor IN v_definition) = 0 THEN RAISE EXCEPTION 'Cannot locate condition-matcher insertion point'; END IF;
  v_insertion := $insert$
 ELSIF v_fact='player.hand.count_matching_trait' THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_trait:=coalesce(p_condition->>'trait','');
   v_typ:=coalesce(p_condition->>'cardType','character');
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value)
   WHERE (v_typ<>'character' OR public.private_card_effect_is_character_v1(e.value))
     AND public.private_card_effect_has_trait_v1(e.value,v_trait)
     AND (nullif(p_condition->>'levelMax','') IS NULL
          OR public.private_card_effect_level_v1(e.value) <= (p_condition->>'levelMax')::integer)
     AND (nullif(p_condition->>'excludeCardId','') IS NULL
          OR NOT public.private_card_effect_matches_id_v1(e.value,jsonb_build_array(p_condition->>'excludeCardId')));
   v_actual:=to_jsonb(v_count);
 ELSIF v_fact='player.field.character_count' THEN
   SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
   WHERE public.private_card_effect_is_character_v1(e.value);
   v_actual:=to_jsonb(v_count);
$insert$;
  v_definition := replace(v_definition, v_anchor, v_insertion || v_anchor);
  EXECUTE v_definition;

  UPDATE public.private_card_effect_catalog_v1 c
  SET definitions = (
    SELECT jsonb_agg(
      CASE
        WHEN e.value->>'effectId'='card-0706-contact-remove-opponent-police-deploy'
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(e.value->'conditions','[]'::jsonb)) x(value)
            WHERE x.value->>'fact'='player.hand.count_matching_trait')
        THEN jsonb_set(e.value,'{conditions}',coalesce(e.value->'conditions','[]'::jsonb) || jsonb_build_array(jsonb_build_object(
          'fact','player.hand.count_matching_trait','value',1,'operator','greater_than_or_equal',
          'trait','警察','cardType','character','levelMax',7,'excludeCardId','0706')),true)
        WHEN e.value->>'effectId'='card-1139-returning-detective-case-effect'
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(e.value->'conditions','[]'::jsonb)) x(value)
            WHERE x.value->>'fact'='player.field.has_card_name' AND x.value->>'value'='松田陣平')
        THEN jsonb_set(e.value,'{conditions}',coalesce(e.value->'conditions','[]'::jsonb) || jsonb_build_array(jsonb_build_object(
          'fact','player.field.has_card_name','value','松田陣平','operator','equals')),true)
        WHEN e.value->>'effectId'='card-1261-conan-vs-kid-case-effect'
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(e.value->'conditions','[]'::jsonb)) x(value)
            WHERE x.value->>'fact'='player.field.character_count')
        THEN jsonb_set(e.value,'{conditions}',coalesce(e.value->'conditions','[]'::jsonb) || jsonb_build_array(jsonb_build_object(
          'fact','player.field.character_count','value',1,'operator','greater_than_or_equal')),true)
        ELSE e.value
      END ORDER BY e.ordinality)
    FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(value,ordinality)
  )
  WHERE c.catalog_id='main';

  SELECT pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := ' v_claims text;';
  IF position(v_anchor IN v_definition) = 0 THEN RAISE EXCEPTION 'Cannot locate AI activation declaration insertion point'; END IF;
  v_definition := replace(v_definition, v_anchor, v_anchor || E'\n v_case_key text; v_case_id text; v_case_name text; v_case_card jsonb;');
  v_anchor := ' RETURN jsonb_build_object(''activations'', v_items);';
  IF position(v_anchor IN v_definition) = 0 THEN RAISE EXCEPTION 'Cannot locate AI activation return insertion point'; END IF;
  v_insertion := $case_activation$
 v_case_key:=upper(regexp_replace(coalesce(v_board.event_key,''),'[^A-Za-z0-9]','','g'));
 IF v_case_key IN ('B10083P','B10083','1139') THEN
   v_case_id:='1139'; v_case_name:='돌아오지 않는 형사';
 ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
   v_case_id:='1261'; v_case_name:='코난 VS 괴도 키드';
 ELSE v_case_id:=NULL;
 END IF;
 IF v_case_id IS NOT NULL AND EXISTS (
   SELECT 1 FROM public.room_match_states m
   WHERE m.room_id=p_room_id AND m.current_turn_user_id=p_ai_user_id
     AND m.phase='playing' AND NOT m.game_over AND m.turn_step='main' AND m.pending_action IS NULL
 ) THEN
   v_case_card:=jsonb_build_object('instance_id','case:'||v_board.event_key,'key',v_board.event_key,
     'card_id',v_case_id,'card_num',v_board.event_key,'database_id',v_board.event_key,
     'card_type','event','type','event','name',v_case_name);
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='case.activated_ability'
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_case_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce(v_board.case_effect_uses->>(v_def->>'effectId'),'')=v_turn::text THEN CONTINUE; END IF;
     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_case_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN CONTINUE; END IF;
     v_items:=v_items||jsonb_build_array(jsonb_build_object(
       'source_instance_id','case:'||v_board.event_key,'source_kind','case',
       'effect_id',v_def->>'effectId',
       'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','사건 효과'),
       'definition',v_def));
   END LOOP;
 END IF;
$case_activation$;
  v_definition := replace(v_definition, v_anchor, v_insertion || v_anchor);
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := 'v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,''{}''::jsonb));';
  IF position(v_anchor IN v_definition) = 0 THEN RAISE EXCEPTION 'Cannot locate turn-action wrapper insertion point'; END IF;
  v_insertion := $action_guard$
IF p_action='declare_contact' THEN
  v_instance_id:=coalesce(nullif(p_payload->>'attacker_instance_id',''),nullif(p_payload->>'attacker_id',''),
    nullif(p_payload->>'source_instance_id',''),nullif(p_payload->>'instance_id',''));
  v_source_card:=NULL;
  SELECT e.value INTO v_source_card
  FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
  WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;

  IF v_source_card IS NOT NULL AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(v_source_card->'dsl_keywords','[]'::jsonb)
      || coalesce(v_source_card->'dsl_continuous_keywords','[]'::jsonb)) k(value)
    WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
      IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')
  ) THEN RAISE EXCEPTION '돌격[사건] 상태의 캐릭터는 캐릭터를 대상으로 컨택할 수 없습니다.'; END IF;

  v_owner:=nullif(p_payload->>'target_user_id','')::uuid;
  v_disguise_id:=coalesce(nullif(p_payload->>'target_instance_id',''),nullif(p_payload->>'target_id',''));
  v_old_card:=NULL;
  IF v_owner IS NOT NULL AND v_disguise_id IS NOT NULL THEN
    SELECT e.value INTO v_old_card
    FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
    WHERE b.room_id=p_room_id AND b.user_id=v_owner AND e.value->>'instance_id'=v_disguise_id LIMIT 1;
  END IF;

  IF v_source_card IS NOT NULL AND public.private_card_effect_matches_id_v1(v_source_card,'["0938"]'::jsonb)
     AND v_old_card IS NOT NULL AND public.private_card_effect_is_active_v1(v_old_card) THEN
    IF public.private_card_effect_level_v1(v_old_card)<7 THEN
      RAISE EXCEPTION 'D11007은 레벨 7 이상 액티브 캐릭터만 액티브 대상 컨택으로 지정할 수 있습니다.';
    END IF;
    p_payload:=jsonb_set(coalesce(p_payload,'{}'::jsonb),'{allow_active_target}','true'::jsonb,true);
  END IF;
END IF;

$action_guard$;
  v_definition := replace(v_definition, v_anchor, v_insertion || E'\n ' || v_anchor);
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := '''card_effect_continue'',''activate_card_effect''';
  IF position(v_anchor IN v_definition) = 0 THEN RAISE EXCEPTION 'Cannot locate AI action allowlist insertion point'; END IF;
  v_definition := replace(v_definition, v_anchor, '''card_effect_continue'',''activate_card_effect'',''activate_case_effect''');
  EXECUTE v_definition;
END
$migration$;
