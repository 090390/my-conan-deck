-- Treat normal character deployment and event play as the same once-per-turn card play.
-- A pending Next Hint lets the player play one additional character OR one event; either resolves the pending requirement.
ALTER TABLE public.room_player_turn_boards
  ADD COLUMN IF NOT EXISTS base_card_played_this_turn boolean NOT NULL DEFAULT false;

-- Preserve the already-known character-play state for any active turn when introducing the shared flag.
UPDATE public.room_player_turn_boards b
SET base_card_played_this_turn = true
WHERE coalesce(b.base_character_played_this_turn, false)
   OR coalesce(b.character_played_this_turn, false)
   OR EXISTS (
     SELECT 1
     FROM jsonb_array_elements(coalesce(b.field_cards, '[]'::jsonb)) field_card(value)
     WHERE coalesce(field_card.value ->> 'card_type', '') = 'event'
       AND coalesce((field_card.value ->> 'resolving')::boolean, false)
   );

DO $base_card_play_rules$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  -- A basic character cannot be played after either a basic character or event was already played.
  v_old := $old$if coalesce(v_board.base_character_played_this_turn, v_board.character_played_this_turn, false) then raise exception '이번 턴에는 이미 기본 캐릭터를 등장했습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id', '');$old$;
  v_new := $new$if coalesce(v_board.base_card_played_this_turn, false) then raise exception '이번 턴의 기본 카드 사용을 이미 완료했습니다. 추가 카드는 넥스트 힌트를 사용해 주세요.'; end if;
    if coalesce(v_board.base_character_played_this_turn, v_board.character_played_this_turn, false) then raise exception '이번 턴에는 이미 기본 캐릭터를 등장했습니다.'; end if;
    v_id := nullif(p_payload ->> 'instance_id', '');$new$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: character play guard anchor was not found.';
  END IF;

  -- Event cards also consume the basic card play, unless Next Hint is currently pending.
  v_old := $old$if coalesce(v_card ->> 'card_type', '') <> 'event' then raise exception '이벤트 카드만 사용할 수 있습니다.'; end if;
    v_cost_limit := v_board.file_count$old$;
  v_new := $new$if coalesce(v_card ->> 'card_type', '') <> 'event' then raise exception '이벤트 카드만 사용할 수 있습니다.'; end if;
    if coalesce(v_board.base_card_played_this_turn, false)
       and not coalesce(v_board.next_hint_pending, false) then
      raise exception '이번 턴의 기본 카드 사용을 이미 완료했습니다. 추가 카드는 넥스트 힌트를 사용해 주세요.';
    end if;
    v_cost_limit := v_board.file_count$new$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: event play guard anchor was not found.';
  END IF;

  -- Mark basic character deployment as the shared once-per-turn card play.
  v_old := $old$character_played_this_turn = true, base_character_played_this_turn = true, base_action_done = true, updated_at = now()$old$;
  v_new := $new$character_played_this_turn = true, base_character_played_this_turn = true, base_action_done = true, base_card_played_this_turn = true, updated_at = now()$new$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: character state update anchor was not found.';
  END IF;

  -- Playing an event during Next Hint counts as the one required card and clears the pending state.
  v_old := $old$base_action_done = true, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;$old$;
  v_new := $new$base_action_done = true, base_card_played_this_turn = true, next_hint_pending = false, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;$new$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: event state update anchor was not found.';
  END IF;

  -- The character deployed via Next Hint also consumes the shared card-play allowance.
  v_old := $old$next_hint_pending=false,next_hint_used=true,base_action_done=true,updated_at=now()$old$;
  v_new := $new$next_hint_pending=false,next_hint_used=true,base_action_done=true,base_card_played_this_turn=true,updated_at=now()$new$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: Next Hint character state update anchor was not found.';
  END IF;

  -- Reset the shared flag when the new turn begins.
  v_old := $old$next_hint_pending = false,
      base_action_done = false,
      files_to_place = v_count,$old$;
  v_new := $new$next_hint_pending = false,
      base_action_done = false,
      base_card_played_this_turn = false,
      files_to_place = v_count,$new$;
  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: begin-turn reset anchor was not found.';
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'Base card play migration stopped: gameplay function definition is empty.';
  END IF;
  EXECUTE v_definition;
END
$base_card_play_rules$;
