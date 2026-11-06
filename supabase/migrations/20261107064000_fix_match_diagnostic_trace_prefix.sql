-- Fix MT trace code detection: the prefix itself is two characters ("MT"), not three ("MT-").
create or replace function private.lookup_private_match_diagnostics_core_v1(
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

  v_is_trace := left(v_code, 2) = 'MT';
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
