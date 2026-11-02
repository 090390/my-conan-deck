DO $migration$
DECLARE
  v_definition text;
  v_old_attacker text := $old$v_pending := jsonb_set(v_match.pending_action,'{attacker_bonus}',to_jsonb(v_bonus));$old$;
  v_old_target text := $old$v_pending := jsonb_set(v_match.pending_action,'{target_bonus}',to_jsonb(v_bonus));$old$;
  v_new_attacker text := $new$v_pending := jsonb_set(
        v_match.pending_action,
        '{attacker_bonus}',
        to_jsonb(coalesce(nullif(v_match.pending_action ->> 'attacker_bonus','')::integer,0) + v_bonus),
        true
      );$new$;
  v_new_target text := $new$v_pending := jsonb_set(
        v_match.pending_action,
        '{target_bonus}',
        to_jsonb(coalesce(nullif(v_match.pending_action ->> 'target_bonus','')::integer,0) + v_bonus),
        true
      );$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position(v_old_attacker IN v_definition)=0
     OR position(v_old_target IN v_definition)=0 THEN
    RAISE EXCEPTION 'Expected contact cut-in AP assignments were not found; refusing to patch an unexpected function version.';
  END IF;

  v_definition := replace(v_definition,v_old_attacker,v_new_attacker);
  v_definition := replace(v_definition,v_old_target,v_new_target);

  EXECUTE v_definition;
END;
$migration$;
