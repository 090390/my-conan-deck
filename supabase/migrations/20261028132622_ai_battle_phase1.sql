
-- AI battle metadata. Only the service role may read or mutate these records.
create table if not exists public.private_ai_battles (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  human_user_id uuid not null references auth.users(id) on delete cascade,
  ai_user_id uuid not null references auth.users(id),
  worker_locked_until timestamptz,
  created_at timestamptz not null default now(),
  constraint private_ai_battles_room_ai_unique unique (room_id, ai_user_id)
);
alter table public.private_ai_battles enable row level security;
revoke all on public.private_ai_battles from anon, authenticated;
grant all on public.private_ai_battles to service_role;

CREATE OR REPLACE FUNCTION public.create_private_ai_battle_v1(p_room_id uuid, p_human_user_id uuid, p_ai_user_id uuid, p_ai_main_deck jsonb, p_ai_partner_key text, p_ai_event_key text, p_ai_event_rule_code text DEFAULT ''::text)
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

CREATE OR REPLACE FUNCTION public.claim_private_ai_battle_worker_v1(p_room_id uuid, p_human_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_rows integer;
begin
  update public.private_ai_battles
  set worker_locked_until = clock_timestamp() + interval '35 seconds'
  where room_id = p_room_id
    and human_user_id = p_human_user_id
    and (worker_locked_until is null or worker_locked_until < clock_timestamp());
  get diagnostics v_rows = row_count;
  return v_rows = 1;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.release_private_ai_battle_worker_v1(p_room_id uuid, p_human_user_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  update public.private_ai_battles
  set worker_locked_until = null
  where room_id = p_room_id and human_user_id = p_human_user_id;
$function$
;

CREATE OR REPLACE FUNCTION public.perform_private_ai_turn_action_v1(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  select * into v_battle from public.private_ai_battles
  where room_id = p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  if p_action not in (
    'begin_turn','place_files','play_character','play_event','next_hint_take_file',
    'next_hint','cancel_next_hint','partner_assist','partner_deduce','end_turn',
    'declare_contact','attack_evidence','guard_with_character','decline_guard',
    'guard_contact_with_character','decline_contact_guard','contact_use_cutin',
    'contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead',
    'resolve_evidence_attack','acknowledge_evidence_remove','acknowledge_culprits_crime',
    'acknowledge_hand_reveal','acknowledge_deck_remove','acknowledge_file_remove',
    'acknowledge_shared_deck_peek','finish_event','solve_case','declare_solution',
    'rest_partner_manual','refresh_deck','return_deck_peek','share_deck_peek_card',
    'take_deck_peek_card','remove_deck_peek_card','shuffle_deck'
  ) then
    raise exception 'AI 대전에서 허용되지 않은 행동입니다.';
  end if;

  select * into v_match from public.room_match_states
  where room_id = p_room_id for update;
  if not found or v_match.game_over then
    raise exception '이미 종료된 AI 대전입니다.';
  end if;

  if cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 then
    raise exception 'AI 대전은 중도 종료 응답을 기다리는 동안 일시 중지되어 있습니다.';
  end if;

  if v_match.current_turn_user_id is distinct from v_battle.ai_user_id
    and coalesce(v_match.pending_action ->> 'target_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'next_responder_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'initiator_user_id', '') <> v_battle.ai_user_id::text then
    raise exception '현재 AI가 행동할 차례가 아닙니다.';
  end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  v_result := public.perform_private_turn_action_v2(
    p_room_id, p_action, coalesce(p_payload, '{}'::jsonb)
  );

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

CREATE OR REPLACE FUNCTION public.submit_private_ai_mulligan_v1(p_room_id uuid, p_return_instance_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  select * into v_battle from public.private_ai_battles
  where room_id = p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  select * into v_match from public.room_match_states
  where room_id = p_room_id for update;
  if not found or v_match.phase <> 'mulligan' then
    raise exception '멀리건 단계가 아닙니다.';
  end if;

  if exists (
    select 1 from public.room_player_game_states gs
    where gs.room_id = p_room_id and gs.user_id = v_battle.ai_user_id and gs.mulligan_done
  ) then
    return public.get_private_match_state(p_room_id);
  end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  v_result := public.submit_private_mulligan(
    p_room_id, coalesce(p_return_instance_ids, '[]'::jsonb)
  );

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

CREATE OR REPLACE FUNCTION public.respond_private_ai_cancel_v1(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
begin
  select * into v_battle from public.private_ai_battles
  where room_id = p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  select * into v_match from public.room_match_states where room_id = p_room_id for update;
  if not found or v_match.game_over then return; end if;
  if not (v_battle.human_user_id = any(coalesce(v_match.cancel_requested_by, '{}'::uuid[]))) then
    return;
  end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  perform public.respond_private_match_cancel_v1(p_room_id, true);

  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  raise;
end;
$function$
;

revoke all on function public.create_private_ai_battle_v1(uuid,uuid,uuid,jsonb,text,text,text) from public, anon, authenticated;
revoke all on function public.claim_private_ai_battle_worker_v1(uuid,uuid) from public, anon, authenticated;
revoke all on function public.release_private_ai_battle_worker_v1(uuid,uuid) from public, anon, authenticated;
revoke all on function public.perform_private_ai_turn_action_v1(uuid,text,jsonb) from public, anon, authenticated;
revoke all on function public.submit_private_ai_mulligan_v1(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.respond_private_ai_cancel_v1(uuid) from public, anon, authenticated;
grant execute on function public.create_private_ai_battle_v1(uuid,uuid,uuid,jsonb,text,text,text) to service_role;
grant execute on function public.claim_private_ai_battle_worker_v1(uuid,uuid) to service_role;
grant execute on function public.release_private_ai_battle_worker_v1(uuid,uuid) to service_role;
grant execute on function public.perform_private_ai_turn_action_v1(uuid,text,jsonb) to service_role;
grant execute on function public.submit_private_ai_mulligan_v1(uuid,jsonb) to service_role;
grant execute on function public.respond_private_ai_cancel_v1(uuid) to service_role;
