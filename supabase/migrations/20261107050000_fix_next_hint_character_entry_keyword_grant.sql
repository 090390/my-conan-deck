-- Fix built-in source_character targeting for grant_keyword, and allow
-- emergency cancellation of an already-declared Next Hint.

DO $migration$
DECLARE
  v_effect_definition text;
  v_old_grant_target text := $old_grant$
      IF nullif(v_step->>'target','') IS NOT NULL THEN
        v_path:=string_to_array(replace(v_step->>'target','vars.',''),'.');
        v_data:=v_vars #> v_path;
        v_item:=v_data->0;
        v_card:=coalesce(v_item->'card',v_item);
        v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
      ELSE
        v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
      END IF;
$old_grant$;
  v_new_grant_target text := $new_grant$
      IF replace(coalesce(v_step->>'target',''),'vars.','')='source_character' THEN
        -- source_character is a built-in target, not a saved variable.
        v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
        v_target_owner:=v_source_user;
      ELSIF nullif(v_step->>'target','') IS NOT NULL THEN
        v_path:=string_to_array(replace(v_step->>'target','vars.',''),'.');
        v_data:=v_vars #> v_path;
        v_item:=v_data->0;
        v_card:=coalesce(v_item->'card',v_item);
        v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
      ELSE
        v_card:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
      END IF;
$new_grant$;
  v_ai_definition text;
  v_old_action_allowlist text := $old_actions$if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime','acknowledge_culprits_crime','rest_partner_manual','acknowledge_evidence_remove') then$old_actions$;
  v_new_action_allowlist text := $new_actions$if p_action not in ('begin_turn','play_character','partner_assist','partner_deduce','investigate','attack_character','attack_evidence','guard_with_character','decline_guard','end_turn','declare_solution','solve_case','culprits_crime','acknowledge_culprits_crime','rest_partner_manual','acknowledge_evidence_remove','cancel_next_hint') then$new_actions$;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_effect_definition;
  IF length(v_effect_definition)-length(replace(v_effect_definition,v_old_grant_target,'')) <> length(v_old_grant_target) THEN
    RAISE EXCEPTION 'grant_keyword source target block was not found exactly once; refusing to patch.';
  END IF;
  EXECUTE replace(v_effect_definition,v_old_grant_target,v_new_grant_target);

  SELECT pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure)
    INTO v_ai_definition;
  IF length(v_ai_definition)-length(replace(v_ai_definition,v_old_action_allowlist,'')) <> length(v_old_action_allowlist) THEN
    RAISE EXCEPTION 'AI turn-action allowlist was not found exactly once; refusing to patch.';
  END IF;
  EXECUTE replace(v_ai_definition,v_old_action_allowlist,v_new_action_allowlist);
END
$migration$;
