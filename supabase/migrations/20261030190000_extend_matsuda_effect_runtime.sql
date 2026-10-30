
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  -- Allow card effect filters to select the opponent's evidence area.
  SELECT pg_get_functiondef('public.private_card_effect_get_candidates_v1(uuid,uuid,uuid,text,jsonb,text,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$
 IF p_from IN ('deck','hand','remove_area','evidence_area') THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_data:=CASE p_from WHEN 'deck' THEN coalesce(v_game.deck_order,'[]'::jsonb) WHEN 'hand' THEN coalesce(v_game.hand,'[]'::jsonb)
     WHEN 'remove_area' THEN coalesce(v_game.remove_cards,'[]'::jsonb) ELSE coalesce(v_game.evidence_cards,'[]'::jsonb) END;
   v_owner:=p_actor; v_zone:=p_from;
$old$;
  v_replacement := $new$
IF p_from='opponent_evidence' THEN
   SELECT * INTO v_game FROM public.room_player_game_states
   WHERE room_id=p_room_id AND user_id<>p_actor ORDER BY seat LIMIT 1;
   v_data:=coalesce(v_game.evidence_cards,'[]'::jsonb);
   v_owner:=v_game.user_id; v_zone:='evidence_area';
 ELSIF p_from IN ('deck','hand','remove_area','evidence_area') THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_data:=CASE p_from WHEN 'deck' THEN coalesce(v_game.deck_order,'[]'::jsonb) WHEN 'hand' THEN coalesce(v_game.hand,'[]'::jsonb)
     WHEN 'remove_area' THEN coalesce(v_game.remove_cards,'[]'::jsonb) ELSE coalesce(v_game.evidence_cards,'[]'::jsonb) END;
   v_owner:=p_actor; v_zone:=p_from;
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'candidate-zone insertion anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  -- Resolve derived facts used by the Matsuda MR effect and investigate effect.
  SELECT pg_get_functiondef('public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$   RETURN coalesce(p_vars #> v_path,'null'::jsonb);$old$;
  v_replacement := $new$
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
     RETURN to_jsonb(EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))<=7
     ));
   END IF;
   RETURN coalesce(p_vars #> v_path,'null'::jsonb);$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'vars-fact insertion anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  -- Add custom operations for a private opponent-hand reveal and an opponent-deck investigate.
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$ v_from_zone text;$old$;
  v_replacement := $new$ v_from_zone text;
 v_hand_owner uuid; v_hand_cards jsonb;
 v_investigate_owner uuid; v_investigate_deck jsonb; v_investigate_cards jsonb;
 v_investigate_remaining jsonb; v_investigate_count integer; v_investigate_low boolean;
 v_drawn_card jsonb;$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'effect runner declaration anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);

  v_anchor := $old$   ELSIF v_op='peek_top_cards' THEN$old$;
  v_replacement := $new$
   ELSIF v_op='reveal_opponent_hand' THEN
     SELECT user_id INTO v_hand_owner FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     IF v_hand_owner IS NULL THEN RAISE EXCEPTION '손패를 공개할 상대 플레이어를 찾을 수 없습니다.'; END IF;
     SELECT coalesce(hand,'[]'::jsonb) INTO v_hand_cards
       FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_hand_owner FOR UPDATE;
     v_waiting:=jsonb_build_object('kind','ack','advance_step',true,'chooser_user_id',v_owner);
     v_pending:=jsonb_build_object(
       'type','card_effect_reveal_ack','effect_id',v_effect_id,
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_owner,
       'source_user_id',v_hand_owner,
       'prompt','상대의 공개된 손패를 확인한 뒤 효과를 계속 진행하세요.',
       'revealed_cards',v_hand_cards
     );
     UPDATE public.private_card_effect_runs_v1 SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states SET pending_action=v_pending,state_version=state_version+1,
       last_action_label='카드 효과: 상대 손패 공개를 확인해 주세요.' WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='investigate_opponent_deck' THEN
     SELECT user_id,coalesce(deck_order,'[]'::jsonb)
       INTO v_investigate_owner,v_investigate_deck
       FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id<>v_owner
       ORDER BY seat LIMIT 1 FOR UPDATE;
     IF v_investigate_owner IS NULL THEN RAISE EXCEPTION '조사할 상대 덱을 찾을 수 없습니다.'; END IF;
     v_investigate_count:=least(greatest(0,coalesce((v_step->>'count')::integer,1)),
       jsonb_array_length(coalesce(v_investigate_deck,'[]'::jsonb)));
     SELECT coalesce(jsonb_agg(jsonb_build_object(
       'instance_id',e.value->>'instance_id','owner_user_id',v_investigate_owner,
       'zone','peek','card',e.value
     ) ORDER BY e.ordinality) FILTER(WHERE e.ordinality<=v_investigate_count),'[]'::jsonb)
       INTO v_investigate_cards
       FROM jsonb_array_elements(coalesce(v_investigate_deck,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.ordinality>v_investigate_count),'[]'::jsonb)
       INTO v_investigate_remaining
       FROM jsonb_array_elements(coalesce(v_investigate_deck,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality);
     UPDATE public.room_player_game_states SET deck_order=coalesce(v_investigate_remaining,'[]'::jsonb),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_investigate_owner;
     SELECT EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_investigate_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))<=7
     ) INTO v_investigate_low;
     v_vars:=jsonb_set(v_vars,ARRAY[v_step->>'saveAs'],jsonb_build_object(
       'revealed',coalesce(v_investigate_cards,'[]'::jsonb),
       'selected','[]'::jsonb,
       'has_level_at_most_7',coalesce(v_investigate_low,false)
     ),true);
     UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,step_index=step_index+1,updated_at=now()
       WHERE room_id=p_room_id;
     CONTINUE;

   ELSIF v_op='peek_top_cards' THEN$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'effect runner custom-op insertion anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);

  -- Let gain_evidence target the opponent and optionally expose the acquired evidence.
  v_anchor := $old$
   ELSIF v_op='gain_evidence' THEN
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_owner,'evidence');
     END LOOP;
