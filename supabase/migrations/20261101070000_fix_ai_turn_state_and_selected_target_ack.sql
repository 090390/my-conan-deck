-- Expose the actual basic-card-play flag to the AI. base_action_done also includes partner actions.
CREATE OR REPLACE FUNCTION public.get_private_turn_state_v2(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_result jsonb;
  v_my_remove jsonb;
  v_opponent_remove jsonb;
  v_boards jsonb;
  v_my_peek jsonb;
  v_shared_peeks jsonb;
  v_shared_hand_reveal jsonb;
  v_my_deck_count integer := 0;
  v_my_file_cards jsonb := '[]'::jsonb;
  v_winner_name text;
  v_winner_turn integer;
begin
  if v_user is null then raise exception '로그인이 필요합니다.'; end if;
  if not exists (select 1 from public.room_players rp where rp.room_id = p_room_id and rp.user_id = v_user) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  v_result := public.get_private_turn_state(p_room_id);
  select coalesce(m.end_display_names ->> (v_result ->> 'winner_user_id'), (select coalesce(nullif(rp.temporary_nickname,''), '플레이어 ' || rp.seat::text) from public.room_players rp where rp.room_id=p_room_id and rp.user_id=(v_result ->> 'winner_user_id')::uuid)), coalesce(m.winner_turn_number, (v_result ->> 'turn_number')::integer)
    into v_winner_name, v_winner_turn from public.room_match_states m where m.room_id=p_room_id;

  select coalesce(gs.remove_cards, '[]'::jsonb) into v_my_remove
  from public.room_player_game_states gs where gs.room_id = p_room_id and gs.user_id = v_user;
  select coalesce(gs.file_cards, '[]'::jsonb) into v_my_file_cards
  from public.room_player_game_states gs where gs.room_id = p_room_id and gs.user_id = v_user;
  select coalesce(gs.remove_cards, '[]'::jsonb) into v_opponent_remove
  from public.room_player_game_states gs where gs.room_id = p_room_id and gs.user_id <> v_user order by gs.seat limit 1;

  select jsonb_build_object(
    'source_user_id', p.source_user_id,
    'source_display_name', coalesce(nullif(rp.temporary_nickname, ''), '플레이어 ' || rp.seat::text),
    'cards', p.cards,
    'shared_instance_ids', coalesce(p.shared_instance_ids, '[]'::jsonb),
    'shared_acknowledged', coalesce(p.shared_acknowledged, false)
  ) into v_my_peek
  from public.room_deck_peeks p
  join public.room_players rp on rp.room_id = p.room_id and rp.user_id = p.source_user_id
  where p.room_id = p_room_id and p.viewer_user_id = v_user and p.returned_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_user_id', p.source_user_id,
    'source_display_name', coalesce(nullif(rp.temporary_nickname, ''), '플레이어 ' || rp.seat::text),
    'card', card.value,
    'returned', (p.returned_at is not null)
  ) order by card.ordinality), '[]'::jsonb) into v_shared_peeks
  from public.room_deck_peeks p
  join public.room_players rp on rp.room_id = p.room_id and rp.user_id = p.source_user_id
  cross join lateral jsonb_array_elements(coalesce(p.cards, '[]'::jsonb)) with ordinality card(value, ordinality)
  where p.room_id = p_room_id and p.viewer_user_id <> v_user
    and not coalesce(p.shared_acknowledged, false)
    and coalesce(p.shared_instance_ids, '[]'::jsonb) @> jsonb_build_array(card.value ->> 'instance_id');

  select jsonb_build_object(
    'source_user_id', r.source_user_id,
    'source_display_name', coalesce(nullif(rp.temporary_nickname, ''), '플레이어 ' || rp.seat::text),
    'cards', r.cards
  ) into v_shared_hand_reveal
  from public.room_hand_reveals r
  join public.room_players rp on rp.room_id=r.room_id and rp.user_id=r.source_user_id
  where r.room_id=p_room_id and r.viewer_user_id=v_user;

  select jsonb_array_length(coalesce(gs.deck_order, '[]'::jsonb))
    + coalesce((select jsonb_array_length(p.cards) from public.room_deck_peeks p where p.room_id=p_room_id and p.source_user_id=v_user and p.returned_at is null),0)
  into v_my_deck_count
  from public.room_player_game_states gs where gs.room_id=p_room_id and gs.user_id=v_user;

  select coalesce(jsonb_agg(
    b.value || jsonb_build_object(
      'temporary_nickname', rp.temporary_nickname,
      'display_name', coalesce(nullif(rp.temporary_nickname, ''), '플레이어 ' || rp.seat::text),
      'case_phase', coalesce(tb.case_phase, 'incident'),
      'next_hint_pending', coalesce(tb.next_hint_pending, false),
      'base_action_done', coalesce(tb.base_action_done, false),
      'base_card_played_this_turn', coalesce(tb.base_card_played_this_turn, false),
      'character_played_this_turn', coalesce(tb.character_played_this_turn, false),
      'base_character_played_this_turn', coalesce(tb.base_character_played_this_turn, false),
      'partner_mr_card', tb.partner_mr_card,
      'partner_non_mr_cards', coalesce(tb.partner_non_mr_cards, '[]'::jsonb),
      'evidence_private_cards', case when rp.user_id = v_user then coalesce((
        select jsonb_agg(
          case
            when coalesce((ev.value ->> 'face_up')::boolean,false) is true then ev.value
            else jsonb_build_object('instance_id', ev.value ->> 'instance_id', 'face_up', false)
          end order by ev.ordinality
        )
        from public.room_player_game_states evidence_state
        cross join lateral jsonb_array_elements(coalesce(evidence_state.evidence_cards, '[]'::jsonb)) with ordinality ev(value, ordinality)
        where evidence_state.room_id = p_room_id and evidence_state.user_id = rp.user_id
      ), '[]'::jsonb) else '[]'::jsonb end,
      'evidence_public_cards', coalesce((
        select jsonb_agg(
          case
            when coalesce((ev.value ->> 'face_up')::boolean,false) is true then ev.value
            else jsonb_build_object('instance_id', ev.value ->> 'instance_id', 'face_up', false)
          end order by ev.ordinality
        )
        from public.room_player_game_states gs
        cross join lateral jsonb_array_elements(coalesce(gs.evidence_cards, '[]'::jsonb)) with ordinality ev(value, ordinality)
        where gs.room_id=p_room_id and gs.user_id=rp.user_id and coalesce(ev.value ->> 'face_up','false')='true'
      ), '[]'::jsonb),
      'deck_count', coalesce((
        select jsonb_array_length(coalesce(gs.deck_order, '[]'::jsonb))
          + coalesce((select jsonb_array_length(p.cards) from public.room_deck_peeks p where p.room_id=p_room_id and p.source_user_id=rp.user_id and p.returned_at is null),0)
        from public.room_player_game_states gs where gs.room_id=p_room_id and gs.user_id=rp.user_id
      ),0)
    ) order by rp.seat
  ), '[]'::jsonb) into v_boards
  from jsonb_array_elements(coalesce(v_result -> 'boards', '[]'::jsonb)) b(value)
  join public.room_players rp on rp.room_id=p_room_id and rp.user_id::text=(b.value ->> 'user_id')
  left join public.room_player_turn_boards tb on tb.room_id=p_room_id and tb.user_id=rp.user_id;

  return v_result || jsonb_build_object(
    'case_phase', coalesce((select tb.case_phase from public.room_player_turn_boards tb where tb.room_id=p_room_id and tb.user_id=v_user), 'incident'),
    'winner_display_name', v_winner_name,
    'winner_turn_number', v_winner_turn,
    'my_remove_cards', coalesce(v_my_remove, '[]'::jsonb),
    'my_file_cards', coalesce(v_my_file_cards, '[]'::jsonb),
    'opponent_remove_cards', coalesce(v_opponent_remove, '[]'::jsonb),
    'boards', coalesce(v_boards, '[]'::jsonb),
    'my_deck_count', coalesce(v_my_deck_count, 0),
    'my_deck_peek', v_my_peek,
    'shared_deck_peek_cards', coalesce(v_shared_peeks, '[]'::jsonb),
    'shared_hand_reveal', v_shared_hand_reveal,
    'deck_peek_in_progress', exists (select 1 from public.room_deck_peeks p where p.room_id=p_room_id and p.returned_at is null),
    'deck_peek_waiting_for_ack', exists (select 1 from public.room_deck_peeks p where p.room_id=p_room_id and p.returned_at is not null and not coalesce(p.shared_acknowledged,false) and jsonb_array_length(coalesce(p.shared_instance_ids,'[]'::jsonb)) > 0),
    'deck_peek_locked', exists (select 1 from public.room_deck_peeks p where p.room_id=p_room_id),
    'is_first_player', ((v_result ->> 'first_player_user_id') = v_user::text),
    'my_role', case when (v_result ->> 'first_player_user_id') = v_user::text then 'first' else 'second' end,
    'cancel_requested_by', to_jsonb(coalesce((select m.cancel_requested_by from public.room_match_states m where m.room_id = p_room_id), '{}'::uuid[])),
    'cancel_vote_count', cardinality(coalesce((select m.cancel_requested_by from public.room_match_states m where m.room_id = p_room_id), '{}'::uuid[])),
    'cancelled', coalesce((select m.game_over and m.winner_user_id is null and m.last_action_label like '모의전 취소 완료:%' from public.room_match_states m where m.room_id = p_room_id), false)
  );
