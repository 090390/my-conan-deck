create or replace function public.force_end_private_ai_battle_v1(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_user uuid := auth.uid();
  v_battle public.private_ai_battles%rowtype;
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select * into v_battle
  from public.private_ai_battles
  where room_id = p_room_id
  for update;

  if not found or v_battle.human_user_id is distinct from v_user then
    raise exception '본인의 AI 대전만 강제 종료할 수 있습니다.';
  end if;

  -- AI battles cannot be resumed. Remove non-cascading history/cache rows first.
  delete from public.private_match_action_logs where room_id = p_room_id;
  delete from public.private_match_turn_zone_snapshots where room_id = p_room_id;
  delete from public.private_match_greetings where room_id = p_room_id;
  delete from public.room_deck_peeks where room_id = p_room_id;
  delete from public.room_hand_reveals where room_id = p_room_id;

  -- Room-owned game state (including players, decks, boards, battle metadata,
  -- pending effect runs and play history) is removed by the room FK cascades.
  delete from public.rooms where id = p_room_id;

  return jsonb_build_object('ok', true, 'room_id', p_room_id);
end;
$function$;

revoke all on function public.force_end_private_ai_battle_v1(uuid) from public;
grant execute on function public.force_end_private_ai_battle_v1(uuid) to authenticated;
