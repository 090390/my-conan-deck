-- Conan TCG: robust follow-up fixes for peek sharing, field capacity, manual MR routing and AP adjustments.
-- Safe to apply after earlier gameplay migrations; the SQL function rewrite is idempotent.

DO $followup_function_patch$
DECLARE
  v_signature text;
  v_definition text;
  v_original text;
  v_start integer;
  v_end integer;
  v_action_block text;
  v_tail text;
  v_next integer;
  v_found_function boolean := false;
  v_warning text := '상대에게 공개하도록 지정한 카드는 먼저 공개 선택을 취소한 뒤 손패로 가져와 주세요.';
  v_new_character_guard text := $char_guard$IF (
    SELECT count(*)
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) AS field_card(value)
    WHERE upper(coalesce(field_card.value ->> 'card_type','')) = 'CHARACTER'
  ) >= 5 THEN
    RAISE EXCEPTION '현장에 캐릭터 카드가 이미 5장 있습니다.';
  END IF;$char_guard$;
  v_marker text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.perform_private_turn_action_v2(uuid,text,jsonb)',
    'public.perform_private_turn_action(uuid,text,jsonb)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN CONTINUE; END IF;
    v_found_function := true;
    SELECT pg_get_functiondef(to_regprocedure(v_signature)) INTO v_definition;
    v_definition := replace(v_definition, chr(13), '');
    v_original := v_definition;

    -- Remove the obsolete check blocking take_deck_peek_card after a card had been shared.
    v_definition := regexp_replace(
      v_definition,
      'raise[[:space:]]+exception[^;]*상대에게 공개하도록 지정한 카드는 먼저 공개 선택을 취소한 뒤 손패로 가져와 주세요[^;]*;',
      'NULL;',
      'gi'
    );
    IF position(v_warning in v_definition) > 0
       AND position(v_warning in v_original) > 0
       AND v_definition = v_original THEN
      RAISE EXCEPTION '후속 수정 중 공개 선택 검사를 찾았지만 제거하지 못했습니다: %', v_signature;
    END IF;

    -- Events do not consume the five-character capacity, even if the field already has five characters.
    v_marker := 'if p_action = ''play_event'' then';
    v_start := position(v_marker in lower(v_definition));
    IF v_start > 0 THEN
      v_tail := substring(v_definition from v_start + length(v_marker));
      v_end := position('if p_action = ''finish_event'' then' in lower(v_tail));
      IF v_end > 0 THEN
        v_end := v_start + length(v_marker) + v_end - 1;
      ELSE
        v_next := position('if p_action = ' in lower(v_tail));
        IF v_next > 0 THEN
          v_end := v_start + length(v_marker) + v_next - 1;
        ELSE
          v_end := length(v_definition) + 1;
        END IF;
      END IF;
      v_action_block := substring(v_definition from v_start for v_end - v_start);
      v_action_block := regexp_replace(
        v_action_block,
        'raise[[:space:]]+exception[[:space:]]+''[^'']*5장[^'']*''[[:space:]]*;',
        'NULL;',
        'gi'
      );
      v_definition := substring(v_definition from 1 for v_start - 1)
        || v_action_block || substring(v_definition from v_end);
    END IF;

    -- Any remaining five-card exception must count characters, not all field cards.
    v_definition := regexp_replace(
      v_definition,
      'raise[[:space:]]+exception[[:space:]]+''[^'']*5장[^'']*''[[:space:]]*;',
      v_new_character_guard,
      'gi'
    );

    IF position(v_warning in v_definition) > 0 THEN
      RAISE EXCEPTION '공개 선택 차단 문구가 턴 처리 함수에 남아 있습니다: %', v_signature;
    END IF;

    IF v_definition IS DISTINCT FROM v_original THEN
      EXECUTE v_definition;
    END IF;
  END LOOP;

  IF NOT v_found_function THEN
    RAISE EXCEPTION 'perform_private_turn_action 함수가 없어 후속 규칙 수정을 적용하지 못했습니다.';
  END IF;
END
$followup_function_patch$;

