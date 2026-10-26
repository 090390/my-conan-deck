-- Keep field MRs in the MR partner area when sent to Remove, make evidence guard lead to cut-in contact,
-- and clear the temporary Next Hint lock after the selected character is deployed.
DO $patch$
DECLARE
  v_definition text;
  v_guard_start integer;
  v_guard_end integer;
  v_move_start integer;
  v_move_anchor integer;
  v_old_next_hint text := 'next_hint_pending=false,next_hint_used=true,base_action_done=true,base_card_played_this_turn=true,updated_at=now()';
  v_new_next_hint text := 'next_hint_pending=false,next_hint_used=false,base_action_done=true,base_card_played_this_turn=true,updated_at=now()';

  v_new_guard text := $guard$if p_action = 'guard_with_character' then
    if v_match.pending_action ->> 'type' is distinct from 'evidence_attack'
       or v_match.pending_action ->> 'target_user_id' is distinct from v_user::text then
      raise exception '현재 이 공격에 응답할 수 없습니다.';
    end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id
        and coalesce(e.value ->> 'card_type','')='character';
    if v_card is null then raise exception '가드할 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce((v_card ->> 'rested')::boolean,false)
       or coalesce(v_card ->> 'status','active') in ('rested','stunned') then
      raise exception '액티브 상태의 캐릭터만 가드할 수 있습니다.';
    end if;
    select * into v_opponent_board
      from public.room_player_turn_boards b
      where b.room_id=p_room_id
        and b.user_id=(v_match.pending_action ->> 'attacker_user_id')::uuid
      for update;
    if not found then raise exception '증거를 공격한 플레이어의 보드를 찾을 수 없습니다.'; end if;
    select e.value into v_attacker
      from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_match.pending_action ->> 'attacker_instance_id'
        and coalesce(e.value ->> 'card_type','')='character';
    if v_attacker is null then raise exception '증거 공격에 사용한 캐릭터를 찾을 수 없습니다.'; end if;

    select coalesce(jsonb_agg(
      case when e.value ->> 'instance_id'=v_id
        then e.value || jsonb_build_object('rested',true,'status','rested')
        else e.value end
      order by e.ordinality),'[]'::jsonb)
      into v_new_status_field
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b
      set field_cards=v_new_status_field,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;

    v_pending := v_match.pending_action || jsonb_build_object(
      'type','character_contact',
      'target_instance_id',v_id,
      'attacker_ap',coalesce(nullif(v_attacker ->> 'ap','')::numeric,0)+coalesce(nullif(v_attacker ->> 'ap_bonus','')::numeric,0),
      'target_ap',coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0),
      'attacker_bonus',0,'target_bonus',0,
      'attacker_cut_in_used',false,'target_cut_in_used',false,
      'attacker_cut_in_passed',false,'target_cut_in_passed',false,
      'cut_in_used',false,'guarded_contact',true,'guarded_evidence_attack',true,
      'guarded_evidence_instance_id',coalesce(
        (v_game.evidence_cards -> (jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))-1)) ->> 'instance_id',''
      )
    );
    v_pending := jsonb_set(v_pending,'{cut_in_priority_user_id}',to_jsonb(
      case when coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0)
                  <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0)
           then v_pending ->> 'target_user_id' else v_pending ->> 'attacker_user_id' end
    ));
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(
      case when coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0)
                  <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0)
           then v_pending ->> 'target_user_id' else v_pending ->> 'attacker_user_id' end
    ));
    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label=format('증거 공격을 %s로 가드했습니다. 가드 캐릭터는 슬립 상태이며 양쪽의 컷인 선택 후 AP를 비교합니다.',coalesce(v_card ->> 'key','캐릭터'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;$guard$;

  v_new_mr_move text := $mr_move$if v_dest='remove'
   and not v_is_mr_partner
   and not v_is_non_mr_partner
   and upper(coalesce(v_card ->> 'rarity',''))='MR' then
    -- A field MR sent to Remove actually replaces the MR partner-area card.
    if coalesce(v_board.partner_mr_card ->> 'instance_id','') <> ''
       and v_board.partner_mr_card ->> 'instance_id' is distinct from v_id then
      update public.room_player_game_states g
        set remove_cards=coalesce(g.remove_cards,'[]'::jsonb)||jsonb_build_array(
          v_board.partner_mr_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn'
            - 'resolving' - 'host_instance_id' - 'set_owner_user_id'
        ), updated_at=now()
        where g.room_id=p_room_id and g.user_id=v_owner_id;
      update public.room_player_turn_boards b
        set remove_count=coalesce(remove_count,0)+1,updated_at=now()
        where b.room_id=p_room_id and b.user_id=v_owner_id;
    end if;
    update public.room_player_turn_boards b
      set field_cards=v_field_new,
          partner_mr_card=v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn'
            - 'resolving' - 'face_up' - 'host_instance_id' - 'set_owner_user_id',
          partner_non_mr_cards=coalesce(v_partner_non_mr_new,'[]'::jsonb),
          updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_owner_id;
    update public.room_match_states m
      set state_version=state_version+1,
          last_action_label=format('MR %s가 리무브 대신 MR 파트너 에이리어로 이동했습니다.',coalesce(v_card ->> 'key','카드'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;$mr_move$;

BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  v_guard_start := position('if p_action = ''guard_with_character'' then' IN v_definition);
  IF v_guard_start=0 THEN RAISE EXCEPTION 'Could not find evidence guard branch.'; END IF;
  v_guard_end := position('if p_action = ''stun_character'' then' IN substring(v_definition FROM v_guard_start));
  IF v_guard_end=0 THEN RAISE EXCEPTION 'Could not find the end of evidence guard branch.'; END IF;
  v_definition := overlay(v_definition placing v_new_guard || E'\n\n  ' FROM v_guard_start FOR v_guard_end-1);

  v_move_start := position('if p_action = ''move_field_card'' then' IN v_definition);
  IF v_move_start=0 THEN RAISE EXCEPTION 'Could not find move_field_card branch.'; END IF;
  v_move_anchor := position('if v_dest = ''hand'' then' IN substring(v_definition FROM v_move_start));
  IF v_move_anchor=0 THEN RAISE EXCEPTION 'Could not find move_field_card destination handling.'; END IF;
  v_definition := overlay(v_definition placing v_new_mr_move || E'\n    ' FROM v_move_start+v_move_anchor-1 FOR 0);

  IF (length(v_definition)-length(replace(v_definition,v_old_next_hint,'')))/length(v_old_next_hint) <> 1 THEN
    RAISE EXCEPTION 'Could not find the unique Next Hint completion flag.';
  END IF;
  v_definition := replace(v_definition,v_old_next_hint,v_new_next_hint);
  EXECUTE v_definition;
END
$patch$;
