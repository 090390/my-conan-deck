alter table public.room_player_decks
  add column if not exists partner_color text;

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
  v_color text := lower(trim(coalesce(p_partner_color,'')));
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
  if v_color not in ('red','yellow','blue','green','white','black','적','황','청','녹','백','흑','赤','黄','青','緑','白','黒') then
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

revoke all on function public.set_private_room_partner_color_v1(uuid,text) from public;
grant execute on function public.set_private_room_partner_color_v1(uuid,text) to authenticated;

create or replace function public.private_card_effect_partner_color_v1(p_room_id uuid, p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_key text;
  v_card jsonb;
  v_board public.room_player_turn_boards%rowtype;
  v_deck jsonb;
  v_partner_color text;
begin
  select * into v_board
  from public.room_player_turn_boards
  where room_id=p_room_id and user_id=p_user_id;

  if not found then return null; end if;
  v_key:=v_board.partner_key;

  select partner_color,coalesce(main_deck,'[]'::jsonb)
    into v_partner_color,v_deck
  from public.room_player_decks
  where room_id=p_room_id and user_id=p_user_id;

  if nullif(trim(coalesce(v_partner_color,'')),'') is not null then
    return public.private_card_effect_color_v1(jsonb_build_object('color',v_partner_color));
  end if;

  if v_board.partner_mr_card is not null and (v_board.partner_mr_card->>'key')=v_key then
    return public.private_card_effect_color_v1(v_board.partner_mr_card);
  end if;

  select e.value into v_card
  from jsonb_array_elements(coalesce(v_board.partner_non_mr_cards,'[]'::jsonb)) e(value)
  where e.value->>'key'=v_key or e.value->>'instance_id'=v_key
  limit 1;
  if v_card is not null then return public.private_card_effect_color_v1(v_card); end if;

  select e.value into v_card
  from jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
  where e.value->>'key'=v_key
  limit 1;
  if v_card is not null then return public.private_card_effect_color_v1(v_card); end if;

  select e.value into v_card
  from jsonb_array_elements(coalesce(v_deck,'[]'::jsonb)) e(value)
  where e.value->>'key'=v_key
  limit 1;
  return public.private_card_effect_color_v1(v_card);
end
$function$;
