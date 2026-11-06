
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.match_diagnostic_sessions (
  id uuid primary key default gen_random_uuid(),
  trace_code text not null unique,
  room_id uuid not null unique,
  match_mode text not null default 'human' check (match_mode in ('human','ai')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text,
  participants jsonb not null default '[]'::jsonb,
  last_activity_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists match_diagnostic_sessions_activity_idx
  on private.match_diagnostic_sessions(last_activity_at desc);

create table if not exists private.match_diagnostic_events (
  id bigint generated always as identity primary key,
  session_id uuid not null references private.match_diagnostic_sessions(id) on delete cascade,
  event_type text not null,
  created_at timestamptz not null default now(),
  turn_number integer,
  actor_user_id uuid,
  actor_label text,
  action_label text,
  phase text,
  turn_step text,
  state_version bigint,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  context jsonb not null default '{}'::jsonb
);

create index if not exists match_diagnostic_events_session_created_idx
  on private.match_diagnostic_events(session_id, created_at, id);

create table if not exists private.match_diagnostic_errors (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references private.match_diagnostic_sessions(id) on delete cascade,
  report_code text not null unique,
  reported_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '60 days'),
  actor_user_id uuid,
  action text not null,
  error_message text not null,
  error_code text,
  context jsonb not null default '{}'::jsonb
);

create index if not exists match_diagnostic_errors_session_reported_idx
  on private.match_diagnostic_errors(session_id, reported_at desc);

create table if not exists private.match_diagnostic_admin_attempts (
  user_id uuid primary key,
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0
);

revoke all on all tables in schema private from public, anon, authenticated, service_role;

create or replace function private.match_diagnostic_code_v1(p_prefix text)
returns text
language sql
volatile
set search_path = pg_catalog
as $function$
  select p_prefix || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4)) || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))
$function$;

revoke all on function private.match_diagnostic_code_v1(text) from public, anon, authenticated, service_role;

create or replace function private.match_diagnostic_safe_state_v1(p_room_id uuid, p_state jsonb)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'phase', p_state ->> 'phase',
    'case_phase', p_state ->> 'case_phase',
    'turn_number', nullif(p_state ->> 'turn_number', '')::integer,
    'turn_step', p_state ->> 'turn_step',
    'state_version', nullif(p_state ->> 'state_version', '')::bigint,
    'first_player_user_id', p_state ->> 'first_player_user_id',
    'current_turn_user_id', p_state ->> 'current_turn_user_id',
    'game_over', nullif(p_state ->> 'game_over', '')::boolean,
    'winner_user_id', p_state ->> 'winner_user_id',
    'pending_action', case when jsonb_typeof(p_state -> 'pending_action') = 'object' then
      jsonb_strip_nulls(jsonb_build_object(
        'type', p_state -> 'pending_action' ->> 'type',
        'step', p_state -> 'pending_action' ->> 'step',
        'operation', p_state -> 'pending_action' ->> 'operation',
        'source_user_id', p_state -> 'pending_action' ->> 'source_user_id',
        'source_instance_id', p_state -> 'pending_action' ->> 'source_instance_id',
        'source_card_key', p_state -> 'pending_action' ->> 'source_card_key',
        'target_user_id', p_state -> 'pending_action' ->> 'target_user_id',
        'target_instance_id', p_state -> 'pending_action' ->> 'target_instance_id',
        'chooser_user_id', p_state -> 'pending_action' ->> 'chooser_user_id',
        'initiator_user_id', p_state -> 'pending_action' ->> 'initiator_user_id',
        'next_responder_user_id', p_state -> 'pending_action' ->> 'next_responder_user_id',
        'selected_count', p_state -> 'pending_action' ->> 'selected_count',
        'count', p_state -> 'pending_action' ->> 'count'
      ))
    else null end,
    'boards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', b.user_id,
        'seat', b.seat,
        'field_cards', coalesce((
          select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
            'instance_id', c.value ->> 'instance_id',
            'key', c.value ->> 'key',
            'card_id', c.value ->> 'card_id',
            'status', c.value ->> 'status',
            'rested', c.value -> 'rested',
            'stunned', c.value -> 'stunned'
          )))
          from jsonb_array_elements(coalesce(b.field_cards, '[]'::jsonb)) c(value)
        ), '[]'::jsonb),
        'file_count', b.file_count,
        'evidence_count', b.evidence_count,
        'remove_count', b.remove_count,
        'partner_rested', b.partner_rested,
        'partner_assist_used', b.partner_assist_used,
        'partner_deduction_used', b.partner_deduction_used,
        'character_played_this_turn', b.character_played_this_turn,
        'next_hint_used', b.next_hint_used,
        'files_to_place', b.files_to_place,
        'files_placed_this_turn', b.files_placed_this_turn,
        'base_action_done', b.base_action_done,
        'base_card_played_this_turn', b.base_card_played_this_turn,
        'first_character_entered_this_turn', b.first_character_entered_this_turn,
        'case_phase', b.case_phase,
        'next_hint_pending', b.next_hint_pending
      ) order by b.seat)
      from public.room_player_turn_boards b
      where b.room_id = p_room_id
    ), '[]'::jsonb)
  ))
