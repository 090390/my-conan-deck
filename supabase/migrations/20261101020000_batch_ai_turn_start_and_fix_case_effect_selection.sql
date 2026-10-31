-- 1) Evidence cards omit face_up when they are facedown. Treat that
-- representation as false so DSL filters can select facedown evidence.
DO $migration$
DECLARE
  v_oid regprocedure;
  v_definition text;
  v_old text := $old$  ELSE actual:=coalesce(p_card->f,'null'::jsonb);$old$;
  v_new text := $new$  WHEN 'face_up' THEN actual:=to_jsonb(coalesce(nullif(p_card->>'face_up','')::boolean,false));
  ELSE actual:=coalesce(p_card->f,'null'::jsonb);$new$;
BEGIN
  FOREACH v_oid IN ARRAY ARRAY[
    'public.private_card_effect_filter_matches_v1(uuid,jsonb,uuid,uuid,jsonb)'::regprocedure,
    'public.private_card_effect_filter_matches_with_vars_v1(uuid,jsonb,uuid,uuid,jsonb,jsonb)'::regprocedure
  ] LOOP
    SELECT pg_get_functiondef(v_oid) INTO v_definition;
    IF position($$WHEN 'face_up'$$ IN v_definition)=0 THEN
      IF position(v_old IN v_definition)=0 THEN
        RAISE EXCEPTION 'face_up 필터 삽입 위치를 찾지 못했습니다: %',v_oid;
      END IF;
      v_definition:=replace(v_definition,v_old,v_new);
      EXECUTE v_definition;
    END IF;
  END LOOP;
END;
$migration$;

-- 2) A triggered card-effect prompt must carry its originating card through
-- to the client. Case event cards use virtual instance IDs (case:<event key>)
-- and therefore cannot be rediscovered by scanning normal field-card arrays.
DO $migration$
DECLARE
  v_definition text;
  v_old text := 'pending_action=v_pending';
  v_new text := 'pending_action=v_pending||jsonb_build_object(''source_card'',coalesce(v_run.context->''source_card'',''{}''::jsonb),''source_card_name'',coalesce(v_run.context->''source_card''->>''name'',''''))';
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  IF position('source_card_name' IN v_definition)=0 THEN
    IF position(v_old IN v_definition)=0 THEN
      RAISE EXCEPTION '카드 효과 대기 동작 위치를 찾지 못했습니다.';
    END IF;
    v_definition:=replace(v_definition,v_old,v_new);
    EXECUTE v_definition;
  END IF;
END;
$migration$;

-- 3) AI turn start performs status refresh, draw, and file placement inside
-- one wrapper/RPC call. The user sees a single AI turn-start action.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$v_result := public.perform_private_turn_action_v2(
    p_room_id, p_action, coalesce(p_payload, '{}'::jsonb)
  );$old$;
  v_new text := $new$IF p_action='begin_turn' THEN
    v_result := public.perform_private_turn_action_v2(
      p_room_id, 'begin_turn', coalesce(p_payload, '{}'::jsonb)
    );
    IF coalesce(v_result->>'turn_step','')='file' THEN
      v_result := public.perform_private_turn_action_v2(
        p_room_id, 'place_files', '{}'::jsonb
      );
    END IF;
  ELSE
    v_result := public.perform_private_turn_action_v2(
      p_room_id, p_action, coalesce(p_payload, '{}'::jsonb)
    );
  END IF;$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position($$IF p_action='begin_turn' THEN$$ IN v_definition)=0 THEN
    IF position(v_old IN v_definition)=0 THEN
      RAISE EXCEPTION 'AI 턴 시작 행동 호출 코드를 찾지 못했습니다.';
    END IF;
    v_definition:=replace(v_definition,v_old,v_new);
    EXECUTE v_definition;
  END IF;
END;
$migration$;