$old$;
  v_replacement := $new$
   ELSIF v_op='gain_evidence' THEN
     v_target_owner:=v_owner;
     IF v_step->>'targetOwner'='opponent' THEN
       SELECT user_id INTO v_target_owner FROM public.room_players
         WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     END IF;
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       v_drawn_card:=public.draw_private_turn_card(p_room_id,v_target_owner,'evidence');
       IF coalesce((v_step->>'faceUp')::boolean,false) AND v_drawn_card IS NOT NULL THEN
         UPDATE public.room_player_game_states gs
         SET evidence_cards=coalesce((
           SELECT jsonb_agg(
             CASE WHEN e.value->>'instance_id'=v_drawn_card->>'instance_id'
               THEN e.value||jsonb_build_object('face_up',true) ELSE e.value END
             ORDER BY e.ordinality)
           FROM jsonb_array_elements(coalesce(gs.evidence_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
         ),'[]'::jsonb),updated_at=now()
         WHERE gs.room_id=p_room_id AND gs.user_id=v_target_owner;
       END IF;
     END LOOP;
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'gain_evidence patch anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);

  -- Ensure evidence-card removal triggers only run when the card actually enters the remove area.
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_after_evidence,'[]'::jsonb)) e(value)
         WHERE e.value->>'instance_id'=v_old_evidence_card->>'instance_id') THEN
$old$;
  v_replacement := $new$
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_after_evidence,'[]'::jsonb)) e(value)
         WHERE e.value->>'instance_id'=v_old_evidence_card->>'instance_id')
         AND EXISTS(
           SELECT 1 FROM public.room_player_game_states gs
           CROSS JOIN LATERAL jsonb_array_elements(coalesce(gs.remove_cards,'[]'::jsonb)) removed(value)
           WHERE gs.room_id=p_room_id AND gs.user_id=v_evidence_owner
             AND removed.value->>'instance_id'=v_old_evidence_card->>'instance_id'
         ) THEN
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'evidence-trigger filter anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  -- Fire evidence.card_removed triggers from effect-run moves into the remove area too.
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure) INTO v_definition;
  v_anchor := $old$
       IF v_to='remove_area' AND v_from_zone='field' THEN
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'removed_on_turn_user_id',v_match.current_turn_user_id);
$old$;
  v_replacement := $new$
       IF v_to='remove_area' AND v_from_zone='field' THEN
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'removed_on_turn_user_id',v_match.current_turn_user_id);
$new$;
  -- The insertion for evidence-zone removal is appended immediately after the existing field-removal child-queue block.
  v_anchor := $old$
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1 SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;

       ELSIF v_to='field' AND public.private_card_effect_is_character_v1(v_card) THEN
