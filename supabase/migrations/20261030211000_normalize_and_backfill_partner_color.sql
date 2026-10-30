-- Allow the partner-colour metadata field to be filled without changing the submitted deck.
create or replace function public.reject_private_deck_changes_after_start()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_room_id uuid;
begin
  if tg_op='DELETE' then
    v_room_id:=old.room_id;
  else
    v_room_id:=new.room_id;
  end if;

  if exists(select 1 from public.room_match_states s where s.room_id=v_room_id) then
    if tg_op='UPDATE'
       and new.room_id is not distinct from old.room_id
       and new.user_id is not distinct from old.user_id
       and new.main_deck is not distinct from old.main_deck
       and new.partner_key is not distinct from old.partner_key
       and new.event_key is not distinct from old.event_key
       and new.event_rule_code is not distinct from old.event_rule_code
       and new.event_has_non_blue_color is not distinct from old.event_has_non_blue_color
       and new.submitted_at is not distinct from old.submitted_at then
      return new;
    end if;
    raise exception '게임이 시작되어 덱을 변경할 수 없습니다.';
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end
$function$;

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
  if v_user is null then raise exception '로그인이 필요합니다.'; end if;
  if not exists (
    select 1 from public.room_players
    where room_id=p_room_id and user_id=v_user
  ) then raise exception '이 방의 참가자가 아닙니다.'; end if;
  if v_color not in ('red','yellow','blue','green','white','black') then
    raise exception '파트너 카드 색상을 확인할 수 없습니다: %',p_partner_color;
  end if;
  update public.room_player_decks set partner_color=v_color
  where room_id=p_room_id and user_id=v_user;
  if not found then raise exception '파트너 색상을 저장할 덱 정보를 찾을 수 없습니다.'; end if;
  return jsonb_build_object('ok',true,'partner_color',v_color);
end
$function$;

revoke all on function public.set_private_room_partner_color_v1(uuid,text) from public;
grant execute on function public.set_private_room_partner_color_v1(uuid,text) to authenticated;

update public.room_player_decks
set partner_color='yellow'
where upper(partner_key) in ('PR261','PR259')
  and coalesce(partner_color,'')='';
