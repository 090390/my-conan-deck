-- Fix field-MR departure routing, guarantee a fresh mutual cut-in window after a guard,
-- and allow partner assist again after the required Next Hint character is played.
DO $migration$
DECLARE
  v_action_def text;
  v_contact_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_action_def;

  -- Partner assist is blocked only while a Next Hint's required character is still pending,
  -- not for the remainder of the turn.
  v_old := $old$if p_action = 'partner_assist' and v_board.next_hint_used then raise exception '넥스트 힌트를 사용한 턴에는 파트너 어시스트를 할 수 없습니다.'; end if;$old$;
  v_new := $new$if p_action = 'partner_assist' and coalesce(v_board.next_hint_pending,false) then raise exception '넥스트 힌트로 가져온 캐릭터를 먼저 등장시켜야 파트너 어시스트를 사용할 수 있습니다.'; end if;$new$;
  IF position(v_old IN v_action_def) = 0 THEN
    RAISE EXCEPTION 'partner_assist guard anchor not found; no changes applied';
  END IF;
  v_action_def := replace(v_action_def, v_old, v_new);

  -- When a guard is selected, clear any cut-in flags from the pre-guard stage and start
  -- a fresh, mutual cut-in exchange using the chosen active guard character.
  v_old := $old$v_pending := jsonb_set(v_match.pending_action,'{guarded_original_target_instance_id}',to_jsonb(v_match.pending_action ->> 'target_instance_id'));
    v_pending := jsonb_set(v_pending,'{target_instance_id}',to_jsonb(v_id));
    v_pending := jsonb_set(v_pending,'{target_ap}',to_jsonb(coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0)));
    v_pending := jsonb_set(v_pending,'{type}',to_jsonb('character_contact'::text));$old$;
  v_new := $new$v_pending := jsonb_set(v_match.pending_action,'{guarded_original_target_instance_id}',to_jsonb(v_match.pending_action ->> 'target_instance_id'));
    v_pending := jsonb_set(v_pending,'{target_instance_id}',to_jsonb(v_id));
    v_pending := jsonb_set(v_pending,'{target_ap}',to_jsonb(coalesce(nullif(v_card ->> 'ap','')::numeric,0)+coalesce(nullif(v_card ->> 'ap_bonus','')::numeric,0)));
    v_pending := jsonb_set(v_pending,'{type}',to_jsonb('character_contact'::text));
    v_pending := v_pending - 'attacker_cut_in_used' - 'target_cut_in_used' - 'attacker_cut_in_passed' - 'target_cut_in_passed' - 'cut_in_used';
    v_pending := jsonb_set(v_pending,'{attacker_bonus}',to_jsonb(0));
    v_pending := jsonb_set(v_pending,'{target_bonus}',to_jsonb(0));$new$;
  IF position(v_old IN v_action_def) = 0 THEN
    RAISE EXCEPTION 'guard cut-in reset anchor not found; no changes applied';
  END IF;
  v_action_def := replace(v_action_def, v_old, v_new);

  SELECT replace(pg_get_functiondef('public.resolve_private_character_contact(uuid,jsonb)'::regprocedure), chr(13), '')
    INTO v_contact_def;

  -- If the field MR loses the contact while an MR is already in the MR partner slot,
  -- move the old partner MR to Remove before placing the newly departed field MR there.
  v_old := $old$v_loser_is_mr := upper(coalesce(v_target_card ->> 'rarity', '')) = 'MR';
    if v_loser_is_mr then$old$;
  v_new := $new$v_loser_is_mr := upper(coalesce(v_target_card ->> 'rarity', '')) = 'MR';
    if v_loser_is_mr
       and coalesce(v_target_board.partner_mr_card ->> 'instance_id','') <> ''
       and v_target_board.partner_mr_card ->> 'instance_id' is distinct from v_target_card ->> 'instance_id' then
      update public.room_player_game_states gs
        set remove_cards = coalesce(gs.remove_cards, '[]'::jsonb) ||
          jsonb_build_array(v_target_board.partner_mr_card - 'rested' - 'status' - 'ap_bonus' - 'summoned_this_turn' - 'resolving' - 'host_instance_id' - 'set_owner_user_id'),
            updated_at = now()
        where gs.room_id = p_room_id and gs.user_id = v_target_user;
      update public.room_player_turn_boards b
        set remove_count = coalesce(b.remove_count,0) + 1, updated_at = now()
        where b.room_id = p_room_id and b.user_id = v_target_user;
    end if;
    if v_loser_is_mr then$new$;
  IF position(v_old IN v_contact_def) = 0 THEN
    RAISE EXCEPTION 'MR contact anchor not found; no changes applied';
  END IF;
  v_contact_def := replace(v_contact_def, v_old, v_new);

  EXECUTE v_action_def;
  EXECUTE v_contact_def;
END;
$migration$;
