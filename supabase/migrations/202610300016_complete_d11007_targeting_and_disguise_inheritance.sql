CREATE OR REPLACE FUNCTION public.perform_private_turn_action_v2_legacy(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_match record;
  v_board record;
  v_game record;
  v_owner uuid;
  v_card jsonb;
  v_file_top jsonb;
  v_hand_new jsonb;
  v_files_new jsonb;
  v_field_new jsonb;
  v_remove_new jsonb;
  v_deck_new jsonb;
  v_id text;
  v_owner_id uuid;
  v_dest text;
  v_count integer;
  v_i integer;
  v_cost numeric;
  v_cost_limit integer;
  v_label text := '';
  v_old_result jsonb;
  v_opponent_board public.room_player_turn_boards%rowtype;
  v_opponent_game public.room_player_game_states%rowtype;
  v_attacker jsonb;
  v_target jsonb;
  v_pending jsonb;
  v_mr_value integer;
  v_bonus integer;
  v_ap numeric;
  v_target_ap numeric;
  v_amount integer;
  v_status text;
  v_is_mr_partner boolean := false;
  v_is_non_mr_partner boolean := false;
  v_partner_non_mr_new jsonb;
  v_new_status_field jsonb;
  v_evidence_cards jsonb;
  v_instance_order jsonb;
  v_ordered_cards jsonb;
  v_shared_ids jsonb;
  v_source_id uuid;
  v_peek public.room_deck_peeks%rowtype;
  v_other_user uuid;
  v_target_user_id uuid;
  v_target_id text;
  v_attack_id text;
  v_allow_fresh boolean;
  v_hand_reveal_ids jsonb;
  v_hand_reveal_cards jsonb;
  v_culprit_count integer := 0;
  v_deck_size integer := 0;
  v_culprit_key text;
  v_kid_stun_lock boolean := false;
  v_cut_in_subject jsonb;
begin
  if v_user is null then raise exception '로그인이 필요합니다.'; end if;
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then raise exception '행동 데이터 형식이 올바르지 않습니다.'; end if;
  select * into v_match from public.room_match_states m where m.room_id = p_room_id for update;
  if not found then raise exception '먼저 게임을 시작해 주세요.'; end if;
  if not exists (select 1 from public.room_players rp where rp.room_id = p_room_id and rp.user_id = v_user) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  if v_match.phase <> 'playing' or v_match.game_over then raise exception '진행 중인 게임이 아닙니다.'; end if;
  if cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 then
    raise exception '중도 종료 응답 대기 중입니다. 상대가 응답할 때까지 게임이 일시 중지됩니다.';
  end if;
  select * into v_board from public.room_player_turn_boards b where b.room_id = p_room_id and b.user_id = v_user for update;
  if not found then raise exception '자신의 보드 데이터를 찾을 수 없습니다.'; end if;
  select * into v_game from public.room_player_game_states g where g.room_id = p_room_id and g.user_id = v_user for update;
  if not found then raise exception '자신의 게임 데이터를 찾을 수 없습니다.'; end if;

  if exists (select 1 from public.room_deck_peeks p where p.room_id = p_room_id)
    and p_action not in ('peek_deck','share_deck_peek_card','share_all_deck_peek_cards','take_deck_peek_card','remove_deck_peek_card','return_deck_peek','acknowledge_shared_deck_peek','reveal_hand_cards','acknowledge_hand_reveal') then
    raise exception '덱에서 꺼내 본 카드를 먼저 덱으로 되돌려 주세요.';
  end if;

  if v_match.pending_action is not null and v_match.pending_action ->> 'type' in ('character_contact_guard', 'character_contact', 'mislead_response', 'evidence_attack_reveal', 'evidence_attack', 'deck_remove_reveal', 'file_remove_reveal', 'culprits_crime_reveal', 'evidence_remove_reveal') then
    if p_action not in ('guard_contact_with_character','decline_contact_guard','contact_adjust_ap','contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead','resolve_evidence_attack','guard_with_character','decline_guard','acknowledge_deck_remove','acknowledge_file_remove','acknowledge_hand_reveal','acknowledge_culprits_crime','acknowledge_evidence_remove') then
      raise exception '현재 진행 중인 응답을 먼저 마쳐 주세요.';
    end if;
  elsif p_action in ('guard_contact_with_character','decline_contact_guard','contact_adjust_ap','contact_use_cutin','contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead','resolve_evidence_attack','guard_with_character','decline_guard','acknowledge_deck_remove','acknowledge_file_remove','acknowledge_culprits_crime','acknowledge_evidence_remove') then
    raise exception '응답할 컨택/미스리드/증거 공개가 없습니다.';
  end if;


  -- Temporarily reveal only selected cards from the current player's hand; never move them.
  if p_action = 'reveal_hand_cards' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 마친 뒤 손패를 공개해 주세요.'; end if;
    if exists (select 1 from public.room_hand_reveals r where r.room_id=p_room_id) then raise exception '상대가 이전에 공개한 손패를 먼저 확인해 주세요.'; end if;
    v_hand_reveal_ids := p_payload -> 'instance_ids';
    if v_hand_reveal_ids is null or jsonb_typeof(v_hand_reveal_ids) <> 'array'
       or jsonb_array_length(v_hand_reveal_ids) < 1 or jsonb_array_length(v_hand_reveal_ids) > jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb)) then
      raise exception '공개할 손패 카드를 1장 이상 선택해 주세요.';
    end if;
    if (select count(distinct value) from jsonb_array_elements_text(v_hand_reveal_ids)) <> jsonb_array_length(v_hand_reveal_ids) then
      raise exception '공개 카드 선택에 중복 항목이 있습니다.';
    end if;
    select coalesce(jsonb_agg(h.value order by requested.ordinality), '[]'::jsonb)
      into v_hand_reveal_cards
      from jsonb_array_elements_text(v_hand_reveal_ids) with ordinality requested(value, ordinality)
      join jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) h(value)
        on h.value ->> 'instance_id' = requested.value;
    if jsonb_array_length(coalesce(v_hand_reveal_cards,'[]'::jsonb)) <> jsonb_array_length(v_hand_reveal_ids) then
      raise exception '손패에 없는 카드가 포함되어 있습니다. 손패를 새로고침한 후 다시 선택해 주세요.';
    end if;
    select rp.user_id into v_other_user from public.room_players rp
      where rp.room_id=p_room_id and rp.user_id<>v_user limit 1;
    if v_other_user is null then raise exception '공개할 상대 플레이어를 찾을 수 없습니다.'; end if;
    insert into public.room_hand_reveals(room_id,source_user_id,viewer_user_id,cards,created_at)
      values(p_room_id,v_user,v_other_user,v_hand_reveal_cards,now());
    update public.room_match_states m set state_version=state_version+1,
      last_action_label=format('손패 %s장을 상대에게 잠시 공개했습니다.',jsonb_array_length(v_hand_reveal_cards))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'acknowledge_hand_reveal' then
    delete from public.room_hand_reveals r
      where r.room_id=p_room_id and r.viewer_user_id=v_user;
    if not found then raise exception '확인할 공개 손패가 없습니다.'; end if;
    update public.room_match_states m set state_version=state_version+1,
      last_action_label='상대가 공개한 손패를 확인했습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Temporarily reserve the top N cards of either player's deck for a private peek.
  if p_action = 'peek_deck' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 마친 뒤 덱을 살펴봐 주세요.'; end if;
    if exists (select 1 from public.room_deck_peeks p where p.room_id=p_room_id) then raise exception '현재 덱을 살펴보는 중입니다. 먼저 되돌려 주세요.'; end if;
    v_source_id := coalesce(nullif(p_payload ->> 'source_user_id','')::uuid, v_user);
    if not exists (select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_source_id) then raise exception '선택한 덱의 소유자를 찾을 수 없습니다.'; end if;
    v_count := coalesce(nullif(p_payload ->> 'count','')::integer, 1);
    if v_count < 1 or v_count > 100 then raise exception '덱에서 살펴볼 카드는 1~100장으로 지정해 주세요.'; end if;
    select gs.deck_order into v_deck_new from public.room_player_game_states gs where gs.room_id=p_room_id and gs.user_id=v_source_id for update;
    if jsonb_array_length(coalesce(v_deck_new,'[]'::jsonb)) < v_count then raise exception '선택한 덱에 살펴볼 만큼의 카드가 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.ordinality <= v_count), '[]'::jsonb),
           coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.ordinality > v_count), '[]'::jsonb)
      into v_files_new, v_hand_new from jsonb_array_elements(v_deck_new) with ordinality e(value, ordinality);
    update public.room_player_game_states gs set deck_order=v_hand_new, updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_source_id;
    insert into public.room_deck_peeks(room_id,source_user_id,viewer_user_id,cards,shared_instance_ids,updated_at)
      values(p_room_id,v_source_id,v_user,v_files_new,'[]'::jsonb,now());
    update public.room_match_states m set state_version=state_version+1,last_action_label=format('덱 위 %s장을 임시로 살펴봅니다. 확인 후 순서를 정해 되돌려 주세요.',v_count) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'take_deck_peek_card' then
    select * into v_peek from public.room_deck_peeks p
      where p.room_id=p_room_id and p.viewer_user_id=v_user and p.returned_at is null for update;
    if not found or v_peek.source_user_id <> v_user then raise exception '본인 덱을 살펴보는 중일 때만 선택한 카드를 손패로 가져올 수 있습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    if coalesce(v_peek.shared_instance_ids,'[]'::jsonb) @> jsonb_build_array(v_id) then NULL; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '살펴보는 카드 목록에서 선택한 카드를 찾지 못했습니다.'; end if;
    update public.room_player_game_states gs set hand=coalesce(gs.hand,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_id),'[]'::jsonb)
      into v_files_new from jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    if jsonb_array_length(coalesce(v_files_new,'[]'::jsonb))=0 then
      delete from public.room_deck_peeks where room_id=p_room_id;
    else
      update public.room_deck_peeks p set cards=v_files_new,shared_instance_ids=coalesce(p.shared_instance_ids,'[]'::jsonb) - v_id,updated_at=now() where p.room_id=p_room_id;
    end if;
    update public.room_match_states m set state_version=state_version+1,last_action_label='살펴본 카드 한 장을 손패로 가져왔습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'remove_deck_peek_card' then
    select * into v_peek from public.room_deck_peeks p
      where p.room_id = p_room_id and p.viewer_user_id = v_user and p.returned_at is null for update;
    if not found then raise exception '현재 본인에게 열린 덱 살펴보기 창이 없습니다.'; end if;
    if v_peek.source_user_id is distinct from v_user then
      raise exception '본인 덱을 살펴보는 중일 때만 선택한 카드를 리무브할 수 있습니다.';
    end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    if v_id is null then raise exception '리무브할 카드를 선택해 주세요.'; end if;
    if coalesce(v_peek.shared_instance_ids,'[]'::jsonb) @> jsonb_build_array(v_id) then
      raise exception '상대에게 공개하도록 지정한 카드는 공개 지정을 취소한 뒤 리무브해 주세요.';
    end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id' = v_id;
    if v_card is null then raise exception '살펴보는 카드 목록에서 선택한 카드를 찾지 못했습니다.'; end if;

    select coalesce(jsonb_agg(e.value order by e.ordinality)
      filter (where e.value ->> 'instance_id' is distinct from v_id), '[]'::jsonb)
      into v_files_new
      from jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) with ordinality e(value,ordinality);

    update public.room_player_game_states gs
      set remove_cards = coalesce(gs.remove_cards,'[]'::jsonb)
          || jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'),
          updated_at = now()
      where gs.room_id = p_room_id and gs.user_id = v_user;
    if not found then raise exception '자신의 게임 데이터를 찾을 수 없습니다.'; end if;

    update public.room_player_turn_boards tb
      set remove_count = coalesce(tb.remove_count,0) + 1, updated_at = now()
      where tb.room_id = p_room_id and tb.user_id = v_user;

    if jsonb_array_length(coalesce(v_files_new,'[]'::jsonb)) = 0
       and jsonb_array_length(coalesce(v_peek.shared_instance_ids,'[]'::jsonb)) = 0 then
      delete from public.room_deck_peeks p where p.room_id = p_room_id;
    else
      update public.room_deck_peeks p set cards = coalesce(v_files_new,'[]'::jsonb), updated_at = now()
        where p.room_id = p_room_id and p.viewer_user_id = v_user and p.returned_at is null;
    end if;

    update public.room_match_states m set state_version = state_version + 1,
      last_action_label = '덱 살펴보기에서 선택한 카드 한 장을 리무브 에이리어로 이동했습니다.'
      where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'share_deck_peek_card' then
    select * into v_peek from public.room_deck_peeks p where p.room_id=p_room_id and p.viewer_user_id=v_user and p.returned_at is null for update;
    if not found then raise exception '현재 본인에게 열린 덱 살펴보기 창이 없습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    if not exists (select 1 from jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) c(value) where c.value ->> 'instance_id'=v_id) then raise exception '공개할 카드를 찾을 수 없습니다.'; end if;
    if coalesce(v_peek.shared_instance_ids,'[]'::jsonb) @> jsonb_build_array(v_id) then
      select coalesce(jsonb_agg(to_jsonb(e.value) order by e.ordinality),'[]'::jsonb) into v_shared_ids
      from jsonb_array_elements_text(coalesce(v_peek.shared_instance_ids,'[]'::jsonb)) with ordinality e(value,ordinality) where e.value <> v_id;
    else
      v_shared_ids := coalesce(v_peek.shared_instance_ids,'[]'::jsonb) || jsonb_build_array(v_id);
    end if;
    update public.room_deck_peeks p set shared_instance_ids=v_shared_ids, shared_acknowledged=false, updated_at=now() where p.room_id=p_room_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label=case when coalesce(v_peek.shared_instance_ids,'[]'::jsonb) @> jsonb_build_array(v_id) then '덱 살펴보기에서 선택한 카드의 공개 선택을 취소했습니다.' else '덱 살펴보기에서 선택한 카드를 상대에게 공개했습니다.' end where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'share_all_deck_peek_cards' then
    select * into v_peek from public.room_deck_peeks p
      where p.room_id=p_room_id and p.viewer_user_id=v_user and p.returned_at is null for update;
    if not found then raise exception '공개할 본인 덱 살펴보기 창이 없습니다.'; end if;
    if jsonb_array_length(coalesce(v_peek.cards,'[]'::jsonb))=0 then raise exception '공개할 카드가 없습니다.'; end if;
    if jsonb_array_length(coalesce(v_peek.shared_instance_ids,'[]'::jsonb))=jsonb_array_length(coalesce(v_peek.cards,'[]'::jsonb)) then
      v_shared_ids := '[]'::jsonb;
    else
      select coalesce(jsonb_agg(to_jsonb(card.value ->> 'instance_id') order by card.ordinality),'[]'::jsonb)
        into v_shared_ids from jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) with ordinality card(value,ordinality);
    end if;
    update public.room_deck_peeks p set shared_instance_ids=v_shared_ids,shared_acknowledged=false,updated_at=now() where p.room_id=p_room_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label=case when jsonb_array_length(v_shared_ids)=0 then '덱 전체 공개 선택을 취소했습니다.' else format('덱 %s장을 상대에게 전체 공개하도록 선택했습니다.',jsonb_array_length(v_shared_ids)) end where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'return_deck_peek' then
    select * into v_peek from public.room_deck_peeks p where p.room_id=p_room_id and p.viewer_user_id=v_user and p.returned_at is null for update;
    if not found then raise exception '현재 되돌릴 덱 살펴보기 카드가 없습니다.'; end if;
    v_dest := lower(coalesce(p_payload ->> 'destination','top'));
    if v_dest not in ('top','bottom') then raise exception '덱 되돌리기 위치는 top 또는 bottom이어야 합니다.'; end if;
    v_instance_order := p_payload -> 'instance_order';
    if v_instance_order is null or jsonb_typeof(v_instance_order) <> 'array' or jsonb_array_length(v_instance_order) <> jsonb_array_length(coalesce(v_peek.cards,'[]'::jsonb)) then raise exception '되돌릴 카드의 순서 목록이 올바르지 않습니다.'; end if;
    if (select count(distinct value) from jsonb_array_elements_text(v_instance_order)) <> jsonb_array_length(v_instance_order) then raise exception '카드 순서에 중복된 카드가 있습니다.'; end if;
    select coalesce(jsonb_agg(card.value order by ids.ordinality),'[]'::jsonb)
      into v_ordered_cards
      from jsonb_array_elements_text(v_instance_order) with ordinality ids(value,ordinality)
      join jsonb_array_elements(coalesce(v_peek.cards,'[]'::jsonb)) card(value) on card.value ->> 'instance_id'=ids.value;
    if jsonb_array_length(coalesce(v_ordered_cards,'[]'::jsonb)) <> jsonb_array_length(coalesce(v_peek.cards,'[]'::jsonb)) then raise exception '되돌릴 카드 목록에 현재 살펴본 카드가 아닌 항목이 있습니다.'; end if;
    select gs.deck_order into v_deck_new from public.room_player_game_states gs where gs.room_id=p_room_id and gs.user_id=v_peek.source_user_id for update;
    if v_dest='top' then v_deck_new := coalesce(v_ordered_cards,'[]'::jsonb) || coalesce(v_deck_new,'[]'::jsonb);
    else v_deck_new := coalesce(v_deck_new,'[]'::jsonb) || coalesce(v_ordered_cards,'[]'::jsonb); end if;
    update public.room_player_game_states gs set deck_order=v_deck_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_peek.source_user_id;
    if jsonb_array_length(coalesce(v_peek.shared_instance_ids,'[]'::jsonb)) > 0 and not coalesce(v_peek.shared_acknowledged,false) then
      update public.room_deck_peeks p set returned_at=now(),updated_at=now() where p.room_id=p_room_id;
    else
      delete from public.room_deck_peeks p where p.room_id=p_room_id;
    end if;
    update public.room_match_states m set state_version=state_version+1,last_action_label=format('살펴본 %s장을 순서를 지정해 덱 %s에 되돌렸습니다.%s',jsonb_array_length(v_ordered_cards),case when v_dest='top' then '위' else '아래' end,case when jsonb_array_length(coalesce(v_peek.shared_instance_ids,'[]'::jsonb)) > 0 then ' 상대가 공개 카드를 확인할 때까지 대기합니다.' else '' end) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'acknowledge_shared_deck_peek' then
    select * into v_peek from public.room_deck_peeks p
    where p.room_id=p_room_id and p.viewer_user_id <> v_user
      and jsonb_array_length(coalesce(p.shared_instance_ids,'[]'::jsonb)) > 0
      and not coalesce(p.shared_acknowledged,false)
    for update;
    if not found then raise exception '확인할 공개 덱 카드가 없습니다.'; end if;
    if v_peek.returned_at is not null then
      delete from public.room_deck_peeks p where p.room_id=p_room_id;
    else
      update public.room_deck_peeks p set shared_acknowledged=true,updated_at=now() where p.room_id=p_room_id;
    end if;
    update public.room_match_states m set state_version=state_version+1,last_action_label='상대가 공개한 덱 카드를 확인했습니다. 공개 창을 닫았습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Reserve the first N deck cards and reveal them to both players. Only after both acknowledge
  -- the reveal are the cards moved from the deck to the owner's remove area.
  if p_action = 'remove_top_deck' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답이나 공개 확인을 먼저 완료해 주세요.'; end if;
    v_count := coalesce(nullif(p_payload ->> 'count','')::integer,1);
    select gs.deck_order into v_deck_new from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_user for update;
    if v_count < 1 or v_count > jsonb_array_length(coalesce(v_deck_new,'[]'::jsonb)) then raise exception '리무브할 장수가 현재 덱의 카드 수를 벗어났습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality<=v_count),'[]'::jsonb)
      into v_files_new from jsonb_array_elements(coalesce(v_deck_new,'[]'::jsonb)) with ordinality e(value,ordinality);
    if jsonb_array_length(coalesce(v_files_new,'[]'::jsonb))<>v_count then raise exception '덱 위 카드 목록을 준비하지 못했습니다.'; end if;
    v_pending := jsonb_build_object(
      'type','deck_remove_reveal',
      'source_user_id',v_user::text,
      'cards',v_files_new,
      'acknowledged_user_ids','[]'::jsonb,
      'requested_count',v_count
    );
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,
      last_action_label=format('덱 위 %s장을 양쪽 플레이어에게 공개했습니다. 두 사람 모두 확인하면 리무브로 이동합니다.',v_count)
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'acknowledge_deck_remove' then
    if v_match.pending_action ->> 'type' is distinct from 'deck_remove_reveal' then raise exception '확인할 덱 리무브 공개가 없습니다.'; end if;
    v_shared_ids := coalesce(v_match.pending_action -> 'acknowledged_user_ids','[]'::jsonb);
    if v_shared_ids @> jsonb_build_array(v_user::text) then raise exception '이미 공개 확인을 완료했습니다.'; end if;
    v_shared_ids := v_shared_ids || jsonb_build_array(v_user::text);
    v_pending := v_match.pending_action || jsonb_build_object('acknowledged_user_ids',v_shared_ids);
    if jsonb_array_length(v_shared_ids) >= (select count(*) from public.room_players rp where rp.room_id=p_room_id) then
      v_source_id := (v_match.pending_action ->> 'source_user_id')::uuid;
      v_files_new := coalesce(v_match.pending_action -> 'cards','[]'::jsonb);
      v_count := jsonb_array_length(v_files_new);
      if v_count < 1 then raise exception '리무브할 공개 카드가 없습니다.'; end if;
      select gs.deck_order into v_deck_new from public.room_player_game_states gs
        where gs.room_id=p_room_id and gs.user_id=v_source_id for update;
      if jsonb_array_length(coalesce(v_deck_new,'[]'::jsonb)) < v_count then raise exception '공개 확인 중 덱 상태가 바뀌었습니다. 새로고침 후 확인해 주세요.'; end if;
      -- The global pending-action lock prevents deck changes, so dropping the first N preserves the rest.
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality>v_count),'[]'::jsonb)
        into v_hand_new from jsonb_array_elements(coalesce(v_deck_new,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set deck_order=coalesce(v_hand_new,'[]'::jsonb),
        remove_cards=coalesce(gs.remove_cards,'[]'::jsonb)||coalesce((
          select jsonb_agg(card.value - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' order by card.ordinality)
          from jsonb_array_elements(v_files_new) with ordinality card(value,ordinality)
        ),'[]'::jsonb),updated_at=now()
        where gs.room_id=p_room_id and gs.user_id=v_source_id;
      update public.room_player_turn_boards tb set remove_count=remove_count+v_count,updated_at=now()
        where tb.room_id=p_room_id and tb.user_id=v_source_id;
      update public.room_match_states m set pending_action=null,state_version=state_version+1,
        last_action_label=format('양쪽 플레이어가 확인하여 덱 위 %s장을 리무브 에이리어로 이동했습니다.',v_count)
        where m.room_id=p_room_id;
    else
      update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,
        last_action_label=format('덱 위 공개 카드 확인 %s/%s명 완료. 두 사람 모두 확인하면 리무브로 이동합니다.',jsonb_array_length(v_shared_ids),(select count(*) from public.room_players rp where rp.room_id=p_room_id))
        where m.room_id=p_room_id;
    end if;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'acknowledge_file_remove' then
    if v_match.pending_action ->> 'type' is distinct from 'file_remove_reveal' then
      raise exception '확인할 파일 카드 리무브 공개가 없습니다.';
    end if;
    v_shared_ids := coalesce(v_match.pending_action -> 'acknowledged_user_ids','[]'::jsonb);
    if v_shared_ids @> jsonb_build_array(v_user::text) then raise exception '이미 공개 확인을 완료했습니다.'; end if;
    v_shared_ids := v_shared_ids || jsonb_build_array(v_user::text);
    v_pending := v_match.pending_action || jsonb_build_object('acknowledged_user_ids',v_shared_ids);
    if jsonb_array_length(v_shared_ids) >= (select count(*) from public.room_players rp where rp.room_id=p_room_id) then
      v_source_id := (v_match.pending_action ->> 'source_user_id')::uuid;
      v_files_new := coalesce(v_match.pending_action -> 'cards','[]'::jsonb);
      if jsonb_array_length(v_files_new) <> 1 then raise exception '리무브할 파일 카드 정보가 올바르지 않습니다.'; end if;
      select gs.file_cards into v_deck_new from public.room_player_game_states gs
        where gs.room_id=p_room_id and gs.user_id=v_source_id for update;
      v_count := jsonb_array_length(coalesce(v_deck_new,'[]'::jsonb));
      if v_count < 1 then raise exception '확인 중 파일 카드가 사라졌습니다. 상태를 새로고침해 주세요.'; end if;
      v_card := v_deck_new -> (v_count - 1);
      if (v_card ->> 'instance_id') is distinct from (v_files_new -> 0 ->> 'instance_id') then
        raise exception '파일 카드 순서가 바뀌었습니다. 새로고침 후 다시 확인해 주세요.';
      end if;
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality < v_count),'[]'::jsonb)
        into v_hand_new from jsonb_array_elements(coalesce(v_deck_new,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set
        file_cards=coalesce(v_hand_new,'[]'::jsonb),
        remove_cards=coalesce(gs.remove_cards,'[]'::jsonb)||jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'),
        updated_at=now()
        where gs.room_id=p_room_id and gs.user_id=v_source_id;
      update public.room_player_turn_boards tb set
        file_count=greatest(0,coalesce(tb.file_count,0)-1),
        remove_count=coalesce(tb.remove_count,0)+1,
        updated_at=now()
        where tb.room_id=p_room_id and tb.user_id=v_source_id;
      update public.room_match_states m set pending_action=null,state_version=state_version+1,
        last_action_label='양쪽 플레이어가 확인하여 파일 맨 위 카드를 리무브 에이리어로 이동했습니다.'
        where m.room_id=p_room_id;
    else
      update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,
        last_action_label=format('파일 맨 위 카드 리무브 확인 %s/%s명 완료. 두 사람 모두 확인하면 이동합니다.',jsonb_array_length(v_shared_ids),(select count(*) from public.room_players rp where rp.room_id=p_room_id))
        where m.room_id=p_room_id;
    end if;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Reveal only the newest N evidence cards. Revealed cards stay in the evidence pile.
  if p_action = 'expose_evidence' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 마친 뒤 증거를 공개해 주세요.'; end if;
    v_source_id := coalesce(nullif(p_payload ->> 'target_user_id','')::uuid,v_user);
    if not exists (select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_source_id) then raise exception '증거 소유자를 찾을 수 없습니다.'; end if;
    v_count := coalesce(nullif(p_payload ->> 'count','')::integer,1);
    select gs.evidence_cards into v_evidence_cards from public.room_player_game_states gs where gs.room_id=p_room_id and gs.user_id=v_source_id for update;
    if v_count < 1 or v_count > jsonb_array_length(coalesce(v_evidence_cards,'[]'::jsonb)) then raise exception '공개할 증거 수가 현재 증거 카드 수를 벗어났습니다.'; end if;
    select coalesce(jsonb_agg(case when e.ordinality > jsonb_array_length(coalesce(v_evidence_cards,'[]'::jsonb))-v_count then e.value || jsonb_build_object('face_up',true) else e.value end order by e.ordinality),'[]'::jsonb)
      into v_evidence_cards from jsonb_array_elements(coalesce(v_evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set evidence_cards=v_evidence_cards,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_source_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label=format('%s의 가장 위 증거 %s장을 공개했습니다.',case when v_source_id=v_user then '내' else '상대' end,v_count) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- A successful unguarded evidence attack first publishes the targeted card in a modal.
  if p_action = 'decline_guard' then
    if v_match.pending_action ->> 'type' is distinct from 'evidence_attack' or v_match.pending_action ->> 'target_user_id' is distinct from v_user::text then raise exception '현재 이 공격에 응답할 수 없습니다.'; end if;
    if jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))=0 then raise exception '공개할 증거 카드를 찾을 수 없습니다.'; end if;
    v_card := (v_game.evidence_cards -> (jsonb_array_length(v_game.evidence_cards)-1)) || jsonb_build_object('hirameki_achieved',true);
    v_pending := v_match.pending_action || jsonb_build_object('type','evidence_attack_reveal','revealed_evidence_card',v_card);
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,last_action_label=format('증거 공격이 통과했습니다. 대상 증거 %s를 양쪽 플레이어에게 공개했습니다. 확인 후 리무브합니다.',coalesce(v_card ->> 'key','카드')) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'resolve_evidence_attack' then
    if v_match.pending_action ->> 'type' is distinct from 'evidence_attack_reveal' or v_match.pending_action ->> 'target_user_id' is distinct from v_user::text then raise exception '공개된 증거 공격의 대상 플레이어만 확정할 수 있습니다.'; end if;
    v_source_id := v_user;
    v_card := v_match.pending_action -> 'revealed_evidence_card';
    if v_card is null or jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))=0 then raise exception '공개 후 이동할 증거를 찾을 수 없습니다.'; end if;
    v_target := v_game.evidence_cards -> (jsonb_array_length(v_game.evidence_cards)-1);
    if (v_target ->> 'instance_id') is distinct from (v_card ->> 'instance_id') then raise exception '공개 중 증거 순서가 바뀌었습니다. 상태를 새로고침해 주세요.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality < jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))),'[]'::jsonb)
      into v_files_new from jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set evidence_cards=v_files_new,remove_cards=coalesce(gs.remove_cards,'[]'::jsonb)||jsonb_build_array(v_card || jsonb_build_object('face_up',true)),updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_source_id;
    update public.room_player_turn_boards b set evidence_count=greatest(0,b.evidence_count-1),remove_count=remove_count+1,updated_at=now() where b.room_id=p_room_id and b.user_id=v_source_id;
    v_source_id := (v_match.pending_action ->> 'attacker_user_id')::uuid;
    perform public.draw_private_turn_card(p_room_id,v_source_id,'evidence');
    update public.room_match_states m set pending_action=null,state_version=state_version+1,last_action_label=format('공개된 증거 %s를 리무브로 이동했고 공격자가 증거 1장을 얻었습니다.',coalesce(v_card ->> 'key','카드')) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;


  if p_action = 'declare_solution' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 해결편으로 전환할 수 있습니다.'; end if;
    if v_board.case_phase <> 'incident' then raise exception '이미 해결편입니다.'; end if;
    v_count := case when v_match.first_player_user_id=v_user then 7 else 6 end;
    if v_board.file_count < v_count then raise exception '해결편 전환에는 파일 %장이 필요합니다. 현재 %장입니다.',v_count,v_board.file_count; end if;
    if v_board.partner_rested or v_board.partner_assist_used then raise exception '해결편 전환에는 아직 액티브인 파트너의 어시스트가 필요합니다.'; end if;
    if v_board.next_hint_used then raise exception '넥스트 힌트를 사용한 턴에는 파트너 어시스트 및 해결편 전환을 할 수 없습니다.'; end if;
    update public.room_player_turn_boards b set partner_rested=true,partner_assist_used=true,base_action_done=true,updated_at=now() where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_player_turn_boards b set case_phase='solution',updated_at=now() where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='파트너를 어시스트하고 내 보드를 해결편으로 전환했습니다. 파트너는 슬립 상태이므로 사건 해결 선언은 다시 액티브가 된 뒤 가능합니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'begin_turn' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'begin' or v_match.pending_action is not null then
      raise exception '현재 턴 시작 단계가 아닙니다.';
    end if;
    select exists (
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
            other_card.value #>> '{sourceData,id}',
            other_card.value #>> '{sourceData,databaseId}',
            other_card.value #>> '{sourceData,database_id}',
            other_card.value #>> '{sourceData,cardId}',
            other_card.value #>> '{sourceData,card_id}',
            other_card.value #>> '{sourceData,cardNum}',
            other_card.value #>> '{sourceData,card_num}',
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
          where upper(btrim(coalesce(candidate.value, ''))) IN ('B03046','B03046P','ID:0301','0301') OR coalesce(nullif(ltrim(btrim(candidate.value), '0'), ''), '0') = '301'
             or coalesce(nullif(ltrim(regexp_replace(upper(btrim(candidate.value)), '^ID\s*:\s*', ''), '0'), ''), '0') = '301'
             or nullif(ltrim(regexp_replace(coalesce(candidate.value,''), '[^0-9]', '', 'g'), '0'), '') = '301'
             or (
               (
                 NOT EXISTS (
                   SELECT 1
                   FROM unnest(ARRAY[
                     other_card.value ->> 'name',
                     other_card.value ->> 'nameKo',
                     other_card.value ->> 'name_ko',
                     other_card.value ->> 'originalName',
                     other_card.value ->> 'original_name',
                     other_card.value ->> 'translatedName',
                     other_card.value ->> 'cardName',
                     other_card.value ->> 'card_name',
                     other_card.value ->> 'title',
                     other_card.value #>> '{sourceData,name}',
                     other_card.value #>> '{sourceData,originalName}'
                   ]) AS kid_names(value)
                   WHERE nullif(trim(kid_names.value),'') IS NOT NULL
                 )
                 OR EXISTS (
                   SELECT 1
                   FROM unnest(ARRAY[
                     other_card.value ->> 'name',
                     other_card.value ->> 'nameKo',
                     other_card.value ->> 'name_ko',
                     other_card.value ->> 'originalName',
                     other_card.value ->> 'original_name',
                     other_card.value ->> 'translatedName',
                     other_card.value ->> 'cardName',
                     other_card.value ->> 'card_name',
                     other_card.value ->> 'title',
                     other_card.value #>> '{sourceData,name}',
                     other_card.value #>> '{sourceData,originalName}'
                   ]) AS kid_names(value)
                   WHERE regexp_replace(lower(coalesce(kid_names.value,'')), '[[:space:]]', '', 'g')
                     IN ('괴도키드','怪盗キッド')
                 )
               )
               AND lower(coalesce(other_card.value ->> 'card_type', other_card.value ->> 'type', 'character'))
                 IN ('character','캐릭터','キャラクター')
               AND upper(coalesce(other_card.value ->> 'rarity', other_card.value ->> 'rarity_code', '')) = 'SR'
               AND coalesce(nullif(other_card.value ->> 'cost','')::numeric, -1) = 8
               AND coalesce(nullif(other_card.value ->> 'ap','')::numeric, -1) = 7000
               AND coalesce(nullif(other_card.value ->> 'lp','')::numeric, -1) = 2
               AND EXISTS (
                 SELECT 1
                 FROM unnest(ARRAY[
                   other_card.value ->> 'color',
                   other_card.value ->> 'originalColor',
                   other_card.value ->> 'original_color',
                   other_card.value ->> 'colorJp',
                   other_card.value ->> 'colorKo'
                 ]) AS kid_colors(value)
                 WHERE upper(trim(coalesce(kid_colors.value,''))) IN ('백','白','白色','WHITE')
               )
               AND upper(concat_ws(' ',
                 other_card.value ->> 'set',
                 other_card.value ->> 'originalSet',
                 other_card.value ->> 'original_set',
                 other_card.value ->> 'product',
                 other_card.value ->> 'package'
               )) LIKE '%CT-P03%'
             )
        )
    ) into v_kid_stun_lock;

    select coalesce(jsonb_agg(
      case when e.value ->> 'status' = 'stunned'
        then case when v_kid_stun_lock
           then e.value || jsonb_build_object('status','stunned','rested',false,'summoned_this_turn',false,'ap_bonus',0)
           else e.value || jsonb_build_object('status','rested','rested',true,'summoned_this_turn',false,'ap_bonus',0)
         end
        else e.value || jsonb_build_object('status','active','rested',false,'summoned_this_turn',false,'ap_bonus',0)
      end order by e.ordinality), '[]'::jsonb)
      into v_new_status_field
    from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    v_count := case when v_match.turn_number = 1 and v_user = v_match.first_player_user_id then 1 else 2 end;
    update public.room_player_turn_boards b set
      field_cards = v_new_status_field,
      partner_rested = false,
      partner_assist_used = false,
      partner_deduction_used = false,
      character_played_this_turn = false,
      base_character_played_this_turn = false,
      next_hint_used = false,
      next_hint_pending = false,
      base_action_done = false,
      base_card_played_this_turn = false,
      files_to_place = v_count,
      files_placed_this_turn = 0,
      updated_at = now()
    where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_match_states m set turn_step = 'file', state_version = state_version + 1,
      last_action_label = format('턴 %s 시작: 슬립 카드는 액티브, 스턴은 상대 현장에 ID:0301 괴도 키드가 있으면 스턴 유지, 없으면 슬립으로 전환됩니다. 손패 1장 드로우 후 파일 %s장을 배치합니다.', v_match.turn_number, v_count)
    where m.room_id = p_room_id;
    perform public.draw_private_turn_card(p_room_id, v_user, 'hand');
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- File placement is its own action. The cards come from the top of the deck, face down.
  if p_action = 'place_files' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'file' then raise exception '현재 파일 배치 단계가 아닙니다.'; end if;
    v_count := greatest(0, v_board.files_to_place - v_board.files_placed_this_turn);
    if v_count < 1 then raise exception '필요한 파일을 이미 모두 배치했습니다.'; end if;
    for v_i in 1..v_count loop
      perform public.draw_private_turn_card(p_room_id, v_user, 'file');
    end loop;
    update public.room_player_turn_boards b set
      file_count = file_count + v_count,
      files_placed_this_turn = files_placed_this_turn + v_count,
      updated_at = now()
    where b.room_id = p_room_id and b.user_id = v_user;
    if v_board.files_placed_this_turn + v_count >= v_board.files_to_place then
      update public.room_match_states m set turn_step = 'main' where m.room_id = p_room_id;
      v_label := format('덱 위에서 파일 %s장을 뒤집어 배치했습니다. 메인 행동을 시작할 수 있습니다.', v_count);
    else
      v_label := format('파일 %s장을 배치했습니다.', v_count);
    end if;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = v_label where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Event cards go to the field while their effect is being resolved. The player moves them
  -- to the remove area only after manually confirming that effect resolution is complete.
  if p_action = 'play_event' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then
      raise exception '자신의 메인 단계에서만 이벤트를 사용할 수 있습니다.';
    end if;
    v_id := nullif(p_payload ->> 'instance_id', '');
    select e.value into v_card from jsonb_array_elements(v_game.hand) e(value) where e.value ->> 'instance_id' = v_id;
    if v_card is null then raise exception '손패에서 이벤트 카드를 찾을 수 없습니다.'; end if;
    if coalesce(v_card ->> 'card_type', '') <> 'event' then raise exception '이벤트 카드만 사용할 수 있습니다.'; end if;
    if coalesce(v_board.base_card_played_this_turn, false)
       and not coalesce(v_board.next_hint_pending, false) then
      raise exception '이번 턴의 기본 카드 사용을 이미 완료했습니다. 추가 카드는 넥스트 힌트를 사용해 주세요.';
    end if;
    v_cost_limit := v_board.file_count
      + case when v_board.partner_assist_used then 1 else 0 end
      + case when coalesce(v_board.next_hint_pending,false) then 1 else 0 end;
    v_cost := coalesce(nullif(v_card ->> 'cost', '')::numeric, 0);
    if v_cost > v_cost_limit then raise exception '이벤트 레벨가 현재 상한(%)을 초과합니다.', v_cost_limit; end if;
    if jsonb_array_length(coalesce(v_board.field_cards, '[]'::jsonb)) >= 5 then NULL; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb)
      into v_hand_new from jsonb_array_elements(v_game.hand) with ordinality e(value, ordinality);
    update public.room_player_game_states g set hand = v_hand_new, updated_at = now() where g.room_id = p_room_id and g.user_id = v_user;
    update public.room_player_turn_boards b set field_cards = coalesce(b.field_cards, '[]'::jsonb) || jsonb_build_array(v_card || jsonb_build_object('rested', false, 'ap_bonus', 0, 'resolving', true)), base_action_done = true, base_card_played_this_turn = true, next_hint_pending = false, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;
    v_label := '이벤트를 현장에 놓았습니다. 카드 효과를 확인한 뒤 [효과 처리 완료 → 리무브]를 누르세요.';
    update public.room_match_states m set state_version = state_version + 1, last_action_label = v_label where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'finish_event' then
    v_id := nullif(p_payload ->> 'instance_id', '');
    select e.value into v_card from jsonb_array_elements(v_board.field_cards) e(value) where e.value ->> 'instance_id' = v_id and coalesce(e.value ->> 'card_type', '') = 'event';
    if v_card is null then raise exception '효과 처리를 마칠 이벤트를 현장에서 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb)
      into v_field_new from jsonb_array_elements(v_board.field_cards) with ordinality e(value, ordinality);
    update public.room_player_turn_boards b set field_cards = v_field_new, remove_count = remove_count + 1, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_player_game_states g set remove_cards = coalesce(g.remove_cards, '[]'::jsonb) || jsonb_build_array(v_card - 'resolving'), updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_user;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = '이벤트 효과 처리가 끝나 리무브 영역으로 이동했습니다.' where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Manual effect utility: draw a chosen number of cards, even when an effect resolves off-turn.
  if p_action = 'draw_cards' then
    v_count := coalesce(nullif(p_payload ->> 'count', '')::integer, 1);
    if v_count < 1 or v_count > 20 then raise exception '드로우는 한 번에 1~20장으로 지정해 주세요.'; end if;
    for v_i in 1..v_count loop perform public.draw_private_turn_card(p_room_id, v_user, 'hand'); end loop;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = format('효과 처리로 카드 %s장을 손패에 가져왔습니다.', v_count) where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Additional character deployment is a manual-effect action and bypasses both the normal
  -- once-per-turn character count and the ordinary cost ceiling. The five-card field limit remains.
  if p_action = 'extra_play_event' then
    v_id := nullif(p_payload ->> 'instance_id', '');
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_game.hand, '[]'::jsonb)) e(value)
      where e.value ->> 'instance_id' = v_id;
    if v_card is null then raise exception '추가 사용할 이벤트를 손패에서 찾을 수 없습니다.'; end if;
    if coalesce(v_card ->> 'card_type', '') <> 'event' then raise exception '효과로 추가 사용은 이벤트 카드만 가능합니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb)
      into v_hand_new
      from jsonb_array_elements(coalesce(v_game.hand, '[]'::jsonb)) with ordinality e(value, ordinality);
    update public.room_player_game_states g
      set hand = v_hand_new, updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_user;
    update public.room_player_turn_boards b
      set field_cards = coalesce(b.field_cards, '[]'::jsonb)
            || jsonb_build_array(v_card || jsonb_build_object('rested', false, 'ap_bonus', 0, 'resolving', true)),
          base_action_done = true,
          base_card_played_this_turn = true,
          next_hint_pending = false,
          updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_match_states m
      set state_version = state_version + 1,
          last_action_label = '효과 처리로 이벤트를 추가 사용했습니다. 카드 효과를 확인한 뒤 [효과 처리 완료 → 리무브]를 누르세요. (턴당 사용 제한 무시)'
      where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'extra_play_character' then
    v_id := nullif(p_payload ->> 'instance_id', '');
    select e.value into v_card from jsonb_array_elements(v_game.hand) e(value) where e.value ->> 'instance_id' = v_id;
    if v_card is null then raise exception '추가 등장할 캐릭터를 손패에서 찾을 수 없습니다.'; end if;
    if coalesce(v_card ->> 'card_type', '') <> 'character' then raise exception '추가 등장은 캐릭터 카드만 가능합니다.'; end if;
    if jsonb_array_length(coalesce(v_board.field_cards, '[]'::jsonb)) >= 5
      and not (upper(coalesce(v_card ->> 'rarity', '')) IN ('MR','MRP')
        and exists (select 1 from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value) where upper(coalesce(e.value ->> 'rarity', '')) IN ('MR','MRP')))
    then IF (
    SELECT count(*)
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) AS field_card(value)
    WHERE upper(coalesce(field_card.value ->> 'card_type','')) = 'CHARACTER'
  ) >= 5 THEN
    RAISE EXCEPTION '현장 캐릭터 수 제한을 초과했습니다.';
  END IF; end if;
    if upper(coalesce(v_card ->> 'rarity', '')) IN ('MR','MRP') then perform public.clear_private_field_mr_for_deployment(p_room_id, v_user); end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb)
      into v_hand_new from jsonb_array_elements(v_game.hand) with ordinality e(value, ordinality);
    update public.room_player_game_states g set hand = v_hand_new, updated_at = now() where g.room_id = p_room_id and g.user_id = v_user;
    update public.room_player_turn_boards b set field_cards = coalesce(b.field_cards, '[]'::jsonb) || jsonb_build_array(v_card || jsonb_build_object('rested', false, 'status', 'active', 'summoned_this_turn', true, 'ap_bonus', 0)), base_action_done = true, base_card_played_this_turn = true, next_hint_pending = false, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = '효과 처리로 캐릭터를 추가 등장했습니다. (레벨/턴당 등장 제한 무시)' where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Next Hint is legal only AFTER a main action. Each use takes one face-down file into hand,
  -- then deploys one character from the hand; no once-per-turn count is applied to Next Hint itself.
  if p_action = 'next_hint_take_file' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 넥스트 힌트를 사용할 수 있습니다.'; end if;
    if not v_board.base_action_done then raise exception '먼저 기본 행동을 완료해야 넥스트 힌트를 사용할 수 있습니다.'; end if;
    if coalesce(v_board.next_hint_pending,false) then raise exception '이미 넥스트 힌트 등장 카드를 선택하고 있습니다.'; end if;
    if jsonb_array_length(coalesce(v_game.file_cards,'[]'::jsonb)) < 1 then raise exception '파일 에이리어에 가져올 카드가 없습니다.'; end if;
    v_file_top := v_game.file_cards -> (jsonb_array_length(v_game.file_cards)-1);
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality < jsonb_array_length(v_game.file_cards)),'[]'::jsonb)
      into v_files_new from jsonb_array_elements(coalesce(v_game.file_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set hand=coalesce(gs.hand,'[]'::jsonb)||jsonb_build_array(v_file_top),file_cards=v_files_new,updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b set file_count=greatest(0,b.file_count-1),next_hint_used=true,next_hint_pending=true,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='넥스트 힌트 선언: 파일 맨 위 카드를 먼저 손패로 가져왔습니다. 이제 손패에서 등장할 캐릭터를 선택하세요.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'next_hint' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 넥스트 힌트를 사용할 수 있습니다.'; end if;
    if not v_board.base_action_done or not coalesce(v_board.next_hint_pending,false) then raise exception '먼저 넥스트 힌트를 선언하고 파일 카드를 손패로 가져와야 합니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
    if v_card is null or coalesce(v_card ->> 'card_type','') <> 'character' then raise exception '넥스트 힌트 등장은 손패의 캐릭터 카드만 선택할 수 있습니다.'; end if;
    if jsonb_array_length(coalesce(v_board.field_cards,'[]'::jsonb)) >= 5
      and not (upper(coalesce(v_card ->> 'rarity',''))='MR' and exists(select 1 from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value) where upper(coalesce(e.value ->> 'rarity',''))='MR'))
      then IF (
    SELECT count(*)
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) AS field_card(value)
    WHERE upper(coalesce(field_card.value ->> 'card_type','')) = 'CHARACTER'
  ) >= 5 THEN
    RAISE EXCEPTION '현장 캐릭터 수 제한을 초과했습니다.';
  END IF; end if;
    v_cost_limit := v_board.file_count + 1 + case when v_board.partner_assist_used then 1 else 0 end;
    v_cost := coalesce(nullif(v_card ->> 'cost','')::numeric,0);
    if v_cost > v_cost_limit then raise exception '넥스트 힌트 선언 시점의 레벨 상한(%)을 초과합니다.',v_cost_limit; end if;
    if upper(coalesce(v_card ->> 'rarity',''))='MR' then perform public.clear_private_field_mr_for_deployment(p_room_id,v_user); end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_id),'[]'::jsonb)
      into v_hand_new from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set hand=v_hand_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards b set
      field_cards=coalesce(b.field_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('rested',false,'status','active','summoned_this_turn',true,'ap_bonus',0)),
      next_hint_pending=false,next_hint_used=false,base_action_done=true,base_card_played_this_turn=true,updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='넥스트 힌트: 손패에서 선택한 캐릭터를 등장했습니다. 파일이 남아 있다면 다시 넥스트 힌트를 선언할 수 있습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'move_evidence_to_hand' then
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

  -- Move an already face-up evidence card to its owner's deck bottom, without regard to whose turn it is.
  if p_action = 'move_evidence_to_deck_bottom' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'instance_id','');
    if not exists (select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_owner_id) then raise exception '증거 카드 소유자를 찾을 수 없습니다.'; end if;
    select * into v_opponent_game from public.room_player_game_states gs where gs.room_id=p_room_id and gs.user_id=v_owner_id for update;
    if not found then raise exception '증거 카드 소유자의 게임 데이터를 찾을 수 없습니다.'; end if;
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id and (coalesce((e.value ->> 'face_up')::boolean,false) is true or v_owner_id=v_user);
    if v_card is null then raise exception '이동할 수 있는 증거 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_id),'[]'::jsonb)
      into v_files_new
      from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs
      set evidence_cards=coalesce(v_files_new,'[]'::jsonb),
          deck_order=coalesce(gs.deck_order,'[]'::jsonb)||jsonb_build_array(v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'),
          updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_owner_id;
    update public.room_player_turn_boards tb set evidence_count=greatest(0,coalesce(tb.evidence_count,0)-1),updated_at=now()
      where tb.room_id=p_room_id and tb.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,
      last_action_label=format('%s의 공개 증거 1장을 해당 플레이어의 덱 맨 아래로 이동했습니다.',case when v_owner_id=v_user then '내' else '상대' end)
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Require both players to inspect an evidence card before it leaves the evidence area.
  if p_action = 'acknowledge_evidence_remove' then
    if v_match.pending_action ->> 'type' is distinct from 'evidence_remove_reveal' then
      raise exception '확인할 증거 리무브 공개가 없습니다.';
    end if;
    v_shared_ids := coalesce(v_match.pending_action -> 'acknowledged_user_ids','[]'::jsonb);
    if v_shared_ids @> jsonb_build_array(v_user::text) then
      raise exception '이미 이 증거 카드를 확인했습니다.';
    end if;
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
    if v_owner_id is null or v_id is null then
      raise exception '공개된 증거 카드의 소유자 또는 인스턴스 ID가 없습니다.';
    end if;
    select * into v_opponent_game
      from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_owner_id
      for update;
    if not found then raise exception '증거 카드 소유자의 게임 데이터를 찾을 수 없습니다.'; end if;
    if not exists (
      select 1 from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id
    ) then
      raise exception '공개 중 증거 영역이 바뀌었습니다. 새로고침 후 다시 확인해 주세요.';
    end if;

    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id' is distinct from v_id),'[]'::jsonb)
      into v_files_new
      from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
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

  -- Start the shared reveal first; the evidence itself stays in its owner’s evidence area until both confirm.
  if p_action = 'move_evidence_to_remove' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'instance_id','');
    if not exists (select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_owner_id) then raise exception '증거 카드 소유자를 찾을 수 없습니다.'; end if;
    select * into v_opponent_game
      from public.room_player_game_states gs
      where gs.room_id=p_room_id and gs.user_id=v_owner_id
      for update;
    if not found then raise exception '증거 카드 소유자의 게임 데이터를 찾을 수 없습니다.'; end if;
    select e.value into v_card
      from jsonb_array_elements(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)) e(value)
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

  -- Move a field card between zones for effects. This is intentionally manual-effect powered,
  -- can be used for either player's field, and changes only the appropriate owner's private zone.
  if p_action = 'move_field_card' then
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id', '')::uuid, v_user);
    v_dest := lower(coalesce(p_payload ->> 'destination', ''));
    v_id := nullif(p_payload ->> 'instance_id', '');
    if v_owner_id <> v_user and not exists (select 1 from public.room_players rp where rp.room_id = p_room_id and rp.user_id = v_owner_id) then raise exception '선택한 카드 소유자를 찾을 수 없습니다.'; end if;
    if v_dest not in ('hand', 'deck', 'remove', 'evidence_top') then raise exception '이동 목적지는 손패/덱/리무브/앞면 증거 중에서 선택해 주세요.'; end if;
    if v_dest='evidence_top' and v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료한 뒤 증거 카드를 이동해 주세요.'; end if;
    select * into v_board from public.room_player_turn_boards b where b.room_id = p_room_id and b.user_id = v_owner_id for update;
    if not found then raise exception '카드 소유자의 보드를 찾을 수 없습니다.'; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id;
    v_is_mr_partner := false;
    v_is_non_mr_partner := false;
    if v_card is null and v_board.partner_mr_card ->> 'instance_id' = v_id then
      v_card := v_board.partner_mr_card;
      v_is_mr_partner := true;
    end if;
    if v_card is null then
      select e.value into v_card from jsonb_array_elements(coalesce(v_board.partner_non_mr_cards, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id;
      v_is_non_mr_partner := v_card is not null;
    end if;
    if v_card is null then raise exception '현장 또는 MR 파트너 에이리어에서 이동할 카드를 찾을 수 없습니다.'; end if;
    if v_is_mr_partner or v_is_non_mr_partner then
      v_field_new := coalesce(v_board.field_cards, '[]'::jsonb);
    else
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb)
        into v_field_new from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    end if;
    if v_is_non_mr_partner then
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' is distinct from v_id), '[]'::jsonb)
        into v_partner_non_mr_new from jsonb_array_elements(coalesce(v_board.partner_non_mr_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    else
      v_partner_non_mr_new := coalesce(v_board.partner_non_mr_cards, '[]'::jsonb);
    end if;
    select * into v_game from public.room_player_game_states g where g.room_id = p_room_id and g.user_id = v_owner_id for update;
    if not found then raise exception '카드 소유자의 비공개 게임 데이터를 찾을 수 없습니다.'; end if;
    if v_dest='remove'
   and not v_is_mr_partner
   and not v_is_non_mr_partner
   and upper(coalesce(v_card ->> 'rarity',v_card ->> 'rarity_code',v_card ->> 'rarityCode',v_card #>> '{sourceData,rarity}',v_card #>> '{raw,rarity}',p_payload ->> 'rarity','')) IN ('MR','MRP') then
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
  end if;
    if v_dest = 'hand' then
      update public.room_player_game_states g set hand = coalesce(g.hand, '[]'::jsonb) || jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'), updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_owner_id;
    elsif v_dest = 'deck' then
      update public.room_player_game_states g set deck_order = coalesce(g.deck_order, '[]'::jsonb) || jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'), updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_owner_id;
    elsif v_dest = 'evidence_top' then
      update public.room_player_game_states g set
        evidence_cards = coalesce(g.evidence_cards, '[]'::jsonb) || jsonb_build_array((v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving') || jsonb_build_object('face_up', true)),
        updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_owner_id;
    else
      update public.room_player_game_states g set remove_cards = coalesce(g.remove_cards, '[]'::jsonb) || jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'), updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_owner_id;
    end if;
    update public.room_player_turn_boards b set
      field_cards = v_field_new,
      partner_mr_card = case when v_is_mr_partner then null else b.partner_mr_card end,
      partner_non_mr_cards = coalesce(v_partner_non_mr_new, '[]'::jsonb),
      evidence_count = coalesce(evidence_count,0) + case when v_dest = 'evidence_top' then 1 else 0 end,
      remove_count = remove_count + case when v_dest = 'remove' then 1 else 0 end,
      updated_at = now()
    where b.room_id = p_room_id and b.user_id = v_owner_id;
    update public.room_match_states m set state_version = state_version + 1,
      last_action_label = format('카드를 %s 영역으로 이동했습니다.', case v_dest when 'hand' then '손패' when 'deck' then '덱 아래' when 'evidence_top' then '앞면 공개 증거 맨 위' else '리무브' end)
      where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Move one selected card from the remove area to the caller's hand.
  if p_action = 'move_remove_card_to_hand' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '리무브 영역에서 해당 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id),'[]'::jsonb)
      into v_remove_new from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set remove_cards=v_remove_new, hand=coalesce(gs.hand,'[]'::jsonb)||jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up'), updated_at=now()
      where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards tb set remove_count=greatest(0,coalesce(tb.remove_count,0)-1),updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='리무브 영역의 카드를 손패로 가져왔습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Effect-driven appearance from remove area. Nested SET/stacked cards are not counted as field slots.
  if p_action = 'play_remove_character' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    if jsonb_array_length(coalesce(v_board.field_cards,'[]'::jsonb)) >= 5 then IF (
    SELECT count(*)
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) AS field_card(value)
    WHERE upper(coalesce(field_card.value ->> 'card_type','')) = 'CHARACTER'
  ) >= 5 THEN
    RAISE EXCEPTION '현장 캐릭터 수 제한을 초과했습니다.';
  END IF; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '리무브 영역에서 해당 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id),'[]'::jsonb) into v_remove_new
      from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    v_field_new := coalesce(v_board.field_cards,'[]'::jsonb) || jsonb_build_array((v_card - 'face_up' - 'resolving') || jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',true));
    update public.room_player_game_states gs set remove_cards=v_remove_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards tb set field_cards=v_field_new,remove_count=greatest(0,coalesce(tb.remove_count,0)-1),base_action_done=true,character_played_this_turn=true,updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='효과 처리: 리무브 영역의 캐릭터를 현장에 등장시켰습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- Chosen hand/remove card can be transferred into the MR partner area by manual effect.
  if p_action = 'move_card_to_mr_partner' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_dest := lower(coalesce(p_payload ->> 'source',''));
    v_id := nullif(p_payload ->> 'instance_id','');
    if v_dest='hand' then
      select e.value into v_card from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
      if v_card is null then raise exception '손패에서 해당 카드를 찾을 수 없습니다.'; end if;
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id),'[]'::jsonb) into v_hand_new
        from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set hand=v_hand_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    elsif v_dest='remove' then
      select e.value into v_card from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
      if v_card is null then raise exception '리무브 영역에서 해당 카드를 찾을 수 없습니다.'; end if;
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id),'[]'::jsonb) into v_remove_new
        from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set remove_cards=v_remove_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
      update public.room_player_turn_boards tb set remove_count=greatest(0,coalesce(tb.remove_count,0)-1),updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_user;
    else raise exception '손패 또는 리무브 영역에서 카드를 선택해 주세요.'; end if;
    v_card := (v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'face_up') || jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',false);
    if upper(coalesce(v_card ->> 'rarity', v_card ->> 'rarity_code', v_card ->> 'rarityCode', v_card ->> 'rarityKo', '')) = 'MR' then
      if v_board.partner_mr_card is not null then raise exception 'MR 파트너 에이리어의 MR 슬롯이 이미 사용 중입니다.'; end if;
      update public.room_player_turn_boards tb set partner_mr_card=v_card,updated_at=now()
        where tb.room_id=p_room_id and tb.user_id=v_user;
    else
      update public.room_player_turn_boards tb set partner_non_mr_cards=coalesce(tb.partner_non_mr_cards,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
        where tb.room_id=p_room_id and tb.user_id=v_user;
    end if;
    update public.room_match_states m set state_version=state_version+1,last_action_label=case when upper(coalesce(v_card ->> 'rarity', v_card ->> 'rarity_code', v_card ->> 'rarityCode', v_card ->> 'rarityKo', ''))='MR' then '선택한 MR 카드를 MR 파트너 에이리어에 이동했습니다.' else '선택한 비MR 카드를 MR 외 카드 박스에 이동했습니다.' end where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- SET: put a selected hand/remove/top-of-deck card underneath a target field host visually.
  if p_action = 'set_card_to_field' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'host_owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'host_instance_id','');
    v_dest := lower(coalesce(p_payload ->> 'source',''));
    if not exists(select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_owner_id) then raise exception '세트 대상 카드 소유자를 찾을 수 없습니다.'; end if;
    select * into v_opponent_board from public.room_player_turn_boards tb where tb.room_id=p_room_id and tb.user_id=v_owner_id for update;
    if not exists(select 1 from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id) then raise exception '세트할 대상이 현장에 없습니다.'; end if;
    if v_dest='hand' then
      v_attack_id := nullif(p_payload ->> 'source_instance_id','');
      select e.value into v_card from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_attack_id;
      if v_card is null then raise exception '손패에서 세트할 카드를 찾을 수 없습니다.'; end if;
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_attack_id),'[]'::jsonb) into v_hand_new from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set hand=v_hand_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    elsif v_dest='remove' then
      v_attack_id := nullif(p_payload ->> 'source_instance_id','');
      select e.value into v_card from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_attack_id;
      if v_card is null then raise exception '리무브 영역에서 세트할 카드를 찾을 수 없습니다.'; end if;
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_attack_id),'[]'::jsonb) into v_remove_new from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set remove_cards=v_remove_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
      update public.room_player_turn_boards tb set remove_count=greatest(0,coalesce(tb.remove_count,0)-1),updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_user;
    elsif v_dest='deck_top' then
      if jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb))<1 then raise exception '덱에 세트할 카드가 없습니다.'; end if;
      v_card := v_game.deck_order -> 0;
      select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality>1),'[]'::jsonb) into v_deck_new from jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) with ordinality e(value,ordinality);
      update public.room_player_game_states gs set deck_order=v_deck_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    else raise exception '손패, 리무브, 덱 위 중에서 세트 카드를 선택해 주세요.'; end if;
    if lower(coalesce(v_card ->> 'card_type','')) not in ('event','character') then raise exception '캐릭터 또는 이벤트 카드만 세트할 수 있습니다.'; end if;
    v_card := (v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving') || jsonb_build_object('face_up',coalesce((p_payload ->> 'face_up')::boolean,false),'set_owner_user_id',v_user,'host_instance_id',v_id);
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('set_cards',coalesce(e.value -> 'set_cards','[]'::jsonb)||jsonb_build_array(v_card)) else e.value end order by e.ordinality),'[]'::jsonb) into v_field_new
      from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards tb set field_cards=v_field_new,updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label=format('카드 1장을 현장 카드 아래에 %s으로 세트했습니다.',case when coalesce((p_payload ->> 'face_up')::boolean,false) then '앞면' else '뒷면' end) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'stack_remove_under_field' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    v_owner_id := coalesce(nullif(p_payload ->> 'host_owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'host_instance_id','');
    v_attack_id := nullif(p_payload ->> 'source_instance_id','');
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_attack_id;
    if v_card is null then raise exception '리무브 영역에서 겹칠 카드를 찾을 수 없습니다.'; end if;
    select * into v_opponent_board from public.room_player_turn_boards tb where tb.room_id=p_room_id and tb.user_id=v_owner_id for update;
    if not exists(select 1 from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id) then raise exception '겹쳐 둘 현장 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_attack_id),'[]'::jsonb) into v_remove_new from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set remove_cards=v_remove_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('stacked_cards',coalesce(e.value -> 'stacked_cards','[]'::jsonb)||jsonb_build_array((v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving')||jsonb_build_object('face_up',coalesce((p_payload ->> 'face_up')::boolean,true),'set_owner_user_id',v_user,'host_instance_id',v_id)) ) else e.value end order by e.ordinality),'[]'::jsonb) into v_field_new
      from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards tb set field_cards=v_field_new,updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_owner_id;
    update public.room_player_turn_boards tb set remove_count=greatest(0,coalesce(tb.remove_count,0)-1),updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='리무브 카드 1장을 현장 카드 아래에 겹쳤습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'move_set_card_to_hand' then
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

  if p_action = 'reveal_set_card' then
    v_owner_id := coalesce(nullif(p_payload ->> 'host_owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'host_instance_id','');
    v_attack_id := nullif(p_payload ->> 'set_instance_id','');
    select * into v_opponent_board from public.room_player_turn_boards tb where tb.room_id=p_room_id and tb.user_id=v_owner_id for update;
    if not found then raise exception '세트 카드 소유자의 보드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('set_cards',coalesce((select jsonb_agg(case when sc.value ->> 'instance_id'=v_attack_id then sc.value || jsonb_build_object('face_up',true) else sc.value end order by sc.ordinality) from jsonb_array_elements(coalesce(e.value -> 'set_cards','[]'::jsonb)) with ordinality sc(value,ordinality)),'[]'::jsonb)) else e.value end order by e.ordinality),'[]'::jsonb) into v_field_new
      from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    if not exists(select 1 from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) host(value) cross join lateral jsonb_array_elements(coalesce(host.value -> 'set_cards','[]'::jsonb)) sc(value) where host.value ->> 'instance_id'=v_id and sc.value ->> 'instance_id'=v_attack_id and coalesce((sc.value ->> 'face_up')::boolean,false)=false) then raise exception '뒷면 세트 카드를 찾을 수 없습니다.'; end if;
    update public.room_player_turn_boards tb set field_cards=v_field_new,updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label='세트 카드를 앞면으로 공개했습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- The file's newest card is publicly revealed to both players before it moves to remove.
  if p_action = 'remove_top_file' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    if jsonb_array_length(coalesce(v_game.file_cards,'[]'::jsonb)) < 1 then raise exception '파일 에이리어가 비어 있습니다.'; end if;
    v_card := v_game.file_cards -> (jsonb_array_length(v_game.file_cards)-1);
    v_pending := jsonb_build_object(
      'type','file_remove_reveal',
      'source_user_id',v_user::text,
      'cards',jsonb_build_array(v_card),
      'acknowledged_user_ids','[]'::jsonb
    );
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,
      last_action_label='파일 맨 위 카드를 양쪽 플레이어에게 공개했습니다. 두 사람 모두 확인하면 리무브로 이동합니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- File area top is the last JSON array item, matching the UI order.
  if p_action = 'take_top_file_to_hand' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    if jsonb_array_length(coalesce(v_game.file_cards,'[]'::jsonb))<1 then raise exception '파일 에이리어가 비어 있습니다.'; end if;
    v_card := (v_game.file_cards -> (jsonb_array_length(v_game.file_cards)-1)) - 'face_up';
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.ordinality < jsonb_array_length(coalesce(v_game.file_cards,'[]'::jsonb))),'[]'::jsonb) into v_files_new
      from jsonb_array_elements(coalesce(v_game.file_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set file_cards=v_files_new,hand=coalesce(gs.hand,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_player_turn_boards tb set file_count=greatest(0,coalesce(tb.file_count,0)-1),updated_at=now() where tb.room_id=p_room_id and tb.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='파일 맨 위 카드를 손패로 가져왔습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'reveal_top_file' then
    if jsonb_array_length(coalesce(v_game.file_cards,'[]'::jsonb))<1 then raise exception '파일 에이리어가 비어 있습니다.'; end if;
    v_i := jsonb_array_length(v_game.file_cards)-1;
    v_card := v_game.file_cards -> v_i;
    if coalesce((v_card ->> 'face_up')::boolean,false) then raise exception '파일 맨 위 카드는 이미 앞면입니다.'; end if;
    select coalesce(jsonb_agg(case when e.ordinality=v_i+1 then e.value || jsonb_build_object('face_up',true) else e.value end order by e.ordinality),'[]'::jsonb) into v_files_new
      from jsonb_array_elements(coalesce(v_game.file_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states gs set file_cards=v_files_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='파일 맨 위 카드를 앞면으로 공개했습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'move_hand_card' then
    v_id := nullif(p_payload ->> 'instance_id', '');
    v_dest := lower(coalesce(p_payload ->> 'destination', ''));
    if v_dest not in ('deck', 'deck_top', 'remove', 'file_top', 'file_bottom') then raise exception '손패 이동 목적지를 선택해 주세요.'; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.hand, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id;
    if v_card is null then raise exception '손패에서 이동할 카드를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb)
      into v_hand_new from jsonb_array_elements(coalesce(v_game.hand, '[]'::jsonb)) with ordinality e(value, ordinality);
    if v_dest in ('deck','deck_top') then
      update public.room_player_game_states g set hand = v_hand_new, deck_order = case when v_dest='deck_top' then jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving') || coalesce(g.deck_order, '[]'::jsonb) else coalesce(g.deck_order, '[]'::jsonb) || jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving') end, updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_user;
    elsif v_dest in ('file_top','file_bottom') then
      update public.room_player_game_states g set hand=v_hand_new,
        file_cards=case when v_dest='file_top' then coalesce(g.file_cards,'[]'::jsonb)||jsonb_build_array((v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving')||jsonb_build_object('face_up',true)) else jsonb_build_array((v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving')||jsonb_build_object('face_up',true))||coalesce(g.file_cards,'[]'::jsonb) end, updated_at=now()
      where g.room_id=p_room_id and g.user_id=v_user;
      update public.room_player_turn_boards b set file_count=coalesce(file_count,0)+1,updated_at=now() where b.room_id=p_room_id and b.user_id=v_user;
    elsif v_dest='remove' then
      update public.room_player_game_states g set hand = v_hand_new, remove_cards = coalesce(g.remove_cards, '[]'::jsonb) || jsonb_build_array(v_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving'), updated_at = now()
      where g.room_id = p_room_id and g.user_id = v_user;
      update public.room_player_turn_boards b set remove_count = remove_count + 1, updated_at = now() where b.room_id = p_room_id and b.user_id = v_user;
    end if;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = format('손패 카드를 %s 영역으로 이동했습니다.', case v_dest when 'deck_top' then '덱 위' when 'deck' then '덱 아래' when 'file_top' then '파일 맨 위(앞면)' when 'file_bottom' then '파일 맨 아래(앞면)' when 'remove' then '리무브' else v_dest end) where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'move_hand_card_to_evidence' then
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

  if p_action = 'gain_evidence_from_deck' then
    if v_match.pending_action is not null then raise exception '진행 중인 응답을 먼저 완료해 주세요.'; end if;
    if jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)) < 1 then raise exception '증거로 가져올 덱 카드가 없습니다.'; end if;
    perform public.draw_private_turn_card(p_room_id,v_user,'evidence');
    update public.room_match_states m set state_version=state_version+1,
      last_action_label='내 덱 맨 위 카드 1장을 증거 에이리어로 가져왔습니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'shuffle_deck' then
    select coalesce(jsonb_agg(e.value order by random()),'[]'::jsonb) into v_deck_new
      from jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb)) e(value);
    update public.room_player_game_states gs set deck_order=v_deck_new,updated_at=now() where gs.room_id=p_room_id and gs.user_id=v_user;
    update public.room_match_states m set state_version=state_version+1,last_action_label='내 덱을 전체 셔플했습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'add_ap_bonus' then
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'instance_id','');
    v_amount := coalesce(nullif(p_payload ->> 'amount','')::integer,0);
    if v_amount < 1 or v_amount > 10000 then raise exception 'AP 추가 수치는 1~10000 사이로 입력해 주세요.'; end if;
    if not exists(select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_owner_id) then raise exception 'AP 추가 대상의 소유자를 찾을 수 없습니다.'; end if;
    select * into v_board from public.room_player_turn_boards b where b.room_id=p_room_id and b.user_id=v_owner_id for update;
    if not found then raise exception 'AP 추가 대상 보드를 찾을 수 없습니다.'; end if;
    if not exists(select 1 from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id and coalesce(e.value ->> 'card_type','')='character') then raise exception 'AP를 추가할 현장 캐릭터를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('ap_bonus',coalesce(nullif(e.value ->> 'ap_bonus','')::integer,0)+v_amount) else e.value end order by e.ordinality),'[]'::jsonb)
      into v_new_status_field from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b set field_cards=v_new_status_field,updated_at=now() where b.room_id=p_room_id and b.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label=format('효과 처리: 캐릭터 한 장의 AP를 이번 턴 동안 +%s 했습니다.',v_amount) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'rest_character_manual' then
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'instance_id','');
    select * into v_board from public.room_player_turn_boards b where b.room_id=p_room_id and b.user_id=v_owner_id for update;
    if not found then raise exception '슬립 대상 보드를 찾을 수 없습니다.'; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id and coalesce(e.value ->> 'card_type','')='character';
    if v_card is null then raise exception '슬립할 현장 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce(v_card ->> 'status','active') = 'rested'
        or (coalesce((v_card ->> 'rested')::boolean,false) and coalesce(v_card ->> 'status','active') <> 'stunned') then
      raise exception '이미 슬립 상태인 캐릭터입니다.';
    end if;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('rested',true,'status','rested') else e.value end order by e.ordinality),'[]'::jsonb)
      into v_new_status_field from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b set field_cards=v_new_status_field,updated_at=now() where b.room_id=p_room_id and b.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label=format('효과 처리: %s 캐릭터를 수동으로 슬립 상태로 만들었습니다.',coalesce(v_card ->> 'key','선택한')) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'activate_character' then
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id','')::uuid,v_user);
    v_id := nullif(p_payload ->> 'instance_id','');
    select * into v_board from public.room_player_turn_boards b where b.room_id=p_room_id and b.user_id=v_owner_id for update;
    if not found or not exists(select 1 from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id and coalesce(e.value ->> 'card_type','')='character') then raise exception '액티브로 되돌릴 현장 캐릭터를 찾을 수 없습니다.'; end if;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('rested',false,'status','active','summoned_this_turn',coalesce((e.value ->> 'summoned_this_turn')::boolean,false)) else e.value end order by e.ordinality),'[]'::jsonb)
      into v_new_status_field from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b set field_cards=v_new_status_field,updated_at=now() where b.room_id=p_room_id and b.user_id=v_owner_id;
    update public.room_match_states m set state_version=state_version+1,last_action_label='효과 처리: 선택한 캐릭터를 액티브 상태로 되돌렸습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'guard_with_character' then
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
  end if;

  if p_action = 'stun_character' then
    v_owner_id := coalesce(nullif(p_payload ->> 'owner_user_id', '')::uuid, v_user);
    v_id := nullif(p_payload ->> 'instance_id', '');
    if not exists (select 1 from public.room_players rp where rp.room_id = p_room_id and rp.user_id = v_owner_id) then raise exception '스턴 대상 소유자를 찾을 수 없습니다.'; end if;
    select * into v_board from public.room_player_turn_boards b where b.room_id = p_room_id and b.user_id = v_owner_id for update;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id' = v_id then e.value || jsonb_build_object('status','stunned','rested',true,'summoned_this_turn',false) else e.value end order by e.ordinality), '[]'::jsonb)
      into v_field_new from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    if not exists (select 1 from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id) then raise exception '스턴할 현장 캐릭터를 찾을 수 없습니다.'; end if;
    update public.room_player_turn_boards b set field_cards = v_field_new, updated_at = now() where b.room_id = p_room_id and b.user_id = v_owner_id;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = '효과 처리: 선택한 캐릭터를 스턴(180도 회전) 상태로 만들었습니다.' where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'play_character' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 등장할 수 있습니다.'; end if;
    if coalesce(v_board.base_card_played_this_turn, false) then raise exception '이번 턴의 기본 카드 사용을 이미 완료했습니다. 추가 카드는 넥스트 힌트를 사용해 주세요.'; end if;
    if coalesce(v_board.base_character_played_this_turn, v_board.character_played_this_turn, false) then raise exception '이번 턴에는 이미 기본 캐릭터를 등장했습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id', '');
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.hand, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id;
    if v_card is null or coalesce(v_card ->> 'card_type', '') <> 'character' then raise exception '손패에서 등장할 캐릭터를 찾을 수 없습니다.'; end if;
    if jsonb_array_length(coalesce(v_board.field_cards, '[]'::jsonb)) >= 5
      and not (upper(coalesce(v_card ->> 'rarity', '')) IN ('MR','MRP')
        and exists (select 1 from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value) where upper(coalesce(e.value ->> 'rarity', '')) IN ('MR','MRP')))
    then IF (
    SELECT count(*)
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) AS field_card(value)
    WHERE upper(coalesce(field_card.value ->> 'card_type','')) = 'CHARACTER'
  ) >= 5 THEN
    RAISE EXCEPTION '현장 캐릭터 수 제한을 초과했습니다.';
  END IF; end if;
    v_cost_limit := v_board.file_count + case when v_board.partner_assist_used then 1 else 0 end;
    if coalesce(nullif(v_card ->> 'cost', '')::numeric, 0) > v_cost_limit then raise exception '현재 레벨 상한(%)을 초과합니다.', v_cost_limit; end if;
    if upper(coalesce(v_card ->> 'rarity', '')) IN ('MR','MRP') then perform public.clear_private_field_mr_for_deployment(p_room_id, v_user); end if;
    select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.value ->> 'instance_id' <> v_id), '[]'::jsonb) into v_hand_new
    from jsonb_array_elements(coalesce(v_game.hand, '[]'::jsonb)) with ordinality e(value, ordinality);
    update public.room_player_game_states g set hand = v_hand_new, updated_at = now() where g.room_id = p_room_id and g.user_id = v_user;
    update public.room_player_turn_boards b set field_cards = coalesce(b.field_cards, '[]'::jsonb) || jsonb_build_array(v_card || jsonb_build_object('rested',false,'status','active','summoned_this_turn',true,'ap_bonus',0)), character_played_this_turn = true, base_character_played_this_turn = true, base_action_done = true, base_card_played_this_turn = true, updated_at = now()
    where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_match_states m set state_version = state_version + 1, last_action_label = '캐릭터를 현장에 등장했습니다. 새로 등장한 카드는 기본적으로 이번 턴에 행동할 수 없습니다.' where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'partner_deduce' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 파트너 추리를 할 수 있습니다.'; end if;
    if v_board.partner_rested then raise exception '파트너는 이번 턴에 이미 행동했습니다.'; end if;
    update public.room_player_turn_boards b set partner_rested = true, partner_deduction_used = true, base_action_done = true, updated_at = now() where b.room_id = p_room_id and b.user_id = v_user;
    perform public.draw_private_turn_card(p_room_id, v_user, 'evidence');
    update public.room_match_states m set state_version = state_version + 1, last_action_label = '파트너 추리: 증거 1장을 획득했습니다.' where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'investigate' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 추리할 수 있습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id', '');
    v_amount := coalesce(nullif(p_payload ->> 'evidence_count', '')::integer, 0);
    if v_amount < 0 or v_amount > 3 then raise exception '캐릭터 추리 증거 수는 0~3장입니다.'; end if;
    select e.value into v_card from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id;
    if v_card is null or coalesce(v_card ->> 'card_type', '') <> 'character' then raise exception '추리할 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce((v_card ->> 'rested')::boolean, false) or coalesce(v_card ->> 'status','') in ('rested','stunned') then raise exception '슬립/스턴 상태의 캐릭터는 추리할 수 없습니다.'; end if;
    if coalesce((v_card ->> 'summoned_this_turn')::boolean, false) and coalesce((p_payload ->> 'allow_newly_played')::boolean, false) is not true then raise exception '이번 턴에 등장한 캐릭터는 기본적으로 행동할 수 없습니다. 효과 예외 옵션을 켜 주세요.'; end if;
    select rp.user_id into v_other_user from public.room_players rp where rp.room_id = p_room_id and rp.user_id <> v_user limit 1;
    select * into v_opponent_board from public.room_player_turn_boards b where b.room_id = p_room_id and b.user_id = v_other_user for update;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id' = v_id then e.value || jsonb_build_object('rested',true,'status','rested') else e.value end order by e.ordinality), '[]'::jsonb)
      into v_new_status_field from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    update public.room_player_turn_boards b set field_cards = v_new_status_field, base_action_done = true, updated_at = now() where b.room_id = p_room_id and b.user_id = v_user;
    if v_amount > 0 and exists (
      select 1 from jsonb_array_elements(coalesce(v_opponent_board.field_cards, '[]'::jsonb)) e(value)
      where coalesce((e.value ->> 'rested')::boolean, false) = false
        and coalesce(e.value ->> 'status','active') = 'active'
        and coalesce((e.value ->> 'summoned_this_turn')::boolean, false) = false
        and coalesce(nullif(e.value ->> 'mislead_value','')::integer, 0) > 0
    ) then
      v_pending := jsonb_build_object('type','mislead_response','investigator_user_id',v_user,'investigator_instance_id',v_id,'target_user_id',v_other_user,'evidence_count',v_amount);
      update public.room_match_states m set pending_action = v_pending, state_version = state_version + 1,
        last_action_label = '추리 선언: 상대에게 액티브 미스리드 사용 기회가 있습니다.' where m.room_id = p_room_id;
    else
      for v_i in 1..v_amount loop perform public.draw_private_turn_card(p_room_id, v_user, 'evidence'); end loop;
      update public.room_match_states m set state_version = state_version + 1, last_action_label = format('캐릭터 추리: 증거 %s장을 획득했습니다.', v_amount) where m.room_id = p_room_id;
    end if;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'pass_mislead' then
    if v_match.pending_action ->> 'type' <> 'mislead_response' or v_match.pending_action ->> 'target_user_id' <> v_user::text then raise exception '현재 미스리드에 응답할 수 없습니다.'; end if;
    v_target_user_id := (v_match.pending_action ->> 'investigator_user_id')::uuid;
    v_amount := coalesce(nullif(v_match.pending_action ->> 'evidence_count','')::integer,0);
    for v_i in 1..v_amount loop perform public.draw_private_turn_card(p_room_id, v_target_user_id, 'evidence'); end loop;
    update public.room_match_states m set pending_action = null, state_version = state_version + 1, last_action_label = format('미스리드 없이 추리를 진행했습니다. 증거 %s장을 획득했습니다.',v_amount) where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'resolve_mislead' then
    if v_match.pending_action ->> 'type' <> 'mislead_response' or v_match.pending_action ->> 'target_user_id' <> v_user::text then raise exception '현재 미스리드에 응답할 수 없습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value) where e.value ->> 'instance_id' = v_id;
    if v_card is null or coalesce((v_card ->> 'rested')::boolean,false) or coalesce(v_card ->> 'status','active') <> 'active' then raise exception '액티브 상태의 미스리드 캐릭터를 선택해 주세요.'; end if;
    if coalesce((v_card ->> 'summoned_this_turn')::boolean,false) and coalesce((p_payload ->> 'allow_newly_played')::boolean,false) is not true then raise exception '이번 턴에 등장한 캐릭터의 효과 예외 옵션을 켜 주세요.'; end if;
    v_mr_value := greatest(0,coalesce(nullif(v_card ->> 'mislead_value','')::integer,0));
    if v_mr_value < 1 then raise exception '이 카드의 미스리드 수치를 확인할 수 없습니다.'; end if;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id' = v_id then e.value || jsonb_build_object('rested',true,'status','rested') else e.value end order by e.ordinality), '[]'::jsonb)
      into v_new_status_field from jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) with ordinality e(value, ordinality);
    update public.room_player_turn_boards b set field_cards = v_new_status_field, base_action_done = true, updated_at = now() where b.room_id = p_room_id and b.user_id = v_user;
    v_target_user_id := (v_match.pending_action ->> 'investigator_user_id')::uuid;
    v_amount := greatest(0,coalesce(nullif(v_match.pending_action ->> 'evidence_count','')::integer,0) - v_mr_value);
    for v_i in 1..v_amount loop perform public.draw_private_turn_card(p_room_id, v_target_user_id, 'evidence'); end loop;
    update public.room_match_states m set pending_action = null, state_version = state_version + 1,
      last_action_label = format('미스리드 %s 발동: 상대 추리를 %s장 줄여 증거 %s장을 획득하게 했습니다.',v_mr_value,least(v_mr_value,coalesce(nullif(v_match.pending_action ->> 'evidence_count','')::integer,0)),v_amount)
    where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'declare_contact' then
    if v_match.current_turn_user_id <> v_user or v_match.turn_step <> 'main' or v_match.pending_action is not null then raise exception '자신의 메인 단계에서만 컨택할 수 있습니다.'; end if;
    v_attack_id := nullif(p_payload ->> 'attacker_instance_id','');
    v_target_id := nullif(p_payload ->> 'target_instance_id','');
    v_target_user_id := nullif(p_payload ->> 'target_user_id','')::uuid;
    if v_target_user_id is null or v_target_user_id = v_user or not exists(select 1 from public.room_players rp where rp.room_id=p_room_id and rp.user_id=v_target_user_id) then raise exception '상대 캐릭터를 지정해 주세요.'; end if;
    select * into v_opponent_board from public.room_player_turn_boards b where b.room_id=p_room_id and b.user_id=v_target_user_id for update;
    if not found then raise exception '상대 보드를 찾을 수 없습니다.'; end if;
    select e.value into v_attacker from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_attack_id and e.value ->> 'card_type'='character';
    select e.value into v_target from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_target_id and e.value ->> 'card_type'='character';
    if v_attacker is null or v_target is null then raise exception '공격자 또는 대상 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce((v_attacker ->> 'rested')::boolean,false) or coalesce(v_attacker ->> 'status','active') in ('rested','stunned') then raise exception '슬립/스턴 상태의 캐릭터는 공격할 수 없습니다.'; end if;
    if coalesce((v_attacker ->> 'summoned_this_turn')::boolean,false) and coalesce((p_payload ->> 'allow_newly_played')::boolean,false) is not true then raise exception '이번 턴 등장한 캐릭터는 기본적으로 공격할 수 없습니다.'; end if;
    if coalesce((v_target ->> 'rested')::boolean,false)=false and coalesce(v_target ->> 'status','active')='active'
       and coalesce((p_payload ->> 'allow_active_target')::boolean,false) is not true
       and NOT (
         public.private_card_effect_matches_id_v1(v_attacker,'["0938"]'::jsonb)
         AND public.private_card_effect_level_v1(v_target)>=7
       ) then
      raise exception '기본적으로 슬립/스턴 상태의 상대 캐릭터만 공격할 수 있습니다. 단, 마츠다 진페이는 레벨 7 이상 액티브 캐릭터에도 컨택할 수 있습니다.';
    end if;
    v_pending := jsonb_build_object(
      'type','character_contact_guard','attacker_user_id',v_user,'attacker_instance_id',v_attack_id,
      'target_user_id',v_target_user_id,'target_instance_id',v_target_id,
      'attacker_ap',coalesce(nullif(v_attacker ->> 'ap','')::numeric,0)+coalesce(nullif(v_attacker ->> 'ap_bonus','')::numeric,0),
      'target_ap',coalesce(nullif(v_target ->> 'ap','')::numeric,0)+coalesce(nullif(v_target ->> 'ap_bonus','')::numeric,0),
      'attacker_bonus',0,'target_bonus',0,'cut_in_used',false,'attacker_cut_in_used',false,'target_cut_in_used',false,'next_responder_user_id',v_target_user_id
    );
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_attack_id then e.value || jsonb_build_object('rested',true,'status','rested') else e.value end order by e.ordinality),'[]'::jsonb)
      into v_new_status_field from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b set field_cards=v_new_status_field,base_action_done=true,updated_at=now() where b.room_id=p_room_id and b.user_id=v_user;
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,last_action_label='컨택 선언. 수비자가 가드할 캐릭터를 지정하거나 가드하지 않을 수 있습니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'contact_use_disguise' then
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
      || jsonb_build_object(
        'rested',true,'status','rested',
        'ap_bonus',coalesce(nullif(v_target->>'ap_bonus','')::numeric,0),
        'dsl_ap_bonus',coalesce(nullif(v_target->>'dsl_ap_bonus','')::numeric,0),
        'summoned_this_turn',true,
        'under_cards',coalesce(v_target->'under_cards','[]'::jsonb),
        'stacked_cards',coalesce(v_target->'stacked_cards','[]'::jsonb),
        'dsl_keywords',coalesce(v_target->'dsl_keywords','[]'::jsonb),
        'dsl_continuous_keywords',coalesce(v_target->'dsl_continuous_keywords','[]'::jsonb),
        'dsl_bond_name_overrides',coalesce(v_target->'dsl_bond_name_overrides','[]'::jsonb),
        'dsl_return_to_deck_bottom_turn',v_target->'dsl_return_to_deck_bottom_turn',
        'dsl_return_to_deck_bottom_after_user_id',v_target->'dsl_return_to_deck_bottom_after_user_id',
        'haya_activated_turn_number',v_target->'haya_activated_turn_number',
        'mislead_value',coalesce(v_target->'mislead_value',v_card->'mislead_value')
      )
    );

    update public.room_player_game_states gs
      set hand=v_hand_new,
          deck_order=coalesce(gs.deck_order,'[]'::jsonb)||jsonb_build_array(
            v_target - 'rested' - 'status' - 'ap_bonus' - 'dsl_ap_bonus' - 'summoned_this_turn' - 'resolving'
              - 'under_cards' - 'stacked_cards' - 'dsl_keywords' - 'dsl_continuous_keywords'
              - 'dsl_bond_name_overrides' - 'dsl_return_to_deck_bottom_turn' - 'dsl_return_to_deck_bottom_after_user_id'
              - 'haya_activated_turn_number' - 'mislead_value'
          ),
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
  end if;

  if p_action = 'guard_contact_with_character' then
    if v_match.pending_action ->> 'type' <> 'character_contact_guard' or v_match.pending_action ->> 'target_user_id' <> v_user::text then raise exception '현재 컨택 가드를 선택할 차례가 아닙니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select * into v_opponent_board from public.room_player_turn_boards b where b.room_id=p_room_id and b.user_id=v_user for update;
    select e.value into v_card from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) e(value)
      where e.value ->> 'instance_id'=v_id and e.value ->> 'card_type'='character';
    if v_card is null or v_id=v_match.pending_action ->> 'target_instance_id' then raise exception '가드할 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce((v_card ->> 'rested')::boolean,false) or coalesce(v_card ->> 'status','active')<>'active' then raise exception '액티브 상태의 캐릭터로 가드해 주세요.'; end if;
    select coalesce(jsonb_agg(case when e.value ->> 'instance_id'=v_id then e.value || jsonb_build_object('rested',true,'status','rested') else e.value end order by e.ordinality),'[]'::jsonb)
      into v_field_new from jsonb_array_elements(coalesce(v_opponent_board.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_turn_boards b set field_cards=v_field_new,updated_at=now() where b.room_id=p_room_id and b.user_id=v_user;
    v_pending := jsonb_set(v_match.pending_action,'{guarded_original_target_instance_id}',to_jsonb(v_match.pending_action ->> 'target_instance_id'));
    v_pending := jsonb_set(v_pending,'{target_instance_id}',to_jsonb(v_id));
    v_pending := jsonb_set(v_pending,'{target_ap}',to_jsonb(coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0)));
    v_pending := jsonb_set(v_pending,'{type}',to_jsonb('character_contact'::text));
    v_pending := v_pending - 'attacker_cut_in_used' - 'target_cut_in_used' - 'attacker_cut_in_passed' - 'target_cut_in_passed' - 'cut_in_used';
    v_pending := v_pending || jsonb_build_object(
      'attacker_cut_in_used',false,
      'target_cut_in_used',false,
      'attacker_cut_in_passed',false,
      'target_cut_in_passed',false,
      'cut_in_used',false,
      'guarded_contact',true,
      'attacker_bonus',0,
      'target_bonus',0
    );
    
v_pending := jsonb_set(v_pending,'{cut_in_priority_user_id}',to_jsonb(
  CASE
    WHEN coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'target_bonus','')::numeric,0)
       <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'attacker_bonus','')::numeric,0)
    THEN v_pending ->> 'target_user_id'
    ELSE v_pending ->> 'attacker_user_id'
  END
));
v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(
  CASE
    WHEN coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'target_bonus','')::numeric,0)
       <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'attacker_bonus','')::numeric,0)
    THEN v_pending ->> 'target_user_id'
    ELSE v_pending ->> 'attacker_user_id'
  END
));
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,last_action_label=format('수비자가 %s로 컨택을 가드했습니다. 해당 캐릭터는 슬립되었으며 컷인 선택으로 진행합니다.',coalesce(v_card ->> 'key','캐릭터')) where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  if p_action = 'decline_contact_guard' then
    if v_match.pending_action ->> 'type' <> 'character_contact_guard' or v_match.pending_action ->> 'target_user_id' <> v_user::text then raise exception '현재 컨택 가드를 선택할 차례가 아닙니다.'; end if;
    v_pending := jsonb_set(v_match.pending_action,'{type}',to_jsonb('character_contact'::text));
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_user::text));
    
