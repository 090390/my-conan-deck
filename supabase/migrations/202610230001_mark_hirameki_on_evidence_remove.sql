-- Preserve a visible marker when a Hirameki card is moved from evidence to the remove area.
-- The UI only displays the marker on cards that actually have a Hirameki effect.
DO $mark_hirameki_on_evidence_remove$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'perform_private_turn_action_v2 was not found.';
  END IF;

  v_old := $old_expression$coalesce(gs.remove_cards,'[]'::jsonb)||jsonb_build_array(v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving')$old_expression$;
  v_new := $new_expression$coalesce(gs.remove_cards,'[]'::jsonb)||jsonb_build_array((v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving') || jsonb_build_object('hirameki_achieved', true))$new_expression$;

  IF position(v_old IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Evidence-to-remove expression was not found; no changes applied.';
  END IF;

  EXECUTE v_definition;
  REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated;
END;
$mark_hirameki_on_evidence_remove$;
