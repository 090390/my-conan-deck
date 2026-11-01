-- Expose legal event effects to the AI after it has paid for Next Hint.
-- The normal base-card gate remains unchanged; the additional branch is limited
-- to an explicitly pending Next Hint that the server already permits play_event to consume.

DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$ IF coalesce(v_is_own_turn,false)
    AND coalesce(v_turn_step,'')='main'
    AND NOT coalesce(v_board.base_card_played_this_turn,false)
    AND NOT coalesce(v_board.character_played_this_turn,false) THEN$old$;
  v_new text := $new$ IF coalesce(v_is_own_turn,false)
    AND coalesce(v_turn_step,'')='main'
    AND (
      (
        NOT coalesce(v_board.base_card_played_this_turn,false)
        AND NOT coalesce(v_board.character_played_this_turn,false)
      )
      OR coalesce(v_board.next_hint_pending,false)
    ) THEN$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure
  ) INTO v_definition;

  IF position(v_new IN v_definition)>0 THEN
    RETURN;
  END IF;

  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'AI event-candidate gate was not found in get_private_ai_card_effect_activations_v1.';
  END IF;

  v_definition:=replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$migration$;
