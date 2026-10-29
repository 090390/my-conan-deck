CREATE OR REPLACE FUNCTION public.create_private_ai_battle_v1(p_room_id uuid, p_human_user_id uuid, p_ai_user_id uuid, p_ai_main_deck jsonb, p_ai_partner_key text, p_ai_event_key text, p_ai_event_has_non_blue_color boolean, p_ai_event_rule_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_invite_code text;
  v_ai_email text;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  if p_room_id is null or p_human_user_id is null or p_ai_user_id is null then
    raise exception 'AI 대전 생성 정보가 올바르지 않습니다.';
  end if;

  select lower(coalesce(u.email, '')) into v_ai_email
  from auth.users u where u.id = p_ai_user_id;
  if v_ai_email is distinct from 'conan-tcg-ai-bot@my-conan-deck.invalid' then
    raise exception 'AI 대전용 계정을 확인할 수 없습니다.';
  end if;

  select r.invite_code into v_invite_code
  from public.rooms r
  where r.id = p_room_id and r.host_user_id = p_human_user_id and r.status = 'waiting'
  for update;
  if v_invite_code is null then
    raise exception 'AI 대전용 방을 찾을 수 없거나 생성 권한이 없습니다.';
  end if;

  if not exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.user_id = p_human_user_id and rp.seat = 1
  ) then
    raise exception 'AI 대전의 사람 플레이어 좌석을 찾을 수 없습니다.';
  end if;
  if exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.user_id <> p_human_user_id
  ) then
    raise exception '이미 다른 플레이어가 참가한 방은 AI 대전으로 전환할 수 없습니다.';
  end if;
  if not exists (
    select 1 from public.room_player_decks d
    where d.room_id = p_room_id and d.user_id = p_human_user_id
  ) or not exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.user_id = p_human_user_id and rp.is_ready
  ) then
    raise exception '먼저 사람 플레이어의 덱을 제출해 주세요.';
  end if;
  if exists (select 1 from public.private_ai_battles b where b.room_id = p_room_id) then
    raise exception '이 방은 이미 AI 대전으로 설정되어 있습니다.';
  end if;

  insert into public.private_ai_battles(room_id, human_user_id, ai_user_id)
  values (p_room_id, p_human_user_id, p_ai_user_id);

  perform set_config('request.jwt.claim.sub', p_ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_ai_user_id::text,
    'role', 'authenticated',
    'email', v_ai_email
  )::text, true);

  perform 1 from public.join_private_room(v_invite_code);
  perform 1 from public.submit_private_room_deck(
    p_room_id,
    p_ai_main_deck,
    p_ai_partner_key,
    p_ai_event_key,
    coalesce(p_ai_event_rule_code, '')
  );

  -- Persist event-color metadata before start_private_match inserts room_match_states.
  -- The room_player_decks lock trigger intentionally rejects updates after that point.
  update public.room_player_decks
     set event_has_non_blue_color = coalesce(p_ai_event_has_non_blue_color, false)
   where room_id = p_room_id and user_id = p_ai_user_id;
  if not found then
    raise exception 'AI 플레이어의 덱 또는 사건 카드 정보를 저장하지 못했습니다.';
  end if;

  update public.room_players
  set temporary_nickname = 'AI 탐정'
  where room_id = p_room_id and user_id = p_ai_user_id;

  perform set_config('request.jwt.claim.sub', p_human_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_human_user_id::text,
    'role', 'authenticated'
  )::text, true);

  v_result := public.start_private_match(p_room_id);

  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  return v_result;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  raise;
end;
$function$
;

REVOKE ALL ON FUNCTION public.create_private_ai_battle_v1(uuid, uuid, uuid, jsonb, text, text, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_private_ai_battle_v1(uuid, uuid, uuid, jsonb, text, text, boolean, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_private_ai_battle_v1(uuid, uuid, uuid, jsonb, text, text, boolean, text) TO service_role;
