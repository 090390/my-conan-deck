create or replace function public.set_private_room_partner_color_v1(
  p_room_id uuid,
  p_partner_color text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_user uuid := auth.uid();
  v_color text := public.private_card_effect_color_v1(jsonb_build_object('color',p_partner_color));
begin
  if v_user is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if not exists (
    select 1 from public.room_players
    where room_id=p_room_id and user_id=v_user
  ) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;
  if v_color not in ('red','yellow','blue','green','white','black') then
    raise exception '파트너 카드 색상을 확인할 수 없습니다: %', p_partner_color;
  end if;
  update public.room_player_decks
    set partner_color=v_color, submitted_at=coalesce(submitted_at,now())
    where room_id=p_room_id and user_id=v_user;
  if not found then
    raise exception '파트너 색상을 저장할 덱 정보를 찾을 수 없습니다.';
  end if;
  return jsonb_build_object('ok',true,'partner_color',v_color);
end
$function$;

update public.room_player_decks
set partner_color='yellow'
where upper(partner_key) in ('PR261','PR259')
  and coalesce(partner_color,'')='';
