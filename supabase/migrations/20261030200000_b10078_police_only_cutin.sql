-- B10078 (internal card ID 1134): its AP+2000 cut-in is limited to the owner's turn and a Police character.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$    -- B05095: during its owner's turn, each Police character on the owner's field adds 1000 AP.$old$;
  v_replacement := $new$    -- B10078 (internal 1134): AP +2000 only when its owner cuts in on a Police character during their own turn.
    IF public.private_card_effect_matches_id_v1(v_card, '["1134"]'::jsonb) THEN
      IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN
        RAISE EXCEPTION 'B10078 컷인은 자신의 턴 중에만 사용할 수 있습니다.';
      END IF;
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
      IF v_cut_in_subject IS NULL
         OR NOT public.private_card_effect_is_character_v1(v_cut_in_subject)
         OR NOT public.private_card_effect_has_trait_v1(v_cut_in_subject, '警察') THEN
        RAISE EXCEPTION 'B10078 컷인은 특징 [경찰] 캐릭터에만 사용할 수 있습니다.';
      END IF;
      v_bonus := greatest(v_bonus, 2000);
    END IF;

    -- B05095: during its owner's turn, each Police character on the owner's field adds 1000 AP.$new$;

  IF position(v_anchor IN v_definition)=0 THEN
    RAISE EXCEPTION 'B10078 cut-in insertion anchor missing';
  END IF;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;
END
$migration$;
