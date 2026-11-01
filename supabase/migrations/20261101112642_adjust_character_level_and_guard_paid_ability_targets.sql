CREATE OR REPLACE FUNCTION public.private_card_effect_level_v1(p_card jsonb)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT coalesce(
    nullif(regexp_replace(coalesce(
      p_card ->> 'level', p_card ->> 'cost',
      p_card ->> 'level_number', p_card #>> '{sourceData,level}',
      p_card #>> '{sourceData,cost}', p_card #>> '{raw,level}',
      p_card #>> '{raw,cost}', ''
    ), '[^0-9-]', '', 'g'), '')::integer,
    0
  ) + coalesce(nullif(p_card ->> 'level_bonus', '')::integer, 0)
$function$;

CREATE OR REPLACE FUNCTION public.adjust_private_character_level_v1(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_instance_id text,
  p_delta integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_card jsonb;
  v_field_new jsonb;
  v_old_bonus integer;
  v_new_bonus integer;
  v_base_level integer;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players
    WHERE room_id = p_room_id AND user_id = v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자만 캐릭터 레벨을 조정할 수 있습니다.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_players
    WHERE room_id = p_room_id AND user_id = p_owner_user_id
  ) THEN
    RAISE EXCEPTION '레벨 조정 대상 소유자의 방 참가 정보를 찾을 수 없습니다.';
  END IF;

  IF p_delta IS NULL OR p_delta = 0 OR p_delta < -100 OR p_delta > 100 THEN
    RAISE EXCEPTION '레벨 조정량은 -100부터 -1, 1부터 100 사이의 정수여야 합니다.';
  END IF;

  SELECT * INTO v_board
  FROM public.room_player_turn_boards
  WHERE room_id = p_room_id AND user_id = p_owner_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '레벨 조정 대상의 턴 보드를 찾을 수 없습니다.';
  END IF;

  SELECT e.value INTO v_card
  FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb)) e(value)
  WHERE e.value ->> 'instance_id' = p_instance_id;

  IF v_card IS NULL THEN
    RAISE EXCEPTION '현장에서 레벨을 조정할 카드를 찾을 수 없습니다.';
  END IF;

  IF lower(coalesce(v_card ->> 'card_type', v_card ->> 'type', '')) <> 'character' THEN
    RAISE EXCEPTION '레벨 조정은 캐릭터 카드에만 적용할 수 있습니다.';
  END IF;

  v_old_bonus := coalesce(nullif(v_card ->> 'level_bonus', '')::integer, 0);
  v_base_level := public.private_card_effect_level_v1(v_card) - v_old_bonus;
  v_new_bonus := v_old_bonus + p_delta;

  IF v_base_level + v_new_bonus < 0 THEN
    RAISE EXCEPTION '캐릭터의 레벨은 0 미만으로 낮출 수 없습니다.';
  END IF;

  IF v_base_level + v_new_bonus > 100 THEN
    RAISE EXCEPTION '조정 후 레벨은 100을 초과할 수 없습니다.';
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE WHEN e.value ->> 'instance_id' = p_instance_id
      THEN jsonb_set(e.value, '{level_bonus}', to_jsonb(v_new_bonus), true)
      ELSE e.value
    END ORDER BY e.ordinality
  ), '[]'::jsonb)
  INTO v_field_new
  FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb))
    WITH ORDINALITY e(value, ordinality);

  UPDATE public.room_player_turn_boards
  SET field_cards = v_field_new, updated_at = now()
  WHERE room_id = p_room_id AND user_id = p_owner_user_id;

  UPDATE public.room_match_states
  SET state_version = state_version + 1,
      last_action_label = format(
        '수동 효과: %s 캐릭터의 레벨을 %s%s 조정했습니다.',
        coalesce(v_card ->> 'key', '선택한'),
        CASE WHEN p_delta > 0 THEN '+' ELSE '' END,
        p_delta
      )
  WHERE room_id = p_room_id;

  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$function$;

DO $patch$
DECLARE
  v_definition text;
  v_old text := $old$jsonb_build_object('ap_bonus',0)$old$;
  v_new text := $new$jsonb_build_object('ap_bonus',0,'level_bonus',0)$new$;
BEGIN
  v_definition := pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  );
  IF position(v_old in v_definition) = 0 THEN
    RAISE EXCEPTION 'end-turn AP bonus reset expression not found; aborting level reset patch';
  END IF;
  EXECUTE replace(v_definition, v_old, v_new);
END
$patch$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN d.value ->> 'effectId' IN (
        'card-1039-declare-remove-character-ap-8000',
        'card-1040-declare-remove-character-level-7'
      )
      THEN jsonb_set(d.value, '{steps,1,from}', '"opponent_field"'::jsonb, false)
      ELSE d.value
    END
    ORDER BY d.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY d(value, ordinality)
)
WHERE c.catalog_id = 'main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(c.definitions) d(value)
    WHERE d.value ->> 'effectId' IN (
      'card-1039-declare-remove-character-ap-8000',
      'card-1040-declare-remove-character-level-7'
    )
  );