$function$;

revoke all on function private.match_diagnostic_safe_state_v1(uuid,jsonb) from public, anon, authenticated, service_role;

create or replace function private.ensure_match_diagnostic_session_v1(p_room_id uuid, p_started_at timestamptz default null)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_session_id uuid;
  v_participants jsonb;
  v_mode text;
  v_started_at timestamptz := coalesce(p_started_at, now());
begin
  if p_room_id is null then
    raise exception '진단 세션의 대전 방 ID가 없습니다.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'seat', rp.seat,
    'user_id', rp.user_id,
    'display_name', coalesce(nullif(trim(rp.temporary_nickname), ''), '플레이어 ' || rp.seat::text)
  ) order by rp.seat), '[]'::jsonb)
  into v_participants
  from public.room_players rp
  where rp.room_id = p_room_id;

  select case when exists (
    select 1 from public.private_ai_battles b where b.room_id = p_room_id
  ) then 'ai' else 'human' end into v_mode;

  insert into private.match_diagnostic_sessions(
    trace_code, room_id, match_mode, started_at, participants, last_activity_at
  )
  values (
    private.match_diagnostic_code_v1('MT'), p_room_id, v_mode, v_started_at,
    v_participants, now()
  )
  on conflict (room_id) do update
    set last_activity_at = greatest(private.match_diagnostic_sessions.last_activity_at, excluded.last_activity_at),
        participants = case
          when jsonb_array_length(excluded.participants) > 0 then excluded.participants
          else private.match_diagnostic_sessions.participants
        end
  returning id into v_session_id;

  return v_session_id;
end;
$function$;

revoke all on function private.ensure_match_diagnostic_session_v1(uuid,timestamptz) from public, anon, authenticated, service_role;

create or replace function private.match_diagnostic_state_capture_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_session_id uuid;
  v_before jsonb := '{}'::jsonb;
  v_after jsonb;
  v_event_type text;
  v_action_label text;
  v_actor uuid := auth.uid();
  v_turn integer;
  v_version bigint;
begin
  if new.phase not in ('mulligan','playing') and new.started_at is null then
    return new;
  end if;

  v_session_id := private.ensure_match_diagnostic_session_v1(
    new.room_id, coalesce(new.started_at, new.created_at, now())
  );

  if tg_op = 'UPDATE' then
    if new.state_version is not distinct from old.state_version
      and new.last_action_label is not distinct from old.last_action_label
      and new.game_over is not distinct from old.game_over
      and new.pending_action is not distinct from old.pending_action then
      return new;
    end if;
    v_before := private.match_diagnostic_safe_state_v1(new.room_id, to_jsonb(old));
  end if;

  v_after := private.match_diagnostic_safe_state_v1(new.room_id, to_jsonb(new));
  v_action_label := nullif(left(trim(coalesce(new.last_action_label, '')), 500), '');
  v_event_type := case
    when tg_op = 'INSERT' then 'match_started'
    when new.game_over and (tg_op = 'INSERT' or not coalesce(old.game_over, false)) then 'match_finished'
    else 'state_transition'
  end;
  v_turn := new.turn_number;
  v_version := new.state_version;

  insert into private.match_diagnostic_events(
    session_id, event_type, turn_number, actor_user_id, actor_label,
    action_label, phase, turn_step, state_version, before_state, after_state, context
  )
  values (
    v_session_id, v_event_type, v_turn, v_actor,
    case when v_actor is null then '시스템' else coalesce((
      select coalesce(nullif(trim(rp.temporary_nickname), ''), '플레이어 ' || rp.seat::text)
      from public.room_players rp where rp.room_id = new.room_id and rp.user_id = v_actor
    ), '플레이어') end,
    coalesce(v_action_label, v_event_type), new.phase, new.turn_step, v_version,
    v_before, v_after,
    jsonb_build_object('operation', tg_op)
  );

  update private.match_diagnostic_sessions
  set last_activity_at = now(),
      ended_at = case when new.game_over then coalesce(ended_at, now()) else ended_at end,
      ended_reason = case when new.game_over then coalesce(ended_reason, 'game_over') else ended_reason end
  where id = v_session_id;

  return new;
