CREATE OR REPLACE FUNCTION public.set_private_character_bullet_manual_v1(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_instance_id text,
  p_enabled boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_match public.room_match_states%ROWTYPE;
  v_board public.room_player_turn_boards%ROWTYPE;
  v_card jsonb;
  v_keywords jsonb;
  v_field_new jsonb;
  v_instance_id text := nullif(btrim(coalesce(p_instance_id, '')), '');
  v_enabled boolean := coalesce(p_enabled, false);
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players
    WHERE room_id = p_room_id AND user_id = v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자만 불렛 수동 지정 상태를 변경할 수 있습니다.';
  END IF;

  IF p_owner_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players
    WHERE room_id = p_room_id AND user_id = p_owner_user_id
  ) THEN
    RAISE EXCEPTION '불렛 지정 대상 카드의 소유자를 찾을 수 없습니다.';
  END IF;

  IF v_instance_id IS NULL THEN
    RAISE EXCEPTION '불렛 지정 대상 카드가 선택되지 않았습니다.';
  END IF;

  SELECT * INTO v_match
  FROM public.room_match_states
  WHERE room_id = p_room_id
  FOR UPDATE;

  IF NOT FOUND OR v_match.phase <> 'playing' OR v_match.game_over THEN
    RAISE EXCEPTION '진행 중인 게임에서만 불렛 수동 지정 상태를 변경할 수 있습니다.';
  END IF;
  IF v_match.pending_action IS NOT NULL THEN
    RAISE EXCEPTION '진행 중인 선택/응답을 먼저 완료해 주세요.';
  END IF;

  SELECT * INTO v_board
  FROM public.room_player_turn_boards
  WHERE room_id = p_room_id AND user_id = p_owner_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '불렛 지정 대상의 턴 보드를 찾을 수 없습니다.';
  END IF;

  SELECT e.value INTO v_card
  FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value)
  WHERE e.value ->> 'instance_id' = v_instance_id
  LIMIT 1;

  IF v_card IS NULL THEN
    RAISE EXCEPTION '현장에서 불렛을 지정할 카드를 찾을 수 없습니다.';
  END IF;
  IF lower(coalesce(v_card ->> 'card_type', '')) <> 'character' THEN
    RAISE EXCEPTION '불렛 수동 지정은 캐릭터 카드에만 적용할 수 있습니다.';
  END IF;

  v_keywords := CASE
    WHEN jsonb_typeof(v_card -> 'dsl_keywords') = 'array' THEN v_card -> 'dsl_keywords'
    ELSE '[]'::jsonb
  END;

  IF v_enabled THEN
    IF NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v_keywords) k(value)
      WHERE coalesce(k.value ->> 'effect_id', '') = 'manual-bullet-toggle'
    ) THEN
      v_keywords := v_keywords || jsonb_build_array(jsonb_build_object(
        'keyword', 'bullet',
        'effect_id', 'manual-bullet-toggle',
        'source', 'manual'
      ));
    END IF;
  ELSE
    SELECT coalesce(jsonb_agg(k.value ORDER BY k.ordinality), '[]'::jsonb)
    INTO v_keywords
    FROM jsonb_array_elements(v_keywords) WITH ORDINALITY k(value, ordinality)
    WHERE coalesce(k.value ->> 'effect_id', '') <> 'manual-bullet-toggle';
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE WHEN e.value ->> 'instance_id' = v_instance_id THEN
      jsonb_set(
        jsonb_set(e.value, '{dsl_keywords}', v_keywords, true),
        '{manual_bullet}', to_jsonb(v_enabled), true
      )
    ELSE e.value END
    ORDER BY e.ordinality
  ), '[]'::jsonb)
  INTO v_field_new
  FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb))
    WITH ORDINALITY e(value, ordinality);

  UPDATE public.room_player_turn_boards
  SET field_cards = v_field_new,
      updated_at = now()
  WHERE room_id = p_room_id AND user_id = p_owner_user_id;

  UPDATE public.room_match_states
  SET state_version = state_version + 1,
      last_action_label = CASE WHEN v_enabled
        THEN format('수동 효과: %s 캐릭터에 불렛을 지정했습니다.', coalesce(v_card ->> 'key', '선택한'))
        ELSE format('수동 효과: %s 캐릭터의 불렛 지정을 해제했습니다.', coalesce(v_card ->> 'key', '선택한'))
      END
  WHERE room_id = p_room_id;

  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.set_private_character_bullet_manual_v1(uuid, uuid, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_private_character_bullet_manual_v1(uuid, uuid, text, boolean) TO authenticated;
