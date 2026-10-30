-- Start catalog-defined event.played effects as soon as an event is played.
CREATE OR REPLACE FUNCTION public.private_card_effect_start_event_v1(
  p_room_id uuid,
  p_actor uuid,
  p_event_card jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_catalog jsonb;
  v_context jsonb;
  v_queue jsonb;
BEGIN
  IF p_event_card IS NULL OR NOT public.private_card_effect_is_character_v1(p_event_card)
     AND lower(coalesce(p_event_card->>'card_type',p_event_card->>'type','')) NOT IN ('event','이벤트','イベント') THEN
    RAISE EXCEPTION '이벤트 카드 정보가 올바르지 않습니다.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id
  ) THEN
    RAISE EXCEPTION '다른 카드 효과가 처리 중입니다.';
  END IF;

  SELECT definitions INTO v_catalog
  FROM public.private_card_effect_catalog_v1
  WHERE catalog_id='main';

  v_context:=jsonb_build_object(
    'source_card',p_event_card,
    'turn_number',(SELECT turn_number FROM public.room_match_states WHERE room_id=p_room_id),
    'event','event.played'
  );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    '__definition',d.value,
    '__actor_user_id',p_actor,
    '__source_user_id',p_actor,
    '__source_instance_id',p_event_card->>'instance_id',
    '__source_card',p_event_card,
    '__context',v_context
  ) ORDER BY d.ordinality),'[]'::jsonb)
  INTO v_queue
  FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
  WHERE d.value->'trigger'->>'event'='event.played'
    AND NOT coalesce((d.value->>'continuous')::boolean,false)
    AND public.private_card_effect_matches_id_v1(
      p_event_card,coalesce(d.value->'cardIds','[]'::jsonb)
    )
    AND public.private_card_effect_conditions_match_v1(
      p_room_id,p_actor,p_actor,p_event_card,v_context,'{}'::jsonb,
      coalesce(d.value->'conditions','[]'::jsonb)
    );

  IF jsonb_array_length(v_queue)=0 THEN
    RETURN;
  END IF;

  INSERT INTO public.private_card_effect_runs_v1(
    room_id,actor_user_id,source_user_id,source_instance_id,trigger_event,
    effect_queue,effect_index,step_index,variables,context,waiting
  ) VALUES (
    p_room_id,p_actor,p_actor,p_event_card->>'instance_id','event.played',
    v_queue,0,0,'{}'::jsonb,v_context,NULL
  );

  PERFORM public.private_card_effect_run_v1(p_room_id);
END
$function$;

DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$
    v_label := '이벤트를 현장에 놓았습니다. 카드 효과를 확인한 뒤 [효과 처리 완료 → 리무브]를 누르세요.';
    update public.room_match_states m set state_version = state_version + 1, last_action_label = v_label where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
$new$;
  v_replacement := $new$
    v_label := '이벤트를 현장에 놓았습니다. 카드 효과를 처리합니다.';
    update public.room_match_states m set state_version = state_version + 1, last_action_label = v_label where m.room_id = p_room_id;
    perform public.private_card_effect_start_event_v1(p_room_id,v_user,v_card);
    return public.get_private_turn_state_v2(p_room_id);
$new$;

  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN
      RAISE EXCEPTION 'play_event integration anchor missing';
    END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;
  EXECUTE v_definition;
END
$migration$;
