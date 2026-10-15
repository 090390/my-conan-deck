-- Conan TCG v8 follow-up: keep facedown evidence identities private and resolve disguise immediately.
-- Idempotent source-level patches against the currently deployed RPC definitions.

DO $match_v8_disguise$
DECLARE
  v_definition text;
  v_action_block text;
  v_start integer;
  v_end integer;
  v_old_effect_token text := $old_effect$nullif(v_card #>> '{sourceData,henso}','')$old_effect$;
  v_new_effect_token text := $new_effect$nullif(p_payload ->> 'disguise_effect',''),
      nullif(p_payload ->> 'disguiseEffect',''),
      nullif(v_card #>> '{sourceData,henso}','')$new_effect$;
  v_resolve_old text := $old_return$return public.get_private_turn_state_v2(p_room_id);$old_return$;
  v_resolve_new text := $new_return$perform public.resolve_private_character_contact(p_room_id,v_pending);
    update public.room_match_states m
      set last_action_label=format('변장: %s가 컨택 대상 대신 등장했고 컷인 없이 컨택을 해결했습니다.',coalesce(v_card ->> 'key','캐릭터'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);$new_return$;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  v_start := position('if p_action = ''contact_use_disguise'' then' in lower(v_definition));
  v_end := position('if p_action = ''guard_contact_with_character'' then' in lower(v_definition));
  IF v_start = 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'v8 follow-up stopped: could not isolate contact_use_disguise action';
  END IF;
  v_action_block := substring(v_definition from v_start for v_end - v_start);

  -- The runtime hand card can lack translated catalog effects; trust the catalog-derived payload value sent by the UI.
  IF position($effect_marker$nullif(p_payload ->> 'disguise_effect','')$effect_marker$ in v_action_block) = 0
     AND position($effect_marker$nullif(p_payload ->> 'disguiseEffect','')$effect_marker$ in v_action_block) = 0 THEN
    IF position(v_old_effect_token in v_action_block) = 0 THEN
      RAISE EXCEPTION 'v8 follow-up stopped: disguise effect validation anchor not found in isolated action';
    END IF;
    v_action_block := replace(v_action_block, v_old_effect_token, v_new_effect_token);
  END IF;

  -- Resolve immediately in the disguise action instead of leaving a pending cut-in response.
  IF position('perform public.resolve_private_character_contact(p_room_id,v_pending);' in lower(v_action_block)) = 0 THEN
    IF position(v_resolve_old in v_action_block) = 0 THEN
      RAISE EXCEPTION 'v8 follow-up stopped: disguise contact resolution return point not found';
    END IF;
    v_action_block := replace(v_action_block, v_resolve_old, v_resolve_new);
  END IF;

  v_definition := substring(v_definition from 1 for v_start - 1)
    || v_action_block
    || substring(v_definition from v_end);

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'v8 follow-up stopped: action function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$match_v8_disguise$;

DO $match_v8_private_evidence_redaction$
DECLARE
  v_definition text;
  v_old text := $old_evidence$jsonb_agg(ev.value order by ev.ordinality)$old_evidence$;
  v_new text := $new_evidence$jsonb_agg(
          case
            when coalesce((ev.value ->> 'face_up')::boolean,false) is true then ev.value
            else jsonb_build_object('instance_id', ev.value ->> 'instance_id', 'face_up', false)
          end order by ev.ordinality
        )$new_evidence$;
  v_marker text := $marker$jsonb_build_object('instance_id', ev.value ->> 'instance_id', 'face_up', false)$marker$;
BEGIN
  SELECT pg_get_functiondef('public.get_private_turn_state_v2(uuid)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  IF position(v_marker in v_definition) = 0 THEN
    IF position(v_old in v_definition) = 0 THEN
      RAISE EXCEPTION 'v8 follow-up stopped: private evidence aggregation anchor not found';
    END IF;
    v_definition := replace(v_definition, v_old, v_new);
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'v8 follow-up stopped: getter function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$match_v8_private_evidence_redaction$;
