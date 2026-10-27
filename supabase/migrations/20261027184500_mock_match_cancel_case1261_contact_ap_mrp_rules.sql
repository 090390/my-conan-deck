ALTER TABLE public.room_match_states
  ADD COLUMN IF NOT EXISTS cancel_requested_by uuid[] NOT NULL DEFAULT '{}'::uuid[];

CREATE OR REPLACE FUNCTION public.clear_private_field_mr_for_deployment(p_room_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_field jsonb;
  v_partner jsonb;
  v_deck jsonb := '[]'::jsonb;
  v_remaining jsonb := '[]'::jsonb;
  v_removed jsonb := '[]'::jsonb;
  v_partner_rarity text;
  v_count integer := 0;
BEGIN
  SELECT b.field_cards, b.partner_mr_card INTO v_field, v_partner
  FROM public.room_player_turn_boards b
  WHERE b.room_id = p_room_id AND b.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR/MRP 교체를 위한 보드 상태를 찾을 수 없습니다.'; END IF;

  SELECT coalesce(d.main_deck, '[]'::jsonb) INTO v_deck
  FROM public.room_player_decks d
  WHERE d.room_id = p_room_id AND d.user_id = p_user_id;

  WITH classified AS (
    SELECT e.value, e.ordinality,
      coalesce(
        nullif(upper(trim(e.value ->> 'rarity')), ''),
        nullif(upper(trim(e.value ->> 'rarity_code')), ''),
        nullif(upper(trim(e.value ->> 'rarityCode')), ''),
        nullif(upper(trim(e.value #>> '{sourceData,rarity}')), ''),
        nullif(upper(trim(e.value #>> '{raw,rarity}')), ''),
        (SELECT upper(nullif(trim(d.value ->> 'rarity'), ''))
         FROM jsonb_array_elements(coalesce(v_deck, '[]'::jsonb)) d(value)
         WHERE d.value ->> 'key' = e.value ->> 'key' LIMIT 1)
      ) AS resolved_rarity
    FROM jsonb_array_elements(coalesce(v_field, '[]'::jsonb)) WITH ORDINALITY e(value, ordinality)
  )
  SELECT
    coalesce(jsonb_agg(c.value ORDER BY c.ordinality) FILTER (WHERE coalesce(c.resolved_rarity, '') NOT IN ('MR','MRP')), '[]'::jsonb),
    coalesce(jsonb_agg(c.value - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' ORDER BY c.ordinality)
      FILTER (WHERE c.resolved_rarity IN ('MR','MRP')), '[]'::jsonb)
  INTO v_remaining, v_removed
  FROM classified c;

  v_partner_rarity := coalesce(
    nullif(upper(trim(v_partner ->> 'rarity')), ''),
    nullif(upper(trim(v_partner ->> 'rarity_code')), ''),
    nullif(upper(trim(v_partner ->> 'rarityCode')), ''),
    nullif(upper(trim(v_partner #>> '{sourceData,rarity}')), ''),
    nullif(upper(trim(v_partner #>> '{raw,rarity}')), ''),
    (SELECT upper(nullif(trim(d.value ->> 'rarity'), ''))
      FROM jsonb_array_elements(coalesce(v_deck, '[]'::jsonb)) d(value)
      WHERE d.value ->> 'key' = v_partner ->> 'key' LIMIT 1)
  );

  IF v_partner IS NOT NULL AND v_partner_rarity IN ('MR','MRP') THEN
    v_removed := coalesce(v_removed, '[]'::jsonb) ||
      jsonb_build_array(v_partner - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving');
  END IF;

  v_count := jsonb_array_length(coalesce(v_removed, '[]'::jsonb));
  UPDATE public.room_player_turn_boards b
  SET field_cards = coalesce(v_remaining, '[]'::jsonb),
      partner_mr_card = CASE WHEN v_partner_rarity IN ('MR','MRP') THEN NULL ELSE v_partner END,
      remove_count = coalesce(b.remove_count, 0) + v_count,
      updated_at = now()
  WHERE b.room_id = p_room_id AND b.user_id = p_user_id;

  IF v_count > 0 THEN
    UPDATE public.room_player_game_states gs
    SET remove_cards = coalesce(gs.remove_cards, '[]'::jsonb) || v_removed,
        updated_at = now()
    WHERE gs.room_id = p_room_id AND gs.user_id = p_user_id;
  END IF;
END;
$function$;

DO $patch$
DECLARE
  v_definition text;
BEGIN
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  v_definition := replace(v_definition,
    $old$upper(coalesce(v_card ->> 'rarity', '')) = 'MR'$old$,
    $new$upper(coalesce(v_card ->> 'rarity', '')) IN ('MR','MRP')$new$);
  v_definition := replace(v_definition,
    $old$upper(coalesce(e.value ->> 'rarity', '')) = 'MR'$old$,
    $new$upper(coalesce(e.value ->> 'rarity', '')) IN ('MR','MRP')$new$);
  v_definition := replace(v_definition,
    $old$upper(coalesce(field_card.value ->> 'rarity','')) = 'MR'$old$,
    $new$upper(coalesce(field_card.value ->> 'rarity','')) IN ('MR','MRP')$new$);
  v_definition := replace(v_definition,
    $old$p_payload ->> 'rarity',''))='MR' then$old$,
    $new$p_payload ->> 'rarity','')) IN ('MR','MRP') then$new$);

  v_definition := replace(v_definition,
    $old$'contact_use_cutin','contact_pass_cutin','contact_use_disguise'$old$,
    $new$'contact_adjust_ap','contact_use_cutin','contact_pass_cutin','contact_use_disguise'$new$);
  IF position('if p_action = ''contact_adjust_ap'' then' in v_definition) = 0 THEN
    IF position('if p_action = ''contact_use_cutin'' then' in v_definition) = 0 THEN
      RAISE EXCEPTION 'contact_use_cutin action block not found; refusing incomplete AP adjustment migration';
    END IF;
    v_definition := replace(v_definition,
      $old$if p_action = 'contact_use_cutin' then$old$,
      $new$if p_action = 'contact_adjust_ap' then
    if v_match.pending_action is null
       or v_match.pending_action ->> 'type' is distinct from 'character_contact'
       or v_match.pending_action ->> 'next_responder_user_id' is distinct from v_user::text then
      raise exception '현재 컨택 응답 차례에서만 AP를 조정할 수 있습니다.';
    end if;
    v_amount := coalesce(nullif(p_payload ->> 'amount','')::integer, 0);
    if v_amount = 0 or abs(v_amount) > 100000 then
      raise exception 'AP 변화량은 1~100000 사이의 정수로 지정해 주세요.';
    end if;
    v_pending := v_match.pending_action;
    if v_user::text = v_pending ->> 'attacker_user_id' then
      v_bonus := coalesce(nullif(v_pending ->> 'attacker_bonus','')::integer, 0) + v_amount;
      if abs(v_bonus) > 1000000 then raise exception '컨택 AP 변경 총합이 허용 범위를 벗어났습니다.'; end if;
      v_pending := jsonb_set(v_pending, '{attacker_bonus}', to_jsonb(v_bonus), true);
    elsif v_user::text = v_pending ->> 'target_user_id' then
      v_bonus := coalesce(nullif(v_pending ->> 'target_bonus','')::integer, 0) + v_amount;
      if abs(v_bonus) > 1000000 then raise exception '컨택 AP 변경 총합이 허용 범위를 벗어났습니다.'; end if;
      v_pending := jsonb_set(v_pending, '{target_bonus}', to_jsonb(v_bonus), true);
    else
      raise exception '현재 컨택의 공격자 또는 수비자만 AP를 조정할 수 있습니다.';
    end if;
    update public.room_match_states m
      set pending_action = v_pending,
          state_version = state_version + 1,
          last_action_label = format('컨택 중 수동 AP 조정: 변화량 %s', v_amount)
      where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'contact_use_cutin' then$new$);
  END IF;

  IF position('v_count := case when v_match.first_player_user_id=v_user then 7 else 6 end;' in v_definition) = 0 THEN
    RAISE EXCEPTION 'solve_case evidence threshold not found; refusing incomplete case exception migration';
  END IF;
  v_definition := replace(v_definition,
    $old$v_count := case when v_match.first_player_user_id=v_user then 7 else 6 end;$old$,
    $new$v_count := case
      when coalesce(v_board.event_rule_code, '') = 'conan_vs_kid_1261'
        or coalesce(nullif(ltrim(v_culprit_key, '0'), ''), '0') in ('1261','11098')
        then case when v_match.first_player_user_id=v_user then 8 else 7 end
      else case when v_match.first_player_user_id=v_user then 7 else 6 end
    end;$new$);

  EXECUTE v_definition;

  v_definition := pg_get_functiondef('public.get_private_turn_state_v2(uuid)'::regprocedure);
  IF position('cancel_requested_by' in v_definition) = 0 THEN
    IF position($old$'my_role', case when (v_result ->> 'first_player_user_id') = v_user::text then 'first' else 'second' end$old$ in v_definition) = 0 THEN
      RAISE EXCEPTION 'get_private_turn_state_v2 output tail not found; refusing incomplete cancel state migration';
    END IF;
    v_definition := replace(v_definition,
      $old$'my_role', case when (v_result ->> 'first_player_user_id') = v_user::text then 'first' else 'second' end$old$,
      $new$'my_role', case when (v_result ->> 'first_player_user_id') = v_user::text then 'first' else 'second' end,
    'cancel_requested_by', to_jsonb(coalesce((select m.cancel_requested_by from public.room_match_states m where m.room_id = p_room_id), '{}'::uuid[])),
    'cancel_vote_count', cardinality(coalesce((select m.cancel_requested_by from public.room_match_states m where m.room_id = p_room_id), '{}'::uuid[])),
    'cancelled', coalesce((select m.game_over and m.winner_user_id is null and m.last_action_label like '모의전 취소 완료:%' from public.room_match_states m where m.room_id = p_room_id), false)$new$);
    EXECUTE v_definition;
  END IF;
END;
$patch$;

DO $patch$
DECLARE v_definition text;
BEGIN
  v_definition := pg_get_functiondef('public.remove_replaced_mr_partner_on_new_mr_v2(uuid,uuid,text)'::regprocedure);
  v_definition := replace(v_definition,
    $old$IF v_new_rarity IS DISTINCT FROM 'MR' THEN$old$,
    $new$IF coalesce(v_new_rarity, '') NOT IN ('MR','MRP') THEN$new$);
  v_definition := replace(v_definition, $old$))='MR'$old$, $new$)) IN ('MR','MRP')$new$);
  v_definition := replace(v_definition,
    $old$v_partner_is_mr := v_new_rarity='MR';$old$,
    $new$v_partner_is_mr := v_new_rarity IN ('MR','MRP');$new$);
  EXECUTE v_definition;
END;
$patch$;

DO $patch$
DECLARE v_definition text;
BEGIN
  v_definition := pg_get_functiondef('public.move_private_field_mr_to_partner_v2(uuid,uuid,text,text)'::regprocedure);
  v_definition := replace(v_definition,
    $old$v_stored_rarity := upper(nullif(trim(v_card ->> 'rarity'),''));$old$,
    $new$v_stored_rarity := coalesce(
      nullif(upper(trim(v_card ->> 'rarity')),''),
      nullif(upper(trim(v_card ->> 'rarity_code')),''),
      nullif(upper(trim(v_card ->> 'rarityCode')),''),
      nullif(upper(trim(v_card #>> '{sourceData,rarity}')),''),
      nullif(upper(trim(v_card #>> '{raw,rarity}')),'')
    );$new$);
  v_definition := replace(v_definition,
    $old$IF upper(coalesce(trim(p_card_rarity),'')) <> 'MR'$old$,
    $new$IF upper(coalesce(trim(p_card_rarity),'')) NOT IN ('MR','MRP')$new$);
  v_definition := replace(v_definition,
    $old$(v_stored_rarity IS NOT NULL AND v_stored_rarity <> 'MR')$old$,
    $new$(v_stored_rarity IS NOT NULL AND v_stored_rarity NOT IN ('MR','MRP'))$new$);
  EXECUTE v_definition;
END;
$patch$;

CREATE OR REPLACE FUNCTION public.resolve_private_character_contact(p_room_id uuid, p_pending jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_attacker_user uuid := (p_pending ->> 'attacker_user_id')::uuid;
  v_target_user uuid := (p_pending ->> 'target_user_id')::uuid;
  v_attacker_id text := p_pending ->> 'attacker_instance_id';
  v_target_id text := p_pending ->> 'target_instance_id';
  v_attacker_board public.room_player_turn_boards%ROWTYPE;
  v_target_board public.room_player_turn_boards%ROWTYPE;
  v_attacker_card jsonb;
  v_target_card jsonb;
  v_attacker_field_new jsonb;
  v_target_field_new jsonb;
  v_clean_target jsonb;
  v_prior_partner jsonb;
  v_attacker_rarity text;
  v_target_rarity text;
  v_attacker_ap numeric;
  v_target_ap numeric;
  v_attacker_wins boolean;
  v_label text;
BEGIN
  SELECT * INTO v_attacker_board FROM public.room_player_turn_boards b
  WHERE b.room_id = p_room_id AND b.user_id = v_attacker_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '공격자의 컨택 보드를 찾을 수 없습니다.'; END IF;

  SELECT * INTO v_target_board FROM public.room_player_turn_boards b
  WHERE b.room_id = p_room_id AND b.user_id = v_target_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '수비자의 컨택 보드를 찾을 수 없습니다.'; END IF;

  SELECT e.value INTO v_attacker_card
  FROM jsonb_array_elements(coalesce(v_attacker_board.field_cards, '[]'::jsonb)) e(value)
  WHERE e.value ->> 'instance_id' = v_attacker_id;
  SELECT e.value INTO v_target_card
  FROM jsonb_array_elements(coalesce(v_target_board.field_cards, '[]'::jsonb)) e(value)
  WHERE e.value ->> 'instance_id' = v_target_id;
  IF v_attacker_card IS NULL OR v_target_card IS NULL THEN
    RAISE EXCEPTION '컨택 도중 공격자 또는 대상 카드가 사라졌습니다.';
  END IF;

  SELECT coalesce(
    nullif(upper(trim(v_attacker_card ->> 'rarity')), ''),
    nullif(upper(trim(v_attacker_card ->> 'rarity_code')), ''),
    nullif(upper(trim(v_attacker_card ->> 'rarityCode')), ''),
    nullif(upper(trim(v_attacker_card #>> '{sourceData,rarity}')), ''),
    nullif(upper(trim(v_attacker_card #>> '{raw,rarity}')), ''),
    (SELECT upper(nullif(trim(d.value ->> 'rarity'), ''))
     FROM public.room_player_decks pd
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(pd.main_deck, '[]'::jsonb)) d(value)
     WHERE pd.room_id = p_room_id AND pd.user_id = v_attacker_user
       AND d.value ->> 'key' = v_attacker_card ->> 'key' LIMIT 1)
  ) INTO v_attacker_rarity;
  SELECT coalesce(
    nullif(upper(trim(v_target_card ->> 'rarity')), ''),
    nullif(upper(trim(v_target_card ->> 'rarity_code')), ''),
    nullif(upper(trim(v_target_card ->> 'rarityCode')), ''),
    nullif(upper(trim(v_target_card #>> '{sourceData,rarity}')), ''),
    nullif(upper(trim(v_target_card #>> '{raw,rarity}')), ''),
    (SELECT upper(nullif(trim(d.value ->> 'rarity'), ''))
     FROM public.room_player_decks pd
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(pd.main_deck, '[]'::jsonb)) d(value)
     WHERE pd.room_id = p_room_id AND pd.user_id = v_target_user
       AND d.value ->> 'key' = v_target_card ->> 'key' LIMIT 1)
  ) INTO v_target_rarity;

  v_attacker_ap := coalesce(nullif(p_pending ->> 'attacker_ap', '')::numeric, 0)
    + coalesce(nullif(p_pending ->> 'attacker_bonus', '')::numeric, 0);
  v_target_ap := coalesce(nullif(p_pending ->> 'target_ap', '')::numeric, 0)
    + coalesce(nullif(p_pending ->> 'target_bonus', '')::numeric, 0);
  v_attacker_wins := v_attacker_ap >= v_target_ap;

  SELECT coalesce(jsonb_agg(
    CASE WHEN e.value ->> 'instance_id' = v_attacker_id
      THEN e.value || jsonb_build_object('rested', true, 'status', 'rested')
      ELSE e.value END ORDER BY e.ordinality
  ), '[]'::jsonb)
  INTO v_attacker_field_new
  FROM jsonb_array_elements(coalesce(v_attacker_board.field_cards, '[]'::jsonb))
    WITH ORDINALITY e(value, ordinality);
  UPDATE public.room_player_turn_boards b
  SET field_cards = v_attacker_field_new, updated_at = now()
  WHERE b.room_id = p_room_id AND b.user_id = v_attacker_user;

  IF v_attacker_wins THEN
    SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
      FILTER (WHERE e.value ->> 'instance_id' IS DISTINCT FROM v_target_id), '[]'::jsonb)
    INTO v_target_field_new
    FROM jsonb_array_elements(coalesce(v_target_board.field_cards, '[]'::jsonb))
      WITH ORDINALITY e(value, ordinality);

    v_clean_target := v_target_card - 'rested' - 'status' - 'ap_bonus'
      - 'summoned_this_turn' - 'resolving' - 'face_up' - 'host_instance_id' - 'set_owner_user_id';

    IF v_target_rarity IN ('MR','MRP') THEN
      v_prior_partner := v_target_board.partner_mr_card;
      IF v_prior_partner IS NOT NULL
         AND coalesce(v_prior_partner ->> 'instance_id', '') <> ''
         AND v_prior_partner ->> 'instance_id' IS DISTINCT FROM v_target_id THEN
        UPDATE public.room_player_game_states gs
        SET remove_cards = coalesce(gs.remove_cards, '[]'::jsonb) ||
          jsonb_build_array(v_prior_partner - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn'
            - 'resolving' - 'face_up' - 'host_instance_id' - 'set_owner_user_id'),
          updated_at = now()
        WHERE gs.room_id = p_room_id AND gs.user_id = v_target_user;
        UPDATE public.room_player_turn_boards b
        SET remove_count = coalesce(b.remove_count, 0) + 1, updated_at = now()
        WHERE b.room_id = p_room_id AND b.user_id = v_target_user;
      END IF;
      UPDATE public.room_player_turn_boards b
      SET field_cards = v_target_field_new,
          partner_mr_card = v_clean_target || jsonb_build_object('rested', false, 'status', 'active', 'ap_bonus', 0, 'summoned_this_turn', false),
          updated_at = now()
      WHERE b.room_id = p_room_id AND b.user_id = v_target_user;
      v_label := format('컨택 성공: 공격자가 AP %s 대 %s로 승리했습니다. 대상 MR/MRP는 MR 파트너 에이리어로 이동했고, 공격자는 슬립 상태가 되었습니다.', v_attacker_ap, v_target_ap);
    ELSE
      UPDATE public.room_player_game_states gs
      SET remove_cards = coalesce(gs.remove_cards, '[]'::jsonb) || jsonb_build_array(v_clean_target),
          updated_at = now()
      WHERE gs.room_id = p_room_id AND gs.user_id = v_target_user;
      UPDATE public.room_player_turn_boards b
      SET field_cards = v_target_field_new,
          remove_count = coalesce(b.remove_count, 0) + 1,
          updated_at = now()
      WHERE b.room_id = p_room_id AND b.user_id = v_target_user;
      v_label := format('컨택 성공: 공격자가 AP %s 대 %s로 승리했습니다. 대상 카드는 리무브되었고, 공격자는 슬립 상태가 되었습니다.', v_attacker_ap, v_target_ap);
    END IF;
  ELSE
    v_label := format('컨택 실패: 공격자가 AP %s 대 %s로 패배했습니다. 대상 카드는 유지되고 공격자는 슬립 상태가 되었습니다.', v_attacker_ap, v_target_ap);
  END IF;

  UPDATE public.room_match_states m
  SET pending_action = NULL, state_version = state_version + 1, last_action_label = v_label
  WHERE m.room_id = p_room_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.vote_private_match_cancel_v1(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_match public.room_match_states%ROWTYPE;
  v_votes uuid[];
  v_player_count integer;
  v_agreed_count integer;
  v_cancelled boolean := false;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.room_players rp WHERE rp.room_id = p_room_id AND rp.user_id = v_user) THEN
    RAISE EXCEPTION '이 방의 참가자만 모의전 취소에 동의할 수 있습니다.';
  END IF;

  SELECT * INTO v_match FROM public.room_match_states m WHERE m.room_id = p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '모의전 상태를 찾을 수 없습니다.'; END IF;

  IF v_match.game_over AND v_match.winner_user_id IS NULL
     AND v_match.last_action_label LIKE '모의전 취소 완료:%' THEN
    RETURN public.get_private_turn_state_v2(p_room_id) ||
      jsonb_build_object('cancelled', true, 'cancel_requested_by', to_jsonb(coalesce(v_match.cancel_requested_by, '{}'::uuid[])),
        'cancel_vote_count', cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])));
  END IF;
  IF v_match.game_over OR v_match.phase IS DISTINCT FROM 'playing' THEN
    RAISE EXCEPTION '진행 중인 모의전만 중도 취소할 수 있습니다.';
  END IF;

  v_votes := coalesce(v_match.cancel_requested_by, '{}'::uuid[]);
  IF NOT (v_user = ANY(v_votes)) THEN v_votes := array_append(v_votes, v_user); END IF;
  SELECT count(*)::integer INTO v_player_count FROM public.room_players rp WHERE rp.room_id = p_room_id;
  SELECT count(*)::integer INTO v_agreed_count
  FROM public.room_players rp WHERE rp.room_id = p_room_id AND rp.user_id = ANY(v_votes);
  v_cancelled := v_player_count = 2 AND v_agreed_count = 2;

  UPDATE public.room_match_states m
  SET cancel_requested_by = v_votes,
      game_over = v_cancelled,
      winner_user_id = CASE WHEN v_cancelled THEN NULL ELSE m.winner_user_id END,
      pending_action = CASE WHEN v_cancelled THEN NULL ELSE m.pending_action END,
      state_version = state_version + 1,
      last_action_label = CASE
        WHEN v_cancelled THEN '모의전 취소 완료: 두 플레이어의 동의로 게임을 중도 종료했습니다.'
        ELSE '모의전 중도 종료 제안: 한 플레이어가 동의했으며 상대 플레이어의 동의를 기다립니다.'
      END
  WHERE m.room_id = p_room_id;

  RETURN public.get_private_turn_state_v2(p_room_id) ||
    jsonb_build_object('cancelled', v_cancelled, 'cancel_requested_by', to_jsonb(v_votes), 'cancel_vote_count', cardinality(v_votes));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.vote_private_match_cancel_v1(uuid) TO authenticated;
