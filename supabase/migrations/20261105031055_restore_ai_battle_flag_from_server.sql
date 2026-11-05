create or replace function public.is_private_ai_battle_v1(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if not exists (
    select 1
    from public.room_players rp
    where rp.room_id = p_room_id
      and rp.user_id = v_user_id
  ) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  return exists (
    select 1
    from public.private_ai_battles b
    where b.room_id = p_room_id
      and b.human_user_id = v_user_id
  );
end;
$function$;

revoke all on function public.is_private_ai_battle_v1(uuid) from public, anon;
grant execute on function public.is_private_ai_battle_v1(uuid) to authenticated;