v_pending := jsonb_set(v_pending,'{cut_in_priority_user_id}',to_jsonb(
  CASE
    WHEN coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'target_bonus','')::numeric,0)
       <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'attacker_bonus','')::numeric,0)
    THEN v_pending ->> 'target_user_id'
    ELSE v_pending ->> 'attacker_user_id'
  END
));
v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(
  CASE
    WHEN coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'target_bonus','')::numeric,0)
       <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'attacker_bonus','')::numeric,0)
    THEN v_pending ->> 'target_user_id'
    ELSE v_pending ->> 'attacker_user_id'
  END
));
update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,last_action_label='수비자가 가드하지 않았습니다. 이제 컷인 사용 여부를 선택합니다.' where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  
if p_action = 'contact_pass_cutin' then
  if v_match.pending_action is null
     or v_match.pending_action ->> 'type' is distinct from 'character_contact' then
    raise exception '컷인 선택 단계가 아닙니다.';
  end if;
  if v_match.pending_action ->> 'next_responder_user_id' is distinct from v_user::text then
    raise exception '현재 컷인 응답 순서가 아닙니다.';
  end if;
  v_pending := v_match.pending_action;

  if v_user::text = v_pending ->> 'target_user_id' then
    v_pending := jsonb_set(v_pending,'{target_cut_in_passed}','true'::jsonb);
    if coalesce(nullif(v_pending ->> 'attacker_cut_in_used','')::boolean,false)
       or coalesce(nullif(v_pending ->> 'attacker_cut_in_passed','')::boolean,false) then
      perform public.resolve_private_character_contact(p_room_id,v_pending);
      return public.get_private_turn_state_v2(p_room_id);
    end if;
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'attacker_user_id'));
    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label='수비자가 컷인을 패스했습니다. 이제 공격자가 컷인 사용 여부를 선택합니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  elsif v_user::text = v_pending ->> 'attacker_user_id' then
    v_pending := jsonb_set(v_pending,'{attacker_cut_in_passed}','true'::jsonb);
    if coalesce(nullif(v_pending ->> 'target_cut_in_used','')::boolean,false)
       or coalesce(nullif(v_pending ->> 'target_cut_in_passed','')::boolean,false) then
      perform public.resolve_private_character_contact(p_room_id,v_pending);
      return public.get_private_turn_state_v2(p_room_id);
    end if;
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'target_user_id'));
    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label='공격자가 컷인을 패스했습니다. 이제 수비자가 컷인 사용 여부를 선택합니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  else
    raise exception '컨택 참가자만 컷인 선택을 처리할 수 있습니다.';
  end if;
