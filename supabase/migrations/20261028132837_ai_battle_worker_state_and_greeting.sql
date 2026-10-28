
CREATE OR REPLACE FUNCTION public.is_private_ai_battle_v1(p_room_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  return exists (
    select 1 from public.private_ai_battles b
    where b.room_id = p_room_id and b.human_user_id = auth.uid()
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_private_ai_turn_state_v1(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  select * into v_battle from public.private_ai_battles where room_id=p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;
  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);
  v_result := public.get_private_turn_state_v2(p_room_id);
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

CREATE OR REPLACE FUNCTION public.prepare_private_ai_greeting_v1(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_greeting jsonb;
begin
  select * into v_battle from public.private_ai_battles where room_id=p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  v_greeting := public.get_private_match_greeting_v1(p_room_id);
  if coalesce(v_greeting ->> 'my_seat', '') = '2'
     and nullif(v_greeting ->> 'seat2_message', '') is null
     and coalesce(v_greeting ->> 'is_complete', 'false') <> 'true' then
    v_greeting := public.submit_private_match_greeting_v1(
      p_room_id, '안녕하세요. AI 탐정입니다. 잘 부탁드리겠습니다.'
    );
  end if;
  v_greeting := public.get_private_match_greeting_v1(p_room_id);
  if coalesce(v_greeting ->> 'is_ready_for_review', 'false') = 'true'
     and coalesce(v_greeting ->> 'my_confirmed', 'false') <> 'true'
     and coalesce(v_greeting ->> 'is_complete', 'false') <> 'true' then
    v_greeting := public.confirm_private_match_greeting_v1(p_room_id);
  end if;

  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  return v_greeting;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  raise;
end;
$function$
;

revoke all on function public.is_private_ai_battle_v1(uuid) from public, anon;
revoke all on function public.get_private_ai_turn_state_v1(uuid) from public, anon, authenticated;
revoke all on function public.prepare_private_ai_greeting_v1(uuid) from public, anon, authenticated;
grant execute on function public.is_private_ai_battle_v1(uuid) to authenticated;
grant execute on function public.get_private_ai_turn_state_v1(uuid) to service_role;
grant execute on function public.prepare_private_ai_greeting_v1(uuid) to service_role;
