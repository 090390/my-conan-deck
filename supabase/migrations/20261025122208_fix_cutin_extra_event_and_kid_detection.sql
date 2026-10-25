-- Fix ID:0627 count, support effect-driven extra event play, and match ID:0301
-- by normalized IDs or the full printed card attributes to avoid missed data shapes.
DO $patch$
DECLARE
  v_definition text;
  v_special_pos integer;
  v_count_pos integer;
  v_bonus_pos integer;
  v_kid_where_pos integer;
  v_kid_where_length integer;
  v_insert_pos integer;
  v_old_bonus text := 'v_bonus := 2000 * greatest(coalesce(v_count,0),0);';
  v_new_bonus text := 'v_bonus := 2000 * (greatest(coalesce(v_count,0),0) + 1);';

  v_new_cutin_count text := $new_count$SELECT count(*)::integer
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
       );$new_count$;

  v_new_kid_where text := $kid$where coalesce(nullif(ltrim(btrim(candidate.value), '0'), ''), '0') = '301'
             or coalesce(nullif(ltrim(regexp_replace(upper(btrim(candidate.value)), '^ID\s*:\s*', ''), '0'), ''), '0') = '301'
             or nullif(ltrim(regexp_replace(coalesce(candidate.value,''), '[^0-9]', '', 'g'), '0'), '') = '301'
             or (
               regexp_replace(lower(coalesce(
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
               )), '[[:space:]]', '', 'g') in ('괴도키드','怪盗キッド')
               and upper(coalesce(other_card.value ->> 'rarity', other_card.value ->> 'rarity_code', '')) = 'SR'
               and coalesce(nullif(other_card.value ->> 'cost','')::numeric, -1) = 8
               and coalesce(nullif(other_card.value ->> 'ap','')::numeric, -1) = 7000
               and coalesce(nullif(other_card.value ->> 'lp','')::numeric, -1) = 2
               and upper(coalesce(other_card.value ->> 'color', other_card.value ->> 'originalColor', other_card.value ->> 'colorJp', '')) in ('백','白','白色','WHITE')
               and upper(coalesce(
                 other_card.value ->> 'set',
                 other_card.value ->> 'originalSet',
                 other_card.value ->> 'original_set',
                 other_card.value ->> 'product',
                 other_card.value ->> 'package',
                 ''
               )) like '%CT-P03%'
             )$kid$;

  v_new_extra_event text := $extra$if p_action = 'extra_play_event' then
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

  if p_action = 'extra_play_character' then$extra$;

BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  v_special_pos := position('IF upper(coalesce(v_card ->> ''key'','''')) IN (''PR158'',''PR164'')' IN v_definition);
  IF v_special_pos = 0 THEN RAISE EXCEPTION 'Could not find the ID:0627 cut-in branch.'; END IF;
  v_count_pos := v_special_pos + position('SELECT count(*)::integer' IN substring(v_definition from v_special_pos)) - 1;
  v_bonus_pos := position(v_old_bonus IN v_definition);
  IF v_count_pos < v_special_pos OR v_bonus_pos <= v_count_pos THEN
    RAISE EXCEPTION 'Could not locate the ID:0627 cut-in count and bonus.';
  END IF;
  v_definition := overlay(v_definition placing v_new_cutin_count || E'\n      ' from v_count_pos for (v_bonus_pos - v_count_pos));
  v_definition := replace(v_definition, v_old_bonus, v_new_bonus);

  v_kid_where_pos := position('where coalesce(nullif(ltrim(btrim(candidate.value)' IN v_definition);
  IF v_kid_where_pos = 0 THEN RAISE EXCEPTION 'Could not find the ID:0301 identifier check.'; END IF;
  v_kid_where_length := position(E'\n        )\n    ) into v_kid_stun_lock;' IN substring(v_definition from v_kid_where_pos)) - 1;
  IF v_kid_where_length <= 0 THEN RAISE EXCEPTION 'Could not locate the end of the ID:0301 check.'; END IF;
  v_definition := overlay(v_definition placing v_new_kid_where from v_kid_where_pos for v_kid_where_length);

  v_insert_pos := position('if p_action = ''extra_play_character'' then' IN v_definition);
  IF v_insert_pos = 0 THEN RAISE EXCEPTION 'Could not find extra character deployment action.'; END IF;
  v_definition := overlay(v_definition placing v_new_extra_event from v_insert_pos for length('if p_action = ''extra_play_character'' then'));

  EXECUTE v_definition;
END
$patch$;
