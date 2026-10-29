DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_old := 'AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,''[]''::jsonb)) e(value) WHERE e.value->>''instance_id''=v_disguise_id) THEN';
  v_new := 'AND (EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,''[]''::jsonb)) e(value) WHERE e.value->>''instance_id''=v_disguise_id) OR EXISTS(SELECT 1 FROM public.room_player_turn_boards pb WHERE pb.room_id=p_room_id AND pb.user_id=v_owner AND pb.partner_mr_card->>''instance_id''=v_disguise_id)) THEN';

  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not locate contact-removed trigger destination check';
  END IF;

  v_definition:=replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$migration$;
