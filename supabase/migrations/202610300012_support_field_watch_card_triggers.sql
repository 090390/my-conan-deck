CREATE OR REPLACE FUNCTION public.private_card_effect_start_event_v1(
  p_room_id uuid, p_actor_user_id uuid, p_source_user_id uuid, p_source_card jsonb,
  p_trigger_event text, p_context jsonb DEFAULT '{}'::jsonb,
  p_only_effect_id text DEFAULT NULL::text, p_require_match boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_catalog jsonb;
 v_def jsonb;
 v_queue jsonb:='[]'::jsonb;
 v_context jsonb;
 v_turn integer;
 v_existing jsonb;
 v_used jsonb;
 v_effect_id text;
 v_watch_card jsonb;
 v_watch_board public.room_player_turn_boards%rowtype;
 v_watch_used jsonb;
 v_scope text;
BEGIN
 IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   IF p_require_match THEN RAISE EXCEPTION '다른 카드 효과가 아직 처리 중입니다.'; END IF;
   RETURN false;
 END IF;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
 v_context:=coalesce(p_context,'{}'::jsonb)||jsonb_build_object(
   'source_card',coalesce(p_source_card,'{}'::jsonb),'turn_number',v_turn
 );

 FOR v_def IN
   SELECT d.value
   FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
   WHERE d.value->'trigger'->>'event'=p_trigger_event
     AND coalesce((d.value->>'continuous')::boolean,false)=false
     AND (p_only_effect_id IS NULL OR d.value->>'effectId'=p_only_effect_id)
   ORDER BY d.ordinality
 LOOP
   v_effect_id:=v_def->>'effectId';
   v_scope:=coalesce(v_def->'trigger'->>'scope','source');
   IF v_scope='field_watch' THEN
     IF p_trigger_event<>'character.entered_field' THEN CONTINUE; END IF;
     SELECT * INTO v_watch_board FROM public.room_player_turn_boards
       WHERE room_id=p_room_id AND user_id=p_actor_user_id;
     FOR v_watch_card IN
       SELECT e.value
       FROM jsonb_array_elements(coalesce(v_watch_board.field_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_matches_id_v1(e.value,coalesce(v_def->'cardIds','[]'::jsonb))
     LOOP
       IF NOT public.private_card_effect_conditions_match_v1(
         p_room_id,p_actor_user_id,p_source_user_id,v_watch_card,v_context,
         '{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
       ) THEN CONTINUE; END IF;
       IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
         v_existing:=public.private_card_effect_get_card_v1(p_room_id,p_source_user_id,v_watch_card->>'instance_id');
         IF v_existing IS NULL THEN CONTINUE; END IF;
         v_watch_used:=coalesce(v_existing->'dsl_effect_uses','[]'::jsonb);
         IF EXISTS(
           SELECT 1 FROM jsonb_array_elements(v_watch_used) u(value)
           WHERE u.value->>'effect_id'=v_effect_id
             AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn
         ) THEN CONTINUE; END IF;
         v_watch_used:=v_watch_used||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'turn_number',v_turn));
         PERFORM public.private_card_effect_patch_card_v1(
           p_room_id,p_source_user_id,v_watch_card->>'instance_id',
           jsonb_build_object('dsl_effect_uses',v_watch_used)
         );
       END IF;
       v_queue:=v_queue||jsonb_build_array(jsonb_build_object(
         '__definition',v_def,'__actor_user_id',p_actor_user_id,'__source_user_id',p_source_user_id,
         '__source_instance_id',v_watch_card->>'instance_id','__source_card',v_watch_card,'__context',v_context
       ));
     END LOOP;
   ELSE
     IF NOT public.private_card_effect_matches_id_v1(coalesce(p_source_card,'{}'::jsonb),coalesce(v_def->'cardIds','[]'::jsonb)) THEN
       CONTINUE;
     END IF;
     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id,p_actor_user_id,p_source_user_id,p_source_card,v_context,
       '{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN CONTINUE; END IF;
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_existing:=public.private_card_effect_get_card_v1(p_room_id,p_source_user_id,p_source_card->>'instance_id');
       v_used:=coalesce(v_existing->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(
         SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_effect_id
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn
       ) THEN CONTINUE; END IF;
       IF v_existing IS NULL THEN RAISE EXCEPTION '턴당 1회 효과의 원본 카드를 찾을 수 없습니다.'; END IF;
       v_used:=v_used||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'turn_number',v_turn));
       PERFORM public.private_card_effect_patch_card_v1(
         p_room_id,p_source_user_id,p_source_card->>'instance_id',jsonb_build_object('dsl_effect_uses',v_used)
       );
     END IF;
     v_queue:=v_queue||jsonb_build_array(v_def);
   END IF;
 END LOOP;

 IF jsonb_array_length(v_queue)=0 THEN
   IF p_require_match THEN RAISE EXCEPTION '이 카드의 효과 조건이 충족되지 않았거나 이번 턴에 이미 사용했습니다.'; END IF;
   RETURN false;
 END IF;
 INSERT INTO public.private_card_effect_runs_v1(
   room_id,actor_user_id,source_user_id,source_instance_id,trigger_event,effect_queue,
   effect_index,step_index,variables,context,waiting,created_at,updated_at
 ) VALUES (
   p_room_id,p_actor_user_id,p_source_user_id,coalesce(p_source_card->>'instance_id',''),p_trigger_event,
   v_queue,0,0,'{}'::jsonb,v_context,NULL,now(),now()
 );
 PERFORM public.private_card_effect_run_v1(p_room_id);
 RETURN true;
END
$function$;