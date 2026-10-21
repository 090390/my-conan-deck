-- Fix MR movement when stored card JSON lacks rarity, restore the correct disguise contact flow,
-- choose cut-in order from live AP, and preserve per-turn evidence/file zone snapshots.

-- 1) Add a rarity-aware MR move RPC. Some live field-card JSON instances omit "rarity";
-- the UI's card catalog can still authoritatively identify MR, and passes that value here.
DO $install_mr_move_v2$
DECLARE
  v_definition text;
  v_old_header text := 'FUNCTION public.move_private_field_mr_to_partner_v1(';
  v_old_guard text := $guard$IF upper(coalesce(v_card ->> 'rarity','')) <> 'MR' THEN
    RAISE EXCEPTION 'MR 카드만 MR 파트너 에이리어로 강제 이동할 수 있습니다.';
  END IF;$guard$;
  v_new_guard text := $newguard$v_stored_rarity := upper(nullif(trim(v_card ->> 'rarity'),''));
  IF upper(coalesce(trim(p_card_rarity),'')) <> 'MR'
     OR (v_stored_rarity IS NOT NULL AND v_stored_rarity <> 'MR') THEN
    RAISE EXCEPTION 'MR 카드만 MR 파트너 에이리어로 강제 이동할 수 있습니다.';
  END IF;$newguard$;
BEGIN
  SELECT pg_get_functiondef('public.move_private_field_mr_to_partner_v1(uuid,uuid,text)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, v_old_header, 'FUNCTION public.move_private_field_mr_to_partner_v2(');
  v_definition := replace(v_definition, 'p_instance_id text', 'p_instance_id text, p_card_rarity text');
  v_definition := replace(v_definition, '$move_private_field_mr_to_partner_v1$', '$move_private_field_mr_to_partner_v2$');
  v_definition := replace(v_definition, '  v_remove_column text;', '  v_remove_column text;' || chr(10) || '  v_stored_rarity text;');

  IF position(v_new_guard in v_definition) = 0 THEN
    IF position(v_old_guard in v_definition) = 0 THEN
      RAISE EXCEPTION 'MR move patch stopped: rarity guard was not found';
    END IF;
    v_definition := replace(v_definition, v_old_guard, v_new_guard);
  END IF;

  EXECUTE v_definition;
END
$install_mr_move_v2$;

REVOKE ALL ON FUNCTION public.move_private_field_mr_to_partner_v2(uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_private_field_mr_to_partner_v2(uuid,uuid,text,text) TO authenticated;

-- 2) Patch the deployed contact action function. Disguise replaces the target with a slipped
-- field character; the original target remains in deck bottom and the attacker gets the only
-- remaining cut-in choice. Ordinary contact asks the lower-AP player first (tie = defender).
DO $patch_contact_flow$
DECLARE
  v_definition text;
  v_original text;
  v_start integer;
  v_end integer;
  v_disguise_end integer;
  v_rel integer;
  v_cut_marker text := $marker$v_pending := jsonb_set(v_pending,'{cut_in_used}','true'::jsonb);$marker$;
  v_cut_pos integer;
  v_tail text;
  v_target_if_pos integer;
  v_end_if_pos integer;
  v_block text;
  v_new_transition text := $transition$
if (coalesce(nullif(v_pending ->> 'attacker_cut_in_used','')::boolean,false)
      or coalesce(nullif(v_pending ->> 'attacker_cut_in_passed','')::boolean,false))
   and (coalesce(nullif(v_pending ->> 'target_cut_in_used','')::boolean,false)
      or coalesce(nullif(v_pending ->> 'target_cut_in_passed','')::boolean,false)) then
  perform public.resolve_private_character_contact(p_room_id,v_pending);
  return public.get_private_turn_state_v2(p_room_id);
end if;
if v_user::text = v_pending ->> 'target_user_id' then
  v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'attacker_user_id'));
  update public.room_match_states m
    set pending_action=v_pending,state_version=state_version+1,
        last_action_label='수비자가 컷인을 사용했습니다. 이제 공격자가 컷인 사용 여부를 선택합니다.'
    where m.room_id=p_room_id;
