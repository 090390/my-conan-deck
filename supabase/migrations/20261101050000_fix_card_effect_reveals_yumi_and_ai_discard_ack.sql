-- Shared reveal acknowledgements, object-safe investigation facts,
-- AI-selected hand-card confirmation, and Next Hint entry triggers.
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
 SELECT * INTO v_other_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id<>p_actor ORDER BY seat LIMIT 1;

 IF p_fact='player.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.evidence.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))); END IF;
 IF p_fact='player.evidence.facedown_count' THEN
   SELECT count(*)::integer INTO v_count FROM jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) e(value)
   WHERE NOT coalesce((e.value->>'face_up')::boolean,false);
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='game.total_evidence_count' THEN
   SELECT coalesce(sum(evidence_count),0)::integer INTO v_count FROM public.room_player_turn_boards WHERE room_id=p_room_id;
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='turn.number' THEN RETURN to_jsonb(coalesce(v_match.turn_number,0)); END IF;
 IF p_fact='contact.source.ap' THEN
   RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,source_ap}','')::numeric,0));
 END IF;
 IF p_fact='contact.target.ap' THEN
   RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,target_ap}','')::numeric,0));
 END IF;
 IF p_fact='opponent.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_other_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.deck.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb))); END IF;
 IF p_fact='player.file.count' THEN RETURN to_jsonb(coalesce(v_board.file_count,0)); END IF;
 IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_board.case_phase,v_match.case_phase,'incident'));
 END IF;
 IF p_fact='player.event.has_non_blue_color' THEN
   SELECT d.event_has_non_blue_color INTO v_bool
   FROM public.room_player_decks d
   WHERE d.room_id=p_room_id AND d.user_id=p_actor;
   RETURN coalesce(to_jsonb(v_bool),'null'::jsonb);
 END IF;
 IF p_fact='player.event.has_detective_vs_kid_trait' THEN
   RETURN to_jsonb(
     coalesce(v_board.event_rule_code,'')='conan_vs_kid_1261'
     OR upper(regexp_replace(coalesce(v_board.event_key,''),'[^A-Za-z0-9]','','g')) IN ('B11098','B11098P','1261')
   );
 END IF;
 IF p_fact='player.partner.color' THEN RETURN to_jsonb(public.private_card_effect_partner_color_v1(p_room_id,p_actor)); END IF;
 IF p_fact='turn.is_source_controller_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id=p_source_user); END IF;
 IF p_fact='turn.is_opponent_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id IS DISTINCT FROM p_source_user); END IF;
 IF p_fact='entry.method' THEN RETURN coalesce(p_context#>'{entry,method}','null'::jsonb); END IF;
 IF p_fact='entry.is_first_character_this_turn' THEN RETURN coalesce(p_context#>'{entry,is_first_character_this_turn}','false'::jsonb); END IF;
 IF p_fact='event.revealed_kudo_or_ran' THEN
   RETURN to_jsonb(EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(p_context->'revealed_hand_cards','[]'::jsonb)) revealed(value)
     WHERE public.private_card_effect_name_matches_v1(coalesce(revealed.value->'card',revealed.value),'工藤新一')
        OR public.private_card_effect_name_matches_v1(coalesce(revealed.value->'card',revealed.value),'毛利蘭')
   ));
 END IF;
 IF p_fact='entry.source.level' THEN RETURN to_jsonb(public.private_card_effect_level_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb))); END IF;
 IF p_fact='entry.source.color' THEN
   RETURN to_jsonb(public.private_card_effect_color_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb)));
 END IF;
 IF p_fact='event.removed_by_controller' THEN
   RETURN to_jsonb(coalesce(p_context->>'removed_by_user_id','')=p_actor::text);
 END IF;
 IF p_fact='entry.source.card_type' THEN RETURN coalesce(p_context#>'{entry,source,card_type}',p_context#>'{entry,source,type}','null'::jsonb); END IF;
 IF p_fact='entry.source.card_name' THEN
   RETURN coalesce(p_context#>'{entry,source,name}',p_context#>'{entry,source,name_ja}',
     p_context#>'{entry,source,nameJa}',p_context#>'{entry,source,title}',p_context#>'{entry,source,card_name}','null'::jsonb);
 END IF;
 IF p_fact='entry.source.card_id' THEN
   RETURN coalesce(p_context#>'{entry,source,card_id}',p_context#>'{entry,source,cardId}',
     p_context#>'{entry,source,database_id}',p_context#>'{entry,source,databaseId}',
     p_context#>'{entry,source,key}',p_context#>'{entry,source,id}','null'::jsonb);
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

   IF p_fact LIKE 'vars.%.has_rarity_mr' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     RETURN to_jsonb(EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE upper(coalesce(e.value#>>'{card,rarity}',e.value->>'rarity','')) IN ('MR','MRP')
     ));
   END IF;
   IF p_fact LIKE 'vars.%.has_level_at_most_7' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     -- investigate_opponent_deck stores a single object with a precomputed
     -- has_level_at_most_7 flag; other effects may store a card array.
     IF jsonb_typeof(v_cards)='object' THEN
       IF v_cards ? 'has_level_at_most_7' THEN
         RETURN to_jsonb(coalesce((v_cards->>'has_level_at_most_7')::boolean,false));
       ELSIF v_cards ? 'card' THEN
         RETURN to_jsonb(public.private_card_effect_level_v1(v_cards->'card')<=7);
       ELSIF jsonb_typeof(v_cards->'revealed')='array' THEN
         v_cards:=v_cards->'revealed';
       ELSE
         RETURN to_jsonb(false);
       END IF;
     END IF;
     IF jsonb_typeof(v_cards)<>'array' THEN RETURN to_jsonb(false); END IF;
     RETURN to_jsonb(EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_cards) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))<=7
     ));
   END IF;

   IF p_fact LIKE 'vars.%.has_rarity_mr' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     RETURN to_jsonb(EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE upper(coalesce(e.value#>>'{card,rarity}',e.value->>'rarity','')) IN ('MR','MRP')
     ));
   END IF;
   IF p_fact LIKE 'vars.%.has_level_at_most_7' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     -- investigate_opponent_deck stores a single object with a precomputed
     -- has_level_at_most_7 flag; other effects may store a card array.
     IF jsonb_typeof(v_cards)='object' THEN
       IF v_cards ? 'has_level_at_most_7' THEN
         RETURN to_jsonb(coalesce((v_cards->>'has_level_at_most_7')::boolean,false));
       ELSIF v_cards ? 'card' THEN
         RETURN to_jsonb(public.private_card_effect_level_v1(v_cards->'card')<=7);
       ELSIF jsonb_typeof(v_cards->'revealed')='array' THEN
         v_cards:=v_cards->'revealed';
       ELSE
         RETURN to_jsonb(false);
       END IF;
     END IF;
     IF jsonb_typeof(v_cards)<>'array' THEN RETURN to_jsonb(false); END IF;
     RETURN to_jsonb(EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_cards) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))<=7
     ));
   END IF;
   RETURN coalesce(p_vars #> v_path,'null'::jsonb);
 END IF;
 RETURN 'null'::jsonb;
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_run_v1(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_run public.private_card_effect_runs_v1%rowtype;
 v_def jsonb; v_step jsonb; v_op text; v_from text; v_to text; v_save text; v_path text[];
 v_vars jsonb; v_data jsonb; v_options jsonb; v_selected jsonb; v_remaining jsonb; v_ordered jsonb;
 v_item jsonb; v_card jsonb; v_wrapper jsonb; v_current jsonb; v_patch jsonb; v_pending jsonb; v_waiting jsonb;
 v_game public.room_player_game_states%rowtype; v_board public.room_player_turn_boards%rowtype;
 v_match public.room_match_states%rowtype; v_owner uuid; v_source_user uuid; v_target_owner uuid;
 v_i integer; v_j integer; v_n integer; v_examined integer; v_matched boolean; v_found boolean;
 v_ids text[]; v_selected_ids text[]; v_effect_id text; v_turn integer; v_amount integer; v_ack_required jsonb; v_ack_ids jsonb; v_ack_user uuid; v_ai_user_id uuid; v_new_ap numeric;
 v_keyword text; v_deck jsonb; v_seen jsonb; v_match_filter jsonb; v_name text;
BEGIN
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF v_run.waiting IS NOT NULL THEN RETURN; END IF;

 LOOP
   SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND THEN RETURN; END IF;

   IF v_run.effect_index >= jsonb_array_length(coalesce(v_run.effect_queue,'[]'::jsonb)) THEN
     PERFORM public.private_card_effect_move_event_to_remove_v1(
       p_room_id,v_run.source_user_id,v_run.source_instance_id
     );
     DELETE FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=CASE WHEN pending_action->>'type' LIKE 'card_effect_%' THEN NULL ELSE pending_action END,
           state_version=state_version+1,
           last_action_label='카드 효과 처리가 완료되었습니다.'
       WHERE room_id=p_room_id;
     RETURN;
   END IF;

   v_def:=v_run.effect_queue->v_run.effect_index;
   IF v_run.step_index >= jsonb_array_length(coalesce(v_def->'steps','[]'::jsonb)) THEN
     UPDATE public.private_card_effect_runs_v1
       SET effect_index=effect_index+1, step_index=0, variables='{}'::jsonb, waiting=NULL, updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;
   END IF;

   v_step:=v_def->'steps'->v_run.step_index;
   v_op:=v_step->>'op';
   v_vars:=coalesce(v_run.variables,'{}'::jsonb);
   v_owner:=v_run.actor_user_id;
   v_source_user:=v_run.source_user_id;
   v_effect_id:=v_def->>'effectId';
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;

   IF v_step ? 'when' AND NOT public.private_card_effect_condition_matches_v1(
     p_room_id,v_owner,v_source_user,coalesce(v_run.context->'source_card','{}'::jsonb),
     coalesce(v_run.context,'{}'::jsonb),v_vars,v_step->'when'
   ) THEN
     UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
     CONTINUE;
   END IF;

   IF v_op='refill_deck_from_remove_area' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     IF jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)) < 4 AND coalesce((v_step->>'includeRemoveArea')::boolean,false) THEN
       v_deck:=coalesce(v_game.deck_order,'[]'::jsonb)||coalesce(v_game.remove_cards,'[]'::jsonb);
       SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb) INTO v_data FROM jsonb_array_elements(v_deck) e(value);
       UPDATE public.room_player_game_states SET deck_order=v_data,remove_cards='[]'::jsonb,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET remove_count=0,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
     END IF;

   ELSIF v_op='peek_top_cards' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_n:=least(greatest(0,coalesce((v_step->>'count')::integer,0)),jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)));
     SELECT coalesce(jsonb_agg(jsonb_build_object('instance_id',e.value->>'instance_id','owner_user_id',v_owner,'zone','peek','card',e.value) ORDER BY e.ordinality)
       FILTER(WHERE e.ordinality<=v_n),'[]'::jsonb)
       INTO v_data FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.ordinality>v_n),'[]'::jsonb)
       INTO v_deck FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states SET deck_order=v_deck,updated_at=now() WHERE room_id=p_room_id AND user_id=v_owner;
     UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],v_data,true),
       step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
     CONTINUE;

   ELSIF v_op='select_cards' THEN
     v_from:=v_step->>'from';
     v_options:=public.private_card_effect_get_candidates_v1(
       p_room_id,v_owner,v_source_user,v_from,coalesce(v_step->'filter','{}'::jsonb),
       coalesce(v_step->>'targetController','self'),v_step->>'uniqueBy',v_vars
     );
     v_n:=jsonb_array_length(coalesce(v_options,'[]'::jsonb));
     IF v_n=0 AND coalesce((v_step->>'min')::integer,0)=0 THEN
       UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],'[]'::jsonb,true),
         step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     IF v_n < coalesce((v_step->>'min')::integer,0) THEN
       RAISE EXCEPTION '효과 처리에 필요한 선택 대상이 부족합니다.';
     END IF;
     v_waiting:=jsonb_build_object('kind','selection','save_as',v_step->>'saveAs','options',v_options,
       'min',coalesce((v_step->>'min')::integer,0),'max',coalesce((v_step->>'max')::integer,1),
       'unique_by',v_step->>'uniqueBy','prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'));
     IF nullif(v_step->>'displayVariable','') IS NOT NULL THEN
       v_path:=string_to_array(replace(v_step->>'displayVariable','vars.',''),'.');
       v_waiting:=v_waiting||jsonb_build_object('display_options',coalesce(v_vars #> v_path,'[]'::jsonb));
     END IF;
     v_pending:=jsonb_build_object('type','card_effect_selection','effect_id',v_effect_id,
       'source_instance_id',v_run.source_instance_id,'chooser_user_id',v_owner,
       'prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'),
       'min',coalesce((v_step->>'min')::integer,0),'max',coalesce((v_step->>'max')::integer,1),
       'optional',coalesce((v_step->>'optional')::boolean,false));
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
       last_action_label='카드 효과: 플레이어의 카드 선택을 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='filter_cards' THEN
     -- Filter an existing variable without asking the player to select cards.
     -- Keep the same wrapped card shape used by select_cards so later
     -- conditions can inspect vars.<saveAs>.count and the matched cards.
     v_from:=coalesce(v_step->>'from','');
     v_options:=public.private_card_effect_get_candidates_v1(
       p_room_id,v_owner,v_source_user,v_from,coalesce(v_step->'filter','{}'::jsonb),
       coalesce(v_step->>'targetController','self'),v_step->>'uniqueBy',v_vars
     );
     v_vars:=jsonb_set(coalesce(v_vars,'{}'::jsonb),ARRAY[v_step->>'saveAs'],coalesce(v_options,'[]'::jsonb),true);
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;

   ELSIF v_op='rest_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF nullif(v_card->>'instance_id','') IS NOT NULL THEN
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
           jsonb_build_object('rested',true,'status','rested'));
       END IF;
     END LOOP;

   ELSIF v_op='ready_source_character' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,
         jsonb_build_object('rested',false,'status','active'));
     END IF;

   ELSIF v_op='modify_contact_ap' THEN
     SELECT pending_action INTO v_pending
       FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
     IF coalesce(v_pending->>'type','')<>'character_contact' THEN
       RAISE EXCEPTION '컨택 AP를 변경할 진행 중인 컨택이 없습니다.';
     END IF;
     v_amount:=coalesce(nullif(v_step->>'amount','')::integer,0);
     IF v_pending->>'attacker_user_id'=v_source_user::text THEN
       v_pending:=jsonb_set(v_pending,'{attacker_bonus}',
         to_jsonb(coalesce((v_pending->>'attacker_bonus')::integer,0)+v_amount),true);
     ELSIF v_pending->>'target_user_id'=v_source_user::text THEN
       v_pending:=jsonb_set(v_pending,'{target_bonus}',
         to_jsonb(coalesce((v_pending->>'target_bonus')::integer,0)+v_amount),true);
     ELSE
       RAISE EXCEPTION '컨택 참가자와 효과 발동 카드의 소유자가 일치하지 않습니다.';
     END IF;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
       last_action_label='카드 효과: 컨택 AP가 변경되었습니다.' WHERE room_id=p_room_id;

   ELSIF v_op='flip_evidence' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_selected_ids:='{}'::text[];
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       IF nullif(v_card->>'instance_id','') IS NOT NULL THEN
         v_selected_ids:=array_append(v_selected_ids,v_card->>'instance_id');
       END IF;
     END LOOP;
     UPDATE public.room_player_game_states g
       SET evidence_cards=coalesce((
         SELECT jsonb_agg(CASE WHEN e.value->>'instance_id'=ANY(v_selected_ids)
           THEN e.value||jsonb_build_object('face_up',true) ELSE e.value END ORDER BY e.ordinality)
         FROM jsonb_array_elements(coalesce(g.evidence_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
       ),'[]'::jsonb),updated_at=now()
       WHERE g.room_id=p_room_id AND g.user_id=v_owner;

   ELSIF v_op='attach_top_card' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
     IF v_card ? 'instance_id' THEN
       UPDATE public.room_player_game_states
         SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_card->>'instance_id'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
       IF v_current IS NULL THEN RAISE EXCEPTION '카드를 겹칠 현장 캐릭터를 찾지 못했습니다.'; END IF;
       v_patch:=jsonb_build_object('under_cards',coalesce(v_current->'under_cards','[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,v_patch);
     END IF;

   ELSIF v_op='win_game' THEN
     UPDATE public.room_match_states
       SET game_over=true,winner_user_id=v_owner,winner_turn_number=turn_number,
           pending_action=NULL,state_version=state_version+1,
           last_action_label='카드 효과로 게임에서 승리했습니다.'
       WHERE room_id=p_room_id AND game_over IS NOT TRUE;

   ELSIF v_op='reveal_opponent_hand' THEN
     SELECT user_id INTO v_target_owner FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality),'[]'::jsonb)
       INTO v_selected
       FROM jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_target_owner);
     v_pending:=jsonb_build_object('type','card_effect_reveal_ack','effect_id',v_effect_id,
       'source_instance_id',v_run.source_instance_id,'chooser_user_id',v_target_owner,
       'source_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','상대 손패 공개를 확인해 주세요.'),
       'revealed_cards',v_selected);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
       last_action_label='카드 효과: 상대 손패 공개 확인을 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='investigate_opponent_deck' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1 FOR UPDATE;
     v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
     IF v_card ? 'instance_id' THEN
       UPDATE public.room_player_game_states
         SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_card->>'instance_id')||jsonb_build_array(v_card),
             updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_game.user_id;
       v_selected:=jsonb_build_array(v_card);
       v_vars:=jsonb_set(coalesce(v_vars,'{}'::jsonb),ARRAY[v_step->>'saveAs'],
         jsonb_build_object('revealed',v_selected,'card',v_card,
           'has_level_at_most_7',coalesce(nullif(v_card->>'cost','')::integer,nullif(v_card->>'level','')::integer,999)<=7),true);
       v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_game.user_id);
       v_pending:=jsonb_build_object('type','card_effect_reveal_ack','effect_id',v_effect_id,
         'source_instance_id',v_run.source_instance_id,'chooser_user_id',v_game.user_id,
         'source_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','상대 덱 위 카드를 공개하고 확인해 주세요.'),
         'revealed_cards',v_selected);
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
       UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
         last_action_label='카드 효과: 상대 덱 위 카드 공개 확인을 기다립니다.' WHERE room_id=p_room_id;
       RETURN;
     ELSE
       v_vars:=jsonb_set(coalesce(v_vars,'{}'::jsonb),ARRAY[v_step->>'saveAs'],
         jsonb_build_object('revealed','[]'::jsonb,'has_level_at_most_7',false),true);
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;

   ELSIF v_op='grant_bond_alias' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_name:=coalesce(v_step->>'name','*');
     SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF nullif(v_card->>'instance_id','') IS NOT NULL THEN
         v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
         v_selected:=coalesce(v_current->'dsl_bond_name_overrides','[]'::jsonb);
         v_selected:=v_selected||jsonb_build_array(jsonb_build_object(
           'name',v_name,'anyName',v_name='*','expires_turn_number',v_turn
         ));
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
           jsonb_build_object('dsl_bond_name_overrides',v_selected));
       END IF;
     END LOOP;

   ELSIF v_op='schedule_move_to_deck_bottom' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF nullif(v_card->>'instance_id','') IS NOT NULL THEN
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
           jsonb_build_object('dsl_return_to_deck_bottom_turn',v_turn,
             'dsl_return_to_deck_bottom_after_user_id',v_owner));
       END IF;
     END LOOP;

   ELSIF v_op='set_turn_flag' THEN
     SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
     UPDATE public.room_player_turn_boards
       SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),
         ARRAY[coalesce(v_step->>'key','')],to_jsonb(v_turn::text),true),
         updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;

   ELSIF v_op='start_contact' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_item:=v_data->0;
     v_card:=coalesce(v_item->'card',v_item);
     v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,NULL);
     IF v_target_owner IS NULL OR v_target_owner=v_owner OR v_card IS NULL OR v_card->>'instance_id' IS NULL THEN
       RAISE EXCEPTION '컨택할 상대 캐릭터를 찾지 못했습니다.';
     END IF;
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '컨택을 시작할 현장 캐릭터를 찾지 못했습니다.'; END IF;
     -- The ability already paid its sleep cost. Temporarily satisfy the normal
     -- declare-contact validation; the action immediately rests the attacker again.
     IF coalesce((v_current->>'rested')::boolean,false) OR coalesce(v_current->>'status','active')='rested' THEN
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,
         jsonb_build_object('rested',false,'status','active'));
     END IF;
     PERFORM public.perform_private_turn_action_v2(p_room_id,'declare_contact',jsonb_build_object(
       'attacker_instance_id',v_run.source_instance_id,
       'target_instance_id',v_card->>'instance_id',
       'target_user_id',v_target_owner,
       'allow_newly_played',false,
       'allow_active_target',false
     ));

   ELSIF v_op='reveal_cards' THEN
      v_path:=string_to_array(replace(coalesce(v_step->>'from',''), 'vars.',''),'.');
      v_data:=v_vars #> v_path;
      SELECT coalesce(jsonb_agg(coalesce(e.value->'card',e.value) ORDER BY e.ordinality),'[]'::jsonb)
        INTO v_selected FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
      IF jsonb_array_length(coalesce(v_selected,'[]'::jsonb))=0 THEN
        UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
        CONTINUE;
      END IF;
      IF coalesce((v_step->>'awaitAcknowledgement')::boolean,false) IS NOT TRUE THEN
        UPDATE public.room_match_states SET state_version=state_version+1,
          last_action_label='카드 효과: 선택한 카드를 공개했습니다.' WHERE room_id=p_room_id;
        UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
        CONTINUE;
      END IF;
      IF coalesce((v_step->>'requireBothAcknowledgements')::boolean,false) THEN
        SELECT coalesce(jsonb_agg(to_jsonb(rp.user_id::text) ORDER BY rp.seat),'[]'::jsonb)
          INTO v_ack_required
          FROM public.room_players rp WHERE rp.room_id=p_room_id;
        IF jsonb_array_length(v_ack_required)<2 THEN
          RAISE EXCEPTION '양측 공개 확인에는 방 참가자 2명이 필요합니다.';
        END IF;
        SELECT ai_user_id INTO v_ai_user_id
          FROM public.private_ai_battles WHERE room_id=p_room_id;
        -- The AI owner has already examined the cards as part of its own effect
        -- resolution, so count that side as acknowledged before asking the human.
        v_ack_ids:=CASE WHEN v_ai_user_id IS NOT NULL AND v_ai_user_id=v_owner
          THEN jsonb_build_array(v_ai_user_id::text) ELSE '[]'::jsonb END;
        SELECT candidate.value::uuid INTO v_ack_user
          FROM jsonb_array_elements_text(v_ack_required) candidate(value)
          WHERE NOT (v_ack_ids @> jsonb_build_array(candidate.value))
          LIMIT 1;
        IF v_ack_user IS NULL THEN
          UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now()
            WHERE room_id=p_room_id;
          CONTINUE;
        END IF;
        v_waiting:=jsonb_build_object(
          'kind','ack','advance_step',true,'require_both_acknowledgements',true,
          'required_user_ids',v_ack_required,'acknowledged_user_ids',v_ack_ids,
          'chooser_user_id',v_ack_user
        );
        v_pending:=jsonb_build_object(
          'type','card_effect_reveal_ack','effect_id',v_effect_id,
          'source_instance_id',v_run.source_instance_id,'chooser_user_id',v_ack_user,
          'source_user_id',v_owner,
          'prompt',coalesce(v_step->>'prompt','공개된 카드를 양쪽 플레이어가 확인해 주세요.'),
          'revealed_cards',v_selected,
          'require_both_acknowledgements',true,
          'required_user_ids',v_ack_required,'acknowledged_user_ids',v_ack_ids
        );
        UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now()
          WHERE room_id=p_room_id;
        UPDATE public.room_match_states
          SET pending_action=v_pending||jsonb_build_object(
            'source_card',coalesce(v_run.context->'source_card','{}'::jsonb),
            'source_card_name',coalesce(v_run.context->'source_card'->>'name','')
          ),state_version=state_version+1,
          last_action_label='카드 효과: 공개된 카드의 양측 확인을 기다립니다.'
          WHERE room_id=p_room_id;
        RETURN;
      END IF;
      v_target_owner:=v_owner;
      IF coalesce(v_step->'to','[]'::jsonb) @> '["opponent"]'::jsonb THEN
        SELECT user_id INTO v_target_owner FROM public.room_players WHERE room_id=p_room_id AND user_id<>v_owner LIMIT 1;
      END IF;
      v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_target_owner);
      v_pending:=jsonb_build_object('type','card_effect_reveal_ack','effect_id',v_effect_id,'source_instance_id',v_run.source_instance_id,
        'chooser_user_id',v_target_owner,'source_user_id',v_owner,'prompt',CASE WHEN v_target_owner<>v_owner THEN '공개된 카드를 확인한 뒤 확인 완료를 눌러 주세요.' ELSE '카드 공개를 확인하고 효과를 계속 진행하세요.' END,
        'revealed_cards',v_selected);
      UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
      UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
        last_action_label='카드 효과: 카드 공개 확인을 기다립니다.' WHERE room_id=p_room_id;
      RETURN;

    ELSIF v_op='move_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''), 'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_to:=coalesce(v_step->>'to','');
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),v_card,v_to,
         CASE WHEN v_to='hand' THEN v_target_owner ELSE v_target_owner END);
     END LOOP;

   ELSIF v_op IN ('move_unselected_to_deck_bottom','move_unselected_to_zone') THEN
     v_from:=v_step->>'from';
     v_path:=string_to_array(replace(coalesce(v_from,''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_selected_ids:='{}'::text[];
     -- Exclude every card already moved to a selected destination.
     -- Keep selectedVariable compatibility for existing definitions.
     FOR v_selected IN
       SELECT value FROM jsonb_array_elements(
         CASE WHEN jsonb_typeof(v_step->'selectedVariables')='array' THEN v_step->'selectedVariables'
              WHEN nullif(v_step->>'selectedVariable','') IS NOT NULL THEN jsonb_build_array(to_jsonb(v_step->>'selectedVariable'))
              ELSE '[]'::jsonb END
       )
     LOOP
       v_path:=string_to_array(replace(coalesce(v_selected #>> '{}',''),'vars.',''),'.');
       v_current:=v_vars #> v_path;
       FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_current,'[]'::jsonb)) LOOP
         v_card:=coalesce(v_item->'card',v_item);
         v_selected_ids:=array_append(v_selected_ids,coalesce(v_card->>'instance_id',v_item->>'instance_id',''));
       END LOOP;
     END LOOP;
     v_remaining:='[]'::jsonb;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       IF NOT (coalesce(v_card->>'instance_id',v_item->>'instance_id','')=ANY(v_selected_ids)) THEN
         v_remaining:=v_remaining||jsonb_build_array(v_item);
       END IF;
     END LOOP;
     v_to:=CASE WHEN v_op='move_unselected_to_deck_bottom' THEN 'deck_bottom' ELSE v_step->>'to' END;
     IF coalesce(v_step->>'order','preserve')='player_choice' THEN
       v_ordered:=v_vars->'__ordered_unselected';
       IF v_ordered IS NULL THEN
         IF jsonb_array_length(coalesce(v_remaining,'[]'::jsonb))=0 THEN
           UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
           CONTINUE;
         ELSIF jsonb_array_length(coalesce(v_remaining,'[]'::jsonb))=1 THEN
           -- One card has no meaningful order choice; send it directly to the bottom.
           v_ordered:=v_remaining;
         ELSE
           v_waiting:=jsonb_build_object('kind','order','options',v_remaining,'save_as','__ordered_unselected',
             'chooser_user_id',v_owner,'prompt','덱 아래로 보낼 카드의 순서를 정하세요. (위에서부터 차례대로 선택)');
           v_pending:=jsonb_build_object('type','card_effect_order','effect_id',v_effect_id,'chooser_user_id',v_owner,
             'prompt','덱 아래 카드의 순서를 정하세요.','options_count',jsonb_array_length(v_remaining));
           UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
           UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
             last_action_label='카드 효과: 덱 아래 카드 순서를 기다립니다.' WHERE room_id=p_room_id;
           RETURN;
         END IF;
       END IF;
       v_remaining:=coalesce(v_ordered,v_remaining);
     END IF;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_remaining,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),v_card,v_to,v_target_owner);
     END LOOP;
     IF v_step ? 'selectedVariable' AND v_vars ? '__ordered_unselected' THEN
       v_vars:=v_vars-'__ordered_unselected';
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;

   ELSIF v_op='reveal_until_match' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_data:=coalesce(v_game.deck_order,'[]'::jsonb); v_remaining:='[]'::jsonb; v_examined:=0; v_matched:=false; v_selected:='[]'::jsonb;
     FOR v_item IN SELECT value FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality) ORDER BY ordinality LOOP
       v_examined:=v_examined+1; v_card:=v_item;
       v_wrapper:=jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_owner,'zone','peek','card',v_card);
       v_selected:=v_selected||jsonb_build_array(v_wrapper);
       IF public.private_card_effect_filter_matches_v1(p_room_id,v_card,v_owner,v_source_user,coalesce(v_step->'match','{}'::jsonb)) THEN
         v_matched:=true; EXIT;
       END IF;
     END LOOP;
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.ordinality>v_examined),'[]'::jsonb)
       INTO v_deck FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states SET deck_order=v_deck,updated_at=now() WHERE room_id=p_room_id AND user_id=v_owner;
     v_data:=jsonb_build_object('revealed',v_selected,
       'matched',CASE WHEN v_matched THEN jsonb_build_array(v_selected->(jsonb_array_length(v_selected)-1)) ELSE '[]'::jsonb END,
       'matched_count',CASE WHEN v_matched THEN 1 ELSE 0 END);
     v_vars:=jsonb_set(v_vars,ARRAY[v_step->>'saveAs'],v_data,true);
     IF jsonb_array_length(coalesce(v_selected,'[]'::jsonb))=0 THEN
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     v_waiting:=jsonb_build_object('kind','sequence','cards',v_selected,'index',0,'chooser_user_id',v_owner,'save_as',v_step->>'saveAs');
     v_pending:=jsonb_build_object('type','card_effect_reveal_sequence','effect_id',v_effect_id,'chooser_user_id',v_owner,
       'prompt','덱 위에서 한 장씩 공개합니다. 공개한 카드를 확인한 뒤 다음 카드를 진행하세요.',
       'revealed_card',coalesce(v_selected->0->'card',v_selected->0),'revealed_count',1,
       'stop_after_match',v_matched);
     UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
       last_action_label='카드 효과: 덱 공개를 진행 중입니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='attach_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF coalesce(v_item->>'zone','')='remove_area' THEN
         UPDATE public.room_player_game_states SET remove_cards=public.private_card_effect_remove_from_array_v1(remove_cards,v_card->>'instance_id'),updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner;
         UPDATE public.room_player_turn_boards SET remove_count=greatest(0,remove_count-1),updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner;
       END IF;
       SELECT public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id) INTO v_current;
       IF v_current IS NULL THEN RAISE EXCEPTION '겹칠 카드의 현장 원본을 찾지 못했습니다.'; END IF;
       v_patch:=jsonb_build_object('under_cards',coalesce(v_current->'under_cards','[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,v_patch);
     END LOOP;

   ELSIF v_op='set_mislead_value' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '미스리드 수치를 설정할 현장 카드를 찾지 못했습니다.'; END IF;
     v_amount:=coalesce(nullif(v_step->>'value','')::integer,0);
     IF v_amount<0 OR v_amount>3 THEN RAISE EXCEPTION '미스리드 수치는 0~3 범위여야 합니다.'; END IF;
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,
       jsonb_build_object('mislead_value',v_amount));

   ELSIF v_op='grant_keyword' THEN
     v_target_owner:=v_source_user; v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
     IF v_card IS NULL THEN RAISE EXCEPTION '키워드를 부여할 카드가 현장에 없습니다.'; END IF;
     v_keyword:=coalesce(v_step->>'keyword','');
     v_selected:=coalesce(v_card->'dsl_keywords','[]'::jsonb);
     IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_selected) x(value) WHERE x.value->>'effect_id'=v_effect_id AND x.value->>'keyword'=v_keyword) THEN
       v_selected:=v_selected||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'keyword',v_keyword,
         'expires_turn_number',(SELECT turn_number FROM public.room_match_states WHERE room_id=p_room_id)));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,jsonb_build_object('dsl_keywords',v_selected));
     END IF;

   ELSIF v_op='modify_stat' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path; v_amount:=coalesce((v_step->>'amount')::integer,0);
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NOT NULL AND v_step->>'stat'='ap' THEN
         v_new_ap:=coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)+v_amount;
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('ap_bonus',v_new_ap));
       END IF;
     END LOOP;

   ELSIF v_op='offer_reaction' THEN
     v_waiting:=jsonb_build_object('kind','reaction','save_as',v_step->>'saveAs',
       'choices',coalesce(v_step->'choices','[]'::jsonb),'chooser_user_id',v_owner);
     v_pending:=jsonb_build_object('type','card_effect_reaction','effect_id',v_effect_id,
       'chooser_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','효과를 발동할까요?'),
       'choices',coalesce(v_step->'choices','[]'::jsonb),'source_instance_id',v_run.source_instance_id);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_run.context->'source_card','{}'::jsonb),'source_card_name',coalesce(v_run.context->'source_card'->>'name','')),state_version=state_version+1,
       last_action_label='카드 효과: 반응 여부를 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='pay_cost' THEN
     IF v_step->>'cost'='sleep_source_character' THEN
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_run.source_instance_id);
       IF v_current IS NULL OR NOT public.private_card_effect_is_active_v1(v_current) THEN
         RAISE EXCEPTION '비용으로 슬립시킬 효과 발동 카드가 액티브 상태가 아닙니다.';
       END IF;
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,jsonb_build_object('rested',true,'status','rested'));
     ELSIF v_step->>'cost'='sleep_selected_character' THEN
       v_path:=string_to_array(replace(coalesce(v_step->>'targetVariable',''),'vars.',''),'.');
       v_data:=v_vars #> v_path;
       v_item:=v_data->0; v_card:=coalesce(v_item->'card',v_item);
       IF v_item IS NULL OR v_card->>'instance_id' IS NULL THEN RAISE EXCEPTION '슬립 비용으로 사용할 캐릭터를 선택해 주세요.'; END IF;
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NULL OR NOT public.private_card_effect_is_active_v1(v_current) THEN RAISE EXCEPTION '슬립 비용 캐릭터는 액티브 상태여야 합니다.'; END IF;
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('rested',true,'status','rested'));
     ELSE
       RAISE EXCEPTION '지원하지 않는 카드 효과 비용입니다.';
     END IF;

   ELSIF v_op='draw_cards' THEN
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,coalesce(v_step->>'destination','hand'));
     END LOOP;

   ELSIF v_op='gain_evidence' THEN
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,'evidence');
     END LOOP;

   ELSIF v_op='mark_keyword_activated' THEN
     SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
     v_turn:=coalesce(nullif(v_run.context->>'turn_number','')::integer,v_turn);
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_run.source_instance_id,
       jsonb_build_object('haya_activated_turn_number',v_turn));

   ELSIF v_op='ready_cards_that_used_keyword' THEN
     v_turn:=coalesce(nullif(v_run.context->>'ending_turn_number','')::integer,
       nullif(v_run.context->>'turn_number','')::integer,v_match.turn_number);
     UPDATE public.room_player_turn_boards b
       SET field_cards=coalesce((SELECT jsonb_agg(
         CASE WHEN coalesce(nullif(e.value->>'haya_activated_turn_number','')::integer,-1)=v_turn
           THEN e.value||jsonb_build_object('rested',false,'status','active')
           ELSE e.value END ORDER BY e.ordinality)
         FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
         partner_mr_card=CASE WHEN coalesce(nullif(b.partner_mr_card->>'haya_activated_turn_number','')::integer,-1)=v_turn
           THEN b.partner_mr_card||jsonb_build_object('rested',false,'status','active') ELSE b.partner_mr_card END,
         updated_at=now()
       WHERE b.room_id=p_room_id AND b.user_id=v_source_user;

   ELSIF v_op='shuffle_deck' THEN
     SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb) INTO v_data
       FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) e(value);
     UPDATE public.room_player_game_states SET deck_order=v_data,updated_at=now() WHERE room_id=p_room_id AND user_id=v_owner;

   ELSIF v_op IN ('set_continuous_stat','set_continuous_keyword') THEN
     NULL;

   ELSIF v_op='modify_lp' THEN
     RAISE EXCEPTION '현재 게임 상태에 LP 수치 저장 필드가 없어 modify_lp 명령을 실행할 수 없습니다. 기존 미스리드 규칙을 사용해 주세요.';

   ELSE
     RAISE EXCEPTION '허용되지 않은 카드 효과 실행 명령: %',coalesce(v_op,'(없음)');
   END IF;

   UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
 END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_continue_v1(p_room_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_run public.private_card_effect_runs_v1%rowtype;
 v_wait jsonb; v_pending jsonb; v_ids jsonb; v_selected jsonb:='[]'::jsonb; v_item jsonb;
 v_id text; v_save text; v_min integer; v_max integer; v_count integer; v_options jsonb;
 v_choice text; v_vars jsonb; v_ordered jsonb; v_cards jsonb; v_index integer; v_next jsonb;
 v_target_owner uuid; v_card jsonb; v_protect_card jsonb; v_board public.room_player_turn_boards%rowtype;
 v_game public.room_player_game_states%rowtype; v_match public.room_match_states%rowtype; v_turn integer; v_key text; v_hand jsonb; v_ai_user_id uuid; v_revealed_cards jsonb; v_ack_required jsonb; v_ack_ids jsonb; v_ack_user uuid;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_run.waiting IS NULL THEN RAISE EXCEPTION '계속 처리할 카드 효과가 없습니다.'; END IF;
 v_wait:=v_run.waiting;
 SELECT pending_action INTO v_pending FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF v_pending IS NULL
   OR coalesce(v_pending->>'chooser_user_id','') IS DISTINCT FROM v_user::text THEN
   RAISE EXCEPTION '현재 카드 효과 선택 차례가 아닙니다.';
 END IF;
 v_vars:=coalesce(v_run.variables,'{}'::jsonb);

 IF v_wait->>'kind'='selection' THEN
   v_ids:=coalesce(p_payload->'selected_instance_ids','[]'::jsonb);
   IF jsonb_typeof(v_ids)<>'array' THEN RAISE EXCEPTION '선택 카드 목록 형식이 올바르지 않습니다.'; END IF;
   v_count:=jsonb_array_length(v_ids); v_min:=coalesce((v_wait->>'min')::integer,0); v_max:=coalesce((v_wait->>'max')::integer,1);
   IF v_count<v_min OR v_count>v_max THEN RAISE EXCEPTION '선택 장수가 허용 범위를 벗어났습니다. (%~%장)',v_min,v_max; END IF;
   IF (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_ids))<>v_count THEN RAISE EXCEPTION '같은 카드를 중복 선택할 수 없습니다.'; END IF;
   v_options:=coalesce(v_wait->'options','[]'::jsonb);
   FOR v_id IN SELECT value FROM jsonb_array_elements_text(v_ids) LOOP
     SELECT value INTO v_item FROM jsonb_array_elements(v_options) WHERE value->>'instance_id'=v_id LIMIT 1;
     IF v_item IS NULL THEN RAISE EXCEPTION '허용된 후보 목록에 없는 카드가 포함되어 있습니다.'; END IF;
     v_selected:=v_selected||jsonb_build_array(v_item);
   END LOOP;
   IF v_wait->>'unique_by'='card_name' AND (
      SELECT count(DISTINCT lower(public.private_card_effect_name_v1(coalesce(value->'card',value))))
      FROM jsonb_array_elements(v_selected)
   )<>jsonb_array_length(v_selected) THEN
     RAISE EXCEPTION '카드명이 서로 다른 캐릭터만 선택할 수 있습니다.';
   END IF;
   v_save:=v_wait->>'save_as';

   -- Special continuation: discard one card to allow the effect targeting Mouri Ran.
   IF v_save='__mouri_ran_protection_cost' THEN
     v_item:=v_selected->0;
     IF v_item IS NULL THEN RAISE EXCEPTION '무효화 방지를 위해 리무브할 손패를 선택해야 합니다.'; END IF;
     v_card:=coalesce(v_item->'card',v_item);
     v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_user);
     PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,'hand',v_card,'remove_area',v_target_owner);
     UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,last_action_label='모리 란 보호 효과의 손패 리무브 비용을 지불했습니다.' WHERE room_id=p_room_id;
     PERFORM public.private_card_effect_run_v1(p_room_id);
     RETURN;
   END IF;

   -- B04003: when the opponent selects this player's Mouri Ran by an ability/effect,
   -- once per turn the opponent must discard one card or that effect is negated.
   IF v_save<>'__mouri_ran_protection_cost' THEN
     SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;
     IF v_match.current_turn_user_id=v_user AND v_run.actor_user_id=v_user THEN
       SELECT coalesce(value->'card',value),nullif(value->>'owner_user_id','')::uuid
         INTO v_card,v_target_owner
       FROM jsonb_array_elements(v_selected)
       WHERE nullif(value->>'owner_user_id','')::uuid IS NOT NULL
         AND nullif(value->>'owner_user_id','')::uuid<>v_user
         AND coalesce(value->>'zone','')='field'
         AND public.private_card_effect_name_matches_v1(coalesce(value->'card',value),'毛利蘭')
       LIMIT 1;
       IF v_target_owner IS NOT NULL THEN
         SELECT * INTO v_board FROM public.room_player_turn_boards
          WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
         SELECT e.value INTO v_protect_card
         FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
         WHERE public.private_card_effect_matches_id_v1(e.value,'["0408"]'::jsonb)
           AND coalesce(v_board.case_effect_uses->>('b04003_protection_'||(e.value->>'instance_id')),'')<>v_match.turn_number::text
         LIMIT 1;
         IF v_protect_card IS NOT NULL THEN
           v_key:='b04003_protection_'||(v_protect_card->>'instance_id');
           UPDATE public.room_player_turn_boards
             SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_key],to_jsonb(v_match.turn_number::text),true),
                 updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner;
           SELECT coalesce(hand,'[]'::jsonb) INTO v_hand
           FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
           v_vars:=jsonb_set(v_vars,ARRAY[v_save],v_selected,true);
           v_wait:=jsonb_build_object(
             'kind','reaction','save_as','__mouri_ran_protection_choice',
             'choices',CASE WHEN jsonb_array_length(v_hand)>0 THEN '["손패 1장 리무브","효과 무효화"]'::jsonb ELSE '["효과 무효화"]'::jsonb END,
             'chooser_user_id',v_user,
             'prompt','모리 란이 선택되었습니다. 손패 1장을 리무브하면 효과가 계속되고, 리무브하지 않으면 해당 효과가 무효화됩니다.'
           );
           UPDATE public.private_card_effect_runs_v1
             SET variables=v_vars,step_index=step_index+1,waiting=v_wait,updated_at=now()
           WHERE room_id=p_room_id;
           UPDATE public.room_match_states
             SET pending_action=jsonb_build_object(
               'type','card_effect_reaction','effect_id',coalesce(v_run.effect_queue->v_run.effect_index->'__definition'->>'effectId',v_run.effect_queue->v_run.effect_index->>'effectId'),
               'source_instance_id',v_run.source_instance_id,
               'chooser_user_id',v_user,'prompt',v_wait->>'prompt','choices',v_wait->'choices'
             ),
             state_version=state_version+1,last_action_label='모리 란 보호 효과의 응답을 기다립니다.'
           WHERE room_id=p_room_id;
           RETURN;
         END IF;
       END IF;
     END IF;
   END IF;

   v_vars:=jsonb_set(v_vars,ARRAY[v_save],v_selected,true);
   -- When the AI chooses a card from the human player's hand, reveal the
   -- chosen card and wait for the human to acknowledge it before moving it.
   SELECT ai_user_id INTO v_ai_user_id FROM public.private_ai_battles WHERE room_id=p_room_id;
   IF v_ai_user_id IS NOT NULL AND v_user=v_ai_user_id
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_selected) chosen(value)
        WHERE chosen.value->>'zone'='hand'
          AND coalesce(nullif(chosen.value->>'owner_user_id','')::uuid,v_user)<>v_user
      ) THEN
     SELECT nullif(chosen.value->>'owner_user_id','')::uuid INTO v_target_owner
     FROM jsonb_array_elements(v_selected) chosen(value)
     WHERE chosen.value->>'zone'='hand'
       AND coalesce(nullif(chosen.value->>'owner_user_id','')::uuid,v_user)<>v_user
     LIMIT 1;
     SELECT coalesce(jsonb_agg(coalesce(chosen.value->'card',chosen.value)),'[]'::jsonb)
       INTO v_revealed_cards
     FROM jsonb_array_elements(v_selected) chosen(value)
     WHERE chosen.value->>'zone'='hand'
       AND coalesce(nullif(chosen.value->>'owner_user_id','')::uuid,v_user)<>v_user;
     v_vars:=jsonb_set(v_vars,ARRAY[v_save],v_selected,true);
     v_wait:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_target_owner);
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,waiting=v_wait,updated_at=now()
       WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=jsonb_build_object(
         'type','card_effect_reveal_ack',
         'effect_id',coalesce(v_run.effect_queue->v_run.effect_index->>'effectId',''),
         'source_instance_id',v_run.source_instance_id,
         'source_user_id',v_user,'chooser_user_id',v_target_owner,
         'prompt','AI가 리무브할 손패 카드를 선택했습니다. 선택된 카드를 확인한 뒤 확인 완료를 눌러 주세요.',
         'revealed_cards',v_revealed_cards
       )||jsonb_build_object(
         'source_card',coalesce(v_run.context->'source_card','{}'::jsonb),
         'source_card_name',coalesce(v_run.context->'source_card'->>'name','')
       ),
       state_version=state_version+1,
       last_action_label='AI가 리무브할 손패 카드를 선택했습니다. 상대 확인을 기다립니다.'
       WHERE room_id=p_room_id;
     RETURN;
   END IF;
   
UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='order' THEN
   v_ids:=coalesce(p_payload->'selected_instance_ids','[]'::jsonb);
   v_options:=coalesce(v_wait->'options','[]'::jsonb);
   v_count:=jsonb_array_length(v_ids);
   IF v_count<>jsonb_array_length(v_options) THEN RAISE EXCEPTION '덱 아래 카드의 순서를 정하려면 각 카드를 정확히 한 번 선택해야 합니다.'; END IF;
   IF (SELECT count(DISTINCT value) FROM jsonb_array_elements_text(v_ids))<>v_count THEN RAISE EXCEPTION '덱 아래 순서에 중복 카드가 있습니다.'; END IF;
   FOR v_id IN SELECT value FROM jsonb_array_elements_text(v_ids) LOOP
     SELECT value INTO v_item FROM jsonb_array_elements(v_options) WHERE value->>'instance_id'=v_id LIMIT 1;
     IF v_item IS NULL THEN RAISE EXCEPTION '허용된 후보 목록에 없는 카드가 포함되어 있습니다.'; END IF;
     v_ordered:=coalesce(v_ordered,'[]'::jsonb)||jsonb_build_array(v_item);
   END LOOP;
   v_save:=coalesce(v_wait->>'save_as','__ordered_unselected');
   v_vars:=jsonb_set(v_vars,ARRAY[v_save],coalesce(v_ordered,'[]'::jsonb),true);
   UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='ack' THEN
   IF coalesce(p_payload->>'decision','acknowledge')<>'acknowledge' THEN RAISE EXCEPTION '공개 확인을 완료해 주세요.'; END IF;
   IF coalesce((v_wait->>'require_both_acknowledgements')::boolean,false) THEN
     v_ack_required:=coalesce(v_wait->'required_user_ids','[]'::jsonb);
     v_ack_ids:=coalesce(v_wait->'acknowledged_user_ids','[]'::jsonb);
     IF NOT (v_ack_required @> jsonb_build_array(v_user::text)) THEN
       RAISE EXCEPTION '이 공개 확인의 참가자로 지정되어 있지 않습니다.';
     END IF;
     IF NOT (v_ack_ids @> jsonb_build_array(v_user::text)) THEN
       v_ack_ids:=v_ack_ids||jsonb_build_array(v_user::text);
     END IF;
     SELECT candidate.value::uuid INTO v_ack_user
     FROM jsonb_array_elements_text(v_ack_required) candidate(value)
     WHERE NOT (v_ack_ids @> jsonb_build_array(candidate.value))
     LIMIT 1;
     IF v_ack_user IS NOT NULL THEN
       v_wait:=jsonb_set(v_wait,'{acknowledged_user_ids}',v_ack_ids,true);
       UPDATE public.private_card_effect_runs_v1 SET waiting=v_wait,updated_at=now()
         WHERE room_id=p_room_id;
       UPDATE public.room_match_states
         SET pending_action=jsonb_set(
           jsonb_set(coalesce(pending_action,'{}'::jsonb),'{acknowledged_user_ids}',v_ack_ids,true),
           '{chooser_user_id}',to_jsonb(v_ack_user::text),true
         ),
         state_version=state_version+1,
         last_action_label=format('카드 효과 공개 확인 %s/%s명 완료. 다른 플레이어의 확인을 기다립니다.',
           jsonb_array_length(v_ack_ids),jsonb_array_length(v_ack_required))
         WHERE room_id=p_room_id;
       RETURN;
     END IF;
   END IF;
   UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='sequence' THEN
   v_cards:=coalesce(v_wait->'cards','[]'::jsonb); v_index:=coalesce((v_wait->>'index')::integer,0)+1;
   IF v_index<jsonb_array_length(v_cards) THEN
     v_next:=v_cards->v_index;
     v_wait:=jsonb_set(v_wait,'{index}',to_jsonb(v_index),true);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_wait,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=jsonb_set(
       jsonb_set(coalesce(pending_action,'{}'::jsonb),'{revealed_card}',coalesce(v_next->'card',v_next),true),
       '{revealed_count}',to_jsonb(v_index+1),true
     ),state_version=state_version+1,last_action_label='카드 효과: 다음 카드를 공개했습니다.' WHERE room_id=p_room_id;
     RETURN;
   ELSE
     UPDATE public.private_card_effect_runs_v1 SET step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;
   END IF;

 ELSIF v_wait->>'kind'='reaction' THEN
   v_choice:=coalesce(p_payload->>'choice','');
   IF NOT (coalesce(v_wait->'choices','[]'::jsonb) @> jsonb_build_array(v_choice)) THEN RAISE EXCEPTION '허용되지 않은 반응 선택입니다.'; END IF;
   IF v_wait->>'save_as'='__mouri_ran_protection_choice' THEN
     IF v_choice='손패 1장 리무브' THEN
       SELECT coalesce(hand,'[]'::jsonb) INTO v_hand
       FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
       IF jsonb_array_length(v_hand)=0 THEN
         v_next:=coalesce(v_run.effect_queue->v_run.effect_index->'__definition',v_run.effect_queue->v_run.effect_index);
         v_index:=jsonb_array_length(coalesce(v_next->'steps','[]'::jsonb));
         UPDATE public.private_card_effect_runs_v1 SET step_index=v_index,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;
         UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,last_action_label='손패가 없어 모리 란을 대상으로 한 효과가 무효화되었습니다.' WHERE room_id=p_room_id;
         PERFORM public.private_card_effect_run_v1(p_room_id);
         RETURN;
       END IF;
       SELECT coalesce(jsonb_agg(jsonb_build_object(
         'instance_id',e.value->>'instance_id','owner_user_id',v_user,'zone','hand','card',e.value
       ) ORDER BY e.ordinality),'[]'::jsonb) INTO v_options
       FROM jsonb_array_elements(v_hand) WITH ORDINALITY e(value,ordinality);
       v_wait:=jsonb_build_object('kind','selection','save_as','__mouri_ran_protection_cost',
         'options',v_options,'min',1,'max',1,'chooser_user_id',v_user,
         'prompt','모리 란을 대상으로 한 효과를 허용하기 위해 리무브할 손패 1장을 선택하세요.');
       UPDATE public.private_card_effect_runs_v1 SET waiting=v_wait,updated_at=now() WHERE room_id=p_room_id;
       UPDATE public.room_match_states SET pending_action=jsonb_build_object(
         'type','card_effect_selection','chooser_user_id',v_user,'prompt',v_wait->>'prompt','min',1,'max',1,'optional',false
       ),state_version=state_version+1,last_action_label='모리 란 보호 효과의 손패 비용을 기다립니다.' WHERE room_id=p_room_id;
       RETURN;
     ELSE
       v_next:=coalesce(v_run.effect_queue->v_run.effect_index->'__definition',v_run.effect_queue->v_run.effect_index);
       v_index:=jsonb_array_length(coalesce(v_next->'steps','[]'::jsonb));
       UPDATE public.private_card_effect_runs_v1 SET step_index=v_index,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;
       UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,last_action_label='모리 란 보호 효과로 상대 효과를 무효화했습니다.' WHERE room_id=p_room_id;
       PERFORM public.private_card_effect_run_v1(p_room_id);
       RETURN;
     END IF;
   END IF;
   v_vars:=jsonb_set(v_vars,ARRAY[v_wait->>'save_as'],to_jsonb(v_choice),true);
   UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;

 ELSE
   RAISE EXCEPTION '지원하지 않는 카드 효과 대기 단계입니다.';
 END IF;
 UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,last_action_label='카드 효과 응답을 처리했습니다.' WHERE room_id=p_room_id AND pending_action->>'type' LIKE 'card_effect_%';
 PERFORM public.private_card_effect_run_v1(p_room_id);
 IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   PERFORM public.private_card_effect_process_scheduled_returns_v1(p_room_id);
 END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.perform_private_turn_action_v2(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_match public.room_match_states%rowtype; v_before_match public.room_match_states%rowtype;
 v_before_boards jsonb; v_before_board jsonb; v_new_board public.room_player_turn_boards%rowtype;
 v_before_pending jsonb; v_after_pending jsonb; v_before_evidence jsonb; v_after_evidence jsonb;
 v_result jsonb; v_source_card jsonb; v_old_card jsonb; v_new_card jsonb; v_old_evidence_card jsonb;
 v_owner uuid; v_instance_id text; v_first_entry boolean; v_turn integer; v_old_field jsonb;
 v_old_board jsonb; v_old_entry jsonb; v_current_field jsonb; v_current_remove jsonb; v_removed boolean;
 v_before_base_character_played boolean:=false; v_first_entry_already boolean:=false;
 v_pending_actor uuid; v_context jsonb; v_event_source_user uuid; v_case_card jsonb; v_case_started boolean;
 v_case_effect_id text; v_case_key text; v_case_internal_id text; v_case_name text; v_case_uses jsonb;
 v_evidence_owner uuid; v_trigger_owner uuid; v_disguise_id text; v_effect_definition jsonb; v_effect_started boolean; v_use_key text;
 v_old_action text:=p_action;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;

 IF p_action='activate_case_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 사건 효과를 발동할 수 있습니다.'; END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user OR v_match.turn_step<>'main' THEN
     RAISE EXCEPTION '자신의 메인 단계에서만 사건 효과를 발동할 수 있습니다.';
   END IF;
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   IF coalesce(v_new_board.case_phase,'incident')<>'solution' THEN RAISE EXCEPTION '해결편에서만 사건 효과를 발동할 수 있습니다.'; END IF;
   v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''),'[^A-Za-z0-9]','','g'));
   IF v_case_key IN ('B10083P','1139','B10083') THEN
     v_case_internal_id:='1139';
     v_case_name:='돌아오지 않는 형사';
     v_case_effect_id:='card-1139-returning-detective-case-effect';
   ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
     v_case_internal_id:='1261';
     v_case_name:='코난 VS 괴도 키드';
     v_case_effect_id:='card-1261-conan-vs-kid-case-effect';
   ELSE
     RAISE EXCEPTION '이 사건 카드에는 아직 선언형 효과가 등록되어 있지 않습니다.';
   END IF;
   IF nullif(p_payload->>'effect_id','') IS NOT NULL AND p_payload->>'effect_id'<>v_case_effect_id THEN
     RAISE EXCEPTION '현재 사건 카드에 등록된 효과와 요청한 효과가 일치하지 않습니다.';
   END IF;
   v_case_uses:=coalesce(v_new_board.case_effect_uses,'{}'::jsonb);
   IF coalesce(v_case_uses->>v_case_effect_id,'')=v_match.turn_number::text THEN
     RAISE EXCEPTION '이 턴에는 이미 해당 사건 효과를 사용했습니다.';
   END IF;
   v_case_card:=jsonb_build_object(
     'instance_id','case:'||v_new_board.event_key,'key',v_new_board.event_key,
     'card_id',v_case_internal_id,'card_num',v_new_board.event_key,
     'database_id',v_new_board.event_key,'card_type','event','type','event','name',v_case_name
   );
   v_case_started:=public.private_card_effect_start_event_v1(
     p_room_id,v_user,v_user,v_case_card,'case.activated_ability',
     jsonb_build_object('turn_number',v_match.turn_number,'case_key',v_new_board.event_key),
     v_case_effect_id,true
   );
   IF NOT coalesce(v_case_started,false) THEN
     RAISE EXCEPTION '사건 효과 조건이 충족되지 않았거나 아직 발동 가능한 효과가 아닙니다.';
   END IF;
   UPDATE public.room_player_turn_boards
     SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_case_effect_id],to_jsonb(v_match.turn_number::text),true),
         updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='card_effect_continue' THEN
   PERFORM public.private_card_effect_continue_v1(p_room_id,coalesce(p_payload,'{}'::jsonb));
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='activate_card_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 효과를 발동할 수 있습니다.'; END IF;
   -- Turn ownership is checked after the card effect timing is loaded.
   -- Turn-step eligibility is checked after the card effect timing is loaded.
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT * INTO v_new_board FROM public.room_player_turn_boards
     WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
   IF v_source_card IS NULL AND v_new_board.partner_mr_card->>'instance_id'=v_instance_id THEN
     v_source_card:=v_new_board.partner_mr_card;
   END IF;
   IF v_source_card IS NULL THEN
     SELECT p.value INTO v_source_card
     FROM jsonb_array_elements(coalesce(v_new_board.partner_non_mr_cards,'[]'::jsonb)) p(value)
     WHERE p.value->>'instance_id'=v_instance_id
     LIMIT 1;
   END IF;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 또는 MR 파트너 카드를 찾을 수 없습니다.'; END IF;
   SELECT d.value INTO v_effect_definition
   FROM public.private_card_effect_catalog_v1 c
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
   WHERE c.catalog_id='main' AND d.value->>'effectId'=p_payload->>'effect_id'
     AND public.private_card_effect_matches_id_v1(v_source_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LIMIT 1;
   IF v_effect_definition IS NULL THEN RAISE EXCEPTION '이 캐릭터에 등록된 효과를 찾을 수 없습니다.'; END IF;
   IF v_new_board.partner_mr_card->>'instance_id'=v_instance_id
      AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 MR 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;
   IF EXISTS (
       SELECT 1 FROM jsonb_array_elements(coalesce(v_new_board.partner_non_mr_cards,'[]'::jsonb)) p(value)
       WHERE p.value->>'instance_id'=v_instance_id
     ) AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;
 
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

   v_use_key:=coalesce(p_payload->>'effect_id','')||':'||v_instance_id;
   SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   IF coalesce((v_effect_definition->>'oncePerTurn')::boolean,false)
      AND coalesce(v_new_board.case_effect_uses->>v_use_key,'')=v_match.turn_number::text THEN
     RAISE EXCEPTION '이 턴에는 이미 해당 능력을 사용했습니다.';
   END IF;
   v_effect_started:=public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
     'character.activated_ability',jsonb_build_object('turn_number',v_match.turn_number),
     p_payload->>'effect_id',true);
   IF NOT coalesce(v_effect_started,false) THEN
     RAISE EXCEPTION '능력의 발동 조건을 충족하지 않습니다.';
   END IF;
   IF coalesce((v_effect_definition->>'oncePerTurn')::boolean,false) THEN
     UPDATE public.room_player_turn_boards
       SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_use_key],to_jsonb(v_match.turn_number::text),true),
           updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_user;
   END IF;
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 SELECT * INTO v_before_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_before_match.phase<>'playing' OR v_before_match.game_over THEN
   RAISE EXCEPTION '진행 중인 게임이 아닙니다.';
 END IF;
 v_before_pending:=v_before_match.pending_action;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'user_id',b.user_id,'field_cards',coalesce(b.field_cards,'[]'::jsonb),'partner_mr_card',b.partner_mr_card,
     'case_phase',b.case_phase,'event_key',b.event_key,'event_rule_code',b.event_rule_code,'file_count',b.file_count
   ) ORDER BY b.seat),'[]'::jsonb) INTO v_before_boards
 FROM public.room_player_turn_boards b WHERE b.room_id=p_room_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',gs.user_id,'evidence_cards',coalesce(gs.evidence_cards,'[]'::jsonb))),'[]'::jsonb)
   INTO v_before_evidence FROM public.room_player_game_states gs WHERE gs.room_id=p_room_id;
 v_turn:=v_before_match.turn_number;
 SELECT coalesce(base_character_played_this_turn,false), first_character_entered_this_turn IS NOT NULL
   INTO v_before_base_character_played, v_first_entry_already
   FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;

 
