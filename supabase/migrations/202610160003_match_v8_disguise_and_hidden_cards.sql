-- Conan TCG v8 follow-up: keep facedown evidence identities private and resolve disguise immediately.
-- Safe to re-run: each block detects whether its replacement is already present.

DO $match_v8_disguise$
DECLARE
  v_definition text;
  v_old_validation text := $old_validation$    if coalesce(
      nullif(v_card ->> 'disguiseEffect',''),
      nullif(v_card ->> 'disguise_effect',''),
      nullif(v_card ->> 'hensoEffect',''),
      nullif(v_card ->> 'henso',''),
      nullif(v_card #>> '{gameSystemEffects,disguise}',''),
      nullif(v_card #>> '{sourceData,henso}','')
    ) is null then
      raise exception '변장 효과가 있는 캐릭터를 선택해 주세요.';
    end if;$old_validation$;
  v_new_validation text := $new_validation$    if coalesce(
      nullif(p_payload ->> 'disguise_effect',''),
      nullif(p_payload ->> 'disguiseEffect',''),
      nullif(v_card ->> 'disguiseEffect',''),
      nullif(v_card ->> 'disguise_effect',''),
      nullif(v_card ->> 'hensoEffect',''),
      nullif(v_card ->> 'henso',''),
      nullif(v_card #>> '{gameSystemEffects,disguise}',''),
      nullif(v_card #>> '{gameSystemEffects,henso}',''),
      nullif(v_card #>> '{sourceData,disguiseEffect}',''),
      nullif(v_card #>> '{sourceData,disguise_effect}',''),
      nullif(v_card #>> '{sourceData,hensoEffect}',''),
      nullif(v_card #>> '{sourceData,henso}','')
    ) is null then
      raise exception '변장 효과가 있는 캐릭터를 선택해 주세요.';
    end if;$new_validation$;
  v_old_resolution text := $old_resolution$    v_pending := jsonb_set(v_pending,'{type}',to_jsonb('character_contact'::text));
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_user::text));
    update public.room_match_states m set pending_action=v_pending,state_version=state_version+1,
      last_action_label=format('변장: %s가 컨택 대상 대신 등장했고, 기존 대상은 덱 맨 아래로 이동했습니다.',coalesce(v_card ->> 'key','캐릭터'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);$old_resolution$;
  v_new_resolution text := $new_resolution$    v_pending := jsonb_set(v_pending,'{type}',to_jsonb('character_contact'::text));
    -- Choosing disguise resolves the contact immediately; neither player gets a cut-in window.
    perform public.resolve_private_character_contact(p_room_id,v_pending);
    update public.room_match_states m
      set last_action_label=format('변장: %s가 컨택 대상 대신 등장했습니다. 변장 후 컷인 없이 컨택을 해결했습니다.',coalesce(v_card ->> 'key','캐릭터'))
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);$new_resolution$;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  IF position(v_new_validation in v_definition) = 0 THEN
    IF position(v_old_validation in v_definition) = 0 THEN
      RAISE EXCEPTION 'v8 follow-up stopped: disguise validation block did not match';
    END IF;
    v_definition := replace(v_definition, v_old_validation, v_new_validation);
  END IF;

  IF position(v_new_resolution in v_definition) = 0 THEN
    IF position(v_old_resolution in v_definition) = 0 THEN
      RAISE EXCEPTION 'v8 follow-up stopped: disguise resolution block did not match';
    END IF;
    v_definition := replace(v_definition, v_old_resolution, v_new_resolution);
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'v8 follow-up stopped: action function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$match_v8_disguise$;

DO $match_v8_private_evidence_redaction$
DECLARE
  v_definition text;
  v_old text := $old_evidence$        select jsonb_agg(ev.value order by ev.ordinality)
        from public.room_player_game_states evidence_state
        cross join lateral jsonb_array_elements(coalesce(evidence_state.evidence_cards, '[]'::jsonb)) with ordinality ev(value, ordinality)
        where evidence_state.room_id = p_room_id and evidence_state.user_id = rp.user_id$old_evidence$;
  v_new text := $new_evidence$        select jsonb_agg(
          case
            when coalesce((ev.value ->> 'face_up')::boolean,false) is true then ev.value
            else jsonb_build_object('instance_id', ev.value ->> 'instance_id', 'face_up', false)
          end order by ev.ordinality
        )
        from public.room_player_game_states evidence_state
        cross join lateral jsonb_array_elements(coalesce(evidence_state.evidence_cards, '[]'::jsonb)) with ordinality ev(value, ordinality)
        where evidence_state.room_id = p_room_id and evidence_state.user_id = rp.user_id$new_evidence$;
BEGIN
  SELECT pg_get_functiondef('public.get_private_turn_state_v2(uuid)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  IF position(v_new in v_definition) = 0 THEN
    IF position(v_old in v_definition) = 0 THEN
      RAISE EXCEPTION 'v8 follow-up stopped: private evidence getter block did not match';
    END IF;
    v_definition := replace(v_definition, v_old, v_new);
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'v8 follow-up stopped: getter function definition is empty';
  END IF;
  EXECUTE v_definition;
END
$match_v8_private_evidence_redaction$;
