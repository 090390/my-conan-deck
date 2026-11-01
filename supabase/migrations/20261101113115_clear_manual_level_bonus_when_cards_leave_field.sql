DO $patch$
DECLARE
  v_move_definition text;
  v_legacy_definition text;
  v_old_move text := $old$-'ap_bonus'-'summoned_this_turn'$old$;
  v_new_move text := $new$-'ap_bonus'-'level_bonus'-'summoned_this_turn'$new$;
  v_old_legacy text := $old$- 'ap_bonus' - 'summoned_this_turn'$old$;
  v_new_legacy text := $new$- 'ap_bonus' - 'level_bonus' - 'summoned_this_turn'$new$;
  v_old_end text;
  v_new_end text;
BEGIN
  v_move_definition := pg_get_functiondef(
    'public.private_card_effect_move_card_v1(uuid,uuid,text,jsonb,text,uuid)'::regprocedure
  );
  IF position(v_old_move in v_move_definition) = 0 THEN
    RAISE EXCEPTION 'field-to-zone cleanup expression not found in card effect mover';
  END IF;
  v_move_definition := replace(v_move_definition, v_old_move, v_new_move);
  v_move_definition := replace(
    v_move_definition,
    $old$jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',false)$old$,
    $new$jsonb_build_object('rested',false,'status','active','ap_bonus',0,'level_bonus',0,'summoned_this_turn',false)$new$
  );
  v_move_definition := replace(
    v_move_definition,
    $old$jsonb_build_object('summoned_this_turn',true,'ap_bonus',0,'entry_method',coalesce(v_card->>'entry_method','event_effect'))$old$,
    $new$jsonb_build_object('summoned_this_turn',true,'ap_bonus',0,'level_bonus',0,'entry_method',coalesce(v_card->>'entry_method','event_effect'))$new$
  );
  EXECUTE v_move_definition;

  v_legacy_definition := pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  );
  IF position(v_old_legacy in v_legacy_definition) = 0 THEN
    RAISE EXCEPTION 'manual field-to-zone cleanup expression not found in legacy turn action';
  END IF;
  v_legacy_definition := replace(v_legacy_definition, v_old_legacy, v_new_legacy);

  v_old_end := $old$  elsif p_action = 'end_turn' then
    update public.room_player_turn_boards set
      base_action_done = false,
      next_hint_pending = false,
      field_cards = coalesce((select jsonb_agg(e.value || jsonb_build_object('ap_bonus',0,'level_bonus',0) order by e.ordinality)
        from jsonb_array_elements(coalesce(room_player_turn_boards.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality)), '[]'::jsonb),
      updated_at=now()
    where room_id = p_room_id and user_id = v_user;
  end if;$old$;

  v_new_end := $new$  elsif p_action = 'end_turn' then
    update public.room_player_turn_boards set
      base_action_done = false,
      next_hint_pending = false,
      field_cards = coalesce((select jsonb_agg(e.value || jsonb_build_object('ap_bonus',0,'level_bonus',0) order by e.ordinality)
        from jsonb_array_elements(coalesce(room_player_turn_boards.field_cards,'[]'::jsonb)) with ordinality e(value,ordinality)), '[]'::jsonb),
      updated_at=now()
    where room_id = p_room_id and user_id = v_user;

    -- Manual level changes are temporary for the current turn, even when they
    -- were applied to a character on the opposing field.
    update public.room_player_turn_boards b
    set field_cards = coalesce((
      select jsonb_agg(
        case when coalesce(nullif(e.value->>'level_bonus','')::integer,0) <> 0
          then e.value || jsonb_build_object('level_bonus',0)
          else e.value
        end order by e.ordinality
      )
      from jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb))
        with ordinality e(value,ordinality)
    ),'[]'::jsonb),
    updated_at=now()
    where b.room_id=p_room_id
      and exists (
        select 1 from jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
        where coalesce(nullif(e.value->>'level_bonus','')::integer,0) <> 0
      );
  end if;$new$;

  IF position(v_old_end in v_legacy_definition) = 0 THEN
    RAISE EXCEPTION 'end-turn reset block not found in legacy turn action';
  END IF;
  v_legacy_definition := replace(v_legacy_definition, v_old_end, v_new_end);

  -- Ensure cards that return from Remove Area start with their printed level.
  v_legacy_definition := replace(
    v_legacy_definition,
    $old$(v_card - 'face_up' - 'resolving') || jsonb_build_object('rested',false,'status','active','ap_bonus',0,'summoned_this_turn',true)$old$,
    $new$(v_card - 'face_up' - 'resolving' - 'level_bonus') || jsonb_build_object('rested',false,'status','active','ap_bonus',0,'level_bonus',0,'summoned_this_turn',true)$new$
  );
  EXECUTE v_legacy_definition;
END
$patch$;
