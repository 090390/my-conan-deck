-- Conan TCG: route a field MR to the MR partner area when a normal game action removes it from the field.
-- Client-side manual move_field_card actions intentionally do not call this helper, preserving manual overrides.
CREATE OR REPLACE FUNCTION public.auto_store_departed_mr_partner_v2(
  p_room_id uuid,
  p_owner_user_id uuid,
  p_card jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $auto_store_departed_mr_partner_v2$
DECLARE
  v_user uuid := auth.uid();
  v_board public.room_player_turn_boards%ROWTYPE;
  v_existing jsonb;
  v_card_id text := coalesce(p_card ->> 'instance_id','');
  v_rarity text := upper(coalesce(p_card ->> 'rarity',''));
  v_col record;
  v_zone jsonb;
  v_remove_column text;
  v_clean_card jsonb;
  v_clean_existing jsonb;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
    RAISE EXCEPTION '이 방의 참가자만 MR 이동 처리를 할 수 있습니다.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=p_owner_user_id) THEN
    RAISE EXCEPTION 'MR 소유자의 방 참가 정보를 찾을 수 없습니다.';
  END IF;
  IF v_card_id='' OR v_rarity <> 'MR' THEN RAISE EXCEPTION '현장을 떠난 MR 카드 정보가 올바르지 않습니다.'; END IF;

  SELECT * INTO v_board
    FROM public.room_player_turn_boards
    WHERE room_id=p_room_id AND user_id=p_owner_user_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'MR 소유자의 턴 보드를 찾을 수 없습니다.'; END IF;

  -- A manual/effect action can be racing with a state refresh. Do not move a card that remains on the field.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
    WHERE e.value ->> 'instance_id' = v_card_id
  ) THEN
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;

  v_existing := v_board.partner_mr_card;
  IF v_existing ->> 'instance_id' = v_card_id THEN
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;

  -- Remove the departed MR from the destination zone where the normal action put it.
  -- Inspect JSONB array columns dynamically to tolerate schema naming differences across deployed revisions.
  FOR v_col IN
    SELECT column_name FROM information_schema.columns
    WHERE table_schema='public' AND table_name='room_player_game_states' AND data_type='jsonb'
    ORDER BY ordinal_position
  LOOP
    EXECUTE format('SELECT %I FROM public.room_player_game_states WHERE room_id=$1 AND user_id=$2', v_col.column_name)
      INTO v_zone USING p_room_id,p_owner_user_id;
    IF jsonb_typeof(v_zone)='array' AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_zone) e(value) WHERE e.value ->> 'instance_id'=v_card_id
    ) THEN
      EXECUTE format(
        'UPDATE public.room_player_game_states SET %I=(' ||
        'SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality), ''[]''::jsonb) ' ||
        'FROM jsonb_array_elements(coalesce(%I, ''[]''::jsonb)) WITH ORDINALITY e(value,ordinality) ' ||
        'WHERE e.value ->> ''instance_id'' IS DISTINCT FROM $3), updated_at=now() ' ||
        'WHERE room_id=$1 AND user_id=$2',
        v_col.column_name,v_col.column_name
      ) USING p_room_id,p_owner_user_id,v_card_id;
      IF v_col.column_name ILIKE '%remove%' AND v_col.column_name NOT ILIKE '%count%' THEN
        UPDATE public.room_player_turn_boards SET remove_count=greatest(0,coalesce(remove_count,0)-1),updated_at=now()
          WHERE room_id=p_room_id AND user_id=p_owner_user_id;
      ELSIF v_col.column_name ILIKE '%evidence%' AND v_col.column_name NOT ILIKE '%count%' THEN
        UPDATE public.room_player_turn_boards SET evidence_count=greatest(0,coalesce(evidence_count,0)-1),updated_at=now()
          WHERE room_id=p_room_id AND user_id=p_owner_user_id;
      ELSIF v_col.column_name ILIKE '%file%' AND v_col.column_name NOT ILIKE '%count%' THEN
        UPDATE public.room_player_turn_boards SET file_count=greatest(0,coalesce(file_count,0)-1),updated_at=now()
          WHERE room_id=p_room_id AND user_id=p_owner_user_id;
      END IF;
    END IF;
  END LOOP;

  -- If an MR is already in the partner area, a newly departed MR replaces it and the previous one moves to remove.
  IF v_existing IS NOT NULL AND coalesce(v_existing ->> 'instance_id','') <> '' THEN
    SELECT column_name INTO v_remove_column
      FROM information_schema.columns
      WHERE table_schema='public' AND table_name='room_player_game_states'
        AND data_type='jsonb' AND column_name ILIKE '%remove%' AND column_name NOT ILIKE '%count%'
      ORDER BY CASE WHEN column_name='remove_cards' THEN 0 WHEN column_name ILIKE '%remove%cards%' THEN 1 ELSE 2 END, ordinal_position
      LIMIT 1;
    IF v_remove_column IS NULL THEN RAISE EXCEPTION '리무브 에이리어 카드 목록을 찾을 수 없습니다.'; END IF;
    v_clean_existing := v_existing - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id';
    EXECUTE format('UPDATE public.room_player_game_states SET %I=coalesce(%I,''[]''::jsonb)||jsonb_build_array($3),updated_at=now() WHERE room_id=$1 AND user_id=$2',v_remove_column,v_remove_column)
      USING p_room_id,p_owner_user_id,v_clean_existing;
    UPDATE public.room_player_turn_boards SET remove_count=coalesce(remove_count,0)+1,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  END IF;

  v_clean_card := p_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id';
  UPDATE public.room_player_turn_boards SET partner_mr_card=v_clean_card,updated_at=now()
    WHERE room_id=p_room_id AND user_id=p_owner_user_id;
  UPDATE public.room_match_states SET state_version=state_version+1,
    last_action_label=format('MR %s가 현장을 떠나 MR 파트너 에이리어로 이동했습니다.',coalesce(p_card ->> 'key','카드'))
    WHERE room_id=p_room_id;
  RETURN public.get_private_turn_state_v2(p_room_id);
END;
$auto_store_departed_mr_partner_v2$;

REVOKE ALL ON FUNCTION public.auto_store_departed_mr_partner_v2(uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_store_departed_mr_partner_v2(uuid,uuid,jsonb) TO authenticated;