else
  v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'target_user_id'));
  update public.room_match_states m
    set pending_action=v_pending,state_version=state_version+1,
        last_action_label='공격자가 컷인을 사용했습니다. 이제 수비자가 컷인 사용 여부를 선택합니다.'
    where m.room_id=p_room_id;
end if;
return public.get_private_turn_state_v2(p_room_id);$transition$;
  v_new_pass_action text := $pass$
if p_action = 'contact_pass_cutin' then
  if v_match.pending_action is null
     or v_match.pending_action ->> 'type' is distinct from 'character_contact' then
    raise exception '컷인 선택 단계가 아닙니다.';
  end if;
  if v_match.pending_action ->> 'next_responder_user_id' is distinct from v_user::text then
    raise exception '현재 컷인 응답 순서가 아닙니다.';
  end if;
  v_pending := v_match.pending_action;

  if v_user::text = v_pending ->> 'target_user_id' then
    v_pending := jsonb_set(v_pending,'{target_cut_in_passed}','true'::jsonb);
    if coalesce(nullif(v_pending ->> 'attacker_cut_in_used','')::boolean,false)
       or coalesce(nullif(v_pending ->> 'attacker_cut_in_passed','')::boolean,false) then
      perform public.resolve_private_character_contact(p_room_id,v_pending);
      return public.get_private_turn_state_v2(p_room_id);
    end if;
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'attacker_user_id'));
    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label='수비자가 컷인을 패스했습니다. 이제 공격자가 컷인 사용 여부를 선택합니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  elsif v_user::text = v_pending ->> 'attacker_user_id' then
    v_pending := jsonb_set(v_pending,'{attacker_cut_in_passed}','true'::jsonb);
    if coalesce(nullif(v_pending ->> 'target_cut_in_used','')::boolean,false)
       or coalesce(nullif(v_pending ->> 'target_cut_in_passed','')::boolean,false) then
      perform public.resolve_private_character_contact(p_room_id,v_pending);
      return public.get_private_turn_state_v2(p_room_id);
    end if;
    v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(v_pending ->> 'target_user_id'));
    update public.room_match_states m
      set pending_action=v_pending,state_version=state_version+1,
          last_action_label='공격자가 컷인을 패스했습니다. 이제 수비자가 컷인 사용 여부를 선택합니다.'
      where m.room_id=p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  else
    raise exception '컨택 참가자만 컷인 선택을 처리할 수 있습니다.';
  end if;
end if;
$pass$;
  v_has_priority_anchor boolean := false;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  v_definition := replace(v_definition, chr(13), '');

  -- Disguise action: the new card stays slipped in the field, not auto-routed as a departed MR.
  v_start := position('if p_action = ''contact_use_disguise'' then' in lower(v_definition));
  v_end := position('if p_action = ''guard_contact_with_character'' then' in lower(v_definition));
  v_disguise_end := v_end;
  IF v_start = 0 OR v_end <= v_start THEN
    RAISE EXCEPTION 'Contact patch stopped: could not isolate contact_use_disguise action';
  END IF;
  v_block := substring(v_definition from v_start for v_end - v_start);
  v_original := v_block;

  v_block := replace(
    v_block,
    'jsonb_build_object(''rested'',false,''status'',''active'',''ap_bonus'',0,''summoned_this_turn'',false)',
    'jsonb_build_object(''rested'',true,''status'',''active'',''ap_bonus'',0,''summoned_this_turn'',true)'
  );
  v_block := replace(
    v_block,
    'v_pending := jsonb_set(v_pending,''{next_responder_user_id}'',to_jsonb(v_user::text));',
    'v_pending := jsonb_set(v_pending,''{target_cut_in_passed}'',''true''::jsonb);' || chr(10) ||
    '    v_pending := jsonb_set(v_pending,''{disguise_replaced_target}'',''true''::jsonb);' || chr(10) ||
    '    v_pending := jsonb_set(v_pending,''{next_responder_user_id}'',to_jsonb(v_match.pending_action ->> ''attacker_user_id''));'
  );

  v_rel := position('perform public.resolve_private_character_contact(p_room_id,v_pending);' in lower(v_block));
  IF v_rel > 0 THEN
    v_end := position('return public.get_private_turn_state_v2(p_room_id);' in lower(substring(v_block from v_rel)));
    IF v_end = 0 THEN RAISE EXCEPTION 'Contact patch stopped: disguise resolution return anchor not found'; END IF;
    v_end := v_rel + v_end + length('return public.get_private_turn_state_v2(p_room_id);') - 1;
    v_block := substring(v_block from 1 for v_rel - 1)
      || $disguise_return$
