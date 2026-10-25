-- Fix empty greetings, make manual partner slip actionable, reveal evidence before manual removal,
-- detect ID:0301 by normalized fields, and reset/reopen guarded contact cut-ins.

DO $patch$
DECLARE
  v_definition text;

  v_old_message_decl text := $old_msg$  v_message text := trim(coalesce(p_message,''));$old_msg$;
  v_new_message_decl text := $new_msg$  v_message text := coalesce(nullif(trim(p_message),''), '안녕하세요. 이번 게임 잘 부탁드리겠습니다.');$new_msg$;

  v_old_gate text := $old_gate$  if v_match.pending_action is not null and v_match.pending_action ->> 'type' in ('character_contact_guard', 'character_contact', 'mislead_response', 'evidence_attack_reveal', 'evidence_attack', 'deck_remove_reveal', 'file_remove_reveal', 'culprits_crime_reveal') then
    if p_action not in ('guard_contact_with_character','decline_contact_guard','contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead','resolve_evidence_attack','guard_with_character','decline_guard','acknowledge_deck_remove','acknowledge_file_remove','acknowledge_hand_reveal','acknowledge_culprits_crime') then
      raise exception '현재 진행 중인 응답을 먼저 마쳐 주세요.';
    end if;
  elsif p_action in ('guard_contact_with_character','decline_contact_guard','contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead','resolve_evidence_attack','guard_with_character','decline_guard','acknowledge_deck_remove','acknowledge_file_remove','acknowledge_culprits_crime') then
    raise exception '응답할 컨택/미스리드/증거 공개가 없습니다.';
  end if;$old_gate$;
  v_new_gate text := $new_gate$  if v_match.pending_action is not null and v_match.pending_action ->> 'type' in ('character_contact_guard', 'character_contact', 'mislead_response', 'evidence_attack_reveal', 'evidence_attack', 'deck_remove_reveal', 'file_remove_reveal', 'culprits_crime_reveal', 'evidence_remove_reveal') then
    if p_action not in ('guard_contact_with_character','decline_contact_guard','contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead','resolve_evidence_attack','guard_with_character','decline_guard','acknowledge_deck_remove','acknowledge_file_remove','acknowledge_hand_reveal','acknowledge_culprits_crime','acknowledge_evidence_remove') then
      raise exception '현재 진행 중인 응답을 먼저 마쳐 주세요.';
    end if;
  elsif p_action in ('guard_contact_with_character','decline_contact_guard','contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead','resolve_evidence_attack','guard_with_character','decline_guard','acknowledge_deck_remove','acknowledge_file_remove','acknowledge_culprits_crime','acknowledge_evidence_remove') then
    raise exception '응답할 컨택/미스리드/증거 공개가 없습니다.';
  end if;$new_gate$;

  v_old_detection text := $old_detect$    select exists (
      select 1
      from public.room_player_turn_boards opponent
      cross join lateral jsonb_array_elements(coalesce(opponent.field_cards, '[]'::jsonb)) other_card(value)
      where opponent.room_id = p_room_id
        and opponent.user_id <> v_user
        and exists (
          select 1
          from unnest(array[
            other_card.value ->> 'key',
            other_card.value ->> 'databaseId',
            other_card.value ->> 'database_id',
            other_card.value ->> 'cardId',
            other_card.value ->> 'card_id',
            other_card.value ->> 'cardNum',
            other_card.value ->> 'card_num',
            other_card.value ->> 'id',
            other_card.value #>> '{sourceData,id}',
            other_card.value #>> '{sourceData,databaseId}',
            other_card.value #>> '{sourceData,database_id}',
            other_card.value #>> '{sourceData,cardId}',
            other_card.value #>> '{sourceData,card_id}',
            other_card.value #>> '{sourceData,cardNum}',
            other_card.value #>> '{sourceData,card_num}',
            other_card.value #>> '{raw,id}',
            other_card.value #>> '{raw,databaseId}',
            other_card.value #>> '{raw,database_id}',
            other_card.value #>> '{raw,cardId}',
            other_card.value #>> '{raw,card_id}',
            other_card.value #>> '{raw,cardNum}',
            other_card.value #>> '{raw,card_num}'
          ]) candidate(value)
          where coalesce(nullif(ltrim(btrim(candidate.value), '0'), ''), '0') = '301'
        )
    ) into v_kid_stun_lock;$old_detect$;
  v_new_detection text := $new_detect$    select exists (
      select 1
      from public.room_player_turn_boards opponent
      cross join lateral jsonb_array_elements(coalesce(opponent.field_cards, '[]'::jsonb)) other_card(value)
      where opponent.room_id = p_room_id
        and opponent.user_id <> v_user
        and exists (
          select 1
          from unnest(array[
            other_card.value ->> 'key',
            other_card.value ->> 'databaseId',
            other_card.value ->> 'database_id',
            other_card.value ->> 'cardId',
            other_card.value ->> 'card_id',
            other_card.value ->> 'cardNum',
            other_card.value ->> 'card_num',
            other_card.value ->> 'id',
            other_card.value ->> 'cardNumber',
            other_card.value ->> 'card_number',
            other_card.value ->> 'databaseID',
            other_card.value ->> 'cardDatabaseId',
            other_card.value ->> 'card_database_id',
            other_card.value ->> 'sourceRecordId',
            other_card.value ->> 'source_record_id',
            other_card.value #>> '{sourceData,id}',
            other_card.value #>> '{sourceData,databaseId}',
            other_card.value #>> '{sourceData,database_id}',
            other_card.value #>> '{sourceData,cardId}',
            other_card.value #>> '{sourceData,card_id}',
            other_card.value #>> '{sourceData,cardNum}',
            other_card.value #>> '{sourceData,card_num}',
            other_card.value #>> '{sourceData,sourceRecordId}',
            other_card.value #>> '{source_data,id}',
            other_card.value #>> '{source_data,databaseId}',
            other_card.value #>> '{source_data,database_id}',
            other_card.value #>> '{source_data,cardId}',
            other_card.value #>> '{source_data,card_id}',
            other_card.value #>> '{source_data,cardNum}',
            other_card.value #>> '{source_data,card_num}',
            other_card.value #>> '{raw,id}',
            other_card.value #>> '{raw,databaseId}',
            other_card.value #>> '{raw,database_id}',
            other_card.value #>> '{raw,cardId}',
            other_card.value #>> '{raw,card_id}',
            other_card.value #>> '{raw,cardNum}',
            other_card.value #>> '{raw,card_num}',
            other_card.value #>> '{data,id}',
            other_card.value #>> '{data,databaseId}',
            other_card.value #>> '{data,database_id}'
          ]) candidate(value)
          where coalesce(nullif(ltrim(btrim(candidate.value), '0'), ''), '0') = '301'
             or coalesce(nullif(ltrim(regexp_replace(upper(btrim(candidate.value)), '^ID\s*:\s*', ''), '0'), ''), '0') = '301'
        )
    ) into v_kid_stun_lock;$new_detect$;

  v_old_move_anchor text := $old_move_anchor$  -- Move a publicly revealed evidence card to its owner's remove area.
  if p_action = 'move_evidence_to_remove' then$old_move_anchor$;
  v_new_move_prefix text := $new_move_prefix$  -- Require a shared reveal before manually moving evidence to Remove.
  if p_action = 'acknowledge_evidence_remove' then
    if v_match.pending_action ->> 'type' is distinct from 'evidence_remove_reveal' then
      raise exception '확인할 증거 리무브 공개가 없습니다.';
    end if;
    v_shared_ids := coalesce(v_match.pending_action -> 'acknowledged_user_ids','[]'::jsonb);
    if v_shared_ids @> jsonb_build_array(v_user::text) then raise exception '이미 이 증거 카드를 확인했습니다.'; end if;
    v_shared_ids := v_shared_ids || jsonb_build_array(v_user::text);

    if jsonb_array_length(v_shared_ids) < 2 then
      update public.room_match_states m
        set pending_action=jsonb_set(v_match.pending_action,'{acknowledged_user_ids}',v_shared_ids,true),
            state_version=state_version+1,
            last_action_label=format('증거 리무브 확인 %s/2명 완료. 두 사람 모두 확인하면 이동합니다.',jsonb_array_length(v_shared_ids))
        where m.room_id=p_room_id;
      return public.get_private_turn_state_v2(p_room_id);
    end if;

    v_owner_id := nullif(v_match.pending_action ->> 'owner_user_id','')::uuid;
    v_card := v_match.pending_action -> 'revealed_evidence_card';
    v_id := nullif(v_card ->> 'instance_id','');
    if v_owner_id is null or v_id is null then raise exception '공개된 증거 카드의 소유자 또는 인스턴스 ID가 없습니다.'; end if;
    select * into v_opponent_game from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_owner_id for update;
    if not found then raise exception '증거 카드 소유자의 게임 데이터를 찾을 수 없습니다.'; end if;
    if not exists (select 1 from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id) then
      raise exception '공개 중 증거 영역이 바뀌었습니다. 새로고침 후 다시 확인해 주세요.';
    end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_id),'[]'::jsonb)
      into v_files_new from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs
      set evidence_cards=coalesce(v_files_new,'[]'::jsonb),
          remove_cards=coalesce(gs.remove_cards,'[]'::jsonb)||jsonb_build_array(
            (v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving')
            || jsonb_build_object('face_up',true,'hirameki_achieved',true)
          ),
          updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_owner_id;
    update public.room_player_turn_boards tb
      set evidence_count=greatest(0,coalesce(tb.evidence_count,0)-1),
          remove_count=coalesce(tb.remove_count,0)+1,updated_at=now()
      where tb.room_id=p_room_id and tb.user_id=v_owner_id;
    update public.room_match_states m
      set pending_action=null,state_version=state_version+1,
          last_action_label=format('%s의 증거 카드를 양쪽 플레이어가 확인해 리무브로 이동했습니다.',case when v_owner_id=v_user then '내' else '상대' end)
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'move_evidence_to_remove' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'instance_id','');
    if not exists (select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_owner_id) then raise exception '증거 카드 소유자를 찾을 수 없습니다.'; end if;
    select * into v_opponent_game from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_owner_id for update;
    if not found then raise exception '증거 카드 소유자의 게임 데이터를 찾을 수 없습니다.'; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id
        and (coalesce((e.value ->> 'face_up')::boolean,false) is true or v_owner_id=v_user);
    if v_card is null then raise exception '이동할 수 있는 증거 카드를 찾을 수 없습니다.'; end if;
    v_card := v_card || jsonb_build_object('face_up',true,'hirameki_achieved',true);
    v_pending := jsonb_build_object(
      'type','evidence_remove_reveal',
      'owner_user_id',v_owner_id::text,
      'revealed_evidence_card',v_card,
      'acknowledged_user_ids','[]'::jsonb
    );
    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label=format('%s의 증거 카드 %s를 양쪽 플레이어에게 공개했습니다. 두 사람 모두 확인하면 리무브로 이동합니다.',case when v_owner_id=v_user then '내' else '상대' end,coalesce(v_card ->> 'key','카드'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Legacy direct-removal code remains unreachable; all live requests use the reveal-first branch.
  if p_action = 'move_evidence_to_remove_legacy_disabled' then$new_move_prefix$;

  v_old_guard_reset text := $old_guard_reset$    v_pending := v_pending - 'attacker_cut_in_used' - 'target_cut_in_used' - 'attacker_cut_in_passed' - 'target_cut_in_passed' - 'cut_in_used';
    v_pending := jsonb_set(v_pending,'{attacker_bonus}',to_jsonb(0));
    v_pending := jsonb_set(v_pending,'{target_bonus}',to_jsonb(0));$old_guard_reset$;
  v_new_guard_reset text := $new_guard_reset$    v_pending := v_pending - 'attacker_cut_in_used' - 'target_cut_in_used' - 'attacker_cut_in_passed' - 'target_cut_in_passed' - 'cut_in_used';
    v_pending := v_pending || jsonb_build_object(
      'attacker_cut_in_used',false,'target_cut_in_used',false,
      'attacker_cut_in_passed',false,'target_cut_in_passed',false,
      'cut_in_used',false,'guarded_contact',true,
      'attacker_bonus',0,'target_bonus',0
    );$new_guard_reset$;

  v_old_decline_card text := $old_decline$    v_card := v_game.evidence_cards -> (jsonb_array_length(v_game.evidence_cards)-1);$old_decline$;
  v_new_decline_card text := $new_decline$    v_card := (v_game.evidence_cards -> (jsonb_array_length(v_game.evidence_cards)-1)) || jsonb_build_object('hirameki_achieved',true);$new_decline$;

  v_old_allowlist text := $old_allow$  if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime','acknowledge_culprits_crime') then$old_allow$;
  v_new_allowlist text := $new_allow$  if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime','acknowledge_culprits_crime','rest_partner_manual','acknowledge_evidence_remove') then$new_allow$;

BEGIN
  SELECT replace(pg_get_functiondef('public.submit_private_match_greeting_v1(uuid,text)'::regprocedure), chr(13), '')
    INTO v_definition;
  IF position(v_old_message_decl IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find greeting message declaration.'; END IF;
  v_definition := replace(v_definition, v_old_message_decl, v_new_message_decl);
  EXECUTE v_definition;

  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;
  IF position(v_old_gate IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find the pending-action gate.'; END IF;
  v_definition := replace(v_definition, v_old_gate, v_new_gate);

  IF position(v_old_detection IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find the ID:0301 presence detector.'; END IF;
  v_definition := replace(v_definition, v_old_detection, v_new_detection);

  IF position(v_old_move_anchor IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find the manual evidence-removal branch.'; END IF;
  v_definition := replace(v_definition, v_old_move_anchor, v_new_move_prefix);

  IF position(v_old_guard_reset IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find the guarded-contact cut-in reset block.'; END IF;
  v_definition := replace(v_definition, v_old_guard_reset, v_new_guard_reset);

  IF position(v_old_decline_card IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find the evidence-attack reveal card assignment.'; END IF;
  v_definition := replace(v_definition, v_old_decline_card, v_new_decline_card);

  IF position(v_old_allowlist IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not find the general action allowlist.'; END IF;
  v_definition := replace(v_definition, v_old_allowlist, v_new_allowlist);

  EXECUTE v_definition;
END
$patch$;
