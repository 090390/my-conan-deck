-- Recognize MR rarity from multiple saved card-data shapes or the resolved client payload.
DO $patch$
DECLARE
  v_definition text;
  v_start integer;
  v_anchor integer;
  v_old text := 'and upper(coalesce(v_card ->> ''rarity'',''''))=''MR'' then';
  v_new text := 'and upper(coalesce(v_card ->> ''rarity'',v_card ->> ''rarity_code'',v_card ->> ''rarityCode'',v_card #>> ''{sourceData,rarity}'',v_card #>> ''{raw,rarity}'',p_payload ->> ''rarity'',''''))=''MR'' then';
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure),chr(13),'')
    INTO v_definition;
  v_start := position('if p_action = ''move_field_card'' then' IN v_definition);
  IF v_start=0 THEN RAISE EXCEPTION 'Could not find move_field_card branch.'; END IF;
  v_anchor := position(v_old IN substring(v_definition FROM v_start));
  IF v_anchor=0 THEN RAISE EXCEPTION 'Could not find MR-to-Remove routing predicate.'; END IF;
  v_definition := overlay(v_definition placing v_new FROM v_start+v_anchor-1 FOR length(v_old));
  EXECUTE v_definition;
END
$patch$;