update public.room_match_states m
  set pending_action=v_pending,state_version=state_version+1,
      last_action_label=format('변장: %s가 컨택 대상을 교체해 슬립 상태로 등장했습니다. 공격자가 컷인 사용 여부를 선택합니다.',coalesce(v_card ->> 'key','캐릭터'))
  where m.room_id=p_room_id;
return public.get_private_turn_state_v2(p_room_id);$disguise_return$
      || substring(v_block from v_end);
  ELSE
    RAISE EXCEPTION 'Contact patch stopped: expected immediate disguise resolution code was not found';
  END IF;

  IF v_block = v_original
     OR position('perform public.resolve_private_character_contact(p_room_id,v_pending);' in lower(v_block)) > 0
     OR position('target_cut_in_passed' in v_block) = 0 THEN
    RAISE EXCEPTION 'Contact patch stopped: disguise replacement patch did not apply';
  END IF;

  v_definition := substring(v_definition from 1 for v_start - 1) || v_block
    || substring(v_definition from v_disguise_end);

  -- Guard declined: compare the AP values that were captured for this contact and override the
  -- default defender-first responder. AP values include the cards' current AP at contact time.
  v_start := position('if p_action = ''decline_contact_guard'' then' in lower(v_definition));
  IF v_start = 0 THEN RAISE EXCEPTION 'Contact patch stopped: decline_contact_guard action not found'; END IF;
  v_tail := substring(v_definition from v_start);
  v_rel := position('if p_action = ' in lower(substring(v_tail from length('if p_action = ''decline_contact_guard'' then') + 1)));
  IF v_rel > 0 THEN
    v_end := v_start + length('if p_action = ''decline_contact_guard'' then') + v_rel - 1;
  ELSE
    RAISE EXCEPTION 'Contact patch stopped: decline_contact_guard end anchor not found';
  END IF;
  v_block := substring(v_definition from v_start for v_end - v_start);
  v_rel := position('update public.room_match_states' in lower(v_block));
  IF v_rel = 0 THEN RAISE EXCEPTION 'Contact patch stopped: decline_contact_guard state update not found'; END IF;
  v_block := substring(v_block from 1 for v_rel - 1)
    || $ap_priority$
