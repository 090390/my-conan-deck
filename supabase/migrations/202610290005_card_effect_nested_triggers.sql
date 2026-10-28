CREATE OR REPLACE FUNCTION public.private_card_effect_move_card_v1(
 p_room_id uuid,p_owner_user uuid,p_from_zone text,p_card jsonb,p_to_zone text,p_target_user uuid DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_source_user uuid:=p_owner_user; v_target_user uuid:=coalesce(p_target_user,p_owner_user);
 v_id text:=p_card->>'instance_id'; v_card jsonb:=p_card;
 v_game public.room_player_game_states%rowtype; v_board public.room_player_turn_boards%rowtype;
 v_old_partner jsonb; v_rarity text;
BEGIN
 IF v_id IS NULL OR v_id='' THEN RAISE EXCEPTION '카드 효과 이동에 instance_id가 없습니다.'; END IF;
 IF p_from_zone NOT IN ('peek','variable','') THEN
   IF p_from_zone='field' THEN
     SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF NOT FOUND THEN RAISE EXCEPTION '카드 이동 원본 현장을 찾을 수 없습니다.'; END IF;
     UPDATE public.room_player_turn_boards SET field_cards=public.private_card_effect_remove_from_array_v1(field_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='hand' THEN
     UPDATE public.room_player_game_states SET hand=public.private_card_effect_remove_from_array_v1(hand,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='remove_area' THEN
     UPDATE public.room_player_game_states SET remove_cards=public.private_card_effect_remove_from_array_v1(remove_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
     UPDATE public.room_player_turn_boards SET remove_count=greatest(0,remove_count-1),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='deck' THEN
     UPDATE public.room_player_game_states SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='evidence_area' THEN
     UPDATE public.room_player_game_states SET evidence_cards=public.private_card_effect_remove_from_array_v1(evidence_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
     UPDATE public.room_player_turn_boards SET evidence_count=greatest(0,evidence_count-1),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   END IF;
 END IF;

 v_card:=v_card-'zone'-'owner_user_id'-'resolving'-'dsl_remove_trigger_queued';
 IF p_from_zone='field' AND p_to_zone='remove_area' THEN v_card:=v_card||jsonb_build_object('dsl_remove_trigger_queued',true); END IF;
 IF p_to_zone='hand' THEN
   UPDATE public.room_player_game_states SET hand=coalesce(hand,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSIF p_to_zone='remove_area' THEN
   v_rarity:=upper(coalesce(v_card->>'rarity',v_card->>'rarity_code',v_card#>>'{sourceData,rarity}',v_card#>>'{raw,rarity}',''));
   IF p_from_zone='field' AND v_rarity IN ('MR','MRP') THEN
     SELECT partner_mr_card INTO v_old_partner FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF v_old_partner IS NOT NULL AND v_old_partner->>'instance_id' IS DISTINCT FROM v_id THEN
       UPDATE public.room_player_game_states SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_old_partner-'rested'-'status'-'ap_bonus'-'summoned_this_turn'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
       UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now() WHERE room_id=p_room_id AND user_id=v_source_user;
     END IF;
     UPDATE public.room_player_turn_boards SET partner_mr_card=v_card||jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',false),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSE
     UPDATE public.room_player_game_states SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
     UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
   END IF;
 ELSIF p_to_zone='deck_bottom' THEN
   UPDATE public.room_player_game_states SET deck_order=coalesce(deck_order,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSIF p_to_zone='field' THEN
   UPDATE public.room_player_turn_boards SET field_cards=coalesce(field_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('rested',false,'status','active','summoned_this_turn',true,'ap_bonus',0,'entry_method',coalesce(v_card->>'entry_method','event_effect'))),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSE
   RAISE EXCEPTION '카드 효과 이동 목적지 %는 아직 지원하지 않습니다.',p_to_zone;
 END IF;
END
$function$;


CREATE OR REPLACE FUNCTION public.private_card_effect_run_v1(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
 v_run public.private_card_effect_runs_v1%rowtype;
 v_def jsonb; v_step jsonb; v_op text; v_from text; v_to text; v_save text; v_path text[];
 v_vars jsonb; v_data jsonb; v_options jsonb; v_selected jsonb; v_remaining jsonb; v_ordered jsonb;
 v_item jsonb; v_card jsonb; v_wrapper jsonb; v_current jsonb; v_patch jsonb; v_pending jsonb; v_waiting jsonb;
 v_game public.room_player_game_states%rowtype; v_board public.room_player_turn_boards%rowtype;
 v_match public.room_match_states%rowtype; v_owner uuid; v_source_user uuid; v_target_owner uuid;
 v_i integer; v_j integer; v_n integer; v_examined integer; v_matched boolean; v_found boolean;
 v_ids text[]; v_selected_ids text[]; v_effect_id text; v_turn integer; v_amount integer; v_new_ap numeric;
 v_keyword text; v_deck jsonb; v_seen jsonb; v_match_filter jsonb; v_name text;
 v_queue_item jsonb; v_effect_context jsonb; v_effect_source_card jsonb; v_effect_source_instance_id text;
 v_child_context jsonb; v_child_queue jsonb; v_child_def jsonb; v_catalog jsonb; v_entry_method text;
 v_first_entry boolean; v_from_zone text;
BEGIN
 SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF v_run.waiting IS NOT NULL THEN RETURN; END IF;

 LOOP
   SELECT * INTO v_run FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND THEN RETURN; END IF;

   IF v_run.effect_index >= jsonb_array_length(coalesce(v_run.effect_queue,'[]'::jsonb)) THEN
     DELETE FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=CASE WHEN pending_action->>'type' LIKE 'card_effect_%' THEN NULL ELSE pending_action END,
           state_version=state_version+1,
           last_action_label='카드 효과 처리가 완료되었습니다.'
       WHERE room_id=p_room_id;
     RETURN;
   END IF;

   v_queue_item:=v_run.effect_queue->v_run.effect_index;
   v_def:=coalesce(v_queue_item->'__definition',v_queue_item);
   v_effect_source_instance_id:=coalesce(nullif(v_queue_item->>'__source_instance_id',''),v_run.source_instance_id);
   v_effect_context:=coalesce(nullif(v_queue_item->'__context','null'::jsonb),v_run.context,'{}'::jsonb);
   v_effect_source_card:=coalesce(nullif(v_queue_item->'__source_card','null'::jsonb),nullif(v_effect_context->'source_card','null'::jsonb),'{}'::jsonb);
   v_owner:=coalesce(nullif(v_queue_item->>'__actor_user_id','')::uuid,v_run.actor_user_id);
   v_source_user:=coalesce(nullif(v_queue_item->>'__source_user_id','')::uuid,v_run.source_user_id);
   IF v_run.step_index >= jsonb_array_length(coalesce(v_def->'steps','[]'::jsonb)) THEN
     UPDATE public.private_card_effect_runs_v1
       SET effect_index=effect_index+1, step_index=0, variables='{}'::jsonb, waiting=NULL, updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;
   END IF;

   v_step:=v_def->'steps'->v_run.step_index;
   v_op:=v_step->>'op';
   v_vars:=coalesce(v_run.variables,'{}'::jsonb);
   v_effect_id:=v_def->>'effectId';
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;

   IF v_step ? 'when' AND NOT public.private_card_effect_condition_matches_v1(
     p_room_id,v_owner,v_source_user,coalesce(v_effect_context->'source_card','{}'::jsonb),
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
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_owner,
       'prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'),
       'min',coalesce((v_step->>'min')::integer,0),'max',coalesce((v_step->>'max')::integer,1),
       'optional',coalesce((v_step->>'optional')::boolean,false));
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 플레이어의 카드 선택을 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

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
     v_target_owner:=v_owner;
     IF coalesce(v_step->'to','[]'::jsonb) @> '["opponent"]'::jsonb THEN
       SELECT user_id INTO v_target_owner FROM public.room_players WHERE room_id=p_room_id AND user_id<>v_owner LIMIT 1;
     END IF;
     v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_target_owner);
     v_pending:=jsonb_build_object('type','card_effect_reveal_ack','effect_id',v_effect_id,'source_instance_id',v_effect_source_instance_id,
       'chooser_user_id',v_target_owner,'source_user_id',v_owner,'prompt',CASE WHEN v_target_owner<>v_owner THEN '공개된 카드를 확인한 뒤 확인 완료를 눌러 주세요.' ELSE '카드 공개를 확인하고 효과를 계속 진행하세요.' END,
       'revealed_cards',v_selected);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 카드 공개 확인을 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='move_cards' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'from',''), 'vars.',''),'.');
     v_data:=v_vars #> v_path;
     SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_from_zone:=coalesce(v_item->>'zone','variable');
       v_to:=coalesce(v_step->>'to','');

       IF v_to='field' THEN
         v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
         v_entry_method:=coalesce(nullif(v_step->>'entryMethod',''),
           CASE WHEN lower(coalesce(v_current->>'card_type',v_current->>'type','')) IN ('event','イベント','이벤트')
             THEN 'event_effect' ELSE 'character_ability' END);
         v_card:=v_card||jsonb_build_object('entry_method',v_entry_method);
       END IF;

       PERFORM public.private_card_effect_move_card_v1(p_room_id,v_target_owner,v_from_zone,v_card,v_to,v_target_owner);

       IF v_to='remove_area' AND v_from_zone='field' THEN
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'removed_on_turn_user_id',v_match.current_turn_user_id);
         v_child_queue:='[]'::jsonb;
         FOR v_child_def IN
           SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog->'definitions','[]'::jsonb)) d(value)
           WHERE d.value->'trigger'->>'event'='character.removed_from_field'
             AND NOT coalesce((d.value->>'continuous')::boolean,false)
             AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
             AND public.private_card_effect_conditions_match_v1(p_room_id,v_target_owner,v_target_owner,v_card,
               v_child_context,'{}'::jsonb,coalesce(d.value->'conditions','[]'::jsonb))
         LOOP
           v_child_queue:=v_child_queue||jsonb_build_array(jsonb_build_object(
             '__definition',v_child_def,'__actor_user_id',v_target_owner,'__source_user_id',v_target_owner,
             '__source_instance_id',v_card->>'instance_id','__source_card',v_card,'__context',v_child_context
           ));
         END LOOP;
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1 SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;

       ELSIF v_to='field' AND public.private_card_effect_is_character_v1(v_card) THEN
         SELECT (first_character_entered_this_turn IS NULL) INTO v_first_entry
         FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
         IF coalesce(v_first_entry,false) THEN
           UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=v_card->>'instance_id',updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_target_owner AND first_character_entered_this_turn IS NULL;
           GET DIAGNOSTICS v_i = ROW_COUNT;
           v_first_entry := v_i=1;
         END IF;
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'entry',jsonb_build_object('method',v_entry_method,'is_first_character_this_turn',coalesce(v_first_entry,false),
             'source',v_effect_source_card));
         v_child_queue:='[]'::jsonb;
         FOR v_child_def IN
           SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog->'definitions','[]'::jsonb)) d(value)
           WHERE d.value->'trigger'->>'event'='character.entered_field'
             AND NOT coalesce((d.value->>'continuous')::boolean,false)
             AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
             AND public.private_card_effect_conditions_match_v1(p_room_id,v_target_owner,v_target_owner,v_card,
               v_child_context,'{}'::jsonb,coalesce(d.value->'conditions','[]'::jsonb))
         LOOP
           v_child_queue:=v_child_queue||jsonb_build_array(jsonb_build_object(
             '__definition',v_child_def,'__actor_user_id',v_target_owner,'__source_user_id',v_target_owner,
             '__source_instance_id',v_card->>'instance_id','__source_card',v_card,'__context',v_child_context
           ));
         END LOOP;
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1 SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;
       END IF;
     END LOOP;

   ELSIF v_op IN ('move_unselected_to_deck_bottom','move_unselected_to_zone') THEN
     v_from:=v_step->>'from';
     v_path:=string_to_array(replace(coalesce(v_from,''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     v_path:=string_to_array(replace(coalesce(v_step->>'selectedVariable',''),'vars.',''),'.');
     v_selected:=v_vars #> v_path;
     v_selected_ids:='{}'::text[];
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_selected,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item);
       v_selected_ids:=array_append(v_selected_ids,coalesce(v_card->>'instance_id',v_item->>'instance_id',''));
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
         END IF;
         v_waiting:=jsonb_build_object('kind','order','options',v_remaining,'save_as','__ordered_unselected',
           'chooser_user_id',v_owner,'prompt','덱 아래로 보낼 카드의 순서를 정하세요. (위에서부터 차례대로 선택)');
         v_pending:=jsonb_build_object('type','card_effect_order','effect_id',v_effect_id,'chooser_user_id',v_owner,
           'prompt','덱 아래로 보낼 카드의 순서를 정하세요.','options_count',jsonb_array_length(v_remaining));
         UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
         UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
           last_action_label='카드 효과: 덱 아래 카드 순서를 기다립니다.' WHERE room_id=p_room_id;
         RETURN;
       END IF;
       v_remaining:=v_ordered;
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
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
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
     v_target_owner:=v_source_user; v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
     IF v_card IS NULL THEN RAISE EXCEPTION '키워드를 부여할 카드가 현장에 없습니다.'; END IF;
     v_keyword:=coalesce(v_step->>'keyword','');
     v_selected:=coalesce(v_card->'dsl_keywords','[]'::jsonb);
     IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_selected) x(value) WHERE x.value->>'effect_id'=v_effect_id AND x.value->>'keyword'=v_keyword) THEN
       v_selected:=v_selected||jsonb_build_array(jsonb_build_object('effect_id',v_effect_id,'keyword',v_keyword,
         'expires_turn_number',(SELECT turn_number FROM public.room_match_states WHERE room_id=p_room_id)));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,jsonb_build_object('dsl_keywords',v_selected));
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
       'choices',coalesce(v_step->'choices','[]'::jsonb),'source_instance_id',v_effect_source_instance_id);
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 반응 여부를 기다립니다.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='pay_cost' THEN
     IF v_step->>'cost'='sleep_source_character' THEN
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
END
$function$;

