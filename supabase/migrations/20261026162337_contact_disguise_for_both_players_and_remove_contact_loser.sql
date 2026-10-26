-- Allow either contact participant to use a disguise during their cut-in response.
-- A contact loser is removed; a losing MR follows the existing MR-partner-area rule.
DO $patch$
DECLARE
  v_definition text;
  v_start integer;
  v_end integer;

  v_new_disguise text := $new_disguise$if p_action = 'contact_use_disguise' then
    if v_match.pending_action ->> 'type' is distinct from 'character_contact'
       or v_match.pending_action ->> 'next_responder_user_id' is distinct from v_user::text then
      raise exception '현재 컷인/변장 선택 차례가 아닙니다.';
    end if;

    if v_user::text = v_match.pending_action ->> 'attacker_user_id' then
      if coalesce(nullif(v_match.pending_action ->> 'attacker_cut_in_used','')::boolean,false)
         or coalesce(nullif(v_match.pending_action ->> 'attacker_cut_in_passed','')::boolean,false) then
        raise exception '이미 이 컨택에서 선택을 마쳤습니다.';
      end if;
      v_target_id := v_match.pending_action ->> 'attacker_instance_id';
    elsif v_user::text = v_match.pending_action ->> 'target_user_id' then
      if coalesce(nullif(v_match.pending_action ->> 'target_cut_in_used','')::boolean,false)
         or coalesce(nullif(v_match.pending_action ->> 'target_cut_in_passed','')::boolean,false) then
        raise exception '이미 이 컨택에서 선택을 마쳤습니다.';
      end if;
      v_target_id := v_match.pending_action ->> 'target_instance_id';
    else
      raise exception '컨택 참가자만 변장을 선택할 수 있습니다.';
    end if;

    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id
        and coalesce(e.value ->> 'card_type','')='character';
    if v_card is null then raise exception '손패에서 변장할 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce(
      nullif(v_card ->> 'disguiseEffect',''),
      nullif(v_card ->> 'disguise_effect',''),
      nullif(v_card ->> 'hensoEffect',''),
      nullif(v_card ->> 'henso',''),
      nullif(v_card #>> '{gameSystemEffects,disguise}',''),
      nullif(v_card #>> '{gameSystemEffects,henso}',''),
      nullif(p_payload ->> 'disguise_effect',''),
      nullif(p_payload ->> 'disguiseEffect',''),
      nullif(v_card #>> '{sourceData,henso}',''),
      nullif(v_card #>> '{sourceData,hensoEffect}','')
    ) is null then
      raise exception '변장 효과가 있는 캐릭터를 선택해 주세요.';
    end if;

    select e.value into v_target
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_target_id
        and coalesce(e.value ->> 'card_type','')='character';
    if v_target is null then raise exception '교체할 컨택 캐릭터를 찾을 수 없습니다.'; end if;

    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_id),'[]'::jsonb)
      into v_hand_new
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_target_id),'[]'::jsonb)
      into v_field_new
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    v_field_new := coalesce(v_field_new,'[]'::jsonb) || jsonb_build_array(
      (v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up' - 'set_owner_user_id' - 'host_instance_id')
      || jsonb_build_object('rested',true,'status','rested','ap_bonus',0,'summoned_this_turn',true)
    );

    update public.room_player_game_states gs
      set hand=v_hand_new,
          deck_order=coalesce(gs.deck_order,'[]'::jsonb)||jsonb_build_array(v_target - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'),
          updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b set field_cards=v_field_new,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;

    v_pending := v_match.pending_action;
    if v_user::text = v_pending ->> 'attacker_user_id' then
      v_pending := jsonb_set(v_pending,'{disguised_original_attacker_instance_id}',to_jsonb(v_target_id));
      v_pending := jsonb_set(v_pending,'{attacker_instance_id}',to_jsonb(v_card ->> 'instance_id'));
      v_pending := jsonb_set(v_pending,'{attacker_ap}',to_jsonb(coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0)));
      v_pending := jsonb_set(v_pending,'{attacker_cut_in_passed}','true'::jsonb);
      v_pending := jsonb_set(v_pending,'{disguise_replaced_attacker}','true'::jsonb);
      v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'target_user_id'));
    else
      v_pending := jsonb_set(v_pending,'{disguised_original_target_instance_id}',to_jsonb(v_target_id));
      v_pending := jsonb_set(v_pending,'{target_instance_id}',to_jsonb(v_card ->> 'instance_id'));
      v_pending := jsonb_set(v_pending,'{target_ap}',to_jsonb(coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0)));
      v_pending := jsonb_set(v_pending,'{target_cut_in_passed}','true'::jsonb);
      v_pending := jsonb_set(v_pending,'{disguise_replaced_target}','true'::jsonb);
      v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'attacker_user_id'));
    end if;

    if (
      coalesce(nullif(v_pending ->> 'attacker_cut_in_used','')::boolean,false)
      or coalesce(nullif(v_pending ->> 'attacker_cut_in_passed','')::boolean,false)
    ) and (
      coalesce(nullif(v_pending ->> 'target_cut_in_used','')::boolean,false)
      or coalesce(nullif(v_pending ->> 'target_cut_in_passed','')::boolean,false)
    ) then
      perform public.resolve_private_character_contact(p_room_id,v_pending);
      return public.get_private_turn_state_v2(p_room_id);
    end if;

    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label=format('변장: %s가 자신의 컨택 캐릭터 대신 슬립 상태로 등장했고, 교체된 캐릭터는 덱 맨 아래로 이동했습니다.',coalesce(v_card ->> 'key','캐릭터'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;$new_disguise$;

  v_old_loss text := $old_loss$  else
    -- A failed attack does not remove the attacker. It remains rested on the field.
    v_label := '컨택 패배: 수비자의 AP가 더 높습니다. 공격자는 리무브되지 않고 현장에 남습니다.';
  end if;$old_loss$;

  v_new_loss text := $new_loss$  else
    -- The character that loses contact leaves the field, regardless of who initiated the attack.
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_attacker_id), '[]'::jsonb)
      into v_new_field from jsonb_array_elements(coalesce(v_attacker_board.field_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    v_loser_is_mr := upper(coalesce(v_attacker_card ->> 'rarity', '')) = 'MR';
    if v_loser_is_mr
       and coalesce(v_attacker_board.partner_mr_card ->> 'instance_id','') <> ''
       and v_attacker_board.partner_mr_card ->> 'instance_id' is distinct from v_attacker_card ->> 'instance_id' then
      update public.room_player_game_states gs
        set remove_cards = coalesce(gs.remove_cards, '[]'::jsonb) ||
          jsonb_build_array(v_attacker_board.partner_mr_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id'),
            updated_at = now()
        where gs.room_id = p_room_id and gs.user_id = v_attacker_user;
      update public.room_player_turn_boards b
        set remove_count = coalesce(b.remove_count,0) + 1, updated_at = now()
        where b.room_id = p_room_id and b.user_id = v_attacker_user;
    end if;
    if v_loser_is_mr then
      update public.room_player_turn_boards b
      set field_cards = v_new_field,
          partner_mr_card = (v_attacker_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving')
            || jsonb_build_object('rested', false, 'status', 'active', 'ap_bonus', 0, 'summoned_this_turn', false),
          updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_attacker_user;
      v_label := '컨택 승리: 수비자가 우세. 공격자 MR 카드를 MR 파트너 에이리어로 이동했습니다.';
    else
      update public.room_player_game_states gs
        set remove_cards = coalesce(gs.remove_cards, '[]'::jsonb)
          || jsonb_build_array(v_attacker_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'),
            updated_at = now()
      where gs.room_id = p_room_id and gs.user_id = v_attacker_user;
      update public.room_player_turn_boards b
        set field_cards = v_new_field,
            remove_count = coalesce(b.remove_count,0) + 1,
            updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_attacker_user;
      v_label := '컨택 승리: 수비자가 우세. 공격자 캐릭터를 리무브했습니다.';
    end if;
  end if;$new_loss$;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;
  v_start := position('if p_action = ''contact_use_disguise'' then' IN v_definition);
  IF v_start = 0 THEN RAISE EXCEPTION 'Could not find contact_use_disguise action branch.'; END IF;
  v_end := position('if p_action = ''guard_contact_with_character'' then' IN substring(v_definition FROM v_start));
  IF v_end = 0 THEN RAISE EXCEPTION 'Could not find the end of contact_use_disguise action branch.'; END IF;
  v_definition := overlay(v_definition placing v_new_disguise || E'\n\n  ' FROM v_start FOR v_end - 1);
  EXECUTE v_definition;

  SELECT replace(pg_get_functiondef('public.resolve_private_character_contact(uuid,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;
  IF position(v_old_loss IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Could not find the current failed-attacker branch in resolve_private_character_contact.';
  END IF;
  v_definition := replace(v_definition, v_old_loss, v_new_loss);
  EXECUTE v_definition;
END
$patch$;