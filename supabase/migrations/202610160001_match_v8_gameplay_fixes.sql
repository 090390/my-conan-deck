-- Conan TCG private-match v8 server rule update
-- This migration safely rewrites the current PL/pgSQL function by replacing known code fragments.
-- It aborts if the expected source blocks do not match, instead of silently applying a partial patch.
-- Review the generated function in a staging Supabase project before applying in production.

DO $match_v8$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  -- GitHub's current function was stored with CRLF line endings in the supplied definition.
  v_definition := replace(v_definition, chr(13), '');

  -- Permit the contact defender to resolve a disguise from hand during the guard-response window.
  IF position($old$'contact_use_cutin','contact_pass_cutin','resolve_mislead'$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$'contact_use_cutin','contact_pass_cutin','resolve_mislead'$old$,
      $new$'contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead'$new$
    );
  ELSIF position($new$'contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead'$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: contact response action allow-list did not match';
  END IF;

  -- Record per-player cut-in usage while preserving the legacy cut_in_used key.
  IF position($old$'attacker_bonus',0,'target_bonus',0,'cut_in_used',false,'next_responder_user_id',v_target_user_id$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$'attacker_bonus',0,'target_bonus',0,'cut_in_used',false,'next_responder_user_id',v_target_user_id$old$,
      $new$'attacker_bonus',0,'target_bonus',0,'cut_in_used',false,'attacker_cut_in_used',false,'target_cut_in_used',false,'next_responder_user_id',v_target_user_id$new$
    );
  ELSIF position($new$'attacker_bonus',0,'target_bonus',0,'cut_in_used',false,'attacker_cut_in_used',false,'target_cut_in_used',false,'next_responder_user_id',v_target_user_id$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: contact pending initialization did not match';
  END IF;

  -- Allow either character or event cards to be set.
  IF position($old$if lower(coalesce(v_card ->> 'card_type','')) <> 'event' then raise exception '이벤트 카드만 세트할 수 있습니다.'; end if;$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$if lower(coalesce(v_card ->> 'card_type','')) <> 'event' then raise exception '이벤트 카드만 세트할 수 있습니다.'; end if;$old$,
      $new$if lower(coalesce(v_card ->> 'card_type','')) not in ('event','character') then raise exception '캐릭터 또는 이벤트 카드만 세트할 수 있습니다.'; end if;$new$
    );
  ELSIF position($new$if lower(coalesce(v_card ->> 'card_type','')) not in ('event','character') then raise exception '캐릭터 또는 이벤트 카드만 세트할 수 있습니다.'; end if;$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: set-card type restriction did not match';
  END IF;

  -- Permit manual stunned -> rested/sleep conversion. A stunned card often also has rested=true.
  IF position($old$if coalesce((v_card ->> 'rested')::boolean,false) or coalesce(v_card ->> 'status','active') in ('rested','stunned') then raise exception '이미 슬립/스턴 상태인 캐릭터입니다.'; end if;$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$if coalesce((v_card ->> 'rested')::boolean,false) or coalesce(v_card ->> 'status','active') in ('rested','stunned') then raise exception '이미 슬립/스턴 상태인 캐릭터입니다.'; end if;$old$,
      $new$if coalesce(v_card ->> 'status','active') = 'rested'
        or (coalesce((v_card ->> 'rested')::boolean,false) and coalesce(v_card ->> 'status','active') <> 'stunned') then
      raise exception '이미 슬립 상태인 캐릭터입니다.';
    end if;$new$
    );
  ELSIF position($new$if coalesce(v_card ->> 'status','active') = 'rested'
        or (coalesce((v_card ->> 'rested')::boolean,false) and coalesce(v_card ->> 'status','active') <> 'stunned') then$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: manual sleep status restriction did not match';
  END IF;

  -- Patch the cut-in bonus assignments using their distinctive expressions rather than an indentation-sensitive block.
  IF position($old$'{attacker_bonus}',to_jsonb(v_bonus));$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$'{attacker_bonus}',to_jsonb(v_bonus));$old$,
      $new$'{attacker_bonus}',to_jsonb(v_bonus));
      v_pending := jsonb_set(v_pending,'{attacker_cut_in_used}','true'::jsonb);$new$
    );
  ELSIF position($new$'{attacker_bonus}',to_jsonb(v_bonus));
      v_pending := jsonb_set(v_pending,'{attacker_cut_in_used}','true'::jsonb);$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: attacker cut-in bonus assignment did not match';
  END IF;

  IF position($old$'{target_bonus}',to_jsonb(v_bonus));$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$'{target_bonus}',to_jsonb(v_bonus));$old$,
      $new$'{target_bonus}',to_jsonb(v_bonus));
      v_pending := jsonb_set(v_pending,'{target_cut_in_used}','true'::jsonb);$new$
    );
  ELSIF position($new$'{target_bonus}',to_jsonb(v_bonus));
      v_pending := jsonb_set(v_pending,'{target_cut_in_used}','true'::jsonb);$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: target cut-in bonus assignment did not match';
  END IF;

  -- After the defender uses a cut-in, let the attacker answer before resolving contact.
  IF position($old$v_pending := jsonb_set(v_pending,'{cut_in_used}','true'::jsonb);$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$v_pending := jsonb_set(v_pending,'{cut_in_used}','true'::jsonb);$old$,
      $new$v_pending := jsonb_set(v_pending,'{cut_in_used}','true'::jsonb);
    if v_user = (v_match.pending_action ->> 'target_user_id')::uuid then
      v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb((v_match.pending_action ->> 'attacker_user_id')));
      update public.room_match_states m
        set pending_action=v_pending,state_version=state_version+1,
            last_action_label='수비자가 컷인을 사용했습니다. 이제 공격자가 컷인 사용 여부를 선택합니다.'
        where m.room_id=p_room_id;
      return public.get_private_turn_state_v2(p_room_id);
    end if;$new$
    );
  ELSIF position($new$v_pending := jsonb_set(v_pending,'{cut_in_used}','true'::jsonb);
    if v_user = (v_match.pending_action ->> 'target_user_id')::uuid then$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: cut-in resolution insertion point did not match';
  END IF;

  -- Return an attached set card to the current player's hand.
  IF position($old$  if p_action = 'reveal_set_card' then$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$  if p_action = 'reveal_set_card' then$old$,
      $new$  if p_action = 'move_set_card_to_hand' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'host_owner_user_id','')::uuid,v_user);
    if v_owner_id <> v_user then raise exception '자신의 세트 카드만 손패로 가져올 수 있습니다.'; end if;
    v_id := nullif(p_payload ->> 'host_instance_id','');
    v_attack_id := nullif(p_payload ->> 'set_instance_id','');

    select * into v_board from public.room_player_turn_boards b
      where b.room_id=p_room_id and b.user_id=v_owner_id for update;
    if not found then raise exception '세트 카드 소유자의 보드를 찾을 수 없습니다.'; end if;
    select e.value into v_target
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id;
    if v_target is null then raise exception '세트 카드를 놓은 현장 카드를 찾을 수 없습니다.'; end if;
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_target -> 'set_cards','[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_attack_id;
    if v_card is null then raise exception '선택한 세트 카드를 찾을 수 없습니다.'; end if;
    if coalesce(v_card ->> 'set_owner_user_id',v_user::text) <> v_user::text then
      raise exception '다른 플레이어가 세트한 카드는 손패로 가져올 수 없습니다.';
    end if;

    select coalesce(jsonb_agg(
      case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object(
        'set_cards',coalesce((
          select jsonb_agg(sc.value order by sc.ordinality)
          from jsonb_array_elements(coalesce(e.value -> 'set_cards','[]'::jsonb)) with ordinality sc(value,ordinality)
          where sc.value ->> 'instance_id' is distinct from v_attack_id
        ),'[]'::jsonb)
      ) else e.value end order by e.ordinality),'[]'::jsonb)
      into v_field_new
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b set field_cards=v_field_new,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_owner_id;
    update public.room_player_game_states gs
      set hand=coalesce(gs.hand,'[]'::jsonb)||jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up' - 'host_instance_id' - 'set_owner_user_id'),
          updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,
      last_action_label='선택한 세트 카드를 손패로 가져왔습니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'reveal_set_card' then$new$
    );
  ELSIF position($new$  if p_action = 'move_set_card_to_hand' then$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: set-card return insertion anchor did not match';
  END IF;

  -- Allow a hand card to become evidence face-up or face-down.
  IF position($old$  if p_action = 'gain_evidence_from_deck' then$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$  if p_action = 'gain_evidence_from_deck' then$old$,
      $new$  if p_action = 'move_hand_card_to_evidence' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '손패에서 증거로 이동할 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_id),'[]'::jsonb)
      into v_hand_new
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
    v_card := (v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up' - 'host_instance_id' - 'set_owner_user_id')
      || jsonb_build_object('face_up',coalesce(nullif(p_payload ->> 'face_up','')::boolean,false));
    update public.room_player_game_states gs
      set hand=v_hand_new,evidence_cards=coalesce(gs.evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b set evidence_count=coalesce(b.evidence_count,0)+1,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,
      last_action_label=format('손패 카드 1장을 증거 에이리어에 %s으로 이동했습니다.',case when coalesce((v_card ->> 'face_up')::boolean,false) then '앞면' else '뒷면' end)
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'gain_evidence_from_deck' then$new$
    );
  ELSIF position($new$  if p_action = 'move_hand_card_to_evidence' then$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: hand-to-evidence insertion anchor did not match';
  END IF;

  -- Allow the owner to retrieve their evidence card into hand (face-up or face-down).
  IF position($old$  -- Move an already face-up evidence card to its owner's deck bottom, without regard to whose turn it is.$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$  -- Move an already face-up evidence card to its owner's deck bottom, without regard to whose turn it is.$old$,
      $new$  if p_action = 'move_evidence_to_hand' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    if v_owner_id <> v_user then raise exception '자신의 증거만 손패로 가져올 수 있습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '증거 에이리어에서 해당 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_id),'[]'::jsonb)
      into v_files_new
      from jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs
      set evidence_cards=v_files_new,
          hand=coalesce(gs.hand,'[]'::jsonb)||jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up' - 'host_instance_id' - 'set_owner_user_id'),
          updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b set evidence_count=greatest(0,coalesce(b.evidence_count,0)-1),updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,
      last_action_label='증거 카드 1장을 손패로 가져왔습니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Move an already face-up evidence card to its owner's deck bottom, without regard to whose turn it is.$new$
    );
  ELSIF position($new$  if p_action = 'move_evidence_to_hand' then$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: evidence-to-hand insertion anchor did not match';
  END IF;

  -- Replace the original contact target with a disguise character from the defending player's hand.
  IF position($old$  if p_action = 'guard_contact_with_character' then$old$ in v_definition) > 0 THEN
    v_definition := replace(
      v_definition,
      $old$  if p_action = 'guard_contact_with_character' then$old$,
      $new$  if p_action = 'contact_use_disguise' then
    if v_match.pending_action ->> 'type' is distinct from 'character_contact_guard'
       or v_match.pending_action ->> 'target_user_id' is distinct from v_user::text then
      raise exception '현재 컨택 대상 플레이어만 변장을 선택할 수 있습니다.';
    end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id and coalesce(e.value ->> 'card_type','')='character';
    if v_card is null then raise exception '손패에서 변장할 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce(
      nullif(v_card ->> 'disguiseEffect',''),
      nullif(v_card ->> 'disguise_effect',''),
      nullif(v_card ->> 'hensoEffect',''),
      nullif(v_card ->> 'henso',''),
      nullif(v_card #>> '{gameSystemEffects,disguise}',''),
      nullif(v_card #>> '{sourceData,henso}','')
    ) is null then
      raise exception '변장 효과가 있는 캐릭터를 선택해 주세요.';
    end if;

    v_id := v_match.pending_action ->> 'target_instance_id';
    select e.value into v_target
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id and coalesce(e.value ->> 'card_type','')='character';
    if v_target is null then raise exception '교체할 컨택 대상 캐릭터를 찾을 수 없습니다.'; end if;

    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from (v_card ->> 'instance_id')),'[]'::jsonb)
      into v_hand_new
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from (v_target ->> 'instance_id')),'[]'::jsonb)
      into v_field_new
      from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    v_field_new := coalesce(v_field_new,'[]'::jsonb) || jsonb_build_array(
      (v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up' - 'set_owner_user_id' - 'host_instance_id')
      || jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',false)
    );

    update public.room_player_game_states gs
      set hand=v_hand_new,
          deck_order=coalesce(gs.deck_order,'[]'::jsonb)||jsonb_build_array(v_target - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'),
          updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b set field_cards=v_field_new,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;

    v_pending := jsonb_set(v_match.pending_action,'{disguised_original_target_instance_id}',to_jsonb(v_target ->> 'instance_id'));
    v_pending := jsonb_set(v_pending,'{target_instance_id}',to_jsonb(v_card ->> 'instance_id'));
    v_pending := jsonb_set(v_pending,'{target_ap}',to_jsonb(coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0)));
    v_pending := jsonb_set(v_pending,'{type}',to_jsonb('character_contact'::text));
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_user::text));
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,
      last_action_label=format('변장: %s가 컨택 대상 대신 등장했고, 기존 대상은 덱 맨 아래로 이동했습니다.',coalesce(v_card ->> 'key','캐릭터'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'guard_contact_with_character' then$new$
    );
  ELSIF position($new$  if p_action = 'contact_use_disguise' then$new$ in v_definition) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: contact disguise insertion anchor did not match';
  END IF;

  -- Ensure the current definition still contains the function terminator before replacing it.
  IF position($function$end;
$function$ in lower(v_definition)) = 0 THEN
    RAISE EXCEPTION 'v8 migration stopped: function terminator not found';
  END IF;

  EXECUTE v_definition;
END
$match_v8$;
