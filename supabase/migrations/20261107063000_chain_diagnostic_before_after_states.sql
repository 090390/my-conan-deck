
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

    select e.after_state into v_before
    from private.match_diagnostic_events e
    where e.session_id = v_session_id
    order by e.created_at desc, e.id desc
    limit 1;

    if v_before is null then
      v_before := private.match_diagnostic_safe_state_v1(new.room_id, to_jsonb(old));
    end if;
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
    coalesce(v_before, '{}'::jsonb), v_after,
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
