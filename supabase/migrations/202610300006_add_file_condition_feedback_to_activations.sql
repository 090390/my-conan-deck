-- Return both eligible activations and those blocked only by a FILE threshold.
CREATE OR REPLACE FUNCTION public.get_private_card_effect_activations_v1(p_room_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid();
 v_catalog jsonb;
 v_board public.room_player_turn_boards%rowtype;
 v_card jsonb;
 v_def jsonb;
 v_used jsonb;
 v_turn integer;
 v_items jsonb:='[]'::jsonb;
 v_locked jsonb:='[]'::jsonb;
 v_label text;
 v_context jsonb:='{}'::jsonb;
 v_conditions jsonb;
 v_required_file integer;
 v_file_count integer;
 v_required_phase text;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
 IF NOT FOUND THEN RAISE EXCEPTION '자신의 보드를 찾을 수 없습니다.'; END IF;
 v_file_count:=coalesce(v_board.file_count,0);

 IF EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    OR EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND (game_over OR phase<>'playing' OR current_turn_user_id<>v_user)) THEN
   RETURN jsonb_build_object('activations','[]'::jsonb,'locked_activations','[]'::jsonb,'current_file_count',v_file_count);
 END IF;

 FOR v_card IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) LOOP
   FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='character.activated_ability'
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb))
       AND coalesce((value->>'continuous')::boolean,false)=false
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     v_conditions:=coalesce(v_def->'conditions','[]'::jsonb);
     SELECT max((c.value->>'value')::integer) INTO v_required_file
     FROM jsonb_array_elements(v_conditions) c(value)
     WHERE c.value->>'fact'='player.file.count'
       AND c.value->>'operator'='greater_than_or_equal'
       AND coalesce(c.value->>'value','') ~ '^[0-9]+$';
     SELECT max(c.value->>'value') INTO v_required_phase
     FROM jsonb_array_elements(v_conditions) c(value)
     WHERE c.value->>'fact'='player.case_phase'
       AND c.value->>'operator'='equals';

     v_label:=coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과');
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,v_user,v_user,v_card,v_context,'{}'::jsonb,v_conditions
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'source_card_key',v_card->>'key',
         'source_name',public.private_card_effect_name_v1(v_card),
         'effect_id',v_def->>'effectId',
         'label',v_label,
         'current_file_count',v_file_count,
         'required_file_count',v_required_file,
         'required_case_phase',v_required_phase
       ));
     ELSIF v_required_file IS NOT NULL AND v_file_count<v_required_file THEN
       -- Show a disabled status only when all other conditions pass and FILE is the blocker.
       IF public.private_card_effect_conditions_match_v1(
         p_room_id,v_user,v_user,v_card,v_context,'{}'::jsonb,
         coalesce((
           SELECT jsonb_agg(c.value)
           FROM jsonb_array_elements(v_conditions) c(value)
           WHERE c.value->>'fact' IS DISTINCT FROM 'player.file.count'
         ),'[]'::jsonb)
       ) THEN
         v_locked:=v_locked||jsonb_build_array(jsonb_build_object(
           'source_instance_id',v_card->>'instance_id',
           'source_card_key',v_card->>'key',
           'source_name',public.private_card_effect_name_v1(v_card),
           'effect_id',v_def->>'effectId',
           'label',v_label,
           'current_file_count',v_file_count,
           'required_file_count',v_required_file,
           'required_case_phase',v_required_phase
         ));
       END IF;
     END IF;
   END LOOP;
 END LOOP;
 RETURN jsonb_build_object(
   'activations',v_items,
   'locked_activations',v_locked,
   'current_file_count',v_file_count,
   'case_phase',v_board.case_phase
 );
END
$function$;

REVOKE ALL ON FUNCTION public.get_private_card_effect_activations_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_private_card_effect_activations_v1(uuid) TO authenticated;
