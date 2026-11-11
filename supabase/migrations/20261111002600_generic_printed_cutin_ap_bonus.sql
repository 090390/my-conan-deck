BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_prepare_miyano_cutin_v1(
  p_room_id uuid,p_user uuid,p_payload jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_match public.room_match_states%rowtype;
  v_game public.room_player_game_states%rowtype;
  v_card jsonb;
  v_cost_card jsonb;
  v_hand jsonb;
  v_new_hand jsonb;
  v_instance text:=nullif(p_payload->>'instance_id','');
  v_cost_instance text:=nullif(p_payload->>'cost_instance_id','');
  v_card_code text;
  v_partner_color text;
  v_hand_count integer;
  v_bonus integer:=0;
  v_ap numeric;
  v_printed_cut_in text;
  v_ap_match text[];
BEGIN
  SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '컷인 사용자의 손패를 찾을 수 없습니다.'; END IF;
  v_hand:=coalesce(v_game.hand,'[]'::jsonb);
  SELECT e.value INTO v_card FROM jsonb_array_elements(v_hand) e(value)
    WHERE e.value->>'instance_id'=v_instance LIMIT 1;
  IF v_card IS NULL THEN RAISE EXCEPTION '손패에서 컷인 카드를 찾을 수 없습니다.'; END IF;

  IF public.private_card_effect_matches_id_v1(v_card,'["1117"]'::jsonb) THEN
    v_card_code:=upper(coalesce(v_card->>'key',v_card->>'card_num',v_card->>'cardNum',v_card->>'cardNumber',
      v_card#>>'{sourceData,card_num}',v_card#>>'{sourceData,cardNumber}',''));
    v_partner_color:=public.private_card_effect_partner_color_v1(p_room_id,p_user);
    v_hand_count:=jsonb_array_length(v_hand);
    IF v_card_code='B10058' THEN v_hand_count:=greatest(0,v_hand_count-1); END IF;
    IF v_partner_color='red' THEN v_bonus:=CASE WHEN v_hand_count<=2 THEN 3000 ELSE 1000 END; END IF;
    SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'instance_id'=v_instance
      THEN e.value||jsonb_build_object('cut_in_bonus',v_bonus) ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb)
      INTO v_new_hand FROM jsonb_array_elements(v_hand) WITH ORDINALITY e(value,ordinality);
    UPDATE public.room_player_game_states SET hand=v_new_hand,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_user;

  ELSIF public.private_card_effect_matches_id_v1(v_card,'["0893"]'::jsonb) THEN
    IF v_match.current_turn_user_id=p_user AND v_cost_instance IS NOT NULL THEN
      SELECT e.value INTO v_cost_card FROM jsonb_array_elements(v_hand) e(value)
        WHERE e.value->>'instance_id'=v_cost_instance AND e.value->>'instance_id'<>v_instance LIMIT 1;
      IF v_cost_card IS NULL OR NOT public.private_card_effect_is_character_v1(v_cost_card) THEN
        RAISE EXCEPTION '미야노 히데미 컷인 비용은 컷인 카드 이외의 손패 캐릭터 1장이어야 합니다.';
      END IF;
      v_ap:=coalesce(nullif(v_cost_card->>'ap','')::numeric,nullif(v_cost_card#>>'{sourceData,ap}','')::numeric,0)
        +coalesce(nullif(v_cost_card->>'ap_bonus','')::numeric,0);
      IF v_ap<1000 THEN RAISE EXCEPTION '미야노 히데미 컷인 비용 캐릭터의 AP가 1000 미만입니다.'; END IF;
      v_bonus:=floor(v_ap/1000)::integer*1000;
      SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality) FILTER(WHERE e.value->>'instance_id'<>v_cost_instance),'[]'::jsonb)
        INTO v_new_hand FROM jsonb_array_elements(v_hand) WITH ORDINALITY e(value,ordinality);
      UPDATE public.room_player_game_states SET hand=v_new_hand,
        remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_cost_card),updated_at=now()
        WHERE room_id=p_room_id AND user_id=p_user;
      UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
        WHERE room_id=p_room_id AND user_id=p_user;
    END IF;
    SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'instance_id'=v_instance
      THEN e.value||jsonb_build_object('cut_in_bonus',v_bonus) ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb)
      INTO v_new_hand FROM jsonb_array_elements(coalesce(
        (SELECT hand FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_user),'[]'::jsonb
      )) WITH ORDINALITY e(value,ordinality);
    UPDATE public.room_player_game_states SET hand=v_new_hand,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_user;

  ELSE
    -- Generic printed-text cut-ins (e.g. D04009 / internal 0140) carry their
    -- AP bonus in sourceData.cut_in rather than a normalized numeric field.
    v_printed_cut_in:=concat_ws(' ',
      v_card->>'cut_in',v_card->>'cutIn',v_card->>'cut_in_text',v_card->>'cutInText',
      v_card->>'cut_in_effect',v_card->>'cutInEffect',
      v_card#>>'{sourceData,cut_in}',v_card#>>'{sourceData,cutIn}',
      v_card#>>'{sourceData,cut_in_text}',v_card#>>'{sourceData,cutInText}',
      v_card#>>'{raw,cut_in}',v_card#>>'{raw,cutIn}'
    );
    v_bonus:=greatest(0,coalesce(nullif(v_card->>'cut_in_bonus','')::integer,0));
    IF v_printed_cut_in ~ '(カットイン|컷인|cut[[:space:]_-]*in)' THEN
      v_ap_match:=regexp_match(v_printed_cut_in,'(ＡＰ|AP)[[:space:]]*[＋+][[:space:]]*([0-9０-９,，]+)');
      IF v_ap_match IS NOT NULL THEN
        v_bonus:=greatest(v_bonus,
          replace(translate(v_ap_match[2],'０１２３４５６７８９，','0123456789,'),',','')::integer
        );
      END IF;
    END IF;
    IF v_bonus>0 THEN
      SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'instance_id'=v_instance
        THEN e.value||jsonb_build_object('cut_in_bonus',v_bonus) ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb)
        INTO v_new_hand FROM jsonb_array_elements(v_hand) WITH ORDINALITY e(value,ordinality);
      UPDATE public.room_player_game_states SET hand=v_new_hand,updated_at=now()
        WHERE room_id=p_room_id AND user_id=p_user;
    END IF;
  END IF;
END
$function$;

COMMIT;