IF p_action='declare_contact' THEN
  v_instance_id:=coalesce(
    nullif(p_payload->>'attacker_instance_id',''),
    nullif(p_payload->>'attacker_id',''),
    nullif(p_payload->>'source_instance_id',''),
    nullif(p_payload->>'instance_id','')
  );
  v_source_card:=NULL;
  SELECT e.value INTO v_source_card
  FROM public.room_player_turn_boards b
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
  WHERE b.room_id=p_room_id AND b.user_id=v_user
    AND e.value->>'instance_id'=v_instance_id
  LIMIT 1;

  IF v_source_card IS NOT NULL AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      coalesce(v_source_card->'dsl_keywords','[]'::jsonb)
      || coalesce(v_source_card->'dsl_continuous_keywords','[]'::jsonb)
    ) k(value)
    WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
      IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')
  ) THEN
    RAISE EXCEPTION '돌격[사건] 상태의 캐릭터는 캐릭터를 대상으로 컨택할 수 없습니다.';
  END IF;

  v_owner:=nullif(p_payload->>'target_user_id','')::uuid;
  v_disguise_id:=coalesce(nullif(p_payload->>'target_instance_id',''),nullif(p_payload->>'target_id',''));
  v_old_card:=NULL;
  IF v_owner IS NOT NULL AND v_disguise_id IS NOT NULL THEN
    SELECT e.value INTO v_old_card
    FROM public.room_player_turn_boards b
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
    WHERE b.room_id=p_room_id AND b.user_id=v_owner
      AND e.value->>'instance_id'=v_disguise_id
    LIMIT 1;
  END IF;

  IF v_source_card IS NOT NULL
     AND public.private_card_effect_matches_id_v1(v_source_card,'["0938"]'::jsonb)
     AND v_old_card IS NOT NULL
     AND public.private_card_effect_is_active_v1(v_old_card) THEN
    IF public.private_card_effect_level_v1(v_old_card)<7 THEN
      RAISE EXCEPTION 'D11007은 레벨 7 이상 액티브 캐릭터만 액티브 대상 컨택으로 지정할 수 있습니다.';
    END IF;
    p_payload:=jsonb_set(coalesce(p_payload,'{}'::jsonb),'{allow_active_target}','true'::jsonb,true);
  END IF;