end if;

if p_action = 'contact_adjust_ap' then
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

  if p_action = 'contact_use_cutin' then
    if v_match.pending_action ->> 'type' <> 'character_contact' or v_match.pending_action ->> 'next_responder_user_id' <> v_user::text then raise exception '현재 컨택 응답 차례가 아닙니다.'; end if;
    if (
  (
    v_user::text = (v_match.pending_action ->> 'target_user_id')
    AND (
      COALESCE(NULLIF(v_match.pending_action ->> 'target_cut_in_used','')::boolean,false)
      OR COALESCE(NULLIF(v_match.pending_action ->> 'target_cut_in_passed','')::boolean,false)
    )
  )
  OR
  (
    v_user::text = (v_match.pending_action ->> 'attacker_user_id')
    AND (
      COALESCE(NULLIF(v_match.pending_action ->> 'attacker_cut_in_used','')::boolean,false)
      OR COALESCE(NULLIF(v_match.pending_action ->> 'attacker_cut_in_passed','')::boolean,false)
    )
  )
) then raise exception '이 컨택에서는 이미 컷인을 사용했습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id','');
    select e.value into v_card from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '손패에서 컷인 카드를 찾을 수 없습니다.'; end if;
    v_bonus := greatest(0,coalesce(nullif(v_card ->> 'cut_in_bonus','')::integer,0));

    -- PR278: partner-yellow adds 1000 AP, and draws one if used to support a Police character.
    IF public.private_card_effect_matches_id_v1(v_card, '["0940"]'::jsonb)
       AND public.private_card_effect_partner_color_v1(p_room_id, v_user) = 'yellow' THEN
      v_bonus := v_bonus + 1000;
      v_target_id := CASE
        WHEN v_user::text = v_match.pending_action ->> 'attacker_user_id'
          THEN coalesce(v_match.pending_action ->> 'attacker_instance_id', v_match.pending_action ->> 'attacker_id')
        ELSE coalesce(v_match.pending_action ->> 'target_instance_id', v_match.pending_action ->> 'target_id')
      END;
      v_cut_in_subject := NULL;
      SELECT e.value INTO v_cut_in_subject
      FROM public.room_player_turn_boards b
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards, '[]'::jsonb)) e(value)
      WHERE b.room_id = p_room_id AND b.user_id = v_user
        AND e.value ->> 'instance_id' = v_target_id
      LIMIT 1;
      IF v_cut_in_subject IS NOT NULL
         AND public.private_card_effect_is_character_v1(v_cut_in_subject)
         AND public.private_card_effect_has_trait_v1(v_cut_in_subject, '警察') THEN
        PERFORM public.draw_private_turn_card(p_room_id, v_user, 'hand');
      END IF;
    END IF;

    -- B05095: during its owner's turn, each Police character on the owner's field adds 1000 AP.
    IF public.private_card_effect_matches_id_v1(v_card, '["0593"]'::jsonb)
       AND v_match.current_turn_user_id = v_user THEN
      SELECT count(*)::integer INTO v_count
      FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) field_card(value)
      WHERE public.private_card_effect_is_character_v1(field_card.value)
        AND public.private_card_effect_has_trait_v1(field_card.value, '警察');
      v_bonus := v_bonus + 1000 * greatest(coalesce(v_count, 0), 0);
    END IF;
    IF upper(coalesce(v_card ->> 'key','')) IN ('PR158','PR164')
       OR EXISTS (
         SELECT 1
         FROM unnest(ARRAY[
           v_card ->> 'cardId', v_card ->> 'card_id', v_card ->> 'cardNum', v_card ->> 'card_num',
           v_card ->> 'databaseId', v_card ->> 'database_id', v_card ->> 'id',
           v_card #>> '{sourceData,cardId}', v_card #>> '{sourceData,card_id}',
           v_card #>> '{sourceData,cardNum}', v_card #>> '{sourceData,card_num}',
           v_card #>> '{sourceData,databaseId}', v_card #>> '{sourceData,database_id}',
           v_card #>> '{sourceData,id}'
         ]) AS cutin_ids(identifier)
         WHERE nullif(ltrim(regexp_replace(coalesce(cutin_ids.identifier,''), '[^0-9]', '', 'g'), '0'), '') = '627'
       )
    THEN
      SELECT count(*)::integer
         INTO v_count
       FROM jsonb_array_elements(coalesce(v_game.remove_cards, '[]'::jsonb)) AS removed(value)
       WHERE EXISTS (
         SELECT 1
         FROM unnest(ARRAY[
           removed.value ->> 'name',
           removed.value ->> 'nameKo',
           removed.value ->> 'name_ko',
           removed.value ->> 'originalName',
           removed.value ->> 'original_name',
           removed.value ->> 'translatedName',
           removed.value ->> 'translated_name',
           removed.value ->> 'cardName',
           removed.value ->> 'card_name',
           removed.value ->> 'title',
           removed.value #>> '{sourceData,name}',
           removed.value #>> '{sourceData,nameKo}',
           removed.value #>> '{sourceData,name_ko}',
           removed.value #>> '{sourceData,originalName}',
           removed.value #>> '{raw,name}',
           removed.value #>> '{raw,nameKo}'
         ]) AS card_names(value)
         WHERE lower(regexp_replace(coalesce(card_names.value,''), '[[:space:]]', '', 'g'))
           IN ('범인','犯人')
       );
      v_bonus := 2000 * (greatest(coalesce(v_count,0),0) + 1);
    END IF;
        select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_id),'[]'::jsonb) into v_hand_new
      from jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb)) with ordinality e(value,ordinality);
    update public.room_player_game_states g set hand=v_hand_new,remove_cards=coalesce(g.remove_cards,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now() where g.room_id=p_room_id and g.user_id=v_user;
    update public.room_player_turn_boards b set remove_count=remove_count+1,updated_at=now() where b.room_id=p_room_id and b.user_id=v_user;
    if v_user=(v_match.pending_action ->> 'attacker_user_id')::uuid then
      v_pending := jsonb_set(v_match.pending_action,'{attacker_bonus}',to_jsonb(v_bonus));
      v_pending := jsonb_set(v_pending,'{attacker_cut_in_used}','true'::jsonb);
    else
      v_pending := jsonb_set(v_match.pending_action,'{target_bonus}',to_jsonb(v_bonus));
      v_pending := jsonb_set(v_pending,'{target_cut_in_used}','true'::jsonb);
    end if;
    v_pending := jsonb_set(v_pending,'{cut_in_used}','true'::jsonb);

if (coalesce(nullif(v_pending ->> 'attacker_cut_in_used','')::boolean,false)
      or coalesce(nullif(v_pending ->> 'attacker_cut_in_passed','')::boolean,false))
   and (coalesce(nullif(v_pending ->> 'target_cut_in_used','')::boolean,false)
      or coalesce(nullif(v_pending ->> 'target_cut_in_passed','')::boolean,false)) then
  perform public.resolve_private_character_contact(p_room_id,v_pending);
  return public.get_private_turn_state_v2(p_room_id);
end if;
if v_user::text = v_pending ->> 'target_user_id' then
  v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'attacker_user_id'));
  update public.room_match_states m
    set pending_action=v_pending,state_version=state_version+1,
        last_action_label='수비자가 컷인을 사용했습니다. 이제 공격자가 컷인 사용 여부를 선택합니다.'
    where m.room_id=p_room_id;
