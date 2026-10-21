-- Fix private-zone RPCs, cut-in selection, one-MR-per-player rule, and Culprits' Crime verification.
-- Privileged functions validate room participation and are executable only by authenticated users.

CREATE OR REPLACE FUNCTION public.move_private_evidence_to_deck_top_v1(
  p_room_id uuid, p_owner_user_id uuid, p_instance_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $move_private_evidence_to_deck_top_v1$
DECLARE
  v_user uuid := auth.uid();
  v_game public.room_player_game_states%ROWTYPE;
  v_board public.room_player_turn_boards%ROWTYPE;
  v_card jsonb;
  v_evidence_new jsonb;
  v_deck_card jsonb;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user
  ) THEN RAISE EXCEPTION '이 방의 참가자만 증거 카드를 이동할 수 있습니다.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id
  ) THEN RAISE EXCEPTION '증거 카드 소유자의 방 참가 정보를 찾을 수 없습니다.'; END IF;

  SELECT * INTO v_game FROM public.room_player_game_states
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '증거 카드 소유자의 덱 상태를 찾을 수 없습니다.'; END IF;
  SELECT * INTO v_board FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '증거 카드 소유자의 턴 보드를 찾을 수 없습니다.'; END IF;

  SELECT e.value INTO v_card
    FROM jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) e(value)
    WHERE e.value ->> 'instance_id'=p_instance_id;
  IF v_card IS NULL THEN RAISE EXCEPTION '선택한 증거 카드를 찾을 수 없습니다.'; END IF;

  SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
    FILTER (WHERE e.value ->> 'instance_id' IS DISTINCT FROM p_instance_id),'[]'::jsonb)
    INTO v_evidence_new
    FROM jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality);

  v_deck_card := v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus'
    - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id';

  UPDATE public.room_player_game_states
    SET evidence_cards=v_evidence_new,
        deck_order=jsonb_build_array(v_deck_card)||coalesce(deck_order,'[]'::jsonb),
        updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_player_turn_boards
    SET evidence_count=jsonb_array_length(coalesce(v_evidence_new,'[]'::jsonb)),updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_match_states
    SET state_version=state_version+1,last_action_label='증거 카드 1장을 소유자의 덱 맨 위로 이동했습니다.'
    WHERE room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$move_private_evidence_to_deck_top_v1$;

REVOKE ALL ON FUNCTION public.move_private_evidence_to_deck_top_v1(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_private_evidence_to_deck_top_v1(uuid,uuid,text) TO authenticated;


CREATE OR REPLACE FUNCTION public.move_private_mr_partner_to_zone_v1(
  p_room_id uuid, p_owner_user_id uuid, p_instance_id text, p_destination text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $move_private_mr_partner_to_zone_v1$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_game public.room_player_game_states%ROWTYPE;
  v_card jsonb;
  v_clean_card jsonb;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user
  ) THEN RAISE EXCEPTION '이 방의 참가자만 MR 파트너 카드를 이동할 수 있습니다.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id
  ) THEN RAISE EXCEPTION 'MR 소유자의 방 참가 정보를 찾을 수 없습니다.'; END IF;
  IF p_destination NOT IN ('hand','deck','remove') THEN
    RAISE EXCEPTION '지원하지 않는 MR 이동 위치입니다.';
  END IF;

  SELECT * INTO v_board FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 파트너 보드를 찾을 수 없습니다.'; END IF;
  v_card := v_board.partner_mr_card;
  IF v_card IS NULL OR v_card ->> 'instance_id' IS DISTINCT FROM p_instance_id THEN
    RAISE EXCEPTION 'MR 파트너 영역에서 선택한 카드를 찾을 수 없습니다.';
  END IF;
  SELECT * INTO v_game FROM public.room_player_game_states
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 카드 영역을 찾을 수 없습니다.'; END IF;

  v_clean_card := v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus'
    - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id';
  IF p_destination='hand' THEN
    UPDATE public.room_player_game_states
      SET hand=coalesce(hand,'[]'::jsonb)||jsonb_build_array(v_clean_card),updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  ELSIF p_destination='deck' THEN
    UPDATE public.room_player_game_states
      SET deck_order=coalesce(deck_order,'[]'::jsonb)||jsonb_build_array(v_clean_card),updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  ELSE
    UPDATE public.room_player_game_states
      SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_clean_card),updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
    UPDATE public.room_player_turn_boards
      SET remove_count=coalesce(remove_count,0)+1,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  END IF;
  UPDATE public.room_player_turn_boards SET partner_mr_card=NULL,updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_match_states SET state_version=state_version+1,
    last_action_label=CASE p_destination
      WHEN 'hand' THEN 'MR 파트너 카드를 소유자의 손패로 수동 이동했습니다.'
      WHEN 'deck' THEN 'MR 파트너 카드를 소유자의 덱 맨 아래로 수동 이동했습니다.'
      ELSE 'MR 파트너 카드를 리무브 에이리어로 수동 이동했습니다.'
    END
    WHERE room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$move_private_mr_partner_to_zone_v1$;

