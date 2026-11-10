-- FILEn card-effect conditions count the assisted partner card as one additional file.
-- Keep the activation availability/readout on the same effective count.
BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_fact_v1(p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb, p_context jsonb, p_vars jsonb, p_fact text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_match public.room_match_states%rowtype; v_game public.room_player_game_states%rowtype;
 v_board public.room_player_turn_boards%rowtype; v_other_game public.room_player_game_states%rowtype;
 v_cards jsonb; v_result jsonb; v_kw text; v_path text[]; v_bool boolean; v_count integer;
BEGIN
 SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
 IF p_fact='player.file.count' THEN
   -- FILE conditions count the partner card when it has been assisted this turn.
   RETURN to_jsonb(coalesce(v_board.file_count,0)
     + CASE WHEN coalesce(v_board.partner_assist_used,false) THEN 1 ELSE 0 END);
 END IF;
 IF p_fact='player.deployable_level' THEN
   RETURN to_jsonb(coalesce(v_board.file_count,0) + CASE WHEN coalesce(v_board.partner_assist_used,false) THEN 1 ELSE 0 END);
 END IF;
 SELECT * INTO v_other_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id<>p_actor ORDER BY seat LIMIT 1;
 IF p_fact='player.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.field.character.count' THEN
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
   WHERE public.private_card_effect_is_character_v1(e.value);
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='opponent.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_other_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.deck.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb))); END IF;
 IF p_fact='player.partner.color' THEN RETURN to_jsonb(public.private_card_effect_partner_color_v1(p_room_id,p_actor)); END IF;
 IF p_fact='turn.is_source_controller_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id=p_source_user); END IF;
 IF p_fact='turn.is_opponent_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id IS DISTINCT FROM p_source_user); END IF;
 IF p_fact='entry.method' THEN RETURN coalesce(p_context#>'{entry,method}','null'::jsonb); END IF;
 IF p_fact='entry.is_first_character_this_turn' THEN RETURN coalesce(p_context#>'{entry,is_first_character_this_turn}','false'::jsonb); END IF;
 IF p_fact='entry.source.level' THEN RETURN to_jsonb(public.private_card_effect_level_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb))); END IF;
 IF p_fact='entry.source.card_type' THEN RETURN coalesce(p_context#>'{entry,source,card_type}',p_context#>'{entry,source,type}','null'::jsonb); END IF;
 IF p_fact='player.evidence.facedown_count' THEN
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) e(value)
   WHERE NOT coalesce(nullif(e.value->>'face_up','')::boolean,false);
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_board.case_phase,'incident'));
 END IF;
 IF p_fact='source.instance_id' THEN
   RETURN to_jsonb(coalesce(p_source_card->>'instance_id',''));
 END IF;
 IF p_fact='entry.source.card_name' THEN
   RETURN to_jsonb(public.private_card_effect_name_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb)));
 END IF;
 IF p_fact='entry.source.instance_id' THEN
   RETURN coalesce(p_context#>'{entry,source,instance_id}','null'::jsonb);
 END IF;
 IF p_fact='entry.controller_is_source_controller' THEN
   RETURN to_jsonb(coalesce(p_context#>>'{entry,controller_user_id}',p_source_user::text)=p_source_user::text);
 END IF;
 IF p_fact='contact.source.ap' THEN
   IF p_context#>'{contact,source_ap}' IS NOT NULL THEN
     RETURN p_context#>'{contact,source_ap}';
   ELSIF nullif(p_context#>>'{contact,attacker_user_id}','')::uuid=p_source_user THEN
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,attacker_ap}','')::numeric,0));
   ELSE
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,target_ap}','')::numeric,0));
   END IF;
 END IF;
 IF p_fact='contact.target.ap' THEN
   IF p_context#>'{contact,target_ap}' IS NOT NULL THEN
     RETURN p_context#>'{contact,target_ap}';
   ELSIF nullif(p_context#>>'{contact,attacker_user_id}','')::uuid=p_source_user THEN
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,target_ap}','')::numeric,0));
   ELSE
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,attacker_ap}','')::numeric,0));
   END IF;
 END IF;
 IF p_fact='source.status' THEN
   RETURN to_jsonb(coalesce(p_source_card->>'status',CASE WHEN coalesce((p_source_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END));
 END IF;
 IF p_fact='source.is_active' THEN RETURN to_jsonb(public.private_card_effect_is_active_v1(p_source_card)); END IF;
 IF p_fact='source.under_cards.count' THEN
   RETURN to_jsonb(jsonb_array_length(coalesce(p_source_card->'stacked_cards',p_source_card->'under_cards','[]'::jsonb)));
 END IF;
 IF p_fact='player.field.has_card_name' THEN RETURN 'null'::jsonb; END IF;
 IF p_fact='player.remove_area.count_matching_trait' THEN RETURN 'null'::jsonb; END IF;
 IF p_fact LIKE 'player.field.has_keyword.%' THEN
   v_kw := substr(p_fact,length('player.field.has_keyword.')+1);
   SELECT EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     WHERE public.private_card_effect_has_keyword_v1(e.value,v_kw)
   ) INTO v_bool;
   RETURN to_jsonb(v_bool);
 END IF;
  IF p_fact LIKE 'vars.%.has_rarity_mr' THEN
   v_path := string_to_array(substr(p_fact,6),'.');
   v_path := v_path[1:array_length(v_path,1)-1];
   v_cards := p_vars #> v_path;
   RETURN to_jsonb(EXISTS(
     SELECT 1
     FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
     CROSS JOIN LATERAL (SELECT coalesce(e.value->'card',e.value) AS card) c
     WHERE upper(coalesce(
       c.card->>'rarity',
       c.card->>'rarity_code',
       c.card#>>'{sourceData,rarity}',
       c.card#>>'{raw,rarity}',
       ''
     )) IN ('MR','MRP')
   ));
 END IF;
 IF p_fact LIKE 'vars.%' THEN 
   v_path := string_to_array(substr(p_fact,6),'.');
   IF array_length(v_path,1)>1 AND v_path[array_length(v_path,1)]='count' THEN
     v_path := v_path[1:array_length(v_path,1)-1];
     v_result := p_vars #> v_path;
     IF jsonb_typeof(v_result)='array' THEN RETURN to_jsonb(jsonb_array_length(v_result)); END IF;
     IF jsonb_typeof(v_result)='object' THEN RETURN to_jsonb((SELECT count(*) FROM jsonb_object_keys(v_result))); END IF;
     RETURN to_jsonb(0);
   END IF;
   IF p_fact LIKE 'vars.%.has_level_at_least_8' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     RETURN to_jsonb(EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))>=8));
   END IF;
   RETURN coalesce(p_vars #> v_path,'null'::jsonb);
 END IF;
 RETURN 'null'::jsonb;
END
$function$
;

CREATE OR REPLACE FUNCTION public.get_private_card_effect_activations_v1(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
 v_case_card jsonb; v_case_key text; v_case_id text; v_case_name text;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
 IF NOT FOUND THEN RAISE EXCEPTION '자신의 보드를 찾을 수 없습니다.'; END IF;
 -- Keep the activation list and FILE lock labels consistent with the shared FILE fact.
 v_file_count:=coalesce(v_board.file_count,0)
   + CASE WHEN coalesce(v_board.partner_assist_used,false) THEN 1 ELSE 0 END;

 IF EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    OR EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND (game_over OR phase<>'playing')) THEN
   RETURN jsonb_build_object('activations','[]'::jsonb,'locked_activations','[]'::jsonb,'current_file_count',v_file_count);
 END IF;

 FOR v_card IN SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) LOOP
   
   FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='character.activated_ability'
        AND (
          public.private_card_effect_is_active_v1(v_card)
          OR (
            EXISTS (
              SELECT 1 FROM jsonb_array_elements(coalesce(value->'steps','[]'::jsonb)) step(value)
              WHERE step.value->>'op'='ready_source_character'
            )
            AND (
              coalesce((v_card->>'rested')::boolean,false)
              OR lower(coalesce(v_card->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
            )
            AND NOT (
              coalesce((v_card->>'stunned')::boolean,false)
              OR coalesce((v_card->>'stun')::boolean,false)
              OR coalesce((v_card->>'is_stunned')::boolean,false)
              OR lower(coalesce(v_card->>'status','')) IN ('stunned','stun','스턴')
            )
          )
        )
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
        AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb))
       AND coalesce((value->>'continuous')::boolean,false)=false
       AND (coalesce(value->>'activationTiming','')='any' OR EXISTS(
         SELECT 1 FROM public.room_match_states m WHERE m.room_id=p_room_id
          AND m.current_turn_user_id=v_user AND m.turn_step IN ('begin','file','main')
       ))
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
         'label',v_label,'activation_timing',coalesce(v_def->>'activationTiming','turn'),
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
           'label',v_label,'activation_timing',coalesce(v_def->>'activationTiming','turn'),
           'current_file_count',v_file_count,
           'required_file_count',v_required_file,
           'required_case_phase',v_required_phase
         ));
       END IF;
     END IF;
   END LOOP;
 END LOOP;
 IF v_board.partner_mr_card IS NOT NULL
    AND public.private_card_effect_is_active_v1(v_board.partner_mr_card) THEN
   v_card:=v_board.partner_mr_card;
   FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='character.activated_ability'
        AND (
          public.private_card_effect_is_active_v1(v_card)
          OR (
            EXISTS (
              SELECT 1 FROM jsonb_array_elements(coalesce(value->'steps','[]'::jsonb)) step(value)
              WHERE step.value->>'op'='ready_source_character'
            )
            AND (
              coalesce((v_card->>'rested')::boolean,false)
              OR lower(coalesce(v_card->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
            )
            AND NOT (
              coalesce((v_card->>'stunned')::boolean,false)
              OR coalesce((v_card->>'stun')::boolean,false)
              OR coalesce((v_card->>'is_stunned')::boolean,false)
              OR lower(coalesce(v_card->>'status','')) IN ('stunned','stun','스턴')
            )
          )
        )
       AND coalesce((value->>'allowPartnerArea')::boolean,false)
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
        AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb))
       AND coalesce((value->>'continuous')::boolean,false)=false
       AND (coalesce(value->>'activationTiming','')='any' OR EXISTS(
         SELECT 1 FROM public.room_match_states m WHERE m.room_id=p_room_id
          AND m.current_turn_user_id=v_user AND m.turn_step IN ('begin','file','main')
       ))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     v_conditions:=coalesce(v_def->'conditions','[]'::jsonb);
     IF public.private_card_effect_conditions_match_v1(p_room_id,v_user,v_user,v_card,v_context,'{}'::jsonb,v_conditions) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'source_card_key',v_card->>'key',
         'source_name',public.private_card_effect_name_v1(v_card),
         'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
         'activation_timing',coalesce(v_def->>'activationTiming','turn'),
         'current_file_count',v_file_count
       ));
     END IF;
   END LOOP;
 END IF;


 FOR v_card IN
   SELECT value
   FROM jsonb_array_elements(coalesce(v_board.partner_non_mr_cards,'[]'::jsonb))
 LOOP
   IF NOT public.private_card_effect_is_active_v1(v_card) THEN
     CONTINUE;
   END IF;

   FOR v_def IN
     SELECT value
     FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((value->>'allowPartnerArea')::boolean,false)
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
        AND public.private_card_effect_matches_id_v1(v_card,coalesce(value->'cardIds','[]'::jsonb))
       AND coalesce((value->>'continuous')::boolean,false)=false
       AND (
         coalesce(value->>'activationTiming','')='any'
         OR EXISTS (
           SELECT 1
           FROM public.room_match_states m
           WHERE m.room_id=p_room_id
             AND m.current_turn_user_id=v_user
             AND m.turn_step IN ('begin','file','main')
         )
       )
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS (
         SELECT 1
         FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn
       ) THEN
         CONTINUE;
       END IF;
       v_used:=v_used||jsonb_build_array(jsonb_build_object(
         'effect_id',v_def->>'effectId',
         'turn_number',v_turn
       ));
       PERFORM public.private_card_effect_patch_card_v1(
         p_room_id,v_user,v_card->>'instance_id',
         jsonb_build_object('dsl_effect_uses',v_used)
       );
     END IF;

     v_conditions:=coalesce(v_def->'conditions','[]'::jsonb);
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,v_user,v_user,v_card,v_context,'{}'::jsonb,v_conditions
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'source_card_key',v_card->>'key',
         'source_name',public.private_card_effect_name_v1(v_card),
         'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
         'activation_timing',coalesce(v_def->>'activationTiming','turn'),
         'current_file_count',v_file_count
       ));
     END IF;
   END LOOP;
 END LOOP;

 -- Event-card abilities are synthetic sources rather than field cards.
 v_case_key:=upper(regexp_replace(coalesce(v_board.event_key,''),'[^A-Za-z0-9]','','g'));
 IF v_case_key IN ('B10083P','B10083','1139') THEN
   v_case_id:='1139'; v_case_name:='돌아오지 않는 형사';
 ELSIF v_case_key IN ('B11098','B11098P','1261') OR coalesce(v_board.event_rule_code,'')='conan_vs_kid_1261' THEN
   v_case_id:='1261'; v_case_name:='코난 VS 괴도 키드';
 ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
   v_case_id:='0806'; v_case_name:='흔들리는 마음';
 ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_board.event_rule_code,'')='culprits_1046' THEN
   v_case_id:='1046'; v_case_name:='범인들의 범행';
 ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
   v_case_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
 ELSIF v_case_key IN ('PR320','PR320P','1164') OR coalesce(v_board.event_rule_code,'')='police_academy_1164' THEN
   v_case_id:='1164'; v_case_name:='경찰학교의 목욕탕 청소';
 ELSE
   v_case_id:=NULL;
 END IF;
 IF v_case_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.room_match_states m WHERE m.room_id=p_room_id AND m.current_turn_user_id=v_user AND m.turn_step='main' AND m.pending_action IS NULL) THEN
   v_case_card:=jsonb_build_object(
     'instance_id','case:'||v_board.event_key,'key',v_board.event_key,
     'card_id',v_case_id,'card_num',v_board.event_key,'database_id',v_board.event_key,
     'card_type','event','type','event','name',v_case_name
   );
   FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='case.activated_ability'
       AND public.private_card_effect_matches_id_v1(v_case_card,coalesce(value->'cardIds','[]'::jsonb))
       AND coalesce((value->>'continuous')::boolean,false)=false
       AND (coalesce(value->>'activationTiming','')='any' OR EXISTS(
         SELECT 1 FROM public.room_match_states m WHERE m.room_id=p_room_id
          AND m.current_turn_user_id=v_user AND m.turn_step IN ('begin','file','main')
       ))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false)
        AND coalesce(v_board.case_effect_uses->>(v_def->>'effectId'),'')=v_turn::text THEN
       CONTINUE;
     END IF;
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,v_user,v_user,v_case_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_case_card->>'instance_id','source_card_key',v_board.event_key,
         'source_name',v_case_name,'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId'),'activation_timing',coalesce(v_def->>'activationTiming','turn'),
         'current_file_count',v_file_count,'required_file_count',NULL,
         'required_case_phase',v_board.case_phase
       ));
     END IF;
   END LOOP;
 END IF;

 RETURN jsonb_build_object(
   'activations',v_items,
   'locked_activations',v_locked,
   'current_file_count',v_file_count,
   'case_phase',v_board.case_phase
 );
END
$function$
;

COMMIT;
