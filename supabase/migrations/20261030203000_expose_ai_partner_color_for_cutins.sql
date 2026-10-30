-- Expose the AI player's partner colour even while a contact is pending,
-- so conditional cut-in cards can be evaluated before the AI responds.
CREATE OR REPLACE FUNCTION public.get_private_ai_card_effect_activations_v1(p_room_id uuid, p_ai_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_catalog jsonb;
 v_board public.room_player_turn_boards%rowtype;
 v_card jsonb;
 v_def jsonb;
 v_used jsonb;
 v_turn integer; v_is_own_turn boolean; v_turn_step text;
 v_items jsonb := '[]'::jsonb;
 v_event_items jsonb := '[]'::jsonb;
 v_game public.room_player_game_states%rowtype;
 v_context jsonb := '{}'::jsonb;

 v_case_key text; v_case_id text; v_case_name text; v_case_card jsonb;
 v_pending boolean := false;
 v_partner_color text;
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM public.private_ai_battles b
   WHERE b.room_id = p_room_id AND b.ai_user_id = p_ai_user_id
 ) THEN
   RAISE EXCEPTION 'AI 대전 정보를 찾을 수 없습니다.';
 END IF;

 SELECT m.turn_number, m.current_turn_user_id=p_ai_user_id, m.turn_step,
        m.pending_action IS NOT NULL
 INTO v_turn, v_is_own_turn, v_turn_step, v_pending
 FROM public.room_match_states m
 WHERE m.room_id = p_room_id
   AND m.phase = 'playing'
   AND NOT m.game_over;

 IF NOT FOUND THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb, 'event_candidates', '[]'::jsonb,
     'partner_color', NULL);
 END IF;

 SELECT * INTO v_board
 FROM public.room_player_turn_boards
 WHERE room_id = p_room_id AND user_id = p_ai_user_id;

 IF NOT FOUND THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb, 'event_candidates', '[]'::jsonb,
     'partner_color', NULL);
 END IF;

 v_partner_color := public.private_card_effect_partner_color_v1(p_room_id, p_ai_user_id);

 IF coalesce(v_pending,false)
    OR (coalesce(v_is_own_turn,false) AND coalesce(v_turn_step,'') NOT IN ('file','main'))
    OR EXISTS (SELECT 1 FROM public.private_card_effect_runs_v1 r WHERE r.room_id = p_room_id) THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb, 'event_candidates', '[]'::jsonb,
     'partner_color', v_partner_color);
 END IF;

 SELECT definitions INTO v_catalog
 FROM public.private_card_effect_catalog_v1
 WHERE catalog_id = 'main';

 FOR v_card IN
   SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb))
 LOOP
   IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;
   FOR v_def IN
     SELECT d.value
     FROM jsonb_array_elements(coalesce(v_catalog, '[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event' = 'character.activated_ability'
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean, false)
       AND public.private_card_effect_matches_id_v1(v_card, coalesce(d.value->'cardIds', '[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean, false) THEN
       v_used := coalesce(v_card->'dsl_effect_uses', '[]'::jsonb);
       IF EXISTS (
         SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id' = v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number', '')::integer, -1) = v_turn
       ) THEN
         CONTINUE;
       END IF;
     END IF;

     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id, p_ai_user_id, p_ai_user_id, v_card, v_context, '{}'::jsonb,
       coalesce(v_def->'conditions', '[]'::jsonb)
     ) THEN
       CONTINUE;
     END IF;

     v_items := v_items || jsonb_build_array(jsonb_build_object(
       'source_instance_id', v_card->>'instance_id',
       'effect_id', v_def->>'effectId',
       'label', coalesce(v_def->>'activationLabelKo', v_def->>'effectId', '카드 효과'),
       'definition', v_def
     ));
   END LOOP;
 END LOOP;



 IF v_board.partner_mr_card IS NOT NULL
    AND public.private_card_effect_is_active_v1(v_board.partner_mr_card) THEN
   v_card:=v_board.partner_mr_card;
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((d.value->>'allowPartnerArea')::boolean,false)
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
         'definition',v_def
       ));
     END IF;
   END LOOP;
 END IF;

 IF v_board.partner_mr_card IS NOT NULL
    AND public.private_card_effect_is_active_v1(v_board.partner_mr_card) THEN
   v_card:=v_board.partner_mr_card;
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((d.value->>'allowPartnerArea')::boolean,false)
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
         'definition',v_def
       ));
     END IF;
   END LOOP;
 END IF;

 FOR v_card IN
   SELECT value FROM jsonb_array_elements(coalesce(v_board.partner_non_mr_cards,'[]'::jsonb))
 LOOP
   IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((d.value->>'allowPartnerArea')::boolean,false)
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
         'definition',v_def
       ));
     END IF;
   END LOOP;
 END LOOP;
 
 IF coalesce(v_is_own_turn,false)
    AND coalesce(v_turn_step,'')='main'
    AND NOT coalesce(v_board.base_card_played_this_turn,false)
    AND NOT coalesce(v_board.character_played_this_turn,false) THEN
   SELECT * INTO v_game
   FROM public.room_player_game_states
   WHERE room_id=p_room_id AND user_id=p_ai_user_id;

   v_context:=jsonb_build_object(
     'entry',jsonb_build_object('method','event_play'),
     'turn_number',v_turn
   );
   FOR v_card IN
     SELECT value
     FROM jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb))
     WHERE lower(coalesce(value->>'card_type',''))='event'
   LOOP
     FOR v_def IN
       SELECT d.value
       FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
       WHERE d.value->'trigger'->>'event'='event.played'
         AND NOT coalesce((d.value->>'continuous')::boolean,false)
         AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
     LOOP
       IF public.private_card_effect_conditions_match_v1(
         p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,
         coalesce(v_def->'conditions','[]'::jsonb)
       ) THEN
         v_event_items:=v_event_items||jsonb_build_array(jsonb_build_object(
           'source_instance_id',v_card->>'instance_id',
           'effect_id',v_def->>'effectId',
           'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','이벤트 효과'),
           'definition',v_def
         ));
       END IF;
     END LOOP;
   END LOOP;
   v_context:='{}'::jsonb;
 END IF;

 v_case_key:=upper(regexp_replace(coalesce(v_board.event_key,''),'[^A-Za-z0-9]','','g'));
 IF v_case_key IN ('B10083P','B10083','1139') THEN
   v_case_id:='1139'; v_case_name:='돌아오지 않는 형사';
 ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
   v_case_id:='1261'; v_case_name:='코난 VS 괴도 키드';
 ELSE
   v_case_id:=NULL;
 END IF;

 IF v_case_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.room_match_states m
      WHERE m.room_id=p_room_id AND m.current_turn_user_id=p_ai_user_id
        AND m.phase='playing' AND NOT m.game_over AND m.turn_step='main'
        AND m.pending_action IS NULL
    ) THEN
   v_case_card:=jsonb_build_object(
     'instance_id','case:'||v_board.event_key,
     'key',v_board.event_key,
     'card_id',v_case_id,
     'card_num',v_board.event_key,
     'database_id',v_board.event_key,
     'card_type','event',
     'type','event',
     'name',v_case_name
   );
   FOR v_def IN
     SELECT d.value
     FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='case.activated_ability'
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_case_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce(v_board.case_effect_uses->>(v_def->>'effectId'),'')=v_turn::text THEN
       CONTINUE;
     END IF;
     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_case_card,v_context,'{}'::jsonb,
       coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       CONTINUE;
     END IF;
     v_items:=v_items||jsonb_build_array(jsonb_build_object(
       'source_instance_id','case:'||v_board.event_key,
       'source_kind','case',
       'effect_id',v_def->>'effectId',
       'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','사건 효과'),
       'definition',v_def
     ));
   END LOOP;
 END IF;
 RETURN jsonb_build_object('activations', v_items, 'event_candidates', v_event_items,
   'partner_color', v_partner_color);
END
$function$