$old$;
  v_replacement := $new$
         IF jsonb_array_length(v_child_queue)>0 THEN
           UPDATE public.private_card_effect_runs_v1 SET effect_queue=coalesce(effect_queue,'[]'::jsonb)||v_child_queue,updated_at=now()
           WHERE room_id=p_room_id;
         END IF;

       ELSIF v_to='remove_area' AND v_from_zone='evidence_area' THEN
         v_child_context:=jsonb_build_object('source_card',v_card,'turn_number',v_match.turn_number,
           'evidence_removed_instance_id',v_card->>'instance_id');
         v_child_queue:='[]'::jsonb;
         FOR v_child_def IN
           SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
           WHERE d.value->'trigger'->>'event'='evidence.card_removed'
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
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'effect-runner evidence trigger anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  -- MR characters acquired as evidence transfer to the MR partner area.
  SELECT pg_get_functiondef('public.private_card_effect_move_card_v1(uuid,uuid,text,jsonb,text,uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$
 ELSIF p_to_zone='evidence_area' THEN
   UPDATE public.room_player_game_states SET evidence_cards=coalesce(evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('face_up',true)),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
   UPDATE public.room_player_turn_boards SET evidence_count=evidence_count+1,updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
$old$;
  v_replacement := $new$
 ELSIF p_to_zone='evidence_area' THEN
   v_rarity:=upper(coalesce(v_card->>'rarity',v_card->>'rarity_code',v_card#>>'{sourceData,rarity}',v_card#>>'{raw,rarity}',''));
   IF p_from_zone='field' AND v_rarity IN ('MR','MRP') THEN
     SELECT partner_mr_card INTO v_old_partner FROM public.room_player_turn_boards
       WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF v_old_partner IS NOT NULL AND v_old_partner->>'instance_id' IS DISTINCT FROM v_id THEN
       UPDATE public.room_player_game_states
         SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_old_partner-'rested'-'status'-'ap_bonus'-'summoned_this_turn'),
             updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
       UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
     END IF;
     UPDATE public.room_player_turn_boards
       SET partner_mr_card=v_card||jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',false),
           updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSE
     UPDATE public.room_player_game_states SET evidence_cards=coalesce(evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('face_up',true)),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
     UPDATE public.room_player_turn_boards SET evidence_count=evidence_count+1,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
   END IF;
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'MR evidence-move anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  -- Partner-area activated abilities are only exposed when explicitly declared for that area.
  SELECT pg_get_functiondef('public.get_private_card_effect_activations_v1(uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$
 END LOOP;
 -- Event-card abilities are synthetic sources rather than field cards.$old$;
  v_replacement := $new$
 END LOOP;
 IF v_board.partner_mr_card IS NOT NULL
    AND public.private_card_effect_is_active_v1(v_board.partner_mr_card) THEN
   v_card:=v_board.partner_mr_card;
   FOR v_def IN SELECT value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))
     WHERE value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((value->>'allowPartnerArea')::boolean,false)
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
 -- Event-card abilities are synthetic sources rather than field cards.$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'user partner activation insertion anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$ IF coalesce(v_is_own_turn,false)$old$;
  v_replacement := $new$
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
 IF coalesce(v_is_own_turn,false)$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'AI partner activation insertion anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;

  -- Make activate_card_effect source lookup accept a specifically authorized MR partner-area source.
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_anchor := $old$
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1 FOR UPDATE;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 캐릭터를 찾을 수 없습니다.'; END IF;
   SELECT d.value INTO v_effect_definition
$old$;
  v_replacement := $new$
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT * INTO v_new_board FROM public.room_player_turn_boards
     WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
   IF v_source_card IS NULL AND v_new_board.partner_mr_card->>'instance_id'=v_instance_id THEN
     v_source_card:=v_new_board.partner_mr_card;
   END IF;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 또는 MR 파트너 카드를 찾을 수 없습니다.'; END IF;
   SELECT d.value INTO v_effect_definition
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'user activation source lookup anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  v_anchor := $old$
   IF v_effect_definition IS NULL THEN RAISE EXCEPTION '이 캐릭터에 등록된 효과를 찾을 수 없습니다.'; END IF;
 
IF NOT public.private_card_effect_is_active_v1(v_source_card) THEN
$old$;
  v_replacement := $new$
   IF v_effect_definition IS NULL THEN RAISE EXCEPTION '이 캐릭터에 등록된 효과를 찾을 수 없습니다.'; END IF;
   IF v_new_board.partner_mr_card->>'instance_id'=v_instance_id
      AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 MR 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;
 
IF NOT public.private_card_effect_is_active_v1(v_source_card) THEN
$new$;
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'user activation partner guard anchor missing'; END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;
END
$migration$;