else
  v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'target_user_id'));
  update public.room_match_states m
    set pending_action=v_pending,state_version=state_version+1,
        last_action_label='공격자가 컷인을 사용했습니다. 이제 수비자가 컷인 사용 여부를 선택합니다.'
    where m.room_id=p_room_id;
end if;
return public.get_private_turn_state_v2(p_room_id);

    perform public.resolve_private_character_contact(p_room_id,v_pending);
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  -- All other standard actions remain handled by the previously tested RPC. We wrap its return
  -- value so callers get display names/private remove list, and remember when a base action has
  -- occurred for the Next Hint restriction.
  if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime','acknowledge_culprits_crime','rest_partner_manual','acknowledge_evidence_remove') then
    raise exception '지원하지 않는 턴 행동입니다: %', p_action;
  end if;

  
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
      -- Rebuild the declarer's deck from the current remove pile after the failed check.
      select * into v_game
        from public.room_player_game_states gs
        where gs.room_id=p_room_id and gs.user_id=v_owner_id
        for update;
      if not found then raise exception '범인들의 범행 리프레시: 선언 플레이어의 카드 영역을 찾을 수 없습니다.'; end if;

      select coalesce(jsonb_agg(e.value order by random()),'[]'::jsonb)
        into v_deck_new
        from jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value);
      update public.room_player_game_states gs
        set deck_order=coalesce(v_deck_new,'[]'::jsonb),
            remove_cards='[]'::jsonb,
            updated_at=now()
        where gs.room_id=p_room_id and gs.user_id=v_owner_id;
      update public.room_player_turn_boards b
        set remove_count=0,updated_at=now()
        where b.room_id=p_room_id and b.user_id=v_owner_id;

      -- Preserve the refresh side effect: the opponent receives the new top card as evidence.
      select rp.user_id into v_other_user
        from public.room_players rp
        where rp.room_id=p_room_id and rp.user_id<>v_owner_id
        limit 1;
      if v_other_user is not null then
        select * into v_opponent_game
          from public.room_player_game_states gs
          where gs.room_id=p_room_id and gs.user_id=v_other_user
          for update;
        if jsonb_array_length(coalesce(v_opponent_game.deck_order,'[]'::jsonb))>0 then
          v_card := v_opponent_game.deck_order -> 0;
          select coalesce(jsonb_agg(e.value order by e.ordinality) filter (where e.ordinality>1),'[]'::jsonb)
            into v_deck_new
            from jsonb_array_elements(v_opponent_game.deck_order) with ordinality e(value,ordinality);
          update public.room_player_game_states gs
            set deck_order=coalesce(v_deck_new,'[]'::jsonb),
                evidence_cards=coalesce(v_opponent_game.evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card),
                updated_at=now()
            where gs.room_id=p_room_id and gs.user_id=v_other_user;
          update public.room_player_turn_boards b
            set evidence_count=jsonb_array_length(coalesce(v_opponent_game.evidence_cards,'[]'::jsonb))+1,
                updated_at=now()
            where b.room_id=p_room_id and b.user_id=v_other_user;
        end if;
      end if;

      update public.room_match_states m set
        pending_action=null,state_version=state_version+1,
        last_action_label=format('범인들의 범행 확인 결과 특징 [범인] 증거는 %s장으로 8장 미만입니다. 게임을 계속하며 리프레시했습니다.',v_culprit_count)
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