CREATE OR REPLACE FUNCTION public.perform_private_turn_action_v2(p_room_id uuid,p_action text,p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_match public.room_match_states%rowtype; v_before_match public.room_match_states%rowtype;
 v_before_boards jsonb; v_before_board jsonb; v_new_board public.room_player_turn_boards%rowtype;
 v_before_pending jsonb; v_result jsonb; v_source_card jsonb; v_old_card jsonb; v_new_card jsonb;
 v_owner uuid; v_instance_id text; v_first_entry boolean; v_turn integer; v_old_field jsonb;
 v_old_board jsonb; v_old_entry jsonb; v_current_field jsonb; v_current_remove jsonb; v_removed boolean;
 v_before_base_character_played boolean:=false; v_first_entry_already boolean:=false;
 v_pending_actor uuid; v_context jsonb; v_event_source_user uuid;
 v_old_action text:=p_action;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;

 IF p_action='card_effect_continue' THEN
   PERFORM public.private_card_effect_continue_v1(p_room_id,coalesce(p_payload,'{}'::jsonb));
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='activate_card_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 효과를 발동할 수 있습니다.'; END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION '자신의 턴에만 이 능력을 발동할 수 있습니다.'; END IF;
   IF v_match.turn_step IS DISTINCT FROM 'main' THEN RAISE EXCEPTION '파일 배치가 끝난 뒤 메인 단계에서 능력을 발동할 수 있습니다.'; END IF;
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1 FOR UPDATE;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 캐릭터를 찾을 수 없습니다.'; END IF;
   PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
     'character.activated_ability',jsonb_build_object('turn_number',v_match.turn_number),
     p_payload->>'effect_id',true);
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 SELECT * INTO v_before_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_before_match.phase<>'playing' OR v_before_match.game_over THEN
   RAISE EXCEPTION '진행 중인 게임이 아닙니다.';
 END IF;
 v_before_pending:=v_before_match.pending_action;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',b.user_id,'field_cards',coalesce(b.field_cards,'[]'::jsonb),'partner_mr_card',b.partner_mr_card)
   ORDER BY b.seat),'[]'::jsonb) INTO v_before_boards
 FROM public.room_player_turn_boards b WHERE b.room_id=p_room_id;
 v_turn:=v_before_match.turn_number;
 SELECT coalesce(base_character_played_this_turn,false), first_character_entered_this_turn IS NOT NULL
   INTO v_before_base_character_played, v_first_entry_already
   FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;

 v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));

 IF p_action='begin_turn' THEN
   UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=NULL, updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
 END IF;

 IF p_action='play_character' THEN
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
       'method','manual','is_first_character_this_turn',v_first_entry,'source',v_source_card),
       'turn_number',v_turn);
     PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
       'character.entered_field',v_context,NULL,false);
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
     FOR v_new_card IN SELECT value FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) UNION ALL
       SELECT v_old_card WHERE v_old_card IS NOT NULL LOOP
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_new_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn),NULL,false);
       IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
     END LOOP;
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

 PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
 RETURN public.get_private_turn_state_v2(p_room_id);
END
$function$;



DO $patch_ai$
DECLARE v_definition text;
BEGIN
  IF to_regprocedure('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)') IS NULL THEN RETURN; END IF;
  v_definition := pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure);
  IF position('card_effect_continue' in v_definition)=0 THEN
    IF position('shuffle_deck' in v_definition)=0 THEN
      RAISE EXCEPTION 'AI action allow-list tail not found; refusing partial card effect integration';
    END IF;
    v_definition := replace(v_definition, '''shuffle_deck''', '''shuffle_deck'',''card_effect_continue''');
    IF position('chooser_user_id' in v_definition)=0 THEN
      v_definition := replace(v_definition,
        'and coalesce(v_match.pending_action ->> ''initiator_user_id'', '''') <> v_battle.ai_user_id::text then',
        'and coalesce(v_match.pending_action ->> ''initiator_user_id'', '''') <> v_battle.ai_user_id::text and coalesce(v_match.pending_action ->> ''chooser_user_id'', '''') <> v_battle.ai_user_id::text then');
    END IF;
  END IF;
  EXECUTE v_definition;
END
$patch_ai$;

