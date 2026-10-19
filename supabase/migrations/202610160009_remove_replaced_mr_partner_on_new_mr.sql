-- Conan TCG: a newly played field MR replaces the MR already in the MR partner area.
-- This happens when the new MR enters the field, not later when it leaves the field.
-- Existing manual move controls remain available and are not routed through this RPC.
CREATE OR REPLACE FUNCTION public.remove_replaced_mr_partner_on_new_mr_v2(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_new_field_mr_instance_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $remove_replaced_mr_partner_on_new_mr_v2$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_game public.room_player_game_states%ROWTYPE;
  v_current_mr jsonb;
  v_new_mr jsonb;
  v_remove_column text;
  v_new_rarity text;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
    RAISE EXCEPTION '이 방의 참가자만 MR 영역을 갱신할 수 있습니다.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id) THEN
    RAISE EXCEPTION 'MR 소유자의 방 참가 정보를 찾을 수 없습니다.';
  END IF;

  SELECT * INTO v_board FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 턴 보드를 찾을 수 없습니다.'; END IF;

  SELECT e.value INTO v_new_mr
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE e.value ->> 'instance_id'=p_new_field_mr_instance_id;
  IF v_new_mr IS NULL THEN RETURN public.get_private_turn_state_v2(p_room_id); END IF;
  SELECT upper(coalesce(v_new_mr ->> 'rarity','')) INTO v_new_rarity;
  IF v_new_rarity <> 'MR' THEN RETURN public.get_private_turn_state_v2(p_room_id); END IF;

  v_current_mr := v_board.partner_mr_card;
  IF v_current_mr IS NULL OR coalesce(v_current_mr ->> 'instance_id','')='' THEN
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;
  IF v_current_mr ->> 'instance_id'=p_new_field_mr_instance_id THEN
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;

  SELECT column_name INTO v_remove_column
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='room_player_game_states'
      AND data_type='jsonb' AND column_name ILIKE '%remove%' AND column_name NOT ILIKE '%count%'
    ORDER BY CASE WHEN column_name='remove_cards' THEN 0 WHEN column_name ILIKE '%remove%cards%' THEN 1 ELSE 2 END, ordinal_position
    LIMIT 1;
  IF v_remove_column IS NULL THEN RAISE EXCEPTION '리무브 에이리어 카드 목록을 찾을 수 없습니다.'; END IF;

  UPDATE public.room_player_game_states
    SET updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  EXECUTE format(
    'UPDATE public.room_player_game_states SET %I=coalesce(%I,''[]''::jsonb)||jsonb_build_array($3),updated_at=now() WHERE room_id=$1 AND user_id=$2',
    v_remove_column,v_remove_column
  ) USING p_room_id,p_owner_user_id,
    v_current_mr - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id';
  UPDATE public.room_player_turn_boards
    SET partner_mr_card=NULL,remove_count=coalesce(remove_count,0)+1,updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_match_states
    SET state_version=state_version+1,
        last_action_label=format('새 MR %s가 현장에 등장하여 기존 MR 파트너를 리무브로 이동했습니다.',coalesce(v_new_mr ->> 'key','카드'))
    WHERE room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$remove_replaced_mr_partner_on_new_mr_v2$;

REVOKE ALL ON FUNCTION public.remove_replaced_mr_partner_on_new_mr_v2(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_replaced_mr_partner_on_new_mr_v2(uuid,uuid,text) TO authenticated;