CREATE OR REPLACE FUNCTION public.move_private_field_mr_to_partner_v1(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_instance_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $move_private_field_mr_to_partner_v1$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_game public.room_player_game_states%ROWTYPE;
  v_card jsonb;
  v_previous_mr jsonb;
  v_clean_card jsonb;
  v_clean_previous_mr jsonb;
  v_field_new jsonb;
  v_remove_column text;
  v_replaced_mr boolean := false;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자만 MR 카드를 이동할 수 있습니다.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id
  ) THEN
    RAISE EXCEPTION 'MR 소유자의 방 참가 정보를 찾을 수 없습니다.';
  END IF;

  SELECT * INTO v_board
    FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 턴 보드를 찾을 수 없습니다.'; END IF;

  SELECT e.value INTO v_card
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE e.value ->> 'instance_id'=p_instance_id;
  IF v_card IS NULL THEN
    RAISE EXCEPTION '현장에서 선택한 MR 카드를 찾을 수 없습니다.';
  END IF;
  IF upper(coalesce(v_card ->> 'rarity','')) <> 'MR' THEN
    RAISE EXCEPTION 'MR 카드만 MR 파트너 에이리어로 강제 이동할 수 있습니다.';
  END IF;

  SELECT * INTO v_game
    FROM public.room_player_game_states
    WHERE room_id=p_room_id AND user_id=p_owner_user_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 카드 영역을 찾을 수 없습니다.'; END IF;

  SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
    FILTER (WHERE e.value ->> 'instance_id' IS DISTINCT FROM p_instance_id),'[]'::jsonb)
    INTO v_field_new
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality);

  v_previous_mr := v_board.partner_mr_card;
  IF v_previous_mr IS NOT NULL
     AND coalesce(v_previous_mr ->> 'instance_id','') <> ''
     AND v_previous_mr ->> 'instance_id' IS DISTINCT FROM p_instance_id THEN
    SELECT column_name INTO v_remove_column
      FROM information_schema.columns
      WHERE table_schema='public'
        AND table_name='room_player_game_states'
        AND data_type='jsonb'
        AND column_name ILIKE '%remove%'
        AND column_name NOT ILIKE '%count%'
      ORDER BY CASE
        WHEN column_name='remove_cards' THEN 0
        WHEN column_name ILIKE '%remove%cards%' THEN 1
        ELSE 2
      END, ordinal_position
      LIMIT 1;
    IF v_remove_column IS NULL THEN
      RAISE EXCEPTION '리무브 에이리어 카드 목록을 찾을 수 없습니다.';
    END IF;
    v_clean_previous_mr := v_previous_mr
      - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn'
      - 'resolving' - 'host_instance_id' - 'set_owner_user_id';
    EXECUTE format(
      'UPDATE public.room_player_game_states SET %I=coalesce(%I,''[]''::jsonb)||jsonb_build_array($3),updated_at=now() WHERE room_id=$1 AND user_id=$2',
      v_remove_column,v_remove_column
    ) USING p_room_id,p_owner_user_id,v_clean_previous_mr;
    v_replaced_mr := true;
  END IF;

  v_clean_card := v_card
    - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn'
    - 'resolving' - 'host_instance_id' - 'set_owner_user_id';

  UPDATE public.room_player_turn_boards
    SET field_cards=v_field_new,
        partner_mr_card=v_clean_card,
        remove_count=coalesce(remove_count,0) + CASE WHEN v_replaced_mr THEN 1 ELSE 0 END,
        updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;

  UPDATE public.room_match_states
    SET state_version=state_version+1,
        last_action_label=CASE
          WHEN v_replaced_mr THEN '수동 리무브 이동을 선택한 MR 카드가 MR 파트너 에이리어로 이동했고, 이전 MR 파트너는 리무브로 이동했습니다.'
          ELSE '수동 리무브 이동을 선택한 MR 카드가 MR 파트너 에이리어로 이동했습니다.'
        END
    WHERE room_id=p_room_id;

  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$move_private_field_mr_to_partner_v1$;

CREATE OR REPLACE FUNCTION public.adjust_private_character_ap_v1(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_instance_id text,
  p_delta integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $adjust_private_character_ap_v1$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_card jsonb;
  v_field_new jsonb;
  v_new_bonus numeric;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자만 현장 캐릭터 AP를 조정할 수 있습니다.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id
  ) THEN
    RAISE EXCEPTION 'AP 조정 대상 소유자의 방 참가 정보를 찾을 수 없습니다.';
  END IF;
  IF p_delta IS NULL OR p_delta >= 0 OR p_delta < -10000 THEN
    RAISE EXCEPTION 'AP 감소량은 -1부터 -10000 사이의 정수여야 합니다.';
  END IF;

  SELECT * INTO v_board
    FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'AP 조정 대상의 턴 보드를 찾을 수 없습니다.'; END IF;

  SELECT e.value INTO v_card
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE e.value ->> 'instance_id'=p_instance_id;
  IF v_card IS NULL THEN RAISE EXCEPTION '현장에 AP를 감소시킬 카드를 찾을 수 없습니다.'; END IF;
  IF lower(coalesce(v_card ->> 'card_type','')) <> 'character' THEN
    RAISE EXCEPTION 'AP 감소는 캐릭터 카드에만 적용할 수 있습니다.';
  END IF;

  v_new_bonus := coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0) + p_delta;
  SELECT coalesce(jsonb_agg(
    CASE WHEN e.value ->> 'instance_id'=p_instance_id
      THEN jsonb_set(e.value,'{ap_bonus}',to_jsonb(v_new_bonus),true)
      ELSE e.value
    END ORDER BY e.ordinality
  ),'[]'::jsonb)
    INTO v_field_new
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality);

  UPDATE public.room_player_turn_boards
    SET field_cards=v_field_new,updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;

  UPDATE public.room_match_states
    SET state_version=state_version+1,
        last_action_label=format('수동 효과: %s 캐릭터의 AP 보너스를 %s 조정했습니다.',coalesce(v_card ->> 'key','선택한'),p_delta)
    WHERE room_id=p_room_id;

  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$adjust_private_character_ap_v1$;

REVOKE ALL ON FUNCTION public.move_private_field_mr_to_partner_v1(uuid,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adjust_private_character_ap_v1(uuid,uuid,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_private_field_mr_to_partner_v1(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_private_character_ap_v1(uuid,uuid,text,integer) TO authenticated;
