-- Conan TCG: after a card is revealed to the opponent, it may still be moved to hand.
-- Character capacity is five characters; event cards do not consume those slots.
DO $peek_and_capacity_rules$
DECLARE
  v_signature text;
  v_definition text;
  v_original text;
  v_start integer;
  v_end integer;
  v_action_block text;
  v_tail text;
  v_next integer;
  v_any_peek_guard boolean := false;
  v_new_character_guard text := $char_guard$IF (
    SELECT count(*)
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) AS field_card(value)
    WHERE coalesce(field_card.value ->> 'card_type','') = 'character'
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
    SELECT pg_get_functiondef(to_regprocedure(v_signature)) INTO v_definition;
    v_definition := replace(v_definition, chr(13), '');
    v_original := v_definition;

    -- Remove only the obsolete guard that blocked hand-taking a card after revealing it.
    IF position('상대에게 공개하도록 지정한 카드는 먼저 공개 선택을 취소한 뒤 손패로 가져와 주세요.' in v_definition) > 0 THEN
      v_definition := regexp_replace(
        v_definition,
        'raise exception[[:space:]]+''상대에게 공개하도록 지정한 카드는 먼저 공개 선택을 취소한 뒤 손패로 가져와 주세요[.]''[[:space:]]*;',
        'NULL;',
        'gi'
      );
      IF v_definition <> v_original THEN v_any_peek_guard := true; END IF;
    END IF;

    -- Inside play_event, turn a five-total-cards guard into a no-op. Events may be played
    -- even when the field already has five characters; those events do not consume character slots.
    v_marker := 'if p_action = ''play_event'' then';
    v_start := position(v_marker in lower(v_definition));
    IF v_start > 0 THEN
      v_end := position('if p_action = ''finish_event'' then' in lower(substring(v_definition from v_start + length(v_marker))));
      IF v_end > 0 THEN
        v_end := v_start + length(v_marker) + v_end - 1;
      ELSE
        v_tail := substring(v_definition from v_start + length(v_marker));
        v_next := position('if p_action = ' in lower(v_tail));
        IF v_next > 0 THEN v_end := v_start + length(v_marker) + v_next - 1;
        ELSE v_end := length(v_definition) + 1;
        END IF;
      END IF;
      v_action_block := substring(v_definition from v_start for v_end - v_start);
      v_action_block := regexp_replace(
        v_action_block,
        'raise exception[[:space:]]+''[^'']*(현장|카드)[^'']*5장[^'']*''[[:space:]]*;',
        'NULL;',
        'gi'
      );
      v_definition := substring(v_definition from 1 for v_start - 1) || v_action_block || substring(v_definition from v_end);
    END IF;

    -- For any remaining character-play cap errors, check the number of character cards
    -- rather than the number of all field entries (which also include events).
    v_definition := regexp_replace(
      v_definition,
      'raise exception[[:space:]]+''[^'']*(현장|카드)[^'']*5장[^'']*''[[:space:]]*;',
      v_new_character_guard,
      'gi'
    );

    IF v_definition IS DISTINCT FROM v_original THEN
      EXECUTE v_definition;
    END IF;
  END LOOP;

  IF NOT v_any_peek_guard THEN
    RAISE EXCEPTION 'shared deck peek guard was not found in either turn action function; no functions were changed by this migration.';
  END IF;
END
$peek_and_capacity_rules$;
