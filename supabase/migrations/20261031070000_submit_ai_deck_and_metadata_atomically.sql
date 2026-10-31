CREATE OR REPLACE FUNCTION public.submit_private_room_deck_with_metadata_v1(
  p_room_id uuid, p_main_deck jsonb, p_partner_key text, p_event_key text,
  p_event_rule_code text, p_partner_color text, p_event_has_non_blue_color boolean
)
 RETURNS TABLE(out_is_ready boolean, out_total_cards integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_rule_code text := coalesce(nullif(btrim(p_event_rule_code), ''), '');
  v_partner_color text := public.private_card_effect_color_v1(jsonb_build_object('color', p_partner_color));
  v_room_status text;
  v_entry jsonb;
  v_key text;
  v_limit_key text;
  v_count_text text;
  v_count integer;
  v_total integer := 0;
  v_entries integer := 0;
  v_exemption_id text;
  v_key_norm text;
  v_limit_norm text;
  v_card_id_norm text;
  v_card_num_norm text;
  v_database_id_norm text;
begin
  if v_rule_code not in ('', 'culprits_1046', 'conan_vs_kid_1261') then
    raise exception '지원하지 않는 사건 카드 규칙입니다.';
  end if;
  if p_event_has_non_blue_color is null then
    raise exception '사건 색상 판정값이 필요합니다.';
  end if;
  if nullif(btrim(coalesce(p_partner_color, '')), '') is null
     or v_partner_color not in ('red','yellow','blue','green','white','black') then
    raise exception '파트너 카드 색상을 확인할 수 없습니다: %', p_partner_color;
  end if;

  if v_user_id is null then
    raise exception '로그인이 필요합니다.';
  end if;

  select r.status
    into v_room_status
    from public.rooms r
   where r.id = p_room_id;

  if not found then
    raise exception '방을 찾을 수 없습니다.';
  end if;
  if v_room_status <> 'waiting' then
    raise exception '대기 중인 방에서만 덱을 제출할 수 있습니다.';
  end if;
  if not exists (
    select 1 from public.room_players rp
     where rp.room_id = p_room_id and rp.user_id = v_user_id
  ) then
    raise exception '이 방의 참가자가 아닙니다.';
  end if;

  if jsonb_typeof(p_main_deck) <> 'array' then
    raise exception '메인 덱 데이터 형식이 올바르지 않습니다.';
  end if;
  if coalesce(btrim(p_partner_key), '') = '' then
    raise exception '파트너 카드를 선택해 주세요.';
  end if;
  if coalesce(btrim(p_event_key), '') = '' then
    raise exception '사건 카드를 선택해 주세요.';
  end if;

  for v_entry in
    select d.value from jsonb_array_elements(p_main_deck) as d(value)
  loop
    if jsonb_typeof(v_entry) <> 'object' then
      raise exception '메인 덱 카드 항목 형식이 올바르지 않습니다.';
    end if;

    v_key := nullif(btrim(v_entry ->> 'key'), '');
    v_limit_key := nullif(btrim(v_entry ->> 'limit_key'), '');
    v_count_text := v_entry ->> 'count';
    v_exemption_id := nullif(btrim(v_entry ->> 'copy_limit_exemption_id'), '');

    if v_key is null or v_limit_key is null then
      raise exception '카드 식별자가 비어 있습니다.';
    end if;
    if jsonb_typeof(v_entry -> 'count') <> 'number'
       or coalesce(v_count_text, '') !~ '^[0-9]+$' then
      raise exception '카드 장수는 정수로 입력해야 합니다.';
    end if;
    v_count := v_count_text::integer;

    if v_exemption_id is not null then
      if v_exemption_id not in ('0627', '1039') then
        raise exception '복수 장수 제한 예외가 허용된 카드 ID가 아닙니다.';
      end if;
      v_key_norm := case when coalesce(v_key,'') ~ '^[0-9]+$' then coalesce(nullif(ltrim(v_key,'0'),''),'0') else upper(v_key) end;
      v_limit_norm := case when coalesce(v_limit_key,'') ~ '^[0-9]+$' then coalesce(nullif(ltrim(v_limit_key,'0'),''),'0') else upper(v_limit_key) end;
      v_card_id_norm := case when coalesce(v_entry ->> 'card_id','') ~ '^[0-9]+$' then coalesce(nullif(ltrim(v_entry ->> 'card_id','0'),''),'0') else upper(coalesce(v_entry ->> 'card_id','')) end;
      v_card_num_norm := case when coalesce(v_entry ->> 'card_num','') ~ '^[0-9]+$' then coalesce(nullif(ltrim(v_entry ->> 'card_num','0'),''),'0') else upper(coalesce(v_entry ->> 'card_num','')) end;
      v_database_id_norm := case when coalesce(v_entry ->> 'database_id','') ~ '^[0-9]+$' then coalesce(nullif(ltrim(v_entry ->> 'database_id','0'),''),'0') else upper(coalesce(v_entry ->> 'database_id','')) end;
      if v_exemption_id = '0627' and '627' not in (v_key_norm,v_limit_norm,v_card_id_norm,v_card_num_norm,v_database_id_norm) then
        raise exception '0627 카드 식별자가 일치하지 않아 복수 장수 예외를 적용할 수 없습니다.';
      elsif v_exemption_id = '1039' and '1039' not in (v_key_norm,v_limit_norm,v_card_id_norm,v_card_num_norm,v_database_id_norm) then
        raise exception '1039 카드 식별자가 일치하지 않아 복수 장수 예외를 적용할 수 없습니다.';
      end if;
      if v_count < 1 or v_count > 40 then
        raise exception '예외 카드 장수는 1~40장 범위여야 합니다.';
      end if;
    else
      if v_count < 1 or v_count > 3 then
        raise exception '일반 카드는 같은 카드 ID를 1~3장까지 넣을 수 있습니다.';
      end if;
    end if;

    v_total := v_total + v_count;
    v_entries := v_entries + 1;
  end loop;

  if v_entries = 0 or v_total <> 40 then
    raise exception '메인 덱은 정확히 40장이어야 합니다. 현재 %장입니다.', v_total;
  end if;

  if exists (
    select 1
      from jsonb_array_elements(p_main_deck) as d(value)
     group by lower(d.value ->> 'key')
    having count(*) > 1
  ) then
    raise exception '같은 카드 항목이 중복으로 제출되었습니다.';
  end if;

  if exists (
    select 1
      from jsonb_array_elements(p_main_deck) as d(value)
     where coalesce(d.value ->> 'copy_limit_exemption_id','') not in ('0627','1039')
     group by lower(d.value ->> 'limit_key')
    having sum((d.value ->> 'count')::integer) > 3
  ) then
    raise exception '같은 내부 카드 ID는 최대 3장까지 넣을 수 있습니다. (0627, 1039 카드는 예외입니다.)';
  end if;

  -- Persist metadata in the same write before setting room_players.is_ready.
  -- The other player can start the match as soon as they become ready.
  insert into public.room_player_decks
    (room_id, user_id, main_deck, partner_key, event_key, event_rule_code,
     partner_color, event_has_non_blue_color, submitted_at)
  values
    (p_room_id, v_user_id, p_main_deck, btrim(p_partner_key), btrim(p_event_key),
     v_rule_code, v_partner_color, p_event_has_non_blue_color, now())
  on conflict (room_id, user_id) do update
    set main_deck = excluded.main_deck,
        partner_key = excluded.partner_key,
        event_key = excluded.event_key,
        event_rule_code = excluded.event_rule_code,
        partner_color = excluded.partner_color,
        event_has_non_blue_color = excluded.event_has_non_blue_color,
        submitted_at = now();

  update public.room_players rp
     set is_ready = true
   where rp.room_id = p_room_id and rp.user_id = v_user_id;

  return query select true, v_total;
end;
$function$;

REVOKE ALL ON FUNCTION public.submit_private_room_deck_with_metadata_v1(uuid,jsonb,text,text,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_private_room_deck_with_metadata_v1(uuid,jsonb,text,text,text,text,boolean) TO authenticated;
