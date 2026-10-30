create or replace function public.reject_private_deck_changes_after_start()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_room_id uuid;
  v_service_role boolean := coalesce(current_setting('request.jwt.claim.role',true),'')='service_role';
begin
  if tg_op='DELETE' then
    v_room_id:=old.room_id;
  else
    v_room_id:=new.room_id;
  end if;

  if exists(select 1 from public.room_match_states s where s.room_id=v_room_id) then
    if tg_op='UPDATE'
       and v_service_role
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
