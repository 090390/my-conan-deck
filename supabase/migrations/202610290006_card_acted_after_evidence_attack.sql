DO $patch$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  v_anchor := $anchor$ IF p_action='end_turn' THEN$anchor$;
  v_replacement := $replacement$ IF p_action='resolve_evidence_attack'
     AND v_before_pending IS NOT NULL
     AND v_before_pending->>'type'='evidence_attack_reveal'
     AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
     AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
    v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
    v_instance_id:=nullif(v_before_pending->>'attacker_instance_id','');
    IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
      SELECT e.value INTO v_source_card
        FROM public.room_player_turn_boards b
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
        WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user
          AND e.value->>'instance_id'=v_instance_id LIMIT 1;
      IF v_source_card IS NOT NULL THEN
        PERFORM public.private_card_effect_start_event_v1(
          p_room_id,v_event_source_user,v_event_source_user,v_source_card,
          'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false
        );
      END IF;
    END IF;
  END IF;

  IF p_action='end_turn' THEN$replacement$;
  IF position(v_anchor in v_definition)=0 THEN
    RAISE EXCEPTION 'Cannot patch turn-action wrapper: end_turn anchor not found';
  END IF;
  v_definition := replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;
END
$patch$;
