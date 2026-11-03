BEGIN;
-- Runtime operator for calculated hand counts.
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
 v_ids text[]; v_selected_ids text[]; v_effect_id text; v_turn integer; v_amount integer; v_ack_required jsonb; v_ack_ids jsonb; v_ack_user uuid; v_ai_user_id uuid; v_new_ap numeric; v_is_stunned boolean;
 v_keyword text; v_deck jsonb; v_seen jsonb; v_match_filter jsonb; v_name text;
 v_entry jsonb; v_effect_context jsonb; v_effect_source_card jsonb; v_effect_source_instance_id text;
 v_min_select integer; v_max_select integer;
 v_old_sub text := current_setting('request.jwt.claim.sub', true);
 v_old_claims text := current_setting('request.jwt.claims', true); v_required_switch integer;
 v_contact_user uuid; v_contact_instance text; v_contact_attacker_user uuid; v_contact_attacker_instance text;
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

   v_entry:=v_run.effect_queue->v_run.effect_index;
   v_def:=coalesce(v_entry->'__definition',v_entry);
   v_owner:=coalesce(nullif(v_entry->>'__actor_user_id','')::uuid,v_run.actor_user_id);
   v_source_user:=coalesce(nullif(v_entry->>'__source_user_id','')::uuid,v_run.source_user_id);
   v_effect_source_instance_id:=coalesce(v_entry->>'__source_instance_id',v_run.source_instance_id);
   v_effect_context:=coalesce(v_entry->'__context',v_run.context);
   v_effect_source_card:=coalesce(v_entry->'__source_card',v_effect_context->'source_card','{}'::jsonb);
   IF v_run.step_index >= jsonb_array_length(coalesce(v_def->'steps','[]'::jsonb)) THEN
     UPDATE public.private_card_effect_runs_v1
       SET effect_index=effect_index+1, step_index=0, variables='{}'::jsonb, waiting=NULL, updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;
   END IF;

   v_step:=v_def->'steps'->v_run.step_index;
   v_op:=v_step->>'op';
   v_vars:=coalesce(v_run.variables,'{}'::jsonb);
   v_owner:=coalesce(nullif(v_entry->>'__actor_user_id','')::uuid,v_run.actor_user_id);
   v_source_user:=coalesce(nullif(v_entry->>'__source_user_id','')::uuid,v_run.source_user_id);
   v_effect_id:=v_def->>'effectId';
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;

   IF v_step ? 'when' AND NOT public.private_card_effect_condition_matches_v1(
     p_room_id,v_owner,v_source_user,coalesce(v_effect_source_card,'{}'::jsonb),
     coalesce(v_effect_context,'{}'::jsonb),v_vars,v_step->'when'
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
     v_min_select:=coalesce(nullif(v_step->>'min','')::integer,0);
     v_max_select:=coalesce(nullif(v_step->>'max','')::integer,1);
     IF nullif(v_step->>'minFrom','') IS NOT NULL THEN
       v_path:=string_to_array(replace(v_step->>'minFrom','vars.',''),'.');
       v_data:=v_vars #> v_path;
       v_min_select:=CASE WHEN jsonb_typeof(v_data)='number' THEN greatest(0,(v_data#>>'{}')::integer)
         WHEN jsonb_typeof(v_data)='object' THEN greatest(0,coalesce((v_data->>'count')::integer,0)) ELSE 0 END;
     END IF;
     IF nullif(v_step->>'maxFrom','') IS NOT NULL THEN
       v_path:=string_to_array(replace(v_step->>'maxFrom','vars.',''),'.');
       v_data:=v_vars #> v_path;
       v_max_select:=CASE WHEN jsonb_typeof(v_data)='number' THEN greatest(0,(v_data#>>'{}')::integer)
         WHEN jsonb_typeof(v_data)='object' THEN greatest(0,coalesce((v_data->>'count')::integer,0)) ELSE v_max_select END;
     END IF;
     v_options:=public.private_card_effect_get_candidates_v1(
       p_room_id,v_owner,v_source_user,v_from,coalesce(v_step->'filter','{}'::jsonb),
       coalesce(v_step->>'targetController','self'),v_step->>'uniqueBy',v_vars
     );
     v_n:=jsonb_array_length(coalesce(v_options,'[]'::jsonb));
     IF v_n=0 AND v_min_select=0 THEN
       IF nullif(v_step->>'emptyMessage','') IS NOT NULL THEN
         INSERT INTO public.private_match_action_logs(room_id,turn_number,actor_user_id,action_label)
         SELECT p_room_id,coalesce(rms.turn_number,0),v_owner,v_step->>'emptyMessage'
         FROM public.room_match_states rms
         WHERE rms.room_id=p_room_id;
       END IF;
       UPDATE public.private_card_effect_runs_v1 SET variables=jsonb_set(variables,ARRAY[v_step->>'saveAs'],'[]'::jsonb,true),
         step_index=step_index+1,updated_at=now() WHERE room_id=p_room_id;
       CONTINUE;
     END IF;
     IF v_n < v_min_select THEN
       RAISE EXCEPTION '효과 처리에 필요한 선택 대상이 부족합니다.';
     END IF;
     v_target_owner:=v_owner;
     IF coalesce(v_step->>'chooser','self')='opponent' THEN
       SELECT user_id INTO v_target_owner
       FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner
       ORDER BY seat LIMIT 1;
       IF v_target_owner IS NULL THEN RAISE EXCEPTION '효과 대상을 선택할 상대 플레이어가 없습니다.'; END IF;
     END IF;
     v_waiting:=jsonb_build_object('kind','selection','save_as',v_step->>'saveAs','options',v_options,
       'min',v_min_select,'max',v_max_select,
       'chooser_user_id',v_target_owner,
       'unique_by',v_step->>'uniqueBy','prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'));
     IF nullif(v_step->>'displayVariable','') IS NOT NULL THEN
       v_path:=string_to_array(replace(v_step->>'displayVariable','vars.',''),'.');
       v_waiting:=v_waiting||jsonb_build_object('display_options',coalesce(v_vars #> v_path,'[]'::jsonb));
     END IF;
     v_pending:=jsonb_build_object('type','card_effect_selection','effect_id',v_effect_id,
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_target_owner,
       'prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'),
       'min',v_min_select,'max',v_max_select,
       'optional',coalesce((v_step->>'optional')::boolean,false));
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
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

   ELSIF v_op='calculate_switch_count' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'deploymentVariable',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     SELECT count(*)::integer INTO v_required_switch
       FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_owner
         AND public.private_card_effect_is_character_v1(e.value);
     v_required_switch:=greatest(0,v_required_switch+jsonb_array_length(coalesce(v_data,'[]'::jsonb))-5);
     v_vars:=jsonb_set(v_vars,ARRAY[v_step->>'saveAs'],to_jsonb(v_required_switch),true);
     UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;

   ELSIF v_op='calculate_hand_difference' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_n:=jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb));
     IF coalesce(v_step->>'mode','deficit')='excess' THEN
       v_n:=greatest(0,v_n-coalesce(nullif(v_step->>'targetCount','')::integer,0));
     ELSE
       v_n:=greatest(0,coalesce(nullif(v_step->>'targetCount','')::integer,0)-v_n);
     END IF;
     v_vars:=jsonb_set(coalesce(v_vars,'{}'::jsonb),ARRAY[v_step->>'saveAs'],to_jsonb(v_n),true);
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

   ELSIF v_op='ready_cards' THEN
      v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
      v_data:=v_vars #> v_path;
      FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
        v_card:=coalesce(v_item->'card',v_item);
        v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
        v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
        IF v_current IS NULL THEN CONTINUE; END IF;
        v_is_stunned:=lower(coalesce(v_current->>'status','')) IN ('stunned','stun','스턴');
        IF v_is_stunned THEN
          PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
            jsonb_build_object('rested',true,'status','stunned'));
        ELSE
          PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
            jsonb_build_object('rested',false,'status','active'));
        END IF;
      END LOOP;
    ELSIF v_op='stun_cards' THEN
      v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
      v_data:=v_vars #> v_path;
      FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
        v_card:=coalesce(v_item->'card',v_item);
        v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
        IF public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id') IS NOT NULL THEN
          PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
            jsonb_build_object('rested',false,'status','stunned'));
        END IF;
      END LOOP;
    ELSIF v_op='disable_original_abilities' THEN
      v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
      v_data:=v_vars #> v_path;
      FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
        v_card:=coalesce(v_item->'card',v_item);
        v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
        IF public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id') IS NOT NULL THEN
          PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
            jsonb_build_object('dsl_original_abilities_disabled',true,
              'dsl_original_abilities_disabled_until_turn',v_match.turn_number));
        END IF;
      END LOOP;
    ELSIF v_op='ready_source_character' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
         jsonb_build_object('rested',false,'status','active'));
     END IF;


   ELSIF v_op='grant_contact_remove' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path; v_item:=v_data->0; v_card:=coalesce(v_item->'card',v_item);
     IF v_item IS NOT NULL AND nullif(v_card->>'instance_id','') IS NOT NULL THEN
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
       IF v_current IS NULL THEN RAISE EXCEPTION '컨택 리무브 효과를 부여할 원본 캐릭터를 찾지 못했습니다.'; END IF;
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
         jsonb_build_object('dsl_contact_watch_target_instance_id',v_card->>'instance_id',
           'dsl_contact_watch_expires_turn',v_match.turn_number));
     END IF;

   ELSIF v_op='modify_contact_target_level' THEN
     v_contact_user:=nullif(v_effect_context#>>'{contact,target_user_id}','')::uuid;
     v_contact_instance:=coalesce(v_effect_context#>>'{contact,target_instance_id}',v_effect_context#>>'{contact,target_id}');
     v_current:=CASE WHEN v_contact_user IS NOT NULL AND v_contact_instance IS NOT NULL
       THEN public.private_card_effect_get_card_v1(p_room_id,v_contact_user,v_contact_instance) ELSE NULL END;
     IF v_current IS NOT NULL THEN
       v_amount:=coalesce(nullif(v_step->>'amount','')::integer,-1);
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_contact_user,v_contact_instance,
         jsonb_build_object('level_bonus',coalesce(nullif(v_current->>'level_bonus','')::numeric,0)+v_amount,
           'dsl_temporary_level_bonus',coalesce(nullif(v_current->>'dsl_temporary_level_bonus','')::numeric,0)+v_amount));
     END IF;

   ELSIF v_op='remove_all_contacting_characters' THEN
     v_contact_attacker_user:=nullif(v_effect_context#>>'{contact,attacker_user_id}','')::uuid;
     v_contact_attacker_instance:=coalesce(v_effect_context#>>'{contact,attacker_instance_id}',v_effect_context#>>'{contact,attacker_id}');
     v_contact_user:=nullif(v_effect_context#>>'{contact,target_user_id}','')::uuid;
     v_contact_instance:=coalesce(v_effect_context#>>'{contact,target_instance_id}',v_effect_context#>>'{contact,target_id}');
     v_current:=CASE WHEN v_contact_attacker_user IS NOT NULL AND v_contact_attacker_instance IS NOT NULL
       THEN public.private_card_effect_get_card_v1(p_room_id,v_contact_attacker_user,v_contact_attacker_instance) ELSE NULL END;
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_contact_attacker_user,'field',v_current,'remove_area',v_contact_attacker_user);
     END IF;
     v_current:=CASE WHEN v_contact_user IS NOT NULL AND v_contact_instance IS NOT NULL
       THEN public.private_card_effect_get_card_v1(p_room_id,v_contact_user,v_contact_instance) ELSE NULL END;
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_contact_user,'field',v_current,'remove_area',v_contact_user);
     END IF;
     UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,
       last_action_label='카드 효과: 컨택 중인 모든 캐릭터가 리무브되어 컨택이 종료되었습니다.'
     WHERE room_id=p_room_id AND pending_action->>'type'='character_contact';

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
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
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
     -- Attach the top deck card to the host selected in the target variable.
     -- set_cards is the same field used by the existing manual SET action.
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_contact_instance:=coalesce(v_item->>'instance_id',v_item#>>'{card,instance_id}');
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF v_contact_instance IS NULL THEN RAISE EXCEPTION '세트할 현장 캐릭터의 식별 정보가 없습니다.'; END IF;

       SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
       v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
       IF v_card ? 'instance_id' THEN
         v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_contact_instance);
         IF v_current IS NULL THEN RAISE EXCEPTION '덱 카드를 세트할 대상 캐릭터가 현장에 없습니다.'; END IF;
         UPDATE public.room_player_game_states
         SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_card->>'instance_id'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
         v_patch:=jsonb_build_object(
           'set_cards',coalesce(v_current->'set_cards','[]'::jsonb)||jsonb_build_array(
             (v_card-'rested'-'status'-'ap_bonus'-'level_bonus'-'summoned_this_turn'-'resolving')
             ||jsonb_build_object('face_up',coalesce((v_step->>'faceUp')::boolean,false),
               'set_owner_user_id',v_owner,'host_instance_id',v_contact_instance)
           )
         );
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_contact_instance,v_patch);
       END IF;
     END LOOP;

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
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_target_owner,
       'source_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','상대 손패 공개를 확인해 주세요.'),
       'revealed_cards',v_selected);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
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
         'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_game.user_id,
         'source_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','상대 덱 위 카드를 공개하고 확인해 주세요.'),
         'revealed_cards',v_selected);
       UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
       UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
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
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '컨택을 시작할 현장 캐릭터를 찾지 못했습니다.'; END IF;
     -- The ability already paid its sleep cost. Temporarily satisfy the normal
     -- declare-contact validation; the action immediately rests the attacker again.
     IF coalesce((v_current->>'rested')::boolean,false) OR coalesce(v_current->>'status','active')='rested' THEN
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
         jsonb_build_object('rested',false,'status','active'));
     END IF;
     -- A human may acknowledge the AI's target reveal. Continue the contact as
     -- the ability controller (v_owner), not as the acknowledging player.
     PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
     PERFORM set_config('request.jwt.claims',jsonb_build_object(
       'sub',v_owner::text,'role','authenticated'
     )::text,true);
     PERFORM public.perform_private_turn_action_v2(p_room_id,'declare_contact',jsonb_build_object(
       'attacker_instance_id',v_effect_source_instance_id,
       'target_instance_id',v_card->>'instance_id',
       'target_user_id',v_target_owner,
       'allow_newly_played',false,
       'allow_active_target',false
     ));
     PERFORM set_config('request.jwt.claim.sub',coalesce(v_old_sub,''),true);
     PERFORM set_config('request.jwt.claims',coalesce(v_old_claims,''),true);

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
          'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_ack_user,
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
            'source_card',coalesce(v_effect_source_card,'{}'::jsonb),
            'source_card_name',coalesce(v_effect_source_card->>'name','')
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
      v_pending:=jsonb_build_object('type','card_effect_reveal_ack','effect_id',v_effect_id,'source_instance_id',v_effect_source_instance_id,
        'chooser_user_id',v_target_owner,'source_user_id',v_owner,'prompt',CASE WHEN v_target_owner<>v_owner THEN '공개된 카드를 확인한 뒤 확인 완료를 눌러 주세요.' ELSE '카드 공개를 확인하고 효과를 계속 진행하세요.' END,
        'revealed_cards',v_selected);
      UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
      UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
        last_action_label='카드 효과: 카드 공개 확인을 기다립니다.' WHERE room_id=p_room_id;
      RETURN;

    ELSIF v_op='move_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''), 'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_to:=coalesce(v_step->>'to','');
       IF v_to='evidence_area' AND v_step ? 'faceUp' THEN
         v_card:=v_card||jsonb_build_object('face_up',coalesce(nullif(v_step->>'faceUp','')::boolean,false));
       END IF;
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),v_card,v_to,
         CASE WHEN v_to='hand' THEN v_target_owner ELSE v_target_owner END);
       IF v_to='field' THEN
         PERFORM public.private_card_effect_queue_field_entry_triggers_v1(p_room_id,v_target_owner,v_card);
         IF v_effect_id='card-0721-solution-remove-all-and-deploy-black' THEN
           UPDATE public.room_match_states
             SET state_version=state_version+1,
                 last_action_label=format(
                   '깡 효과: %s 캐릭터를 현장에 등장시켰습니다.',
                   coalesce(v_card->>'name',v_card->>'key','선택한')
                 )
           WHERE room_id=p_room_id;
         END IF;
       END IF;
     END LOOP;

   ELSIF v_op='move_selected_to_deck_bottom' THEN
     -- Collect every explicitly selected card from the configured variables.
     -- ID0735 selects one opponent field character and, optionally, one
     -- same-named opponent remove-area character; both must be moved together.
     v_ordered:=v_vars->'__ordered_selected';
     IF v_ordered IS NULL THEN
       v_remaining:='[]'::jsonb;
       FOR v_selected IN
         SELECT value FROM jsonb_array_elements(coalesce(v_step->'selectedVariables','[]'::jsonb))
       LOOP
         v_path:=string_to_array(replace(coalesce(v_selected #>> '{}',''),'vars.',''),'.');
         v_current:=v_vars #> v_path;
         FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_current,'[]'::jsonb)) LOOP
           v_card:=coalesce(v_item->'card',v_item);
           IF NOT EXISTS (
             SELECT 1
             FROM jsonb_array_elements(coalesce(v_remaining,'[]'::jsonb)) existing(value)
             WHERE coalesce(existing.value->>'instance_id',existing.value#>>'{card,instance_id}','')
               = coalesce(v_card->>'instance_id',v_item->>'instance_id','')
           ) THEN
             v_remaining:=v_remaining||jsonb_build_array(v_item);
           END IF;
         END LOOP;
       END LOOP;

       IF jsonb_array_length(coalesce(v_remaining,'[]'::jsonb))=0 THEN
         UPDATE public.private_card_effect_runs_v1
           SET step_index=step_index+1,updated_at=now()
           WHERE room_id=p_room_id;
         CONTINUE;
       END IF;

       IF coalesce(v_step->>'order','preserve')='player_choice'
          AND jsonb_array_length(v_remaining)>1 THEN
         v_target_owner:=v_owner;
         IF coalesce(v_step->>'chooser','self')='opponent' THEN
           SELECT user_id INTO v_target_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_owner
           ORDER BY seat LIMIT 1;
         END IF;
         v_waiting:=jsonb_build_object(
           'kind','order',
           'options',v_remaining,
           'save_as','__ordered_selected',
           'chooser_user_id',v_target_owner,
           'prompt',coalesce(v_step->>'orderPrompt','덱 아래로 보낼 카드의 순서를 정하세요.')
         );
         v_pending:=jsonb_build_object(
           'type','card_effect_order',
           'effect_id',v_effect_id,
           'chooser_user_id',v_target_owner,
           'prompt',coalesce(v_step->>'orderPrompt','덱 아래 카드의 순서를 정하세요.'),
           'options_count',jsonb_array_length(v_remaining)
         );
         UPDATE public.private_card_effect_runs_v1
           SET waiting=v_waiting,updated_at=now()
           WHERE room_id=p_room_id;
         UPDATE public.room_match_states
           SET pending_action=v_pending||jsonb_build_object(
                 'source_card',coalesce(v_effect_source_card,'{}'::jsonb),
                 'source_card_name',coalesce(v_effect_source_card->>'name','')
               ),
               state_version=state_version+1,
               last_action_label='카드 효과: 상대가 덱 아래 카드 순서를 정하기를 기다립니다.'
           WHERE room_id=p_room_id;
         RETURN;
       END IF;
       v_ordered:=v_remaining;
     END IF;

     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_ordered,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       PERFORM public.private_card_effect_move_card_v1(
         p_room_id,v_target_owner,coalesce(v_item->>'zone','variable'),
         v_card,'deck_bottom',v_target_owner
       );
     END LOOP;
     v_vars:=v_vars-'__ordered_selected';
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;

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
           UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
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
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
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
       SELECT public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id) INTO v_current;
       IF v_current IS NULL THEN RAISE EXCEPTION '겹칠 카드의 현장 원본을 찾지 못했습니다.'; END IF;
       v_patch:=jsonb_build_object('under_cards',coalesce(v_current->'under_cards','[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,v_patch);
     END LOOP;

   ELSIF v_op='set_mislead_value' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NULL THEN RAISE EXCEPTION '미스리드 수치를 설정할 현장 카드를 찾지 못했습니다.'; END IF;
     v_amount:=coalesce(nullif(v_step->>'value','')::integer,0);
     IF v_amount<0 OR v_amount>3 THEN RAISE EXCEPTION '미스리드 수치는 0~3 범위여야 합니다.'; END IF;
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
       jsonb_build_object('mislead_value',v_amount));

   ELSIF v_op='grant_keyword' THEN
     v_target_owner:=v_source_user;
      IF nullif(v_step->>'target','') IS NOT NULL THEN
        v_path:=string_to_array(replace(v_step->>'target','vars.',''),'.');
        v_data:=v_vars #> v_path;
        v_item:=v_data->0;
        v_card:=coalesce(v_item->'card',v_item);
        v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
      ELSE
        v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
      END IF;
     IF v_card IS NULL THEN RAISE EXCEPTION '키워드를 부여할 카드가 현장에 없습니다.'; END IF;
     v_keyword:=coalesce(v_step->>'keyword','');
     v_selected:=coalesce(v_card->'dsl_keywords','[]'::jsonb);
     IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_selected) x(value) WHERE x.value->>'effect_id'=v_effect_id AND x.value->>'keyword'=v_keyword) THEN
       v_selected:=v_selected||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'keyword',v_keyword,
         'expires_turn_number',(SELECT turn_number FROM public.room_match_states WHERE room_id=p_room_id)));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('dsl_keywords',v_selected));
     END IF;

   ELSIF v_op='modify_stat' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_amount:=coalesce((v_step->>'amount')::integer,0);
     -- "source_character" is a built-in target: resolve the effect's source
     -- card directly instead of looking for a nonexistent vars.source_character.
     IF replace(coalesce(v_step->>'target',''),'vars.','')='source_character' THEN
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
       IF v_current IS NULL THEN
         RAISE EXCEPTION 'AP를 변경할 효과 발동 캐릭터를 찾지 못했습니다.';
       END IF;
       v_data:=jsonb_build_array(jsonb_build_object(
         'owner_user_id',v_source_user,'zone','field',
         'instance_id',v_effect_source_instance_id,'card',v_current
       ));
     ELSE
       v_data:=v_vars #> v_path;
     END IF;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NOT NULL AND v_step->>'stat'='ap' THEN
         v_new_ap:=coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)+v_amount;
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('ap_bonus',v_new_ap));
       ELSIF v_current IS NOT NULL AND v_step->>'stat'='level' THEN
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',
           jsonb_build_object('level_bonus',coalesce(nullif(v_current->>'level_bonus','')::numeric,0)+v_amount,
             'dsl_temporary_level_bonus',coalesce(nullif(v_current->>'dsl_temporary_level_bonus','')::numeric,0)+v_amount));
       END IF;
     END LOOP;

   ELSIF v_op='offer_reaction' THEN
     v_waiting:=jsonb_build_object('kind','reaction','save_as',v_step->>'saveAs',
       'choices',coalesce(v_step->'choices','[]'::jsonb),'chooser_user_id',v_owner);
     v_pending:=jsonb_build_object('type','card_effect_reaction','effect_id',v_effect_id,
       'reaction_id',nullif(v_step->>'reactionId',''),
       'chooser_user_id',v_owner,'prompt',coalesce(v_step->>'prompt','효과를 발동할까요?'),
       'choices',coalesce(v_step->'choices','[]'::jsonb),'source_instance_id',v_effect_source_instance_id);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending||jsonb_build_object('source_card',coalesce(v_effect_source_card,'{}'::jsonb),'source_card_name',coalesce(v_effect_source_card->>'name','')),state_version=state_version+1,
       last_action_label='카드 효과: 반응 여부를 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='pay_cost' THEN
     IF v_step->>'cost'='sleep_partner' THEN
       SELECT * INTO v_board FROM public.room_player_turn_boards
         WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
       IF coalesce(v_board.partner_rested,false)
          OR (v_board.partner_mr_card IS NULL AND jsonb_array_length(coalesce(v_board.partner_non_mr_cards,'[]'::jsonb))=0) THEN
         RAISE EXCEPTION '슬립 비용으로 사용할 액티브 파트너가 없습니다.';
       END IF;
       UPDATE public.room_player_turn_boards SET
         partner_rested=true,
         partner_mr_card=CASE WHEN partner_mr_card IS NULL THEN NULL
           ELSE partner_mr_card||jsonb_build_object('rested',true,'status','rested') END,
         partner_non_mr_cards=coalesce((
           SELECT jsonb_agg(CASE WHEN e.ordinality=1 THEN e.value||jsonb_build_object('rested',true,'status','rested') ELSE e.value END ORDER BY e.ordinality)
           FROM jsonb_array_elements(coalesce(partner_non_mr_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
         ),'[]'::jsonb),
         updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     ELSIF v_step->>'cost'='sleep_source_character' THEN
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
       IF v_current IS NULL OR NOT public.private_card_effect_is_active_v1(v_current) THEN
         RAISE EXCEPTION '비용으로 슬립시킬 효과 발동 카드가 액티브 상태가 아닙니다.';
       END IF;
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,jsonb_build_object('rested',true,'status','rested'));
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


   ELSIF v_op='remove_all_field_characters' THEN
     FOR v_target_owner IN
       SELECT rp.user_id FROM public.room_players rp
       WHERE rp.room_id=p_room_id ORDER BY rp.seat
     LOOP
       SELECT * INTO v_board FROM public.room_player_turn_boards
       WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
       FOR v_item IN
         SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb))
       LOOP
         v_card:=v_item;
         IF public.private_card_effect_is_character_v1(v_card) THEN
           PERFORM public.private_card_effect_move_card_v1(
             p_room_id,v_target_owner,'field',v_card,'remove_area',v_target_owner
           );
         END IF;
       END LOOP;
     END LOOP;


   ELSIF v_op='remove_top_evidence_silently' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_data:=coalesce(v_game.evidence_cards,'[]'::jsonb);
     v_n:=jsonb_array_length(v_data);
     IF v_n>0 THEN
       v_card:=v_data->(v_n-1);
       SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
         FILTER (WHERE e.ordinality<v_n),'[]'::jsonb)
         INTO v_remaining FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality);
       UPDATE public.room_player_game_states SET
         evidence_cards=v_remaining,
         remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('face_up',true)),
         updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET
         evidence_count=greatest(0,evidence_count-1),
         remove_count=remove_count+1,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       IF v_effect_id='card-0249-end-turn-swap-evidence' THEN
         UPDATE public.room_match_states
           SET state_version=state_version+1,
               last_action_label=format(
                 'ID:0249 효과: 증거 맨 위 카드 %s를 리무브했습니다.',
                 coalesce(v_card->>'key','카드')
               )
         WHERE room_id=p_room_id;
       END IF;
     ELSIF v_effect_id='card-0249-end-turn-swap-evidence' THEN
       UPDATE public.room_match_states
         SET state_version=state_version+1,
             last_action_label='ID:0249 효과: 증거 에이리어가 비어 있어 리무브를 건너뛰었습니다.'
       WHERE room_id=p_room_id;
     END IF;

   ELSIF v_op='move_source_to_remove_area' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_source_user,'field',v_current,'remove_area',v_source_user);
     END IF;

   ELSIF v_op='move_source_to_faceup_evidence' THEN
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_current IS NOT NULL THEN
       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_source_user,'field',v_current,'evidence_area',v_source_user);
       IF v_effect_id='card-0249-end-turn-swap-evidence' THEN
         UPDATE public.room_match_states
           SET state_version=state_version+1,
               last_action_label='ID:0249 효과: 발동한 범인 카드를 앞면 증거로 이동했습니다.'
         WHERE room_id=p_room_id;
       END IF;
     END IF;

   ELSIF v_op='remove_top_deck_cards_and_refresh_excluding_source_if_empty' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_deck:=coalesce(v_game.deck_order,'[]'::jsonb);
     v_selected:=coalesce(v_game.remove_cards,'[]'::jsonb);
     v_n:=greatest(0,coalesce((v_step->>'count')::integer,5));
     FOR v_i IN 1..v_n LOOP
       EXIT WHEN jsonb_array_length(coalesce(v_deck,'[]'::jsonb))=0;
       v_card:=v_deck->0;
       v_deck:=coalesce((SELECT jsonb_agg(e.value ORDER BY e.ordinality)
         FROM jsonb_array_elements(v_deck) WITH ORDINALITY e(value,ordinality)
         WHERE e.ordinality>1),'[]'::jsonb);
       v_selected:=v_selected||jsonb_build_array(v_card);
     END LOOP;
     v_data:='[]'::jsonb;
     v_remaining:='[]'::jsonb;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_selected,'[]'::jsonb)) LOOP
       IF v_item->>'instance_id' IS DISTINCT FROM v_effect_source_instance_id THEN
         v_data:=v_data||jsonb_build_array(v_item);
       ELSE
         v_remaining:=v_remaining||jsonb_build_array(v_item);
       END IF;
     END LOOP;
     UPDATE public.room_player_game_states SET deck_order=v_deck,remove_cards=v_selected,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     UPDATE public.room_player_turn_boards SET remove_count=jsonb_array_length(v_selected),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     IF jsonb_array_length(coalesce(v_deck,'[]'::jsonb))=0
        AND jsonb_array_length(coalesce(v_data,'[]'::jsonb))>0 THEN
       SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb) INTO v_deck
         FROM jsonb_array_elements(v_data) e(value);
       UPDATE public.room_player_game_states SET deck_order=v_deck,remove_cards=v_remaining,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET remove_count=jsonb_array_length(v_remaining),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       SELECT rp.user_id INTO v_target_owner FROM public.room_players rp
         WHERE rp.room_id=p_room_id AND rp.user_id<>v_owner ORDER BY rp.seat LIMIT 1;
       IF v_target_owner IS NOT NULL THEN
         SELECT * INTO v_game FROM public.room_player_game_states
           WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
         v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
         IF v_card ? 'instance_id' THEN
           UPDATE public.room_player_game_states SET
             deck_order=coalesce((SELECT jsonb_agg(e.value ORDER BY e.ordinality)
               FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
               WHERE e.ordinality>1),'[]'::jsonb),
             evidence_cards=coalesce(v_game.evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card),
             updated_at=now()
             WHERE room_id=p_room_id AND user_id=v_target_owner;
           UPDATE public.room_player_turn_boards SET evidence_count=evidence_count+1,updated_at=now()
             WHERE room_id=p_room_id AND user_id=v_target_owner;
         END IF;
       END IF;
     END IF;

   ELSIF v_op='remove_top_deck_cards_and_refresh_if_empty' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_deck:=coalesce(v_game.deck_order,'[]'::jsonb);
     v_selected:=coalesce(v_game.remove_cards,'[]'::jsonb);
     v_n:=greatest(0,coalesce((v_step->>'count')::integer,5));
     FOR v_i IN 1..v_n LOOP
       EXIT WHEN jsonb_array_length(coalesce(v_deck,'[]'::jsonb))=0;
       v_card:=v_deck->0;
       v_deck:=coalesce((SELECT jsonb_agg(e.value ORDER BY e.ordinality)
         FROM jsonb_array_elements(v_deck) WITH ORDINALITY e(value,ordinality)
         WHERE e.ordinality>1),'[]'::jsonb);
       v_selected:=v_selected||jsonb_build_array(v_card);
     END LOOP;
     UPDATE public.room_player_game_states SET deck_order=v_deck,remove_cards=v_selected,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     UPDATE public.room_player_turn_boards SET remove_count=jsonb_array_length(v_selected),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     IF jsonb_array_length(coalesce(v_deck,'[]'::jsonb))=0 AND jsonb_array_length(coalesce(v_selected,'[]'::jsonb))>0 THEN
       SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb) INTO v_deck
         FROM jsonb_array_elements(v_selected) e(value);
       UPDATE public.room_player_game_states SET deck_order=v_deck,remove_cards='[]'::jsonb,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       UPDATE public.room_player_turn_boards SET remove_count=0,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       SELECT rp.user_id INTO v_target_owner FROM public.room_players rp
         WHERE rp.room_id=p_room_id AND rp.user_id<>v_owner ORDER BY rp.seat LIMIT 1;
       IF v_target_owner IS NOT NULL THEN
         SELECT * INTO v_game FROM public.room_player_game_states
           WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
         v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
         IF v_card ? 'instance_id' THEN
           UPDATE public.room_player_game_states SET
             deck_order=coalesce((SELECT jsonb_agg(e.value ORDER BY e.ordinality)
               FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
               WHERE e.ordinality>1),'[]'::jsonb),
             evidence_cards=coalesce(v_game.evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card),
             updated_at=now()
             WHERE room_id=p_room_id AND user_id=v_target_owner;
           UPDATE public.room_player_turn_boards SET evidence_count=evidence_count+1,updated_at=now()
             WHERE room_id=p_room_id AND user_id=v_target_owner;
         END IF;
       END IF;
     END IF;

   ELSIF v_op='remove_contact_target' THEN
     SELECT pending_action INTO v_pending FROM public.room_match_states
       WHERE room_id=p_room_id FOR UPDATE;
     IF v_pending->>'type'='character_contact'
        AND coalesce(v_pending->>'attacker_instance_id',v_pending->>'attacker_id')=v_effect_source_instance_id
        AND nullif(v_pending->>'target_instance_id','') IS NOT NULL THEN
       v_target_owner:=nullif(v_pending->>'target_user_id','')::uuid;
       v_card:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_pending->>'target_instance_id');
       IF v_card IS NOT NULL THEN
         PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,'field',v_card,'remove_area',v_target_owner);
       END IF;
       UPDATE public.room_match_states SET pending_action=NULL,state_version=state_version+1,
         last_action_label='카드 효과: 컨택한 캐릭터가 리무브되어 컨택이 종료되었습니다.'
         WHERE room_id=p_room_id;
     END IF;

   ELSIF v_op='remove_all_deck_and_refresh' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_selected:=coalesce(v_game.remove_cards,'[]'::jsonb)||coalesce(v_game.deck_order,'[]'::jsonb);
     SELECT coalesce(jsonb_agg(e.value ORDER BY random()),'[]'::jsonb)
       INTO v_deck FROM jsonb_array_elements(coalesce(v_selected,'[]'::jsonb)) e(value);
     UPDATE public.room_player_game_states
       SET deck_order=v_deck,remove_cards='[]'::jsonb,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     UPDATE public.room_player_turn_boards SET remove_count=0,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;
     SELECT rp.user_id INTO v_target_owner
       FROM public.room_players rp WHERE rp.room_id=p_room_id AND rp.user_id<>v_owner
       ORDER BY rp.seat LIMIT 1;
     IF v_target_owner IS NOT NULL THEN
       SELECT * INTO v_game FROM public.room_player_game_states
         WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
       v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
       IF v_card ? 'instance_id' THEN
         UPDATE public.room_player_game_states SET
           deck_order=coalesce((
             SELECT jsonb_agg(e.value ORDER BY e.ordinality)
             FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
             WHERE e.ordinality>1
           ),'[]'::jsonb),
           evidence_cards=coalesce(v_game.evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card),
           updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_target_owner;
         UPDATE public.room_player_turn_boards SET evidence_count=evidence_count+1,updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner;
       END IF;
     END IF;

   ELSIF v_op='reveal_all_evidence' THEN
     UPDATE public.room_player_game_states g
       SET evidence_cards=coalesce((
         SELECT jsonb_agg(e.value||jsonb_build_object('face_up',true) ORDER BY e.ordinality)
         FROM jsonb_array_elements(coalesce(g.evidence_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
       ),'[]'::jsonb),updated_at=now()
       WHERE g.room_id=p_room_id AND g.user_id=v_owner;

   ELSIF v_op='move_top_file_cards' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_data:=coalesce(v_game.file_cards,'[]'::jsonb);
     v_selected:='[]'::jsonb;
     v_selected_ids:='{}'::text[];
     v_n:=greatest(0,coalesce((v_step->>'count')::integer,1));
     FOR v_i IN REVERSE jsonb_array_length(v_data)..1 LOOP
       v_card:=v_data->(v_i-1);
       IF lower(coalesce(v_card->>'card_type',v_card->>'type','')) NOT IN ('partner','파트너','パートナー')
          AND cardinality(v_selected_ids)<v_n THEN
         v_selected:=jsonb_build_array(v_card)||v_selected;
         v_selected_ids:=array_append(v_selected_ids,coalesce(v_card->>'instance_id',''));
       END IF;
     END LOOP;
     IF jsonb_array_length(v_selected)>0 THEN
       SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
         FILTER (WHERE NOT (coalesce(e.value->>'instance_id','')=ANY(v_selected_ids))),'[]'::jsonb)
         INTO v_remaining FROM jsonb_array_elements(v_data) WITH ORDINALITY e(value,ordinality);
       IF coalesce(v_step->>'to','hand')='remove_area' THEN
         UPDATE public.room_player_game_states SET file_cards=v_remaining,
           remove_cards=coalesce(remove_cards,'[]'::jsonb)||v_selected,updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_owner;
         UPDATE public.room_player_turn_boards SET
           file_count=greatest(0,file_count-jsonb_array_length(v_selected)),
           remove_count=remove_count+jsonb_array_length(v_selected),updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_owner;
       ELSE
         UPDATE public.room_player_game_states SET file_cards=v_remaining,
           hand=coalesce(hand,'[]'::jsonb)||v_selected,updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_owner;
         UPDATE public.room_player_turn_boards SET
           file_count=greatest(0,file_count-jsonb_array_length(v_selected)),updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_owner;
       END IF;
     END IF;

   ELSIF v_op='set_next_hint_disabled' THEN
     UPDATE public.room_player_turn_boards
       SET next_hint_used=true,next_hint_pending=false,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_owner;

   ELSIF v_op='draw_cards' THEN
     IF nullif(v_step->>'countFrom','') IS NOT NULL THEN
       v_path:=string_to_array(replace(v_step->>'countFrom','vars.',''),'.');
       v_data:=v_vars #> v_path;
       v_n:=CASE WHEN jsonb_typeof(v_data)='array' THEN jsonb_array_length(v_data)
                 WHEN jsonb_typeof(v_data)='number' THEN (v_data#>>'{}')::integer ELSE 0 END;
     ELSE
       v_n:=coalesce((v_step->>'count')::integer,1);
     END IF;
     FOR v_i IN 1..greatest(0,v_n) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,coalesce(v_step->>'destination','hand'));
     END LOOP;

   ELSIF v_op='gain_evidence' THEN
     v_target_owner:=v_owner;
     IF v_step->>'targetOwner'='opponent' THEN
       SELECT user_id INTO v_target_owner FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     END IF;
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_target_owner,'evidence');
     END LOOP;

   ELSIF v_op='mark_keyword_activated' THEN
     SELECT turn_number INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
     v_turn:=coalesce(nullif(v_effect_context->>'turn_number','')::integer,v_turn);
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,
       jsonb_build_object('haya_activated_turn_number',v_turn));

   ELSIF v_op='ready_cards_that_used_keyword' THEN
     v_turn:=coalesce(nullif(v_effect_context->>'ending_turn_number','')::integer,
       nullif(v_effect_context->>'turn_number','')::integer,v_match.turn_number);
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
-- AI discovery supports rested/stunned sources and case ID1120.
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
   
   FOR v_def IN
     SELECT d.value
     FROM jsonb_array_elements(coalesce(v_catalog, '[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event' = 'character.activated_ability'
       AND (
         public.private_card_effect_is_active_v1(v_card)
         OR (
           NOT coalesce((d.value->>'requiresActiveSource')::boolean,false)
           AND (
             (
               (
                 coalesce((d.value->>'allowRestedSource')::boolean,false)
                 OR EXISTS (
                   SELECT 1 FROM jsonb_array_elements(coalesce(d.value->'steps','[]'::jsonb)) step(value)
                   WHERE step.value->>'op'='ready_source_character'
                 )
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
             OR (
               coalesce((d.value->>'allowStunnedSource')::boolean,false)
               AND (
                 coalesce((v_card->>'stunned')::boolean,false)
                 OR coalesce((v_card->>'stun')::boolean,false)
                 OR coalesce((v_card->>'is_stunned')::boolean,false)
                 OR lower(coalesce(v_card->>'status','')) IN ('stunned','stun','스턴')
               )
             )
           )
         )
       )
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean, false)
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
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
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
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
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
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
   
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((d.value->>'allowPartnerArea')::boolean,false)
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
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
    AND (
      (
        NOT coalesce(v_board.base_card_played_this_turn,false)
        AND NOT coalesce(v_board.character_played_this_turn,false)
      )
      OR coalesce(v_board.next_hint_pending,false)
    ) THEN
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
         AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)
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
   ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
     v_case_id:='0806'; v_case_name:='흔들리는 마음';
 ELSIF v_case_key IN ('B09107P','B09107','1046') THEN
   v_case_id:='1046'; v_case_name:='범인들의 범행';
 ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
   v_case_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
 ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
   v_case_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
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
$function$;
-- Server validation, ID1120 case triggers, and Bullet's no-guard contact path.
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

 IF p_action='solve_case' THEN
   SELECT * INTO v_match
   FROM public.room_match_states
   WHERE room_id=p_room_id
   FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN
     RAISE EXCEPTION '진행 중인 게임에서만 사건을 해결할 수 있습니다.';
   END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user
      OR coalesce(v_match.turn_step,'')<>'main' THEN
     RAISE EXCEPTION '자신의 메인 단계에서만 사건을 해결할 수 있습니다.';
   END IF;
   IF v_match.pending_action IS NOT NULL
      OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '진행 중인 선택/응답을 먼저 완료해 주세요.';
   END IF;
   SELECT * INTO v_new_board
   FROM public.room_player_turn_boards
   WHERE room_id=p_room_id AND user_id=v_user
   FOR UPDATE;
   IF NOT FOUND THEN
     RAISE EXCEPTION '자신의 보드를 찾을 수 없습니다.';
   END IF;
   IF coalesce(v_new_board.case_phase,v_match.case_phase,'incident')<>'solution' THEN
     RAISE EXCEPTION '해결편에서만 사건을 해결할 수 있습니다.';
   END IF;
   v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''),'[^A-Za-z0-9]','','g'));
   IF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_new_board.event_rule_code,'')='culprits_1046' THEN
     RAISE EXCEPTION '범인들의 범행은 일반 사건 해결 대신 사건 선언 효과를 발동해야 합니다.';
   END IF;
   IF v_case_key IN ('B11098','B11098P','1261')
      OR coalesce(v_new_board.event_rule_code,'')='conan_vs_kid_1261' THEN
     IF v_match.first_player_user_id=v_user THEN
       IF coalesce(v_new_board.evidence_count,0)<8 THEN
         RAISE EXCEPTION '이 사건의 해결에는 증거 8장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     ELSE
       IF coalesce(v_new_board.evidence_count,0)<7 THEN
         RAISE EXCEPTION '이 사건의 해결에는 증거 7장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     END IF;
   ELSE
     IF v_match.first_player_user_id=v_user THEN
       IF coalesce(v_new_board.evidence_count,0)<7 THEN
         RAISE EXCEPTION '사건 해결에는 증거 7장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     ELSE
       IF coalesce(v_new_board.evidence_count,0)<6 THEN
         RAISE EXCEPTION '사건 해결에는 증거 6장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     END IF;
   END IF;
   UPDATE public.room_match_states
   SET game_over=true,
       winner_user_id=v_user,
       winner_turn_number=v_match.turn_number,
       last_action_label='사건 해결 성공! 승리 선언이 완료되었습니다.',
       state_version=state_version+1
   WHERE room_id=p_room_id;
   RETURN public.get_private_turn_state_v2(p_room_id);
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
   ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
     v_case_internal_id:='0806';
     v_case_name:='흔들리는 마음';
     v_case_effect_id:='card-0806-case-solution-activated-flip-evidence-level-down';
   ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_new_board.event_rule_code,'')='culprits_1046' THEN
     v_case_internal_id:='1046';
     v_case_name:='범인들의 범행';
     v_case_effect_id:='card-1046-culprits-crime-case-effect';
   ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
     v_case_internal_id:='0666'; v_case_name:='사랑과 추리の検道大会';
     v_case_effect_id:='card-0666-case-solution-flip-two-search-heiji-kazuha';
   ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
     v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     v_case_effect_id:='card-1120-antique-tray-case-effect';
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
    IF coalesce((v_source_card->>'dsl_original_abilities_disabled')::boolean,false) THEN
      RAISE EXCEPTION '원래 능력이 턴 종료 시까지 무효화된 캐릭터입니다.';
    END IF;
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
 