if p_action = 'begin_turn' then
    update public.room_player_turn_boards set base_action_done = false where room_id = p_room_id and user_id = v_user;
  end if;
  if p_action = 'attack_character' then
    raise exception '캐릭터 공격은 컨택 선언(declare_contact)부터 시작해야 합니다.';
  end if;
  if p_action = 'partner_assist' and coalesce(v_board.next_hint_pending,false) then raise exception '넥스트 힌트로 가져온 캐릭터를 먼저 등장시켜야 파트너 어시스트를 사용할 수 있습니다.'; end if;
  if p_action = 'solve_case' then
    v_culprit_key := regexp_replace(coalesce(v_board.event_key, ''), '[^0-9]', '', 'g');
    if coalesce(v_board.event_rule_code, '') = 'culprits_1046'
       or coalesce(nullif(ltrim(v_culprit_key, '0'), ''), '0') = '1046' then
      raise exception '1046 사건 카드는 일반 사건 해결을 사용할 수 없습니다. 범인들의 범행을 선언해 주세요.';
    end if;
    v_count := case
      when coalesce(v_board.event_rule_code, '') = 'conan_vs_kid_1261'
        or coalesce(nullif(ltrim(v_culprit_key, '0'), ''), '0') in ('1261','11098')
        then case when v_match.first_player_user_id=v_user then 8 else 7 end
      else case when v_match.first_player_user_id=v_user then 7 else 6 end
    end;
    if v_board.case_phase <> 'solution' then raise exception '내 보드가 해결편에 진입하지 않았습니다.'; end if;
    if v_board.evidence_count < v_count then raise exception '사건 해결에는 증거 %장이 필요합니다. 현재 %장입니다.',v_count,v_board.evidence_count; end if;
    if coalesce(v_board.partner_rested,false) or coalesce(v_board.partner_assist_used,false) then raise exception '사건 해결 선언에는 액티브 상태의 파트너가 필요합니다.'; end if;
    delete from public.room_hand_reveals r where r.room_id=p_room_id;
    update public.room_match_states m set
      game_over=true,
      winner_user_id=v_user,
      winner_turn_number=m.turn_number,
      end_display_names=coalesce(m.end_display_names, (select jsonb_object_agg(rp.user_id::text, coalesce(nullif(rp.temporary_nickname,''), '플레이어 ' || rp.seat::text)) from public.room_players rp where rp.room_id=p_room_id)),
      state_version=state_version+1,
      last_action_label='사건 해결 성공! 승리 선언이 완료되었습니다.'
    where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;
  if p_action = 'attack_evidence' then
    v_id := nullif(p_payload ->> 'attacker_instance_id','');
    select e.value into v_card from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value) where e.value ->> 'instance_id'=v_id;
    if v_card is null then raise exception '공격할 캐릭터를 찾을 수 없습니다.'; end if;
    if coalesce((v_card ->> 'summoned_this_turn')::boolean,false) and coalesce((p_payload ->> 'allow_newly_played')::boolean,false) is not true then raise exception '이번 턴 등장한 캐릭터는 기본적으로 공격할 수 없습니다.'; end if;
  end if;
  if p_action = 'partner_assist' and jsonb_array_length(coalesce(v_board.field_cards,'[]'::jsonb)) < 0 then raise exception '파트너 어시스트 오류'; end if;
    if p_action = 'end_turn' and coalesce(v_board.next_hint_pending,false) then
    raise exception '넥스트 힌트로 가져온 캐릭터를 먼저 등장시켜야 턴을 종료할 수 있습니다.';
  end if;

    if p_action = 'cancel_next_hint' then
    if v_match.pending_action is not null then
      raise exception '진행 중인 응답을 먼저 완료해야 넥스트 힌트를 응급 취소할 수 있습니다.';
    end if;
    if not coalesce(v_board.next_hint_pending,false) then
      raise exception '취소할 넥스트 힌트가 없습니다.';
    end if;

    update public.room_player_turn_boards b
      set next_hint_pending=false, updated_at=now()
      where b.room_id=p_room_id and b.user_id=v_user;
    if not found then
      raise exception '넥스트 힌트 상태를 갱신하지 못했습니다.';
    end if;

    update public.room_match_states m
      set state_version=state_version+1,
          last_action_label='넥스트 힌트 응급 취소: 캐릭터 등장 의무를 해제했습니다. 가져온 파일 카드는 손패에 유지됩니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

