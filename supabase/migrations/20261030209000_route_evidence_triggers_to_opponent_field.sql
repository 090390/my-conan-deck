-- When an opponent's evidence is removed, fire evidence.card_removed for field-watch cards on the other player's field.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$ v_evidence_owner uuid; v_disguise_id text; v_effect_definition jsonb; v_effect_started boolean; v_use_key text;$old$;
  v_replacement := $new$ v_evidence_owner uuid; v_trigger_owner uuid; v_disguise_id text; v_effect_definition jsonb; v_effect_started boolean; v_use_key text;$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'evidence trigger owner declaration anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;

  v_anchor := $old$         PERFORM public.private_card_effect_start_event_v1(
           p_room_id,v_evidence_owner,v_evidence_owner,v_old_evidence_card,'evidence.card_removed',
           jsonb_build_object('turn_number',v_turn,'evidence_removed_instance_id',v_old_evidence_card->>'instance_id'),NULL,false
         );$old$;
  v_replacement := $new$         SELECT user_id INTO v_trigger_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_evidence_owner
           ORDER BY seat LIMIT 1;
         IF v_trigger_owner IS NOT NULL THEN
           PERFORM public.private_card_effect_start_event_v1(
             p_room_id,v_trigger_owner,v_trigger_owner,v_old_evidence_card,'evidence.card_removed',
             jsonb_build_object(
               'turn_number',v_turn,
               'evidence_removed_instance_id',v_old_evidence_card->>'instance_id',
               'evidence_owner_user_id',v_evidence_owner::text,
               'removed_evidence_card',v_old_evidence_card
             ),NULL,false
           );
         END IF;$new$;
  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN RAISE EXCEPTION 'evidence trigger owner routing anchor missing'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;
  EXECUTE v_definition;
END
$migration$;
