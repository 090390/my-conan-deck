-- Keep stunned characters stunned while the opponent has card ID 0301 (怪盗キッド) in the field.
-- Add a manual partner slip action for card-effect resolution without consuming a base action.

DO $patch$
DECLARE
  v_definition text;
  v_old_decl text := $old_decl$  v_culprit_key text;
begin$old_decl$;
  v_new_decl text := $new_decl$  v_culprit_key text;
  v_kid_stun_lock boolean := false;
begin$new_decl$;
  v_old_stunned_branch text := $old_branch$then e.value || jsonb_build_object('status','rested','rested',true,'summoned_this_turn',false,'ap_bonus',0)$old_branch$;
  v_new_stunned_branch text := $new_branch$then case when v_kid_stun_lock
           then e.value || jsonb_build_object('status','stunned','rested',false,'summoned_this_turn',false,'ap_bonus',0)
           else e.value || jsonb_build_object('status','rested','rested',true,'summoned_this_turn',false,'ap_bonus',0)
         end$new_branch$;
  v_old_label text := $old_label$턴 %s 시작: 슬립 카드는 액티브, 스턴 카드는 슬립으로 전환. 손패 1장 드로우 후 파일 %s장을 배치합니다.$old_label$;
  v_new_label text := $new_label$턴 %s 시작: 슬립 카드는 액티브, 스턴은 상대 현장에 ID:0301 괴도 키드가 있으면 스턴 유지, 없으면 슬립으로 전환됩니다. 손패 1장 드로우 후 파일 %s장을 배치합니다.$new_label$;
  v_old_delegate text := $old_delegate$v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));$old_delegate$;
  v_new_delegate text := $new_delegate$if p_action = 'rest_partner_manual' then
    if v_match.current_turn_user_id is distinct from v_user
       or coalesce(v_match.turn_step, '') <> 'main'
       or v_match.pending_action is not null then
      raise exception '파트너 슬립은 자신의 메인 단계에서만 처리할 수 있습니다.';
    end if;
    if nullif(trim(coalesce(v_board.partner_key, '')), '') is null then
      raise exception '슬립시킬 파트너 카드가 없습니다.';
    end if;
    if coalesce(v_board.partner_rested, false) or coalesce(v_board.partner_assist_used, false) then
      raise exception '파트너가 이미 슬립 상태이거나 이번 턴에 사용되었습니다.';
    end if;
    update public.room_player_turn_boards b
      set partner_rested = true, updated_at = now()
      where b.room_id = p_room_id and b.user_id = v_user;
    update public.room_match_states m
      set state_version = state_version + 1,
          last_action_label = '카드 효과 처리: 파트너를 슬립 상태로 만들었습니다.'
      where m.room_id = p_room_id;
    return public.get_private_turn_state_v2(p_room_id);
  end if;

  v_old_result := public.perform_private_turn_action(p_room_id, p_action, coalesce(p_payload, '{}'::jsonb));$new_delegate$;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  IF position('v_kid_stun_lock boolean := false;' IN v_definition) = 0 THEN
    IF position(v_old_decl IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not find the target declaration block in perform_private_turn_action_v2.';
    END IF;
    v_definition := replace(v_definition, v_old_decl, v_new_decl);
  END IF;

  IF position('then case when v_kid_stun_lock' IN v_definition) = 0 THEN
    IF position(v_old_stunned_branch IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not find the stunned-character recovery expression in perform_private_turn_action_v2.';
    END IF;
    v_definition := replace(v_definition, v_old_stunned_branch, v_new_stunned_branch);
  END IF;

  IF position('상대 현장에 ID:0301 괴도 키드가 있으면 스턴 유지' IN v_definition) = 0 THEN
    IF position(v_old_label IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not find the turn-start status label in perform_private_turn_action_v2.';
    END IF;
    v_definition := replace(v_definition, v_old_label, v_new_label);
  END IF;

  IF position('if p_action = ''rest_partner_manual'' then' IN v_definition) = 0 THEN
    IF position(v_old_delegate IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not find the delegate call in perform_private_turn_action_v2.';
    END IF;
    v_definition := replace(v_definition, v_old_delegate, v_new_delegate);
  END IF;

  EXECUTE v_definition;
END
$patch$;
