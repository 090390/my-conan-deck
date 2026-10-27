DO $patch$
DECLARE
  v_definition text;
BEGIN
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);

  IF position('remove_deck_peek_card' in v_definition) = 0 THEN
    IF position($old$'take_deck_peek_card','return_deck_peek'$old$ in v_definition) = 0 THEN
      RAISE EXCEPTION 'deck peek action whitelist anchor not found';
    END IF;
    v_definition := replace(
      v_definition,
      $old$'take_deck_peek_card','return_deck_peek'$old$,
      $new$'take_deck_peek_card','remove_deck_peek_card','return_deck_peek'$new$
    );

    IF position($old$  if p_action = 'share_deck_peek_card' then$old$ in v_definition) = 0 THEN
      RAISE EXCEPTION 'deck peek action insertion anchor not found';
    END IF;
    v_definition := replace(
      v_definition,
      $old$  if p_action = 'share_deck_peek_card' then$old$,
      $new$  if p_action = 'remove_deck_peek_card' then
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

  if p_action = 'share_deck_peek_card' then$new$
    );
    EXECUTE v_definition;
  END IF;
END;
$patch$;