IF NOT public.private_card_effect_is_active_v1(v_source_card)
   AND (
     coalesce((v_effect_definition->>'requiresActiveSource')::boolean,false)
     OR NOT (
       (
         (
           coalesce((v_effect_definition->>'allowRestedSource')::boolean,false)
           OR EXISTS (
             SELECT 1 FROM jsonb_array_elements(coalesce(v_effect_definition->'steps','[]'::jsonb)) step(value)
             WHERE step.value->>'op'='ready_source_character'
           )
         )
         AND (
           coalesce((v_source_card->>'rested')::boolean,false)
           OR lower(coalesce(v_source_card->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
         )
         AND NOT (
           coalesce((v_source_card->>'stunned')::boolean,false)
           OR coalesce((v_source_card->>'stun')::boolean,false)
           OR coalesce((v_source_card->>'is_stunned')::boolean,false)
           OR lower(coalesce(v_source_card->>'status','')) IN ('stunned','stun','스턴')
         )
       )
       OR (
         coalesce((v_effect_definition->>'allowStunnedSource')::boolean,false)
         AND (
           coalesce((v_source_card->>'stunned')::boolean,false)
           OR coalesce((v_source_card->>'stun')::boolean,false)
           OR coalesce((v_source_card->>'is_stunned')::boolean,false)
           OR lower(coalesce(v_source_card->>'status','')) IN ('stunned','stun','스턴')
         )
       )
     )
   ) THEN
  RAISE EXCEPTION '이 카드 효과는 현재 캐릭터 상태에서 발동할 수 없습니다.';
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


IF p_action='guard_contact_with_character'
   AND coalesce(v_before_pending->>'type','')='character_contact_guard' THEN
   IF EXISTS (
     SELECT 1
     FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) a(value)
     CROSS JOIN LATERAL jsonb_array_elements(
       coalesce(a.value->'dsl_keywords','[]'::jsonb)
       || coalesce(a.value->'dsl_continuous_keywords','[]'::jsonb)
     ) k(value)
     WHERE b.room_id=p_room_id
       AND b.user_id=nullif(v_before_pending->>'attacker_user_id','')::uuid
       AND a.value->>'instance_id'=v_before_pending->>'attacker_instance_id'
       AND lower(coalesce(k.value->>'keyword',k.value#>>'{}','')) IN ('bullet','브렛','ブレット')
   ) THEN
     RAISE EXCEPTION '브렛을 가진 캐릭터의 액션은 가드할 수 없습니다.';
   END IF;
END IF;

 v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));

 IF p_action='declare_contact' THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   IF coalesce(v_after_pending->>'type','')='character_contact_guard' THEN
     SELECT e.value INTO v_source_card
     FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id
       AND b.user_id=nullif(v_after_pending->>'attacker_user_id','')::uuid
       AND e.value->>'instance_id'=v_after_pending->>'attacker_instance_id'
     LIMIT 1;
     IF v_source_card IS NOT NULL AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(
         coalesce(v_source_card->'dsl_keywords','[]'::jsonb)
         || coalesce(v_source_card->'dsl_continuous_keywords','[]'::jsonb)
       ) k(value)
       WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}','')) IN ('bullet','브렛','ブレット')
     ) THEN
       v_after_pending:=jsonb_set(v_after_pending,'{type}',to_jsonb('character_contact'::text));
       v_after_pending:=v_after_pending||jsonb_build_object(
         'cut_in_priority_user_id',
         CASE WHEN coalesce(nullif(v_after_pending->>'target_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'target_bonus','')::numeric,0)
                 <=coalesce(nullif(v_after_pending->>'attacker_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'attacker_bonus','')::numeric,0)
           THEN v_after_pending->>'target_user_id' ELSE v_after_pending->>'attacker_user_id' END,
         'next_responder_user_id',
         CASE WHEN coalesce(nullif(v_after_pending->>'target_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'target_bonus','')::numeric,0)
                 <=coalesce(nullif(v_after_pending->>'attacker_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'attacker_bonus','')::numeric,0)
           THEN v_after_pending->>'target_user_id' ELSE v_after_pending->>'attacker_user_id' END,
         'attacker_cut_in_used',false,'target_cut_in_used',false,
         'attacker_cut_in_passed',false,'target_cut_in_passed',false,
         'cut_in_used',false,'guarded_contact',false
       );
       UPDATE public.room_match_states
       SET pending_action=v_after_pending,state_version=state_version+1,
           last_action_label=format('브렛: %s의 액션은 가드할 수 없습니다. 컷인 선택으로 진행합니다.',
             coalesce(v_source_card->>'name',v_source_card->>'key','캐릭터'))
       WHERE room_id=p_room_id;
     END IF;
   END IF;
 END IF;


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

 IF p_action='declare_contact'
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   IF v_after_pending->>'type'='character_contact'
      AND nullif(v_after_pending->>'attacker_user_id','')::uuid=v_user THEN
     v_instance_id:=coalesce(v_after_pending->>'attacker_instance_id',v_after_pending->>'attacker_id');
     SELECT e.value INTO v_source_card
       FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(
         p_room_id,v_user,v_user,v_source_card,'character.contact_started',
         jsonb_build_object('turn_number',v_turn,'contact',v_after_pending),NULL,false
       );
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
   UPDATE public.room_player_turn_boards b SET
     field_cards=coalesce((SELECT jsonb_agg(CASE WHEN coalesce(nullif(e.value->>'dsl_temporary_level_bonus','')::numeric,0)<>0
       THEN e.value||jsonb_build_object('level_bonus',
         coalesce(nullif(e.value->>'level_bonus','')::numeric,0)-coalesce(nullif(e.value->>'dsl_temporary_level_bonus','')::numeric,0),
         'dsl_temporary_level_bonus',0)
       ELSE e.value END ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
     partner_mr_card=CASE WHEN b.partner_mr_card IS NULL THEN NULL
       WHEN coalesce(nullif(b.partner_mr_card->>'dsl_temporary_level_bonus','')::numeric,0)<>0
       THEN b.partner_mr_card||jsonb_build_object('level_bonus',
         coalesce(nullif(b.partner_mr_card->>'level_bonus','')::numeric,0)-coalesce(nullif(b.partner_mr_card->>'dsl_temporary_level_bonus','')::numeric,0),
         'dsl_temporary_level_bonus',0)
       ELSE b.partner_mr_card END,
     updated_at=now()
   WHERE b.room_id=p_room_id;
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
     ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
       v_case_internal_id:='0806'; v_case_name:='흔들리는 마음';
     ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
       v_case_internal_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
     ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
       v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
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
       'method',CASE WHEN p_action='next_hint' THEN 'next_hint' ELSE 'manual' END,
       'is_first_character_this_turn',v_first_entry,'source',v_source_card,
       'controller_user_id',v_user::text),
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
           'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false);
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
         'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false);
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
         'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false);
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
          'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false
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
         PERFORM public.private_card_effect_start_event_v1(
           p_room_id,v_evidence_owner,v_evidence_owner,v_old_evidence_card,'evidence.card_removed',
           jsonb_build_object(
             'turn_number',v_turn,
             'evidence_removed_instance_id',v_old_evidence_card->>'instance_id',
             'evidence_owner_user_id',v_evidence_owner::text,
             'removed_evidence_card',v_old_evidence_card,
             'watch_user_id',coalesce(v_trigger_owner,v_evidence_owner)::text
           ),NULL,false
         );
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
-- AI RPC permission gate matches the same source-status rules.
CREATE OR REPLACE FUNCTION public.perform_private_ai_turn_action_v1(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  select * into v_battle from public.private_ai_battles
  where room_id = p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  if p_action not in (
    'begin_turn','place_files','play_character','play_event','next_hint_take_file',
    'next_hint','cancel_next_hint','partner_assist','partner_deduce','end_turn',
    'declare_contact','attack_evidence','guard_with_character','decline_guard',
    'guard_contact_with_character','decline_contact_guard','contact_use_cutin',
    'contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead',
    'resolve_evidence_attack','acknowledge_evidence_remove','acknowledge_culprits_crime',
    'acknowledge_hand_reveal','acknowledge_deck_remove','acknowledge_file_remove',
    'acknowledge_shared_deck_peek','finish_event','solve_case','declare_solution',
    'rest_partner_manual','refresh_deck','return_deck_peek','share_deck_peek_card',
    'take_deck_peek_card','remove_deck_peek_card','shuffle_deck','card_effect_continue','activate_card_effect','activate_case_effect','investigate'
  ) then
    raise exception 'AI 대전에서 허용되지 않은 행동입니다.';
  end if;

  select * into v_match from public.room_match_states
  where room_id = p_room_id for update;
  if not found or v_match.game_over then
    raise exception '이미 종료된 AI 대전입니다.';
  end if;

  if cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 then
    raise exception 'AI 대전은 중도 종료 응답을 기다리는 동안 일시 중지되어 있습니다.';
  end if;

  if v_match.current_turn_user_id is distinct from v_battle.ai_user_id
    and coalesce(v_match.pending_action ->> 'target_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'next_responder_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'initiator_user_id', '') <> v_battle.ai_user_id::text and coalesce(v_match.pending_action ->> 'chooser_user_id', '') <> v_battle.ai_user_id::text
    
and NOT (
   p_action = CASE coalesce(v_match.pending_action->>'type','')
     WHEN 'deck_remove_reveal' THEN 'acknowledge_deck_remove'
     WHEN 'file_remove_reveal' THEN 'acknowledge_file_remove'
     WHEN 'culprits_crime_reveal' THEN 'acknowledge_culprits_crime'
     WHEN 'hand_reveal' THEN 'acknowledge_hand_reveal'
     WHEN 'evidence_remove_reveal' THEN 'acknowledge_evidence_remove'
     ELSE ''
   END
   AND coalesce(v_match.pending_action->>'source_user_id','') <> v_battle.ai_user_id::text
   AND NOT (coalesce(v_match.pending_action->'acknowledged_user_ids','[]'::jsonb)
     @> jsonb_build_array(v_battle.ai_user_id::text))
 )
 and NOT (
  (
    p_action='activate_card_effect'
    AND EXISTS (
      SELECT 1
      FROM public.private_card_effect_catalog_v1 c
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
      JOIN public.room_player_turn_boards b ON b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
      WHERE c.catalog_id='main'
        AND d.value->>'effectId'=p_payload->>'effect_id'
        AND d.value->>'activationTiming'='any'
        AND e.value->>'instance_id'=p_payload->>'source_instance_id'
        AND public.private_card_effect_matches_id_v1(e.value,coalesce(d.value->'cardIds','[]'::jsonb))
        AND (
          public.private_card_effect_is_active_v1(e.value)
          OR (
            NOT coalesce((d.value->>'requiresActiveSource')::boolean,false)
            AND (
              (
                (
                  coalesce((d.value->>'allowRestedSource')::boolean,false)
                  OR EXISTS (
                    SELECT 1 FROM jsonb_array_elements(coalesce(d.value->'steps','[]'::jsonb)) step(value)
                    WHERE step.value->>'op'='ready_source_character'
                  )
                )
                AND (
                  coalesce((e.value->>'rested')::boolean,false)
                  OR lower(coalesce(e.value->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
                )
                AND NOT (
                  coalesce((e.value->>'stunned')::boolean,false)
                  OR coalesce((e.value->>'stun')::boolean,false)
                  OR coalesce((e.value->>'is_stunned')::boolean,false)
                  OR lower(coalesce(e.value->>'status','')) IN ('stunned','stun','스턴')
                )
              )
              OR (
                coalesce((d.value->>'allowStunnedSource')::boolean,false)
                AND (
                  coalesce((e.value->>'stunned')::boolean,false)
                  OR coalesce((e.value->>'stun')::boolean,false)
                  OR coalesce((e.value->>'is_stunned')::boolean,false)
                  OR lower(coalesce(e.value->>'status','')) IN ('stunned','stun','스턴')
                )
              )
            )
          )
        )
    )
  )
  OR (
    p_action='investigate'
    AND EXISTS (
      SELECT 1
      FROM public.room_player_turn_boards b
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
      WHERE b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
        AND e.value->>'instance_id'=p_payload->>'instance_id'
        AND public.private_card_effect_is_active_v1(e.value)
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(
            coalesce(e.value->'dsl_keywords','[]'::jsonb)
            || coalesce(e.value->'dsl_continuous_keywords','[]'::jsonb)
          ) k(value)
          WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
            IN ('haya','swift','신속','질풍','疾風')
        )
    )
  )
) then

    raise exception '현재 AI가 행동할 차례가 아닙니다.';
  end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  IF p_action='begin_turn' THEN
    -- Keep status reset, draw, and file placement inside one AI action/RPC.
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
  END IF;

  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  return v_result;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  raise;
end;
$function$;
-- Merge only missing red-handless definitions and preserve live overrides.
WITH new_defs AS (
  SELECT value, ordinality FROM jsonb_array_elements($handless_defs$[{"effectId":"card-0794-activated-discard-hand-remove-character","cardIds":["0794"],"cardNameKo":"세라 마스미&메리","cardNameJa":"世良真純＆メアリー","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","prompt":"비용으로 자신의 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area"},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"field":"card_type","operator":"equals","value":"character"},"prompt":"리무브할 상대 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"oncePerTurn":true,"allowRestedSource":true,"activationLabelKo":"손패 1장 리무브 후 캐릭터 리무브"},{"effectId":"card-0794-activated-draw-at-hand-two","cardIds":["0794"],"cardNameKo":"세라 마스미&메리","cardNameJa":"世良真純＆メアリー","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}],"steps":[{"op":"draw_cards","count":1,"destination":"hand"}],"oncePerTurn":true,"allowPartnerArea":true,"allowRestedSource":true,"activationLabelKo":"손패 2장 이하일 때 1장 드로우"},{"effectId":"card-0220-partner-red-end-turn-remove-ap8000","cardIds":["0220"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"player.turn_ended","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"source.status","operator":"in","value":["rested","stunned"]}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":8000}]},"prompt":"AP 8000 이하인 상대 캐릭터를 최대 1장 선택해 리무브하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"scope":"field_watch"},{"effectId":"card-0220-activated-grant-bullet-or-charge-case","cardIds":["0220"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"field","targetController":"self","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"자신의 현장에서 레벨 7 이하 적 캐릭터를 최대 1장 선택하세요."},{"op":"offer_reaction","reactionId":"card-0220-keyword-choice","actor":"controller","choices":["bullet","charge_case"],"saveAs":"keyword_choice","when":{"fact":"vars.target.count","operator":"greater_than","value":0},"prompt":"선택한 캐릭터에 부여할 키워드를 선택하세요."},{"op":"grant_keyword","target":"vars.target","keyword":"bullet","duration":"turn_end","displayNameKo":"브렛","when":{"fact":"vars.keyword_choice","operator":"equals","value":"bullet"}},{"op":"grant_keyword","target":"vars.target","keyword":"charge_case","duration":"turn_end","displayNameKo":"돌격 [사건]","when":{"fact":"vars.keyword_choice","operator":"equals","value":"charge_case"}}],"oncePerTurn":true,"activationLabelKo":"브렛 또는 돌격 [사건] 부여"},{"effectId":"card-0798-activated-remove-level8-hand-two","cardIds":["0798"],"cardNameKo":"혼도 히데미","cardNameJa":"本堂瑛海","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":8}]},"prompt":"리무브할 상대 레벨 8 이하 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"oncePerTurn":true,"allowRestedSource":true,"activationLabelKo":"손패 2장 이하일 때 레벨 8 이하 리무브"},{"effectId":"card-0798-activated-revive-red-from-remove-file8","cardIds":["0798"],"cardNameKo":"혼도 히데미","cardNameJa":"本堂瑛海","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.partner.color","operator":"equals","value":"red"},{"fact":"player.file.count","operator":"greater_than_or_equal","value":8},{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","prompt":"비용으로 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area"},{"op":"move_top_file_cards","count":1,"to":"remove_area"},{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"deployment","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"리무브 에이리어에서 레벨 7 이하 적 캐릭터를 최대 1장 선택해 등장시키세요."},{"op":"move_cards","from":"deployment","to":"field","when":{"fact":"vars.deployment.count","operator":"greater_than","value":0},"entryMethod":"character_ability"},{"op":"rest_cards","target":"vars.deployment","when":{"fact":"vars.deployment.count","operator":"greater_than","value":0}},{"op":"ready_source_character","when":{"allOf":[{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}},{"op":"ready_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}}],"oncePerTurn":true,"activationLabelKo":"파일 1장과 손패 1장을 리무브해 적 캐릭터 재등장"},{"effectId":"card-0797-on-enter-revive-red-level5","cardIds":["0797"],"cardNameKo":"하네다 슈키치","cardNameJa":"羽田秀𠮷","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"red"}],"steps":[{"op":"filter_cards","from":"remove_area","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":5}]},"saveAs":"available_deployments"},{"op":"offer_reaction","reactionId":"card-0797-revive-red-level5","actor":"controller","choices":["yes","no"],"saveAs":"revive_choice","when":{"allOf":[{"fact":"vars.available_deployments.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}]},"prompt":"하네다 슈키치를 슬립시키고 손패 1장을 리무브해 적 레벨 5 이하 캐릭터를 재등장시킬까요?"},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"},"prompt":"비용으로 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"deployment","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":5}]},"prompt":"리무브 에이리어에서 레벨 5 이하 적 캐릭터를 최대 1장 선택해 등장시키세요."},{"op":"move_cards","from":"deployment","to":"field","entryMethod":"character_ability","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]}},{"op":"rest_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]}},{"op":"ready_source_character","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}},{"op":"ready_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}}],"activationLabelKo":"손패 1장 리무브 후 적 캐릭터 재등장"},{"effectId":"card-0797-hirameki-draw","cardIds":["0797"],"cardNameKo":"하네다 슈키치","cardNameJa":"羽田秀𠮷","trigger":{"event":"evidence.card_removed","timing":"after"},"conditions":[],"steps":[{"op":"draw_cards","count":1,"destination":"hand"}]},{"effectId":"card-0885-end-turn-draw-until-two","cardIds":["0885"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"player.turn_ended","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true}],"steps":[{"op":"calculate_hand_difference","mode":"deficit","targetCount":2,"saveAs":"draw_count"},{"op":"draw_cards","countFrom":"vars.draw_count","destination":"hand"}],"scope":"field_watch"},{"effectId":"card-0885-activated-discard-until-two-remove-character","cardIds":["0885"],"cardNameKo":"오키야 스바루","cardNameJa":"沖矢昴","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.partner.color","operator":"equals","value":"red"}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"calculate_hand_difference","mode":"excess","targetCount":2,"saveAs":"discard_count"},{"op":"select_cards","from":"hand","minFrom":"vars.discard_count","maxFrom":"vars.discard_count","min":0,"max":0,"optional":true,"saveAs":"hand_cost","prompt":"손패가 2장이 될 때까지 리무브할 카드를 선택하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.hand_cost.count","operator":"greater_than","value":0}},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"field":"card_type","operator":"equals","value":"character"},"prompt":"리무브할 상대 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"손패를 2장으로 맞추고 캐릭터 리무브"},{"effectId":"card-0134-continuous-red-partner-swift","cardIds":["0134"],"cardNameKo":"아카이 슈이치","cardNameJa":"赤井秀一","trigger":{"event":"continuous.recalculate","timing":"continuous"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"red"}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"swift","duration":"while_condition_true","modifierId":"red-handless-partner-swift","displayNameKo":"신속"}],"continuous":true},{"effectId":"card-0696-on-enter-solution-return-level5","cardIds":["0696"],"cardNameKo":"제임스 블랙","cardNameJa":"ジェイムズ・ブラック","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.case_phase","operator":"equals","value":"solution"}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":5}]},"prompt":"상대 현장에서 레벨 5 이하 캐릭터를 최대 1장 선택해 상대 손패로 돌리세요."},{"op":"move_cards","from":"target","to":"hand","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"해결편 등장 시 레벨 5 이하 상대 캐릭터 패로 이동"},{"effectId":"card-0696-activated-opponent-discards-hand","cardIds":["0696"],"cardNameKo":"제임스 블랙","cardNameJa":"ジェイムズ・ブラック","trigger":{"event":"character.activated_ability","timing":"after"},"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"opponent.hand.count","operator":"greater_than_or_equal","value":4}],"steps":[{"op":"pay_cost","cost":"sleep_source_character"},{"op":"select_cards","from":"opponent_hand","chooser":"opponent","min":1,"max":1,"optional":false,"saveAs":"opponent_hand_cost","prompt":"상대가 자신의 손패 1장을 선택해 리무브합니다."},{"op":"move_cards","from":"opponent_hand_cost","to":"remove_area"}],"activationLabelKo":"상대 손패 4장 이상일 때 손패 1장 리무브"},{"effectId":"card-0696-hirameki-draw","cardIds":["0696"],"cardNameKo":"제임스 블랙","cardNameJa":"ジェイムズ・ブラック","trigger":{"event":"evidence.card_removed","timing":"after"},"conditions":[],"steps":[{"op":"draw_cards","count":1,"destination":"hand"}]},{"effectId":"card-0224-on-enter-give-evidence-grant-charge-case","cardIds":["0224"],"cardNameKo":"세라 마스미","cardNameJa":"世良真純","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"offer_reaction","reactionId":"card-0224-offer-opponent-evidence-and-charge-case","actor":"controller","choices":["yes","no"],"saveAs":"give_evidence","prompt":"상대에게 증거 1개를 주고, 다른 적 캐릭터 1장까지 돌격 [사건]을 부여할까요?"},{"op":"gain_evidence","count":1,"targetOwner":"opponent","when":{"fact":"vars.give_evidence","operator":"equals","value":"yes"}},{"op":"select_cards","from":"field","targetController":"self","excludeSource":true,"min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"}]},"prompt":"이 캐릭터 이외의 자신의 적 캐릭터를 최대 1장 선택해 돌격 [사건]을 부여하세요.","when":{"fact":"vars.give_evidence","operator":"equals","value":"yes"}},{"op":"grant_keyword","target":"vars.target","keyword":"charge_case","duration":"turn_end","displayNameKo":"돌격 [사건]","when":{"allOf":[{"fact":"vars.give_evidence","operator":"equals","value":"yes"},{"fact":"vars.target.count","operator":"greater_than","value":0}]}}]},{"effectId":"card-0224-hirameki-draw","cardIds":["0224"],"cardNameKo":"세라 마스미","cardNameJa":"世良真純","trigger":{"event":"evidence.card_removed","timing":"after"},"conditions":[],"steps":[{"op":"draw_cards","count":1,"destination":"hand"}]},{"effectId":"card-0799-on-enter-hand-two-red-level7-charge","cardIds":["0799"],"cardNameKo":"아라이데 토모아키","cardNameJa":"新出智明","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}],"steps":[{"op":"select_cards","from":"field","targetController":"self","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"greater_than_or_equal","value":7}]},"prompt":"자신의 레벨 7 이상 적 캐릭터를 최대 1장 선택해 AP+1000과 돌격을 부여하세요."},{"op":"modify_stat","target":"vars.target","stat":"ap","amount":1000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.target.count","operator":"greater_than","value":0}},{"op":"grant_keyword","target":"vars.target","keyword":"charge","duration":"turn_end","displayNameKo":"돌격","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"activationLabelKo":"손패 2장 이하일 때 레벨 7 이상 적 캐릭터 강화"},{"effectId":"card-0143-continuous-red-partner-charge","cardIds":["0143"],"cardNameKo":"안드레 캐멀","cardNameJa":"アンドレ・キャメル","trigger":{"event":"continuous.recalculate","timing":"continuous"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"red"}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","duration":"while_condition_true","modifierId":"red-handless-partner-charge","displayNameKo":"돌격"}],"continuous":true},{"effectId":"card-0802-on-enter-mislead-and-search-red","cardIds":["0802"],"cardNameKo":"제임스 블랙","cardNameJa":"ジェイムズ・ブラック","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"set_mislead_value","target":"source_character","value":1,"duration":"while_in_field"},{"op":"offer_reaction","reactionId":"card-0802-discard-search-red","actor":"controller","choices":["yes","no"],"saveAs":"search_choice","when":{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1},"prompt":"손패 1장을 리무브하고 덱 위 4장에서 적 카드를 찾아볼까요?"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"vars.search_choice","operator":"equals","value":"yes"},"prompt":"비용으로 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.search_choice","operator":"equals","value":"yes"}},{"op":"peek_top_cards","count":4,"allowFewer":true,"saveAs":"seen","when":{"fact":"vars.search_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"saveAs":"selected_red","filter":{"field":"color","operator":"equals","value":"red"},"prompt":"공개해 손패에 추가할 적 카드를 최대 1장 선택하세요.","when":{"fact":"vars.search_choice","operator":"equals","value":"yes"}},{"op":"reveal_cards","from":"selected_red","to":["opponent"],"awaitAcknowledgement":true,"when":{"allOf":[{"fact":"vars.search_choice","operator":"equals","value":"yes"},{"fact":"vars.selected_red.count","operator":"greater_than","value":0}]}},{"op":"move_cards","from":"selected_red","to":"hand","when":{"allOf":[{"fact":"vars.search_choice","operator":"equals","value":"yes"},{"fact":"vars.selected_red.count","operator":"greater_than","value":0}]}},{"op":"move_unselected_to_deck_bottom","from":"seen","selectedVariable":"selected_red","order":"player_choice","when":{"fact":"vars.search_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"second_hand_cost","prompt":"적 카드를 손패에 추가했다면 손패 1장을 추가로 리무브하세요.","when":{"allOf":[{"fact":"vars.search_choice","operator":"equals","value":"yes"},{"fact":"vars.selected_red.count","operator":"greater_than","value":0}]}},{"op":"move_cards","from":"second_hand_cost","to":"remove_area","when":{"allOf":[{"fact":"vars.search_choice","operator":"equals","value":"yes"},{"fact":"vars.selected_red.count","operator":"greater_than","value":0}]}}]},{"effectId":"card-1120-case-solution-discard-hand","cardIds":["1120"],"cardNameKo":"골동품 쟁반은 숨길 수 없다","cardNameJa":"骨董盆は隠せない","trigger":{"event":"case.solution_entered","timing":"after"},"conditions":[{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1},"prompt":"사건이 해결편이 되었으므로 손패 1장을 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area"}]},{"effectId":"card-1120-antique-tray-case-effect","cardIds":["1120"],"cardNameKo":"골동품 쟁반은 숨길 수 없다","cardNameJa":"骨董盆は隠せない","trigger":{"event":"case.activated_ability","timing":"after"},"conditions":[{"fact":"player.case_phase","operator":"equals","value":"solution"}],"steps":[{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","prompt":"비용으로 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area"},{"op":"peek_top_cards","count":2,"allowFewer":true,"saveAs":"top_two"},{"op":"move_cards","from":"top_two","to":"remove_area"},{"op":"offer_reaction","reactionId":"card-1120-antique-tray-mode","actor":"controller","choices":["ap","draw"],"saveAs":"mode","when":{"fact":"player.hand.count","operator":"less_than_or_equal","value":2},"prompt":"사건 효과: 캐릭터 AP+2000 또는 손패 2장 이하일 때 1장 드로우 중 하나를 선택하세요."},{"op":"offer_reaction","reactionId":"card-1120-antique-tray-mode","actor":"controller","choices":["ap"],"saveAs":"mode","when":{"fact":"player.hand.count","operator":"greater_than","value":2},"prompt":"사건 효과: 캐릭터 AP+2000을 선택하세요."},{"op":"select_cards","from":"both_fields","targetController":"any","min":0,"max":1,"optional":true,"saveAs":"ap_target","filter":{"field":"card_type","operator":"equals","value":"character"},"when":{"fact":"vars.mode","operator":"equals","value":"ap"},"prompt":"턴 종료 시까지 AP를 +2000할 캐릭터를 최대 1장 선택하세요."},{"op":"modify_stat","target":"vars.ap_target","stat":"ap","amount":2000,"duration":"turn_end","stacking":"additive","when":{"allOf":[{"fact":"vars.mode","operator":"equals","value":"ap"},{"fact":"vars.ap_target.count","operator":"greater_than","value":0}]}},{"op":"draw_cards","count":1,"destination":"hand","when":{"fact":"vars.mode","operator":"equals","value":"draw"}}],"oncePerTurn":true,"activationLabelKo":"손패와 덱 위 카드 2장 리무브 후 모드 선택"}]$handless_defs$::jsonb)
    WITH ORDINALITY AS n(value,ordinality)
)
UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT coalesce(jsonb_agg(
    CASE WHEN e.value->>'effectId'='card-0796-activated-remove-level7'
      THEN e.value || jsonb_build_object('allowRestedSource',true,'allowStunnedSource',true)
      ELSE e.value END ORDER BY e.ordinality
  ),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY AS e(value,ordinality)
) || (
  SELECT coalesce(jsonb_agg(n.value ORDER BY n.ordinality),'[]'::jsonb)
  FROM new_defs n
  WHERE NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) old(value)
    WHERE old.value->>'effectId'=n.value->>'effectId'
  )
),
updated_at=now()
WHERE c.catalog_id='main';
COMMIT;