end;
$function$;

revoke all on function private.match_diagnostic_state_capture_v1() from public, anon, authenticated, service_role;

drop trigger if exists match_diagnostic_state_capture on public.room_match_states;
create trigger match_diagnostic_state_capture
  after insert or update on public.room_match_states
  for each row execute function private.match_diagnostic_state_capture_v1();

create or replace function private.match_diagnostic_room_deleted_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_session_id uuid;
begin
  update private.match_diagnostic_sessions
  set ended_at = coalesce(ended_at, now()),
      ended_reason = coalesce(ended_reason, 'room_deleted'),
      last_activity_at = now()
  where room_id = old.id
  returning id into v_session_id;

  if v_session_id is not null then
    insert into private.match_diagnostic_events(
      session_id, event_type, action_label, context
    ) values (
      v_session_id, 'room_deleted', '대전 방 데이터 정리',
      jsonb_build_object('retained_independently', true)
    );
  end if;
  return old;
end;
$function$;

revoke all on function private.match_diagnostic_room_deleted_v1() from public, anon, authenticated, service_role;

drop trigger if exists match_diagnostic_room_deleted on public.rooms;
create trigger match_diagnostic_room_deleted
  after delete on public.rooms
  for each row execute function private.match_diagnostic_room_deleted_v1();

