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
  if v_card is not null then return public.private_card_effect_color_v1(v_card); end if;

  -- PR261 is the yellow partner used by the Matsuda Keishicho public deck.
  -- Keep old clients (which do not yet send partner_color) compatible.
  if upper(coalesce(v_key,''))='PR261' then return 'yellow'; end if;

  return null;
end
$function$;
