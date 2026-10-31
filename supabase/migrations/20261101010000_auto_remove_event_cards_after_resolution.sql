-- Event cards are transient field objects while their effect queue resolves.
-- Once the queue finishes (or an event has no applicable effect), move the
-- resolving event to its owner's remove area automatically.
--
-- The helper is deliberately not exposed through the Data API. It is called
-- only from the SECURITY DEFINER effect runner/start functions.

CREATE OR REPLACE FUNCTION public.private_card_effect_move_event_to_remove_v1(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_instance_id text
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_board public.room_player_turn_boards%rowtype;
  v_card jsonb;
BEGIN
  IF p_room_id IS NULL OR p_owner_user_id IS NULL OR nullif(p_instance_id,'') IS NULL THEN
    RETURN false;
  END IF;

  SELECT *
    INTO v_board
    FROM public.room_player_turn_boards
   WHERE room_id=p_room_id AND user_id=p_owner_user_id
   FOR UPDATE;

  IF NOT FOUND THEN RETURN false; END IF;

  SELECT e.value
    INTO v_card
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
   WHERE e.value->>'instance_id'=p_instance_id
     AND lower(coalesce(e.value->>'card_type',''))='event'
     AND coalesce((e.value->>'resolving')::boolean,false)=true
   LIMIT 1;

  IF v_card IS NULL THEN RETURN false; END IF;

  UPDATE public.room_player_turn_boards
     SET field_cards=coalesce((
           SELECT jsonb_agg(e.value ORDER BY e.ordinality)
             FROM jsonb_array_elements(coalesce(field_cards,'[]'::jsonb))
                  WITH ORDINALITY e(value,ordinality)
            WHERE e.value->>'instance_id' IS DISTINCT FROM p_instance_id
         ),'[]'::jsonb),
         remove_count=coalesce(remove_count,0)+1,
         updated_at=now()
   WHERE room_id=p_room_id AND user_id=p_owner_user_id;

  UPDATE public.room_player_game_states
     SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card-'resolving'),
         updated_at=now()
   WHERE room_id=p_room_id AND user_id=p_owner_user_id;

  UPDATE public.room_match_states
     SET state_version=state_version+1,
         last_action_label='이벤트 효과 처리가 완료되어 리무브 에이리어로 이동했습니다.'
   WHERE room_id=p_room_id;

  RETURN true;
END
$function$;

REVOKE ALL ON FUNCTION public.private_card_effect_move_event_to_remove_v1(uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;

-- The regular runner handles events that had one or more matching effect
-- definitions. It waits for the entire queue, including all player selections,
-- before removing the source event.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$IF v_run.effect_index >= jsonb_array_length(coalesce(v_run.effect_queue,'[]'::jsonb)) THEN
     DELETE FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;$old$;
  v_new text := $new$IF v_run.effect_index >= jsonb_array_length(coalesce(v_run.effect_queue,'[]'::jsonb)) THEN
     PERFORM public.private_card_effect_move_event_to_remove_v1(
       p_room_id,v_run.source_user_id,v_run.source_instance_id
     );
     DELETE FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;$new$;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  IF position('private_card_effect_move_event_to_remove_v1' IN v_definition)=0 THEN
    IF position(v_old IN v_definition)=0 THEN
      RAISE EXCEPTION '카드 효과 실행 종료 코드를 찾지 못했습니다.';
    END IF;
    v_definition:=replace(v_definition,v_old,v_new);
    v_definition:=replace(v_definition,E'END\n$function$',E'END;\n$function$');
    v_definition:=v_definition||';';
    EXECUTE v_definition;
  END IF;
END;
$migration$;

-- The 3-argument overload is used by the legacy play_event action. Events with
-- no matching effect still leave the field immediately after being played.
CREATE OR REPLACE FUNCTION public.private_card_effect_start_event_v1(
  p_room_id uuid,
  p_actor uuid,
  p_event_card jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_catalog jsonb;
  v_context jsonb;
  v_queue jsonb;
BEGIN
  IF p_event_card IS NULL
     OR lower(coalesce(p_event_card->>'card_type',p_event_card->>'type','')) NOT IN ('event','이벤트','イベント') THEN
    RAISE EXCEPTION '이벤트 카드 정보가 올바르지 않습니다.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
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
    PERFORM public.private_card_effect_move_event_to_remove_v1(
      p_room_id,p_actor,p_event_card->>'instance_id'
    );
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

-- This overload is also used by other event triggers. Apply the same
-- no-matching-effect cleanup rule to event.played only.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$IF jsonb_array_length(v_queue)=0 THEN
   IF p_require_match THEN RAISE EXCEPTION '이 카드의 효과 조건이 충족되지 않았거나 이번 턴에 이미 사용했습니다.'; END IF;
   RETURN false;
 END IF;$old$;
  v_new text := $new$IF jsonb_array_length(v_queue)=0 THEN
   IF p_require_match THEN
     RAISE EXCEPTION '이 카드의 효과 조건이 충족되지 않았거나 이번 턴에 이미 사용했습니다.';
   END IF;
   IF p_trigger_event='event.played' THEN
     PERFORM public.private_card_effect_move_event_to_remove_v1(
       p_room_id,p_source_user_id,p_source_card->>'instance_id'
     );
   END IF;
   RETURN false;
 END IF;$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean)'::regprocedure
  ) INTO v_definition;

  IF position('private_card_effect_move_event_to_remove_v1' IN v_definition)=0 THEN
    IF position(v_old IN v_definition)=0 THEN
      RAISE EXCEPTION '이벤트 효과 미등록 처리 코드를 찾지 못했습니다.';
    END IF;
    v_definition:=replace(v_definition,v_old,v_new);
    v_definition:=replace(v_definition,E'END\n$function$',E'END;\n$function$');
    v_definition:=v_definition||';';
    EXECUTE v_definition;
  END IF;
END;
$migration$;