if p_action = 'rest_partner_manual' then
    if v_match.current_turn_user_id is distinct from v_user
       or coalesce(v_match.turn_step, '') <> 'main'
       or v_match.pending_action is not null then
      raise exception '파트너 슬립은 자신의 메인 단계에서만 처리할 수 있습니다.';
    end if;
    if nullif(trim(coalesce(v_board.partner_key, '')), '') is null then
      raise exception '슬립시킬 파트너 카드가 없습니다.';
    end if;
    if coalesce(v_board.partner_rested, false) or coalesce(v_board.partner_assist_used, false) then
      raise exception '파트너가 이미 슬립 상태이거나 이번 턴에 사용되었습니다.';
    end if;
    update public.room_player_turn_boards b
      set partner_rested = true, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_match_states m
      set state_version = state_version + 1,
          last_action_label = '카드 효과 처리: 파트너를 슬립 상태로 만들었습니다.'
      where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));
  if p_action in ('play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence') then
    update public.room_player_turn_boards set base_action_done = true where room_id = p_room_id and user_id = v_user;
  elsif p_action = 'end_turn' then
    update public.room_player_turn_boards set
      base_action_done = false,
      next_hint_pending = false,
      field_cards = coalesce((select jsonb_agg(e.value || jsonb_build_object('ap_bonus',0) order by e.ordinality)
        from jsonb_array_elements(coalesce(room_player_turn_boards.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality)), '[]'::jsonb),
      updated_at=now()
    where room_id = p_room_id and user_id = v_user;
  end if;
  return public.get_private_turn_state_v2(p_room_id);
end;
$function$
