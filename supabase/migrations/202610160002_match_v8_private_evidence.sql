-- Conan TCG v8 private evidence controls
-- Exposes full evidence metadata only to the owner of that board.
-- Extends moving evidence so face-down cards can be moved only by their owner.
-- Does not disclose hidden evidence identities to the opposing player.

DO $match_v8_evidence_actions$
DECLARE
  v_definition text;
  v_old text := $old$and coalesce((e.value ->> 'face_up')::boolean,false) is true;$old$;
  v_new text := $new$and (coalesce((e.value ->> 'face_up')::boolean,false) is true or v_owner_id=v_user);$new$;
  v_old_error text := $olderr$앞면 공개 상태인 증거 카드를 찾을 수 없습니다.$olderr$;
  v_new_error text := $newerr$이동할 수 있는 증거 카드를 찾을 수 없습니다.$newerr$;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  IF position(v_new in v_definition) = 0 THEN
    IF position(v_old in v_definition) = 0 THEN
      RAISE EXCEPTION 'v8 private evidence migration stopped: evidence visibility predicate not found';
    END IF;
    v_definition := replace(v_definition, v_old, v_new);
  END IF;
  v_definition := replace(v_definition, v_old_error, v_new_error);

  EXECUTE v_definition;
END
$match_v8_evidence_actions$;

DO $match_v8_evidence_getter$
DECLARE
  v_definition text;
  v_anchor text := $anchor$      'evidence_public_cards', coalesce(($anchor$;
  v_replacement text := $replacement$      'evidence_private_cards', case when rp.user_id = v_user then coalesce((
        select jsonb_agg(ev.value order by ev.ordinality)
        from public.room_player_game_states evidence_state
        cross join lateral jsonb_array_elements(coalesce(evidence_state.evidence_cards, '[]'::jsonb)) with ordinality ev(value, ordinality)
        where evidence_state.room_id = p_room_id and evidence_state.user_id = rp.user_id
      ), '[]'::jsonb) else '[]'::jsonb end,
      'evidence_public_cards', coalesce(($replacement$;
BEGIN
  SELECT pg_get_functiondef('public.get_private_turn_state_v2(uuid)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  IF position($existing$'evidence_private_cards'$existing$ in v_definition) = 0 THEN
    IF position(v_anchor in v_definition) = 0 THEN
      RAISE EXCEPTION 'v8 private evidence migration stopped: evidence_public_cards insertion point not found';
    END IF;
    v_definition := replace(v_definition, v_anchor, v_replacement);
  END IF;

  -- pg_get_functiondef formatting varies; do not rely on an exact newline before $function$.
  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'v8 private evidence migration stopped: getter function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$match_v8_evidence_getter$;
