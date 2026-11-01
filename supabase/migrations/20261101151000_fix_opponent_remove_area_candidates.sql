DO $patch$
DECLARE
  v_definition text;
  v_remove_pos integer;
  v_zone_pos integer;
  v_zone_end integer;
  v_elsif_pos integer;
BEGIN
  v_definition := pg_get_functiondef('public.private_card_effect_get_candidates_v1(uuid,uuid,uuid,text,jsonb,text,text,jsonb)'::regprocedure);
  v_remove_pos := position('v_data:=coalesce(v_game.remove_cards' in v_definition);
  IF v_remove_pos=0 THEN
    RAISE EXCEPTION 'opponent_remove_area lookup not found; aborting migration';
  END IF;
  v_zone_pos := v_remove_pos + position('v_zone:=''remove_area'';' in substring(v_definition from v_remove_pos)) - 1;
  IF v_zone_pos < v_remove_pos THEN
    RAISE EXCEPTION 'opponent_remove_area zone assignment not found; aborting migration';
  END IF;
  v_zone_end := v_zone_pos + length('v_zone:=''remove_area'';') - 1;
  v_elsif_pos := v_zone_end + position(' ELSIF p_from IN (' in substring(v_definition from v_zone_end+1)) - 1;
  IF v_elsif_pos <= v_zone_end THEN
    RAISE EXCEPTION 'next card-zone branch not found; aborting migration';
  END IF;
  -- The old implementation accidentally overwrote remove_cards with evidence_cards
  -- inside the opponent_remove_area branch. Remove that stale evidence lookup.
  v_definition := substring(v_definition from 1 for v_zone_end)
    || substring(v_definition from v_elsif_pos);
  EXECUTE v_definition;
END
$patch$;