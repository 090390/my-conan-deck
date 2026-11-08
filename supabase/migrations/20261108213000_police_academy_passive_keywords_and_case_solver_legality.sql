-- Keep Police Academy partner-colour keywords continuous, and require an active
-- partner before using the partner's case-solving ability.
DO $migration$
DECLARE
  v_definitions jsonb;
  v_count integer;
  v_function_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT definitions INTO v_definitions
    FROM public.private_card_effect_catalog_v1
   WHERE catalog_id = 'main'
   FOR UPDATE;

  IF NOT FOUND OR jsonb_typeof(v_definitions) <> 'array' THEN
    RAISE EXCEPTION 'main 카드 효과 카탈로그를 찾을 수 없습니다.';
  END IF;

  SELECT count(*) INTO v_count
    FROM jsonb_array_elements(v_definitions) d(value)
   WHERE d.value->>'effectId' = 'card-0148-partner-yellow-swift';
  IF v_count <> 1 THEN
    RAISE EXCEPTION '0148 파트너 황 신속 정의가 정확히 1개여야 합니다. 현재 %개입니다.', v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM jsonb_array_elements(v_definitions) d(value)
   WHERE d.value->>'effectId' = 'card-1122-partner-yellow-charge';
  IF v_count <> 1 THEN
    RAISE EXCEPTION '1122 파트너 황 돌격 정의가 정확히 1개여야 합니다. 현재 %개입니다.', v_count;
  END IF;

  SELECT count(*) INTO v_count
    FROM jsonb_array_elements(v_definitions) d(value)
   WHERE d.value->>'effectId' = 'card-0938-on-enter-partner-yellow-charge';
  IF v_count <> 1 THEN
    RAISE EXCEPTION '0938 파트너 황 돌격 정의가 정확히 1개여야 합니다. 현재 %개입니다.', v_count;
  END IF;

  UPDATE public.private_card_effect_catalog_v1 c
     SET definitions = (
       SELECT jsonb_agg(
         CASE d.value->>'effectId'
           WHEN 'card-0148-partner-yellow-swift' THEN
             d.value || jsonb_build_object(
               'trigger', jsonb_build_object('event', 'continuous.recalculate', 'timing', 'continuous'),
               'continuous', true,
               'steps', jsonb_build_array(jsonb_build_object(
                 'op', 'set_continuous_keyword',
                 'target', 'source_character',
                 'keyword', 'haya',
                 'duration', 'while_condition_true',
                 'modifierId', 'police-academy-0148-partner-yellow-swift',
                 'displayNameKo', '신속'
               ))
             )
           WHEN 'card-1122-partner-yellow-charge' THEN
             d.value || jsonb_build_object(
               'trigger', jsonb_build_object('event', 'continuous.recalculate', 'timing', 'continuous'),
               'continuous', true,
               'steps', jsonb_build_array(jsonb_build_object(
                 'op', 'set_continuous_keyword',
                 'target', 'source_character',
                 'keyword', 'charge',
                 'duration', 'while_condition_true',
                 'modifierId', 'police-academy-1122-partner-yellow-charge',
                 'displayNameKo', '돌격'
               ))
             )
           WHEN 'card-0938-on-enter-partner-yellow-charge' THEN
             d.value || jsonb_build_object(
               'trigger', jsonb_build_object('event', 'continuous.recalculate', 'timing', 'continuous'),
               'continuous', true,
               'steps', jsonb_build_array(jsonb_build_object(
                 'op', 'set_continuous_keyword',
                 'target', 'source_character',
                 'keyword', 'charge',
                 'duration', 'while_condition_true',
                 'modifierId', 'police-academy-0938-partner-yellow-charge',
                 'displayNameKo', '돌격'
               ))
             )
           ELSE d.value
         END
         ORDER BY d.ordinality
       )
       FROM jsonb_array_elements(c.definitions) WITH ORDINALITY d(value, ordinality)
     )
   WHERE c.catalog_id = 'main';

  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure
  )
  INTO v_function_definition;

  v_old := $old$
   IF coalesce(v_new_board.case_phase,v_match.case_phase,'incident')<>'solution' THEN
     RAISE EXCEPTION '해결편에서만 사건을 해결할 수 있습니다.';
   END IF;
$old$;

  v_new := $new$
   IF coalesce(v_new_board.case_phase,v_match.case_phase,'incident')<>'solution' THEN
     RAISE EXCEPTION '해결편에서만 사건을 해결할 수 있습니다.';
   END IF;
   IF coalesce(v_new_board.partner_rested,false) THEN
     RAISE EXCEPTION '파트너가 슬립 상태여서 사건 해결을 선언할 수 없습니다.';
   END IF;
$new$;

  IF position(v_old IN v_function_definition) > 0 THEN
    v_function_definition := replace(v_function_definition, v_old, v_new);
    EXECUTE v_function_definition;
  ELSIF position('파트너가 슬립 상태여서 사건 해결을 선언할 수 없습니다.' IN v_function_definition) = 0 THEN
    RAISE EXCEPTION 'solve_case의 파트너 슬립 검증 삽입 위치를 찾지 못했습니다.';
  END IF;
END
$migration$;
