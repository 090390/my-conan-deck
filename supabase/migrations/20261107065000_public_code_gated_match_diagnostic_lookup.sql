-- Allow code holders to inspect diagnostic records without administrator authentication.
-- New codes use a full UUID (122 bits of effective entropy); legacy MT/ER codes remain valid.
-- Anonymous lookups are rate-limited to 10 attempts per client IP per minute.

create table if not exists private.match_diagnostic_lookup_attempts (
  client_hash text primary key check (client_hash ~ '^[0-9a-f]{32}$'),
  window_started_at timestamptz not null default now(),
  attempt_count integer not null default 0
);

alter table private.match_diagnostic_lookup_attempts enable row level security;
create policy match_diag_lookup_attempts_deny_direct_access
  on private.match_diagnostic_lookup_attempts for all to public
  using (false) with check (false);
revoke all on private.match_diagnostic_lookup_attempts from public, anon, authenticated, service_role;

create or replace function private.match_diagnostic_code_v1(p_prefix text)
returns text
language sql
volatile
set search_path = pg_catalog
as $function$
  select p_prefix || '-' ||
    substr(v.code, 1, 8) || '-' ||
    substr(v.code, 9, 8) || '-' ||
    substr(v.code, 17, 8) || '-' ||
    substr(v.code, 25, 8)
  from (select upper(replace(gen_random_uuid()::text, '-', '')) as code) v
$function$;

create or replace function private.lookup_private_match_diagnostics_core_v1(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, extensions
as $function$
declare
  v_headers jsonb := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
  v_client_ip text;
  v_client_hash text;
  v_attempts integer;
  v_session private.match_diagnostic_sessions%rowtype;
  v_code text := upper(trim(coalesce(p_code, '')));
  v_is_trace boolean;
  v_errors jsonb;
  v_events jsonb;
begin
  v_client_ip := coalesce(
    nullif(trim(v_headers ->> 'cf-connecting-ip'), ''),
    nullif(trim(v_headers ->> 'x-real-ip'), ''),
    nullif(trim(split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1)), '')
  );

  if v_client_ip is null then
    return jsonb_build_object(
      'ok', false, 'found', false,
      'message', '조회 요청의 출처를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.'
    );
  end if;

  v_client_hash := md5(v_client_ip);
  insert into private.match_diagnostic_lookup_attempts(client_hash, window_started_at, attempt_count)
  values (v_client_hash, now(), 1)
  on conflict (client_hash) do update
    set attempt_count = case
          when private.match_diagnostic_lookup_attempts.window_started_at < now() - interval '1 minute' then 1
          else private.match_diagnostic_lookup_attempts.attempt_count + 1
        end,
        window_started_at = case
          when private.match_diagnostic_lookup_attempts.window_started_at < now() - interval '1 minute' then now()
          else private.match_diagnostic_lookup_attempts.window_started_at
        end
  returning attempt_count into v_attempts;

  if v_attempts > 10 then
    return jsonb_build_object(
      'ok', false, 'found', false,
      'message', '조회 요청이 너무 많습니다. 1분 후 다시 시도해 주세요.'
    );
  end if;

  if v_code !~ '^(MT|ER)-([0-9A-F]{4}-[0-9A-F]{4}|[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8}-[0-9A-F]{8})$' then
    return jsonb_build_object(
      'ok', false, 'found', false,
      'message', '대전 추적 코드 또는 오류 보고 코드 형식이 올바르지 않습니다.'
    );
  end if;

  v_is_trace := left(v_code, 2) = 'MT';
  if v_is_trace then
    select * into v_session
    from private.match_diagnostic_sessions s
    where s.trace_code = v_code;
  else
    select s.* into v_session
    from private.match_diagnostic_errors e
    join private.match_diagnostic_sessions s on s.id = e.session_id
    where e.report_code = v_code
      and e.expires_at > now();
  end if;

  if v_session.id is null then
    return jsonb_build_object(
      'ok', true, 'found', false,
      'message', '해당 코드의 진단 기록을 찾을 수 없습니다. 오류 보고 코드는 발생일로부터 60일 동안 조회할 수 있습니다.'
    );
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

  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at asc, e.id asc), '[]'::jsonb)
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

revoke all on function private.lookup_private_match_diagnostics_core_v1(text) from public, anon, authenticated, service_role;

grant usage on schema private to anon, authenticated;
grant execute on function private.lookup_private_match_diagnostics_core_v1(text) to anon, authenticated;

create or replace function public.lookup_private_match_diagnostics_v1(p_code text)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, private
as $function$
  select private.lookup_private_match_diagnostics_core_v1(p_code);
$function$;

revoke all on function public.lookup_private_match_diagnostics_v1(text) from public;
grant execute on function public.lookup_private_match_diagnostics_v1(text) to anon, authenticated;

-- Backward-compatible overload for already-open clients; the password parameter is ignored.
create or replace function public.lookup_private_match_diagnostics_v1(
  p_code text,
  p_admin_password text
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, private
as $function$
  select private.lookup_private_match_diagnostics_core_v1(p_code);
$function$;

revoke all on function public.lookup_private_match_diagnostics_v1(text, text) from public;
grant execute on function public.lookup_private_match_diagnostics_v1(text, text) to anon, authenticated;

drop function if exists private.lookup_private_match_diagnostics_core_v1(text, text);

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

  delete from private.match_diagnostic_lookup_attempts
  where window_started_at < now() - interval '1 day';

  return jsonb_build_object(
    'deleted_errors', v_errors,
    'deleted_events', v_events,
    'deleted_sessions', v_sessions
  );
end;
$function$;

revoke all on function private.purge_match_diagnostics_v1() from public, anon, authenticated, service_role;
