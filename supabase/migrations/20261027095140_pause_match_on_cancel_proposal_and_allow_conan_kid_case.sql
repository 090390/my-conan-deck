DO $patch$
DECLARE v_definition text;
BEGIN
  v_definition := pg_get_functiondef('public.submit_private_room_deck(uuid,jsonb,text,text,text)'::regprocedure);
  IF position('conan_vs_kid_1261' in v_definition) = 0 THEN
    IF position($old$v_rule_code not in ('', 'culprits_1046')$old$ in v_definition) = 0 THEN
      RAISE EXCEPTION 'event rule whitelist anchor not found';
    END IF;
    v_definition := replace(v_definition,
      $old$v_rule_code not in ('', 'culprits_1046')$old$,
      $new$v_rule_code not in ('', 'culprits_1046', 'conan_vs_kid_1261')$new$);
    EXECUTE v_definition;
  END IF;
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  IF position('중도 종료 응답 대기 중입니다.' in v_definition) = 0 THEN
    IF position($old$if v_match.phase <> 'playing' or v_match.game_over then raise exception '진행 중인 게임이 아닙니다.'; end if;$old$ in v_definition) = 0 THEN
      RAISE EXCEPTION 'perform_private_turn_action_v2 pause gate anchor not found';
    END IF;
    v_definition := replace(v_definition,
      $old$if v_match.phase <> 'playing' or v_match.game_over then raise exception '진행 중인 게임이 아닙니다.'; end if;$old$,
      $new$if v_match.phase <> 'playing' or v_match.game_over then raise exception '진행 중인 게임이 아닙니다.'; end if;
  if cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 then
    raise exception '중도 종료 응답 대기 중입니다. 상대가 응답할 때까지 게임이 일시 중지됩니다.';
  end if;$new$);
    EXECUTE v_definition;
  END IF;
END;
$patch$;

CREATE OR REPLACE FUNCTION public.vote_private_match_cancel_v1(p_room_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_user uuid := auth.uid(); v_match public.room_match_states%ROWTYPE; v_player_count integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.room_players rp WHERE rp.room_id=p_room_id AND rp.user_id=v_user) THEN RAISE EXCEPTION '이 방의 참가자만 중도 종료를 제안할 수 있습니다.'; END IF;
  SELECT * INTO v_match FROM public.room_match_states m WHERE m.room_id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '모의전 상태를 찾을 수 없습니다.'; END IF;
  IF v_match.game_over OR v_match.phase IS DISTINCT FROM 'playing' THEN RAISE EXCEPTION '진행 중인 모의전만 중도 종료를 제안할 수 있습니다.'; END IF;
  IF cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 THEN RAISE EXCEPTION '이미 중도 종료 제안에 대한 응답을 기다리고 있습니다.'; END IF;
  SELECT count(*)::integer INTO v_player_count FROM public.room_players rp WHERE rp.room_id=p_room_id;
  IF v_player_count <> 2 THEN RAISE EXCEPTION '두 플레이어가 모두 있는 모의전에서만 종료를 제안할 수 있습니다.'; END IF;
  UPDATE public.room_match_states m SET cancel_requested_by=ARRAY[v_user]::uuid[],
    state_version=state_version+1,last_action_label='모의전 중도 종료 제안: 상대 플레이어의 동의를 기다리는 동안 게임을 일시 중지했습니다.'
  WHERE m.room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id) || jsonb_build_object('cancelled',false,
    'cancel_requested_by',to_jsonb(ARRAY[v_user]::uuid[]),'cancel_vote_count',1);
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_private_match_cancel_v1(p_room_id uuid, p_accept boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_user uuid := auth.uid(); v_match public.room_match_states%ROWTYPE; v_requester uuid; v_votes uuid[]; v_player_count integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.room_players rp WHERE rp.room_id=p_room_id AND rp.user_id=v_user) THEN RAISE EXCEPTION '이 방의 참가자만 중도 종료 제안에 응답할 수 있습니다.'; END IF;
  SELECT * INTO v_match FROM public.room_match_states m WHERE m.room_id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '모의전 상태를 찾을 수 없습니다.'; END IF;
  v_votes := coalesce(v_match.cancel_requested_by, '{}'::uuid[]);
  IF v_match.game_over OR v_match.phase IS DISTINCT FROM 'playing' OR cardinality(v_votes) <> 1 THEN RAISE EXCEPTION '응답할 중도 종료 제안이 없습니다.'; END IF;
  v_requester := v_votes[1];
  IF v_requester = v_user THEN RAISE EXCEPTION '중도 종료를 제안한 사람은 자신의 제안에 응답할 수 없습니다.'; END IF;
  SELECT count(*)::integer INTO v_player_count FROM public.room_players rp WHERE rp.room_id=p_room_id;
  IF v_player_count <> 2 THEN RAISE EXCEPTION '두 플레이어가 모두 있는 모의전에서만 종료 응답을 처리할 수 있습니다.'; END IF;
  IF p_accept THEN
    UPDATE public.room_match_states m SET cancel_requested_by=array_append(v_votes,v_user),game_over=true,winner_user_id=NULL,
      pending_action=NULL,state_version=state_version+1,last_action_label='모의전 취소 완료: 두 플레이어의 동의로 게임을 중도 종료했습니다.'
    WHERE m.room_id=p_room_id;
  ELSE
    UPDATE public.room_match_states m SET cancel_requested_by='{}'::uuid[],state_version=state_version+1,
      last_action_label='모의전 중도 종료 제안 거절: 두 플레이어가 게임을 계속할 수 있습니다.'
    WHERE m.room_id=p_room_id;
  END IF;
  RETURN public.get_private_turn_state_v2(p_room_id) || jsonb_build_object('cancelled',p_accept,
    'cancel_requested_by',CASE WHEN p_accept THEN to_jsonb(array_append(v_votes,v_user)) ELSE '[]'::jsonb END,
    'cancel_vote_count',CASE WHEN p_accept THEN 2 ELSE 0 END,'cancel_declined',NOT p_accept);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.vote_private_match_cancel_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_private_match_cancel_v1(uuid,boolean) TO authenticated;