end;
$function$


-- Reveal every AI-selected human hand/field target before the next effect step; preserve dual acknowledgement, sequence and reaction flows.
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

           SELECT ai_user_id INTO v_ai_user_id
             FROM public.private_ai_battles WHERE room_id=p_room_id;
           IF v_ai_user_id IS NOT NULL AND v_user=v_ai_user_id THEN
             v_revealed_cards:=jsonb_build_array(v_card);
             v_wait:=jsonb_build_object(
               'kind','ack','advance_step',true,'chooser_user_id',v_target_owner,
               'resume_special','mouri_ran_protection'
             );
             UPDATE public.private_card_effect_runs_v1
               SET variables=v_vars,step_index=step_index+1,waiting=v_wait,updated_at=now()
               WHERE room_id=p_room_id;
             UPDATE public.room_match_states
               SET pending_action=jsonb_build_object(
                 'type','card_effect_reveal_ack',
                 'effect_id',coalesce(v_run.effect_queue->v_run.effect_index->'__definition'->>'effectId',v_run.effect_queue->v_run.effect_index->>'effectId'),
                 'source_instance_id',v_run.source_instance_id,
                 'source_user_id',v_user,'chooser_user_id',v_target_owner,
                 'prompt','AI가 리무브 대상으로 모리 란을 선택했습니다. 선택된 카드를 확인한 뒤 확인 완료를 눌러 주세요.',
                 'revealed_cards',v_revealed_cards
               )||jsonb_build_object(
                 'source_card',coalesce(v_run.context->'source_card','{}'::jsonb),
                 'source_card_name',coalesce(v_run.context->'source_card'->>'name','')
               ),
               state_version=state_version+1,
               last_action_label='AI가 리무브 대상으로 모리 란을 선택했습니다. 상대 확인을 기다립니다.'
               WHERE room_id=p_room_id;
             RETURN;
           ELSE
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
   END IF;

   v_vars:=jsonb_set(v_vars,ARRAY[v_save],v_selected,true);
   -- Whenever the AI selects a human-owned hand/field card as an effect target,
   -- show the choice before proceeding to the following effect step.
   SELECT ai_user_id INTO v_ai_user_id
     FROM public.private_ai_battles WHERE room_id=p_room_id;
   IF v_ai_user_id IS NOT NULL AND v_user=v_ai_user_id
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_selected) chosen(value)
        WHERE chosen.value->>'zone' IN ('hand','field')
          AND coalesce(nullif(chosen.value->>'owner_user_id','')::uuid,v_user)<>v_user
      ) THEN
     SELECT nullif(chosen.value->>'owner_user_id','')::uuid INTO v_target_owner
       FROM jsonb_array_elements(v_selected) chosen(value)
       WHERE chosen.value->>'zone' IN ('hand','field')
         AND coalesce(nullif(chosen.value->>'owner_user_id','')::uuid,v_user)<>v_user
       LIMIT 1;
     SELECT coalesce(jsonb_agg(coalesce(chosen.value->'card',chosen.value)),'[]'::jsonb)
       INTO v_revealed_cards
       FROM jsonb_array_elements(v_selected) chosen(value)
       WHERE chosen.value->>'zone' IN ('hand','field')
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
         'prompt','AI가 효과 대상으로 선택한 카드입니다. 선택된 카드를 확인한 뒤 확인 완료를 눌러 주세요. 확인 후 카드 효과에 따라 이동합니다.',
         'revealed_cards',v_revealed_cards
       )||jsonb_build_object(
         'source_card',coalesce(v_run.context->'source_card','{}'::jsonb),
         'source_card_name',coalesce(v_run.context->'source_card'->>'name','')
       ),
       state_version=state_version+1,
       last_action_label='AI가 효과 대상을 선택했습니다. 상대 확인을 기다립니다.'
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

   IF coalesce(v_wait->>'resume_special','')='mouri_ran_protection' THEN
     SELECT coalesce(hand,'[]'::jsonb) INTO v_hand
       FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_run.actor_user_id FOR UPDATE;
     v_wait:=jsonb_build_object(
       'kind','reaction','save_as','__mouri_ran_protection_choice',
       'choices',CASE WHEN jsonb_array_length(v_hand)>0
         THEN '["손패 1장 리무브","효과 무효화"]'::jsonb
         ELSE '["효과 무효화"]'::jsonb END,
       'chooser_user_id',v_run.actor_user_id,
       'prompt','모리 란이 선택되었습니다. 손패 1장을 리무브하면 효과가 계속되고, 리무브하지 않으면 해당 효과가 무효화됩니다.'
     );
     UPDATE public.private_card_effect_runs_v1
       SET waiting=v_wait,updated_at=now()
       WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=jsonb_build_object(
         'type','card_effect_reaction',
         'effect_id',coalesce(v_run.effect_queue->v_run.effect_index->'__definition'->>'effectId',v_run.effect_queue->v_run.effect_index->>'effectId'),
         'source_instance_id',v_run.source_instance_id,
         'chooser_user_id',v_run.actor_user_id,
         'prompt',v_wait->>'prompt','choices',v_wait->'choices'
       )||jsonb_build_object(
         'source_card',coalesce(v_run.context->'source_card','{}'::jsonb),
         'source_card_name',coalesce(v_run.context->'source_card'->>'name','')
       ),
       state_version=state_version+1,
       last_action_label='모리 란 보호 효과의 선택 대상 확인이 끝났습니다. AI의 응답을 기다립니다.'
       WHERE room_id=p_room_id;
     RETURN;
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
$function$