REVOKE ALL ON FUNCTION public.move_private_mr_partner_to_zone_v1(uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_private_mr_partner_to_zone_v1(uuid,uuid,text,text) TO authenticated;


-- A newly-entered MR takes the exclusive MR slot across both the field and MR partner area.
-- Legacy field/partner cards whose JSON omitted rarity are checked against the submitted deck metadata.
CREATE OR REPLACE FUNCTION public.remove_replaced_mr_partner_on_new_mr_v2(
  p_room_id uuid, p_owner_user_id uuid, p_new_field_mr_instance_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $remove_replaced_mr_partner_on_new_mr_v2$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_game public.room_player_game_states%ROWTYPE;
  v_new_mr jsonb;
  v_deck_cards jsonb := '[]'::jsonb;
  v_new_rarity text;
  v_old_field_mrs jsonb := '[]'::jsonb;
  v_field_new jsonb := '[]'::jsonb;
  v_clean_removed jsonb := '[]'::jsonb;
  v_partner_card jsonb;
  v_partner_is_mr boolean := false;
  v_remove_new jsonb;
  v_removed_count integer := 0;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user
  ) THEN RAISE EXCEPTION '이 방의 참가자만 MR 에이리어를 갱신할 수 있습니다.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id
  ) THEN RAISE EXCEPTION 'MR 소유자의 방 참가 정보를 찾을 수 없습니다.'; END IF;

  SELECT * INTO v_board FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 턴 보드를 찾을 수 없습니다.'; END IF;
  SELECT main_deck INTO v_deck_cards FROM public.room_player_decks
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;

  SELECT e.value INTO v_new_mr
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE e.value ->> 'instance_id'=p_new_field_mr_instance_id;
  IF v_new_mr IS NULL THEN RETURN public.get_private_turn_state_v2(p_room_id); END IF;

  SELECT coalesce(nullif(upper(trim(v_new_mr ->> 'rarity')),''),
    (SELECT upper(nullif(trim(d.value ->> 'rarity'),''))
      FROM jsonb_array_elements(coalesce(v_deck_cards,'[]'::jsonb)) d(value)
      WHERE d.value ->> 'key'=v_new_mr ->> 'key' LIMIT 1))
    INTO v_new_rarity;
  IF v_new_rarity IS DISTINCT FROM 'MR' THEN
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;

  SELECT * INTO v_game FROM public.room_player_game_states
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 카드 영역을 찾을 수 없습니다.'; END IF;

  SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
    FILTER (
      WHERE e.value ->> 'instance_id' IS DISTINCT FROM p_new_field_mr_instance_id
        AND coalesce(nullif(upper(trim(e.value ->> 'rarity')),''),
          (SELECT upper(nullif(trim(d.value ->> 'rarity'),''))
            FROM jsonb_array_elements(coalesce(v_deck_cards,'[]'::jsonb)) d(value)
            WHERE d.value ->> 'key'=e.value ->> 'key' LIMIT 1))='MR'
    ),'[]'::jsonb)
    INTO v_old_field_mrs
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality);

  SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
    FILTER (WHERE NOT (
      e.value ->> 'instance_id' IS DISTINCT FROM p_new_field_mr_instance_id
      AND coalesce(nullif(upper(trim(e.value ->> 'rarity')),''),
        (SELECT upper(nullif(trim(d.value ->> 'rarity'),''))
          FROM jsonb_array_elements(coalesce(v_deck_cards,'[]'::jsonb)) d(value)
          WHERE d.value ->> 'key'=e.value ->> 'key' LIMIT 1))='MR'
    )),'[]'::jsonb)
    INTO v_field_new
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality);

  v_partner_card := v_board.partner_mr_card;
  IF v_partner_card IS NOT NULL AND coalesce(v_partner_card ->> 'instance_id','')<>'' THEN
    v_new_rarity := coalesce(nullif(upper(trim(v_partner_card ->> 'rarity')),''),
      (SELECT upper(nullif(trim(d.value ->> 'rarity'),''))
        FROM jsonb_array_elements(coalesce(v_deck_cards,'[]'::jsonb)) d(value)
        WHERE d.value ->> 'key'=v_partner_card ->> 'key' LIMIT 1));
    v_partner_is_mr := v_new_rarity='MR';
    IF v_partner_is_mr
       AND v_partner_card ->> 'instance_id' IS DISTINCT FROM p_new_field_mr_instance_id THEN
      v_clean_removed := v_clean_removed || jsonb_build_array(
        v_partner_card - 'face_up' - 'rested' - 'status' - 'ap_bonus'
          - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id'
      );
    END IF;
  END IF;

  SELECT coalesce(jsonb_agg(
    e.value - 'face_up' - 'rested' - 'status' - 'ap_bonus'
      - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id'
    ORDER BY e.ordinality
  ),'[]'::jsonb)
    INTO v_old_field_mrs
    FROM jsonb_array_elements(coalesce(v_old_field_mrs,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality);

  v_clean_removed := v_clean_removed || coalesce(v_old_field_mrs,'[]'::jsonb);
  v_removed_count := jsonb_array_length(coalesce(v_clean_removed,'[]'::jsonb));
  IF v_removed_count=0 AND NOT v_partner_is_mr THEN
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;

  v_remove_new := coalesce(v_game.remove_cards,'[]'::jsonb) || coalesce(v_clean_removed,'[]'::jsonb);
  UPDATE public.room_player_game_states
    SET remove_cards=v_remove_new,updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_player_turn_boards
    SET field_cards=v_field_new,
        partner_mr_card=CASE WHEN v_partner_is_mr THEN NULL ELSE partner_mr_card END,
        remove_count=coalesce(remove_count,0)+v_removed_count,
        updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_match_states
    SET state_version=state_version+1,
        last_action_label=format(
          '새 MR %s가 현장에 등장하여 기존 MR %s장을 리무브 에이리어로 이동했습니다.',
          coalesce(v_new_mr ->> 'key','카드'),v_removed_count
        )
    WHERE room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$remove_replaced_mr_partner_on_new_mr_v2$;

REVOKE ALL ON FUNCTION public.remove_replaced_mr_partner_on_new_mr_v2(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_replaced_mr_partner_on_new_mr_v2(uuid,uuid,text) TO authenticated;


-- Patch the live game-action function without discarding the previously installed gameplay rules.
DO $patch_culprits_crime_and_cutins$
DECLARE
  v_definition text;
  v_original text;
  v_old text;
  v_new text;
  v_start integer;
  v_end integer;
  v_action_block text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition,chr(13),'');
  v_original := v_definition;

  v_old := '(''character_contact_guard'', ''character_contact'', ''mislead_response'', ''evidence_attack_reveal'', ''evidence_attack'', ''deck_remove_reveal'', ''file_remove_reveal'')';
  v_new := '(''character_contact_guard'', ''character_contact'', ''mislead_response'', ''evidence_attack_reveal'', ''evidence_attack'', ''deck_remove_reveal'', ''file_remove_reveal'', ''culprits_crime_reveal'')';
  IF position(v_old in v_definition)=0 THEN RAISE EXCEPTION 'Culprits review patch stopped: pending-action type guard was not found.'; END IF;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := '''acknowledge_deck_remove'',''acknowledge_file_remove'',''acknowledge_hand_reveal'') then';
  v_new := '''acknowledge_deck_remove'',''acknowledge_file_remove'',''acknowledge_hand_reveal'',''acknowledge_culprits_crime'') then';
  IF position(v_old in v_definition)=0 THEN RAISE EXCEPTION 'Culprits review patch stopped: pending-action allowlist was not found.'; END IF;
  v_definition := replace(v_definition,v_old,v_new);

  v_old := '''guard_with_character'',''decline_guard'',''acknowledge_deck_remove'',''acknowledge_file_remove'') then';
  v_new := '''guard_with_character'',''decline_guard'',''acknowledge_deck_remove'',''acknowledge_file_remove'',''acknowledge_culprits_crime'') then';
  IF position(v_old in v_definition)=0 THEN RAISE EXCEPTION 'Culprits review patch stopped: no-pending response allowlist was not found.'; END IF;
  v_definition := replace(v_definition,v_old,v_new);

  v_start := position('if p_action = ''culprits_crime'' then' in lower(v_definition));
  v_end := position('if p_action = ''begin_turn'' then' in lower(v_definition));
  IF v_start=0 OR v_end<=v_start THEN RAISE EXCEPTION 'Culprits review patch stopped: existing Culprits'' Crime action block was not found.'; END IF;

  v_action_block := $culprits_actions$
  if p_action = 'acknowledge_culprits_crime' then
    if v_match.pending_action is null or v_match.pending_action ->> 'type' <> 'culprits_crime_reveal' then
      raise exception '확인할 범인들의 범행 증거 공개가 없습니다.';
    end if;
    v_shared_ids := coalesce(v_match.pending_action -> 'acknowledged_user_ids','[]'::jsonb);
    if exists (select 1 from jsonb_array_elements_text(v_shared_ids) acknowledged(user_id) where acknowledged.user_id=v_user::text) then
      raise exception '이미 범인들의 범행 증거 공개를 확인했습니다.';
    end if;
    v_shared_ids := v_shared_ids || jsonb_build_array(v_user::text);
    if jsonb_array_length(v_shared_ids)<2 then
      update public.room_match_states m
        set pending_action=jsonb_set(v_match.pending_action,'{acknowledged_user_ids}',v_shared_ids,true),
            state_version=state_version+1,
            last_action_label='한 플레이어가 범인들의 범행 증거를 확인했습니다. 다른 플레이어의 확인을 기다립니다.'
        where m.room_id=p_room_id;
      return public.get_private_turn_state_v2(p_room_id);
    end if;

    v_owner_id := nullif(v_match.pending_action ->> 'initiator_user_id','')::uuid;
    if v_owner_id is null or not exists (select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_owner_id) then
      raise exception '범인들의 범행 선언 플레이어를 찾을 수 없습니다.';
    end if;
    select * into v_game from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_owner_id for update;
    if not found then raise exception '범인들의 범행 선언 플레이어의 증거 데이터를 찾을 수 없습니다.'; end if;

    select count(*)::integer into v_culprit_count
    from jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) evidence(value)
    where exists (
      select 1 from jsonb_array_elements_text(
        case when jsonb_typeof(evidence.value -> 'traits')='array'
          then evidence.value -> 'traits' else '[]'::jsonb end
      ) trait(value)
      where lower(trim(trait.value))='범인'
         or (position('특징' in trait.value)>0 and position('범인' in trait.value)>0)
    );

    if v_culprit_count>=8 then
      delete from public.room_hand_reveals r where r.room_id=p_room_id;
      update public.room_match_states m set
        pending_action=null,game_over=true,winner_user_id=v_owner_id,winner_turn_number=m.turn_number,
        end_display_names=coalesce(m.end_display_names,(
          select jsonb_object_agg(rp.user_id::text,coalesce(nullif(rp.temporary_nickname,''),'플레이어 '||rp.seat::text))
          from public.room_players rp where rp.room_id=p_room_id
        )),
        state_version=state_version+1,
        last_action_label=format('범인들의 범행 성공! 특징 [범인] 증거 %s장으로 승리했습니다.',v_culprit_count)
      where m.room_id=p_room_id;
    else
      update public.room_match_states m set
        pending_action=null,state_version=state_version+1,
        last_action_label=format('범인들의 범행 확인 결과 특징 [범인] 증거가 %s장으로 8장 미만입니다. 게임을 계속합니다.',v_culprit_count)
      where m.room_id=p_room_id;
    end if;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'culprits_crime' then
    if v_match.current_turn_user_id is distinct from v_user then
      raise exception '범인들의 범행은 본인 턴에서만 선언할 수 있습니다.';
    end if;
    if coalesce(v_match.turn_step,'')<>'main' then raise exception '범인들의 범행은 메인 단계에서만 선언할 수 있습니다.'; end if;
    if coalesce(v_board.case_phase,'incident')<>'solution' then raise exception '해결편에서만 범인들의 범행을 선언할 수 있습니다.'; end if;
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    if coalesce(v_board.partner_rested,false) OR coalesce(v_board.partner_assist_used,false) then
      raise exception '파트너가 행동하기 전인 상태에서만 범인들의 범행을 선언할 수 있습니다.';
    end if;

    v_culprit_key := regexp_replace(coalesce(v_board.event_key,''),'[^0-9]','','g');
    if coalesce(v_board.event_rule_code,'')<>'culprits_1046'
       and coalesce(nullif(ltrim(v_culprit_key,'0'),''),'0')<>'1046' then
      raise exception '사건 카드 ID 1046을 선택한 플레이어만 사용할 수 있습니다.';
    end if;
    if jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))<8 then
      raise exception '범인들의 범행을 선언하려면 증거가 8장 이상 필요합니다. 현재 %장입니다.',
        jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb));
    end if;

    v_remove_new := coalesce(v_game.remove_cards,'[]'::jsonb)||coalesce(v_game.deck_order,'[]'::jsonb);
    select coalesce(jsonb_agg(e.value||jsonb_build_object('face_up',true) order by e.ordinality),'[]'::jsonb)
      into v_evidence_cards
      from jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);

    update public.room_player_game_states gs
      set deck_order='[]'::jsonb,remove_cards=v_remove_new,evidence_cards=v_evidence_cards,updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b
      set remove_count=jsonb_array_length(coalesce(v_remove_new,'[]'::jsonb)),
          evidence_count=jsonb_array_length(coalesce(v_evidence_cards,'[]'::jsonb)),updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;

    update public.room_match_states m set
      pending_action=jsonb_build_object(
        'type','culprits_crime_reveal','initiator_user_id',v_user::text,
        'revealed_evidence_cards',v_evidence_cards,'acknowledged_user_ids','[]'::jsonb
      ),
      state_version=state_version+1,
      last_action_label=format('범인들의 범행 선언: 덱의 남은 카드 %s장을 리무브로 이동하고 증거 %s장을 모두 공개했습니다. 양쪽 플레이어가 특징 [범인] 수를 확인합니다.',
        jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)),jsonb_array_length(coalesce(v_evidence_cards,'[]'::jsonb)))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

$culprits_actions$;

  v_definition := substring(v_definition from 1 for v_start-1)||v_action_block||substring(v_definition from v_end);
  IF v_definition IS NOT DISTINCT FROM v_original THEN RAISE EXCEPTION 'Culprits/cutin function patch made no changes.'; END IF;

  v_old := $cutin_old$if v_bonus < 1 then raise exception '이 카드는 컷인 AP 보너스가 없습니다.'; end if;$cutin_old$;
  v_new := $cutin_new$if v_bonus < 1 and nullif(trim(v_card ->> 'cut_in_effect'),'') is null then raise exception '컷인 효과가 기록되지 않은 카드입니다.'; end if;$cutin_new$;
  IF position(v_old in v_definition)=0 THEN RAISE EXCEPTION 'Cut-in patch stopped: AP-only validation was not found.'; END IF;
  v_definition := replace(v_definition,v_old,v_new);

  EXECUTE v_definition;
  REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated;
END;
$patch_culprits_crime_and_cutins$;
