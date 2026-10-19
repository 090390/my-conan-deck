-- Conan TCG: manual movement buttons in the MR partner area operate on the MR zone itself.
-- This keeps the ordinary card-move controls while allowing an MR to be deliberately removed only from this area.
CREATE OR REPLACE FUNCTION public.move_private_mr_partner_to_zone_v1(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_instance_id text,
  p_destination text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $move_private_mr_partner_to_zone_v1$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_game public.room_player_game_states%ROWTYPE;
  v_card jsonb;
  v_clean_card jsonb;
  v_remove_column text;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
    RAISE EXCEPTION '이 방의 참가자만 MR 파트너 카드를 이동할 수 있습니다.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id) THEN
    RAISE EXCEPTION 'MR 소유자의 방 참가 정보를 찾을 수 없습니다.';
  END IF;
  IF p_destination NOT IN ('hand','deck','remove') THEN
    RAISE EXCEPTION '지원하지 않는 MR 이동 위치입니다.';
  END IF;
  SELECT * INTO v_board FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 파트너 보드를 찾을 수 없습니다.'; END IF;
  v_card := v_board.partner_mr_card;
  IF v_card IS NULL OR v_card ->> 'instance_id' IS DISTINCT FROM p_instance_id THEN
    RAISE EXCEPTION 'MR 파트너 영역에서 선택한 카드를 찾을 수 없습니다.';
  END IF;
  SELECT * INTO v_game FROM public.room_player_game_states
    WHERE room_id=p_room_id AND user_id=p_owner_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 카드 영역을 찾을 수 없습니다.'; END IF;
  v_clean_card := v_card - 'face_up' - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id';

  IF p_destination='hand' THEN
    UPDATE public.room_player_game_states SET hand=coalesce(hand,'[]'::jsonb)||jsonb_build_array(v_clean_card),updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  ELSIF p_destination='deck' THEN
    UPDATE public.room_player_game_states SET deck_order=coalesce(deck_order,'[]'::jsonb)||jsonb_build_array(v_clean_card),updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  ELSE
    SELECT column_name INTO v_remove_column
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='room_player_game_states'
        AND data_type='jsonb' AND column_name ILIKE '%remove%' AND column_name NOT ILIKE '%count%'
      ORDER BY CASE WHEN column_name='remove_cards' THEN 0 WHEN column_name ILIKE '%remove%cards%' THEN 1 ELSE 2 END, ordinal_position
      LIMIT 1;
    IF v_remove_column IS NULL THEN RAISE EXCEPTION '리무브 영역 카드 목록을 찾을 수 없습니다.'; END IF;
    EXECUTE format('UPDATE public.room_player_game_states SET %I=coalesce(%I,''[]''::jsonb)||jsonb_build_array($3),updated_at=now() WHERE room_id=$1 AND user_id=$2',v_remove_column,v_remove_column)
      USING p_room_id,p_owner_user_id,v_clean_card;
    UPDATE public.room_player_turn_boards SET remove_count=coalesce(remove_count,0)+1,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  END IF;

  UPDATE public.room_player_turn_boards SET partner_mr_card=NULL,updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_match_states SET state_version=state_version+1,
    last_action_label=CASE p_destination
      WHEN 'hand' THEN 'MR 파트너 카드를 소유자의 손패로 수동 이동했습니다.'
      WHEN 'deck' THEN 'MR 파트너 카드를 소유자의 덱 맨 아래로 수동 이동했습니다.'
      ELSE 'MR 파트너 카드를 리무브 에이리어로 수동 이동했습니다.'
    END
    WHERE room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$move_private_mr_partner_to_zone_v1$;

REVOKE ALL ON FUNCTION public.move_private_mr_partner_to_zone_v1(uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_private_mr_partner_to_zone_v1(uuid,uuid,text,text) TO authenticated;
