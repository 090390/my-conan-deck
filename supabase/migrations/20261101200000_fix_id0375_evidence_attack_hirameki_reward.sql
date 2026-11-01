-- ID:0375 (B03126) has a Hirameki that replaces the normal reward for a
-- successful attack against the opponent's evidence. The attacked evidence card
-- still moves to the Remove Area, but the attacker does not gain a new evidence.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$
    v_source_id := (v_match.pending_action ->> 'attacker_user_id')::uuid;
    perform public.draw_private_turn_card(p_room_id,v_source_id,'evidence');
    update public.room_match_states m set pending_action=null,state_version=state_version+1,last_action_label=format('공개된 증거 %s를 리무브로 이동했고 공격자가 증거 1장을 얻었습니다.',coalesce(v_card ->> 'key','카드')) where m.room_id=p_room_id;
$old$;
  v_new text := $new$
    v_source_id := (v_match.pending_action ->> 'attacker_user_id')::uuid;
    IF public.private_card_effect_matches_id_v1(v_card,jsonb_build_array('0375')) THEN
      -- The attacked evidence was already moved to Remove Area above.
      -- Do not draw a replacement evidence card for ID:0375's Hirameki.
      update public.room_match_states m set pending_action=null,state_version=state_version+1,
        last_action_label=format('ID:0375 히라메키 발동: 공개된 증거 %s를 리무브했습니다. 공격자는 증거를 획득하지 않습니다.',coalesce(v_card ->> 'key','카드'))
      where m.room_id=p_room_id;
    ELSE
      perform public.draw_private_turn_card(p_room_id,v_source_id,'evidence');
      update public.room_match_states m set pending_action=null,state_version=state_version+1,
        last_action_label=format('공개된 증거 %s를 리무브로 이동했고 공격자가 증거 1장을 얻었습니다.',coalesce(v_card ->> 'key','카드'))
      where m.room_id=p_room_id;
    END IF;
$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position('ID:0375 히라메키 발동: 공개된 증거' IN v_definition) > 0 THEN
    RETURN;
  END IF;

  IF position(v_old IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Could not find successful evidence attack reward block; migration aborted.';
  END IF;

  v_definition := replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$migration$;