v_pending := jsonb_set(v_pending,'{cut_in_priority_user_id}',to_jsonb(
  CASE
    WHEN coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'target_bonus','')::numeric,0)
       <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'attacker_bonus','')::numeric,0)
    THEN v_pending ->> 'target_user_id'
    ELSE v_pending ->> 'attacker_user_id'
  END
));
v_pending := jsonb_set(v_pending,'{next_responder_user_id}',to_jsonb(
  CASE
    WHEN coalesce(nullif(v_pending ->> 'target_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'target_bonus','')::numeric,0)
       <= coalesce(nullif(v_pending ->> 'attacker_ap','')::numeric,0) + coalesce(nullif(v_pending ->> 'attacker_bonus','')::numeric,0)
    THEN v_pending ->> 'target_user_id'
    ELSE v_pending ->> 'attacker_user_id'
  END
));
$ap_priority$
    || substring(v_block from v_rel);
  v_definition := substring(v_definition from 1 for v_start - 1) || v_block
    || substring(v_definition from v_end);

  -- After either player uses a cut-in, ask the other player if they have not already passed/used.
  v_cut_pos := position(v_cut_marker in lower(v_definition));
  IF v_cut_pos = 0 THEN RAISE EXCEPTION 'Contact patch stopped: cut-in transition anchor not found'; END IF;
  v_tail := substring(v_definition from v_cut_pos + length(v_cut_marker));
  v_target_if_pos := position('if v_user = (v_match.pending_action ->> ''target_user_id'')::uuid then' in lower(v_tail));
  IF v_target_if_pos = 0 THEN RAISE EXCEPTION 'Contact patch stopped: defender-first cut-in transition not found'; END IF;
  v_target_if_pos := v_cut_pos + length(v_cut_marker) + v_target_if_pos - 1;
  v_tail := substring(v_definition from v_target_if_pos);
  v_end_if_pos := position('end if;' in lower(v_tail));
  IF v_end_if_pos = 0 THEN RAISE EXCEPTION 'Contact patch stopped: cut-in transition end not found'; END IF;
  v_end_if_pos := v_target_if_pos + v_end_if_pos + length('end if;');
  v_definition := substring(v_definition from 1 for v_cut_pos - 1)
    || v_cut_marker || chr(10) || v_new_transition || chr(10)
    || substring(v_definition from v_end_if_pos);

  -- Replace pass logic with an order-independent two-player response.
  v_start := position('if p_action = ''contact_pass_cutin'' then' in lower(v_definition));
  IF v_start = 0 THEN RAISE EXCEPTION 'Contact patch stopped: contact_pass_cutin action not found'; END IF;
  v_tail := substring(v_definition from v_start);
  v_rel := position('if p_action = ' in lower(substring(v_tail from length('if p_action = ''contact_pass_cutin'' then') + 1)));
  IF v_rel = 0 THEN RAISE EXCEPTION 'Contact patch stopped: contact_pass_cutin end anchor not found'; END IF;
  v_end := v_start + length('if p_action = ''contact_pass_cutin'' then') + v_rel - 1;
  v_definition := substring(v_definition from 1 for v_start - 1) || v_new_pass_action || chr(10)
    || substring(v_definition from v_end);

  -- Replace the live PL/pgSQL function after all transformations are completed.
  EXECUTE v_definition;
END
$patch_contact_flow$;

REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated;

-- 3) Per-turn, per-player zone snapshot table for post-game playback.
CREATE TABLE IF NOT EXISTS public.private_match_turn_zone_snapshots (
  room_id uuid NOT NULL,
  turn_number integer NOT NULL,
  turn_user_id uuid NOT NULL,
  player_user_id uuid NOT NULL,
  player_seat integer,
  display_name text,
  field_cards jsonb NOT NULL DEFAULT '[]'::jsonb,
  hand_cards jsonb NOT NULL DEFAULT '[]'::jsonb,
  evidence_cards jsonb NOT NULL DEFAULT '[]'::jsonb,
  file_cards jsonb NOT NULL DEFAULT '[]'::jsonb,
  captured_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(room_id,turn_number,turn_user_id,player_user_id)
);

ALTER TABLE public.private_match_turn_zone_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_match_turn_zone_snapshots FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.capture_private_match_turn_zone_snapshot_v1(
  p_room_id uuid,
  p_turn_number integer,
  p_turn_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $capture_private_match_turn_zone_snapshot_v1$
DECLARE
  v_player record;
  v_game_json jsonb;
  v_board_json jsonb;
  v_file_key text;
  v_file_cards jsonb;
BEGIN
  IF p_room_id IS NULL OR p_turn_number IS NULL OR p_turn_user_id IS NULL THEN
    RETURN;
  END IF;

  FOR v_player IN
    SELECT user_id,seat,temporary_nickname
    FROM public.room_players
    WHERE room_id=p_room_id
    ORDER BY seat
  LOOP
    SELECT to_jsonb(gs) INTO v_game_json
    FROM public.room_player_game_states gs
    WHERE gs.room_id=p_room_id AND gs.user_id=v_player.user_id;
    IF v_game_json IS NULL THEN CONTINUE; END IF;

    SELECT to_jsonb(tb) INTO v_board_json
    FROM public.room_player_turn_boards tb
    WHERE tb.room_id=p_room_id AND tb.user_id=v_player.user_id;

    v_file_key := NULL;
    SELECT key INTO v_file_key
    FROM jsonb_each(v_game_json) e(key,value)
    WHERE e.key ILIKE '%file%'
      AND e.key NOT ILIKE '%count%'
      AND e.key NOT ILIKE '%order%'
      AND e.key NOT ILIKE '%peek%'
      AND jsonb_typeof(e.value)='array'
    ORDER BY CASE
      WHEN e.key='file_cards' THEN 0
      WHEN e.key='files_cards' THEN 1
      WHEN e.key='files' THEN 2
      ELSE 3
    END, e.key
    LIMIT 1;

    v_file_cards := CASE
      WHEN v_file_key IS NULL THEN '[]'::jsonb
      ELSE coalesce(v_game_json -> v_file_key,'[]'::jsonb)
    END;

    INSERT INTO public.private_match_turn_zone_snapshots(
      room_id,turn_number,turn_user_id,player_user_id,player_seat,display_name,
      field_cards,hand_cards,evidence_cards,file_cards,captured_at
    )
    VALUES (
      p_room_id,p_turn_number,p_turn_user_id,v_player.user_id,v_player.seat,
      coalesce(nullif(trim(v_player.temporary_nickname),''),'플레이어 '||v_player.seat::text),
      coalesce(v_board_json -> 'field_cards','[]'::jsonb),
      coalesce(v_game_json -> 'hand','[]'::jsonb),
      coalesce(v_game_json -> 'evidence_cards','[]'::jsonb),
      v_file_cards,
      now()
    )
    ON CONFLICT(room_id,turn_number,turn_user_id,player_user_id)
    DO UPDATE SET
      player_seat=EXCLUDED.player_seat,
      display_name=EXCLUDED.display_name,
      field_cards=EXCLUDED.field_cards,
      hand_cards=EXCLUDED.hand_cards,
      evidence_cards=EXCLUDED.evidence_cards,
      file_cards=EXCLUDED.file_cards,
      captured_at=EXCLUDED.captured_at;
  END LOOP;
END;
$capture_private_match_turn_zone_snapshot_v1$;

CREATE OR REPLACE FUNCTION public.capture_private_match_turn_zone_snapshot_trigger_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $capture_private_match_turn_zone_snapshot_trigger_v1$
BEGIN
  IF TG_OP='UPDATE'
     AND OLD.turn_number IS NOT NULL
     AND OLD.current_turn_user_id IS NOT NULL THEN
    PERFORM public.capture_private_match_turn_zone_snapshot_v1(
      OLD.room_id,OLD.turn_number,OLD.current_turn_user_id
    );
  END IF;

  IF NEW.turn_number IS NOT NULL AND NEW.current_turn_user_id IS NOT NULL THEN
    PERFORM public.capture_private_match_turn_zone_snapshot_v1(
      NEW.room_id,NEW.turn_number,NEW.current_turn_user_id
    );
  END IF;
  RETURN NEW;
END;
$capture_private_match_turn_zone_snapshot_trigger_v1$;

DROP TRIGGER IF EXISTS private_match_turn_zone_snapshot_capture ON public.room_match_states;
CREATE TRIGGER private_match_turn_zone_snapshot_capture
  AFTER INSERT OR UPDATE ON public.room_match_states
  FOR EACH ROW
  EXECUTE FUNCTION public.capture_private_match_turn_zone_snapshot_trigger_v1();

CREATE OR REPLACE FUNCTION public.get_private_match_turn_zone_snapshots_v1(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $get_private_match_turn_zone_snapshots_v1$
DECLARE
  v_user uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자만 플레이 기록을 확인할 수 있습니다.';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'room_id',room_id,
    'turn_number',turn_number,
    'turn_user_id',turn_user_id,
    'player_user_id',player_user_id,
    'player_seat',player_seat,
    'display_name',display_name,
    'field_cards',field_cards,
    'hand_cards',hand_cards,
    'evidence_cards',evidence_cards,
    'file_cards',file_cards,
    'captured_at',captured_at
  ) ORDER BY turn_number ASC,captured_at ASC,player_seat ASC),'[]'::jsonb)
  INTO v_result
  FROM public.private_match_turn_zone_snapshots
  WHERE room_id=p_room_id;

  RETURN coalesce(v_result,'[]'::jsonb);
END;
$get_private_match_turn_zone_snapshots_v1$;

REVOKE ALL ON FUNCTION public.capture_private_match_turn_zone_snapshot_v1(uuid,integer,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.capture_private_match_turn_zone_snapshot_trigger_v1() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_private_match_turn_zone_snapshots_v1(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_private_match_turn_zone_snapshots_v1(uuid) TO authenticated;