create or replace function private.record_match_diagnostic_error_v1(
  p_room_id uuid,
  p_actor_user_id uuid,
  p_action text,
  p_error_message text,
  p_error_code text default null,
  p_error_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_session_id uuid;
  v_trace_code text;
  v_report_code text;
  v_safe_context jsonb;
  v_now timestamptz := now();
begin
  v_session_id := private.ensure_match_diagnostic_session_v1(p_room_id, v_now);

  v_safe_context := jsonb_strip_nulls(jsonb_build_object(
    'component', left(coalesce(p_error_context ->> 'component', ''), 80),
    'client_action', left(coalesce(p_error_context ->> 'client_action', ''), 120),
    'ai_action', left(coalesce(p_error_context ->> 'ai_action', ''), 120),
    'blocked_action', left(coalesce(p_error_context ->> 'blocked_action', ''), 120),
    'phase', left(coalesce(p_error_context ->> 'phase', ''), 40),
    'turn_step', left(coalesce(p_error_context ->> 'turn_step', ''), 60),
    'turn_number', left(coalesce(p_error_context ->> 'turn_number', ''), 20),
    'state_version', left(coalesce(p_error_context ->> 'state_version', ''), 30),
    'pending_action_type', left(coalesce(p_error_context ->> 'pending_action_type', ''), 80),
    'last_action_label', left(coalesce(p_error_context ->> 'last_action_label', ''), 500),
    'edge_action', left(coalesce(p_error_context ->> 'edge_action', ''), 40)
  ));

  v_report_code := private.match_diagnostic_code_v1('ER');

  insert into private.match_diagnostic_errors(
    session_id, report_code, reported_at, expires_at, actor_user_id,
    action, error_message, error_code, context
  )
  values (
    v_session_id, v_report_code, v_now, v_now + interval '60 days',
    p_actor_user_id, left(coalesce(nullif(trim(p_action), ''), 'unknown'), 120),
    left(coalesce(nullif(trim(p_error_message), ''), '오류 내용 미상'), 3000),
    left(nullif(trim(coalesce(p_error_code, '')), ''), 80), v_safe_context
  );

  update private.match_diagnostic_sessions
  set last_activity_at = v_now
  where id = v_session_id;

  select trace_code into v_trace_code
  from private.match_diagnostic_sessions where id = v_session_id;

  insert into private.match_diagnostic_events(
    session_id, event_type, actor_user_id, action_label,
    context
  ) values (
    v_session_id, 'error_reported', p_actor_user_id,
    left(coalesce(nullif(trim(p_action), ''), 'unknown'), 120),
    jsonb_build_object(
      'report_code', v_report_code,
      'error_code', left(coalesce(p_error_code, ''), 80),
      'message', left(coalesce(p_error_message, ''), 1000)
    ) || v_safe_context
  );

  return jsonb_build_object(
    'report_code', v_report_code,
    'trace_code', v_trace_code,
    'reported_at', v_now,
    'expires_at', v_now + interval '60 days'
  );
end;
$function$;

revoke all on function private.record_match_diagnostic_error_v1(uuid,uuid,text,text,text,jsonb) from public, anon, authenticated, service_role;

create or replace function public.get_private_match_trace_info_v1(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_session private.match_diagnostic_sessions%rowtype;
begin
  if v_user_id is null or not exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.user_id = v_user_id
  ) then
    raise exception '이 대전의 참가자만 추적 코드를 확인할 수 있습니다.';
  end if;

  select * into v_session
  from private.match_diagnostic_sessions
  where room_id = p_room_id;

  if not found then
    raise exception '대전 진단 세션을 아직 찾을 수 없습니다.';
  end if;

  return jsonb_build_object(
    'trace_code', v_session.trace_code,
    'started_at', v_session.started_at,
    'ended_at', v_session.ended_at
  );
end;
$function$;

revoke all on function public.get_private_match_trace_info_v1(uuid) from public, anon;
grant execute on function public.get_private_match_trace_info_v1(uuid) to authenticated;

create or replace function public.report_private_match_diagnostic_error_v1(
  p_room_id uuid,
  p_action text,
  p_error_message text,
  p_error_code text default null,
  p_error_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or not exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.user_id = v_user_id
  ) then
    raise exception '이 대전의 참가자만 오류 기록을 등록할 수 있습니다.';
  end if;

  return private.record_match_diagnostic_error_v1(
    p_room_id, v_user_id, p_action, p_error_message, p_error_code, p_error_context
  );
end;
$function$;

revoke all on function public.report_private_match_diagnostic_error_v1(uuid,text,text,text,jsonb) from public, anon;
grant execute on function public.report_private_match_diagnostic_error_v1(uuid,text,text,text,jsonb) to authenticated;

create or replace function public.report_private_match_diagnostic_error_internal_v1(
  p_room_id uuid,
  p_actor_user_id uuid,
  p_action text,
  p_error_message text,
  p_error_code text default null,
  p_error_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
begin
  if p_room_id is null then
    raise exception '진단 오류의 대전 방 ID가 없습니다.';
  end if;
  return private.record_match_diagnostic_error_v1(
    p_room_id, p_actor_user_id, p_action, p_error_message, p_error_code, p_error_context
  );
end;
$function$;

revoke all on function public.report_private_match_diagnostic_error_internal_v1(uuid,uuid,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.report_private_match_diagnostic_error_internal_v1(uuid,uuid,text,text,text,jsonb) to service_role;

create or replace function public.lookup_private_match_diagnostics_v1(
  p_code text,
  p_admin_password text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, extensions
as $function$
declare
  v_user_id uuid := auth.uid();
  v_hash text;
  v_attempts integer;
  v_session private.match_diagnostic_sessions%rowtype;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_is_trace boolean;
  v_errors jsonb;
  v_events jsonb;
begin
  if v_user_id is null then
    raise exception '관리자 로그인이 필요합니다.';
  end if;
  if v_code !~ '^(MT|ER)-[0-9A-F]{4}-[0-9A-F]{4}$' then
    return jsonb_build_object('ok', false, 'found', false, 'message', '진단 코드 형식이 올바르지 않습니다.');
  end if;

  insert into private.match_diagnostic_admin_attempts(user_id, window_started_at, attempt_count)
  values (v_user_id, now(), 1)
  on conflict (user_id) do update
    set attempt_count = case
          when private.match_diagnostic_admin_attempts.window_started_at < now() - interval '1 minute' then 1
          else private.match_diagnostic_admin_attempts.attempt_count + 1
        end,
        window_started_at = case
          when private.match_diagnostic_admin_attempts.window_started_at < now() - interval '1 minute' then now()
          else private.match_diagnostic_admin_attempts.window_started_at
        end
  returning attempt_count into v_attempts;

  if v_attempts > 10 then
    return jsonb_build_object('ok', false, 'found', false, 'message', '관리자 인증 시도가 너무 많습니다. 1분 후 다시 시도해 주세요.');
  end if;

  select c.password_hash into v_hash
  from public.site_change_suggestion_admin_config c
  where c.singleton = true;

  if v_hash is null or coalesce(p_admin_password, '') = ''
    or extensions.crypt(p_admin_password, v_hash) is distinct from v_hash then
    return jsonb_build_object('ok', false, 'found', false, 'message', '관리자 비밀번호가 올바르지 않습니다.');
  end if;

  delete from private.match_diagnostic_admin_attempts where user_id = v_user_id;

  v_is_trace := left(v_code, 3) = 'MT';
  if v_is_trace then
    select * into v_session from private.match_diagnostic_sessions s
    where s.trace_code = v_code;
  else
    select s.* into v_session
    from private.match_diagnostic_errors e
    join private.match_diagnostic_sessions s on s.id = e.session_id
    where e.report_code = v_code
      and e.expires_at > now();
  end if;

  if v_session.id is null then
    return jsonb_build_object('ok', true, 'found', false, 'message', '해당 코드의 진단 기록을 찾을 수 없습니다. 오류 코드는 발생일로부터 60일 동안 조회할 수 있습니다.');
  end if;

  select coalesce(jsonb_agg(to_jsonb(e) - 'session_id' order by e.reported_at desc), '[]'::jsonb)
  into v_errors
  from (
    select id, report_code, reported_at, expires_at, actor_user_id,
      action, error_message, error_code, context
    from private.match_diagnostic_errors
    where session_id = v_session.id
    order by reported_at desc
    limit 50
  ) e;

  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at, e.id), '[]'::jsonb)
  into v_events
  from (
    select id, event_type, created_at, turn_number, actor_user_id, actor_label,
      action_label, phase, turn_step, state_version,
      before_state, after_state, context
    from private.match_diagnostic_events
    where session_id = v_session.id
    order by created_at asc, id asc
    limit 1000
  ) e;

  return jsonb_build_object(
    'ok', true,
    'found', true,
    'lookup_type', case when v_is_trace then 'trace' else 'error' end,
    'session', jsonb_build_object(
      'trace_code', v_session.trace_code,
      'room_id', v_session.room_id,
      'match_mode', v_session.match_mode,
      'started_at', v_session.started_at,
      'ended_at', v_session.ended_at,
      'ended_reason', v_session.ended_reason,
      'participants', v_session.participants,
      'last_activity_at', v_session.last_activity_at
    ),
    'errors', v_errors,
    'events', v_events
  );
end;
$function$;

revoke all on function public.lookup_private_match_diagnostics_v1(text,text) from public, anon;
grant execute on function public.lookup_private_match_diagnostics_v1(text,text) to authenticated;

create or replace function private.purge_match_diagnostics_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private
as $function$
declare
  v_errors integer := 0;
  v_events integer := 0;
  v_sessions integer := 0;
begin
  delete from private.match_diagnostic_errors
  where expires_at <= now();
  get diagnostics v_errors = row_count;

  delete from private.match_diagnostic_events e
  where e.created_at < now() - interval '30 days'
    and not exists (
      select 1 from private.match_diagnostic_errors x
      where x.session_id = e.session_id and x.expires_at > now()
    );
  get diagnostics v_events = row_count;

  delete from private.match_diagnostic_sessions s
  where (
      (s.ended_at is not null and s.ended_at < now() - interval '30 days')
      or (s.ended_at is null and s.last_activity_at < now() - interval '90 days')
    )
    and not exists (
      select 1 from private.match_diagnostic_errors x
      where x.session_id = s.id and x.expires_at > now()
    );
  get diagnostics v_sessions = row_count;

  delete from private.match_diagnostic_admin_attempts
  where window_started_at < now() - interval '1 day';

  return jsonb_build_object(
    'deleted_errors', v_errors,
    'deleted_events', v_events,
    'deleted_sessions', v_sessions
  );
end;
$function$;

revoke all on function private.purge_match_diagnostics_v1() from public, anon, authenticated, service_role;

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

do $schedule$
declare
  v_job_id bigint;
begin
  for v_job_id in select jobid from cron.job where jobname = 'match-diagnostic-retention'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'match-diagnostic-retention',
    '15 3 * * *',
    'select private.purge_match_diagnostics_v1();'
  );
end;
$schedule$;