END IF;


 v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));

 IF p_action='declare_contact'
    AND v_before_match.current_turn_user_id=v_user
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   IF v_after_pending->>'type'='character_contact'
      AND nullif(v_after_pending->>'attacker_user_id','')::uuid=v_user THEN
     v_instance_id:=coalesce(v_after_pending->>'attacker_instance_id',v_after_pending->>'attacker_id');
     v_owner:=nullif(v_after_pending->>'target_user_id','')::uuid;
     v_disguise_id:=nullif(v_after_pending->>'target_instance_id','');
     SELECT e.value INTO v_source_card
       FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL AND public.private_card_effect_matches_id_v1(v_source_card,'["0938"]'::jsonb) THEN
       SELECT e.value INTO v_old_card
         FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
         WHERE b.room_id=p_room_id AND b.user_id=v_owner AND e.value->>'instance_id'=v_disguise_id LIMIT 1;
       v_use_key:='card-0938-contact-start-discard-for-ap-3000:'||v_instance_id;
       SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
       IF v_old_card IS NOT NULL
          AND coalesce(v_new_board.case_effect_uses->>v_use_key,'')<>v_before_match.turn_number::text
          AND coalesce(v_before_match.current_turn_user_id,v_user)=v_user THEN
         v_context:=jsonb_build_object(
           'turn_number',v_before_match.turn_number,
           'resume_pending',v_after_pending,
           'contact',jsonb_build_object(
             'source_ap',coalesce(nullif(v_source_card->>'ap','')::numeric,0)+coalesce(nullif(v_source_card->>'ap_bonus','')::numeric,0),
             'target_ap',coalesce(nullif(v_old_card->>'ap','')::numeric,0)+coalesce(nullif(v_old_card->>'ap_bonus','')::numeric,0)
           )
         );
         IF (v_context#>>'{contact,target_ap}')::numeric>(v_context#>>'{contact,source_ap}')::numeric THEN
           PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
             'character.contact_started',v_context,'card-0938-contact-start-discard-for-ap-3000',true);
           UPDATE public.room_player_turn_boards
             SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_use_key],to_jsonb(v_before_match.turn_number::text),true),
                 updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_user;
         END IF;
       END IF;
     END IF;
   END IF;
 END IF;

 IF p_action='contact_use_disguise'
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   v_disguise_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card
   FROM public.room_player_turn_boards b
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
   WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_disguise_id LIMIT 1;
   IF v_source_card IS NOT NULL AND v_after_pending->>'type'='character_contact' THEN
     PERFORM public.private_card_effect_start_event_v1(
       p_room_id,v_user,v_user,v_source_card,'character.disguised',
       jsonb_build_object('turn_number',v_turn,'resume_pending',v_after_pending,
         'contact',v_after_pending,'disguised_instance_id',v_disguise_id),NULL,false
     );
   END IF;
 END IF;

 IF p_action='begin_turn' THEN
   UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=NULL, updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
 END IF;

 IF p_action='declare_solution'
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT value INTO v_before_board FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb))
     WHERE value->>'user_id'=v_user::text LIMIT 1;
   SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
   IF coalesce(v_before_board->>'case_phase','incident')<>'solution'
      AND coalesce(v_new_board.case_phase,'incident')='solution' THEN
     v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''),'[^A-Za-z0-9]','','g'));
     IF v_case_key IN ('B10083P','1139','B10083') THEN
       v_case_internal_id:='1139'; v_case_name:='돌아오지 않는 형사';
     ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
       v_case_internal_id:='1261'; v_case_name:='코난 VS 괴도 키드';
     ELSE
       v_case_internal_id:=NULL;
     END IF;
     IF v_case_internal_id IS NOT NULL THEN
       v_case_card:=jsonb_build_object(
         'instance_id','case:'||v_new_board.event_key,'key',v_new_board.event_key,
         'card_id',v_case_internal_id,'card_num',v_new_board.event_key,
         'database_id',v_new_board.event_key,'card_type','event','type','event','name',v_case_name
       );
       PERFORM public.private_card_effect_start_event_v1(
         p_room_id,v_user,v_user,v_case_card,'case.solution_entered',
         jsonb_build_object('turn_number',v_turn,'case_key',v_new_board.event_key),NULL,false
       );
     END IF;
   END IF;
 END IF;

 IF p_action IN ('play_character','next_hint') THEN
   v_instance_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
   IF v_source_card IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     SELECT value INTO v_before_board FROM jsonb_array_elements(v_before_boards) WHERE value->>'user_id'=v_user::text LIMIT 1;
     v_old_field:=coalesce(v_before_board->'field_cards','[]'::jsonb);
     v_first_entry:=NOT v_first_entry_already;
     IF v_first_entry THEN
       UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=v_instance_id,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_user AND first_character_entered_this_turn IS NULL;
     END IF;
     v_context:=jsonb_build_object('entry',jsonb_build_object(
       'method',CASE WHEN p_action='next_hint' THEN 'next_hint' ELSE 'manual' END,'is_first_character_this_turn',v_first_entry,'source',v_source_card),
       'turn_number',v_turn);
     PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
       'character.entered_field',v_context,NULL,false);
   END IF;
 END IF;

 IF p_action='play_event' AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_instance_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user
       AND e.value->>'instance_id'=v_instance_id AND lower(coalesce(e.value->>'card_type',''))='event' LIMIT 1;
   IF v_source_card IS NOT NULL THEN
     PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
       'event.played',jsonb_build_object('entry',jsonb_build_object('method','event_play'),'turn_number',v_turn),NULL,false);
   END IF;
 END IF;

 IF p_action IN ('investigate','attack_character','attack_evidence','declare_contact') THEN
   IF NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
      AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     v_instance_id:=coalesce(nullif(p_payload->>'instance_id',''),nullif(p_payload->>'attacker_instance_id',''));
     IF v_instance_id IS NOT NULL THEN
       SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
         CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
         WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
       IF v_source_card IS NOT NULL THEN
         PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
           'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
       END IF;
     END IF;
   END IF;
 END IF;

 IF p_action IN ('pass_mislead','resolve_mislead') AND v_before_pending->>'type'='mislead_response'
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'investigator_user_id','')::uuid;
   v_instance_id:=v_before_pending->>'investigator_instance_id';
   IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_event_source_user,v_event_source_user,v_source_card,
         'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
     END IF;
   END IF;
 END IF;

 IF p_action IN ('contact_pass_cutin','contact_use_cutin','contact_use_disguise','resolve_character_contact')
    AND v_before_pending IS NOT NULL
    AND v_before_pending->>'type' IN ('character_contact','character_contact_guard')
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
   v_instance_id:=coalesce(v_before_pending->>'attacker_instance_id',v_before_pending->>'attacker_id');
   v_owner:=nullif(v_before_pending->>'target_user_id','')::uuid;
   v_disguise_id:=nullif(v_before_pending->>'target_instance_id','');
   IF v_event_source_user IS NOT NULL AND v_owner IS NOT NULL AND v_instance_id IS NOT NULL AND v_disguise_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NULL THEN
       SELECT e.value INTO v_source_card FROM jsonb_array_elements(coalesce(
         (SELECT value->'field_cards' FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb))
          WHERE value->>'user_id'=v_event_source_user::text LIMIT 1),'[]'::jsonb)) e(value)
       WHERE e.value->>'instance_id'=v_instance_id LIMIT 1;
     END IF;
     SELECT coalesce(field_cards,'[]'::jsonb) INTO v_current_field FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_owner;
     SELECT coalesce(remove_cards,'[]'::jsonb) INTO v_current_remove FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner;
     IF v_source_card IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_disguise_id)
        AND (EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_disguise_id) OR EXISTS(SELECT 1 FROM public.room_player_turn_boards pb WHERE pb.room_id=p_room_id AND pb.user_id=v_owner AND pb.partner_mr_card->>'instance_id'=v_disguise_id)) THEN
       PERFORM public.private_card_effect_start_event_v1(
         p_room_id,v_event_source_user,v_event_source_user,v_source_card,'character.contact_removed_opponent',
         jsonb_build_object('turn_number',v_turn,'target_card_id',v_disguise_id),NULL,false
       );
     END IF;
   END IF;
 END IF;

 IF p_action IN ('contact_pass_cutin','contact_use_cutin','contact_use_disguise','resolve_character_contact')
    AND v_before_pending IS NOT NULL
    AND v_before_pending->>'type' IN ('character_contact','character_contact_guard')
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
   v_instance_id:=coalesce(v_before_pending->>'attacker_instance_id',v_before_pending->>'attacker_id');
   IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_event_source_user,v_event_source_user,v_source_card,
         'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
     END IF;
   END IF;
 END IF;

 IF p_action='resolve_evidence_attack'
     AND v_before_pending IS NOT NULL
     AND v_before_pending->>'type'='evidence_attack_reveal'
     AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
     AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
    v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
    v_instance_id:=nullif(v_before_pending->>'attacker_instance_id','');
    IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
      SELECT e.value INTO v_source_card
        FROM public.room_player_turn_boards b
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
        WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user
          AND e.value->>'instance_id'=v_instance_id LIMIT 1;
      IF v_source_card IS NOT NULL THEN
        PERFORM public.private_card_effect_start_event_v1(
          p_room_id,v_event_source_user,v_event_source_user,v_source_card,
          'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false
        );
      END IF;
    END IF;
  END IF;

  IF p_action='end_turn' THEN
   UPDATE public.room_player_turn_boards b
    SET field_cards=coalesce((SELECT jsonb_agg(
       e.value||jsonb_build_object('ap_bonus',0,'dsl_ap_bonus',0,
         'dsl_keywords',coalesce((SELECT jsonb_agg(k.value) FROM jsonb_array_elements(coalesce(e.value->'dsl_keywords','[]'::jsonb)) k(value)
          WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>v_turn),'[]'::jsonb))
       ORDER BY e.ordinality)
      FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
       partner_mr_card=CASE WHEN b.partner_mr_card IS NULL THEN NULL ELSE b.partner_mr_card||jsonb_build_object('ap_bonus',0,'dsl_ap_bonus',0,
         'dsl_keywords',coalesce((SELECT jsonb_agg(k.value) FROM jsonb_array_elements(coalesce(b.partner_mr_card->'dsl_keywords','[]'::jsonb)) k(value)
          WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>v_turn),'[]'::jsonb)) END,
       updated_at=now()
    WHERE b.room_id=p_room_id AND b.user_id=v_user;

   IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     SELECT field_cards,partner_mr_card INTO v_current_field,v_old_card FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
     FOR v_new_card IN SELECT value FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) LOOP
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_new_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn,'source_area','field'),NULL,false);
       IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
     END LOOP;
     IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) AND v_old_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_old_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn,'source_area','partner'),NULL,false);
     END IF;
   END IF;
 END IF;

 -- Detect field cards that actually entered an owner's remove area during this action.
 IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL) THEN
   FOR v_old_board IN SELECT value FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb)) LOOP
     v_owner:=nullif(v_old_board->>'user_id','')::uuid;
     FOR v_old_card IN SELECT value FROM jsonb_array_elements(coalesce(v_old_board->'field_cards','[]'::jsonb)) LOOP
       v_instance_id:=v_old_card->>'instance_id';
       IF v_instance_id IS NULL OR v_instance_id='' THEN CONTINUE; END IF;
       SELECT coalesce(field_cards,'[]'::jsonb) INTO v_current_field FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_owner;
       SELECT coalesce(remove_cards,'[]'::jsonb) INTO v_current_remove FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner;
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_instance_id)
         AND (
           EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,'[]'::jsonb)) e(value)
             WHERE e.value->>'instance_id'=v_instance_id AND NOT coalesce((e.value->>'dsl_remove_trigger_queued')::boolean,false))
           OR EXISTS(SELECT 1 FROM public.room_player_turn_boards pb
             WHERE pb.room_id=p_room_id AND pb.user_id=v_owner AND pb.partner_mr_card->>'instance_id'=v_instance_id
               AND NOT coalesce((pb.partner_mr_card->>'dsl_remove_trigger_queued')::boolean,false))
         ) THEN
         PERFORM public.private_card_effect_start_event_v1(p_room_id,v_owner,v_owner,v_old_card,
           'character.removed_from_field',jsonb_build_object('turn_number',v_turn,'removed_on_turn_user_id',v_before_match.current_turn_user_id),NULL,false);
         IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
       END IF;
     END LOOP;
     IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
   END LOOP;
 END IF;

 IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL) THEN
   FOR v_old_board IN SELECT value FROM jsonb_array_elements(coalesce(v_before_evidence,'[]'::jsonb)) LOOP
     v_evidence_owner:=nullif(v_old_board->>'user_id','')::uuid;
     SELECT coalesce(evidence_cards,'[]'::jsonb) INTO v_after_evidence
       FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_evidence_owner;
     FOR v_old_evidence_card IN SELECT value FROM jsonb_array_elements(coalesce(v_old_board->'evidence_cards','[]'::jsonb)) LOOP
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_after_evidence,'[]'::jsonb)) e(value)
         WHERE e.value->>'instance_id'=v_old_evidence_card->>'instance_id')
         AND EXISTS(
           SELECT 1 FROM public.room_player_game_states gs
           CROSS JOIN LATERAL jsonb_array_elements(coalesce(gs.remove_cards,'[]'::jsonb)) removed(value)
           WHERE gs.room_id=p_room_id AND gs.user_id=v_evidence_owner
             AND removed.value->>'instance_id'=v_old_evidence_card->>'instance_id'
         ) THEN
         SELECT user_id INTO v_trigger_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_evidence_owner
           ORDER BY seat LIMIT 1;
         IF v_trigger_owner IS NOT NULL THEN
           PERFORM public.private_card_effect_start_event_v1(
             p_room_id,v_trigger_owner,v_trigger_owner,v_old_evidence_card,'evidence.card_removed',
             jsonb_build_object(
               'turn_number',v_turn,
               'evidence_removed_instance_id',v_old_evidence_card->>'instance_id',
               'evidence_owner_user_id',v_evidence_owner::text,
               'removed_evidence_card',v_old_evidence_card
             ),NULL,false
           );
         END IF;
         IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
       END IF;
     END LOOP;
     IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
   END LOOP;
 END IF;

 IF p_action='end_turn' AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   PERFORM public.private_card_effect_process_scheduled_returns_v1(p_room_id);
 END IF;
 PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
 RETURN public.get_private_turn_state_v2(p_room_id);
END
$function$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(
  SELECT jsonb_agg(
    CASE WHEN e.value->>'effectId'='card-0619-on-enter-remove-top-three-police-charge'
      THEN jsonb_set(
        e.value,'{steps}',
        (
          SELECT jsonb_agg(inserted.step ORDER BY inserted.ord,inserted.subord)
          FROM (
            SELECT s.ordinality AS ord,1 AS subord,s.value AS step
            FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb))
              WITH ORDINALITY s(value,ordinality)
            UNION ALL
            SELECT s.ordinality,2,
              jsonb_build_object(
                'op','reveal_cards','from','vars.seen',
                'awaitAcknowledgement',true,'requireBothAcknowledgements',true,
                'prompt','덱에서 리무브한 카드 3장을 양쪽 플레이어가 확인해 주세요. 경찰 캐릭터가 포함되어 있는지 함께 확인한 뒤 효과를 진행합니다.'
              )
            FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb))
              WITH ORDINALITY s(value,ordinality)
            WHERE s.value->>'op'='peek_top_cards'
              AND NOT EXISTS (
                SELECT 1 FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb)) existing(value)
                WHERE existing.value->>'op'='reveal_cards'
                  AND coalesce((existing.value->>'requireBothAcknowledgements')::boolean,false)
              )
          ) inserted
        ),true
      )
      ELSE e.value
    END ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(value,ordinality)
)
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(c.definitions) e(value)
    WHERE e.value->>'effectId'='card-0619-on-enter-remove-top-three-police-charge'
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb)) s(value)
        WHERE s.value->>'op'='reveal_cards'
          AND coalesce((s.value->>'requireBothAcknowledgements')::boolean,false)
      )
  );

COMMIT;
