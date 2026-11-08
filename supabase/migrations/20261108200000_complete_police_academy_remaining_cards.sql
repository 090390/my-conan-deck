-- Complete the remaining custom effects in the Police Academy deck.
DO $catalog$
DECLARE
  v_new_defs jsonb := $defs$[{"effectId":"card-0147-on-enter-discard-hand-remove-ap8000","cardIds":["0147"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"},{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"offer_reaction","actor":"controller","reactionId":"card-0147-discard-hand-remove-ap8000","choices":["yes","no"],"saveAs":"remove_choice","prompt":"손패 1장을 리무브하고 AP 8000 이하 캐릭터 1장까지 리무브할까요?"},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"vars.remove_choice","operator":"equals","value":"yes"},"prompt":"비용으로 리무브할 손패 1장을 선택하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.remove_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"both_fields","min":0,"max":1,"optional":true,"saveAs":"target","when":{"allOf":[{"fact":"vars.remove_choice","operator":"equals","value":"yes"},{"fact":"vars.hand_cost.count","operator":"greater_than","value":0}]},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":8000}]},"prompt":"리무브할 AP 8000 이하 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"【파트너 황】【등장 시】 - 패 1장을 리무브할 수 있다. 그렇게 할 경우, AP 8000 이하의 캐릭터 1장까지 선택하여 리무브한다.","rationale":"파트너 황 조건을 만족하는 등장 시 선택형 손패 비용을 지불한 경우에만 양쪽 현장에서 AP 8000 이하 캐릭터를 최대 1장 리무브한다."}},{"effectId":"card-1162-partner-yellow-charge-character","cardIds":["1162"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"}],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge_character","duration":"while_condition_true","modifierId":"police-academy-1162-partner-yellow-charge-character","displayNameKo":"돌격[캐릭터]"}],"reviewNotes":{"sourceText":"【パートナー黄】突撃[キャラ]","rationale":"파트너 색상이 황일 때 이 캐릭터가 상시 돌격[캐릭터]을 갖도록 연속 효과로 처리한다."}},{"effectId":"card-1162-opponent-turn-field-remove-peek-top","cardIds":["1162"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"character.removed_from_field","timing":"after"},"conditions":[{"fact":"turn.is_opponent_turn","operator":"equals","value":true}],"steps":[{"op":"peek_top_cards","count":1,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"saveAs":"to_remove","displayVariable":"seen","prompt":"확인한 덱 맨 위 카드를 리무브 에이리어로 옮길까요? 선택하지 않으면 원래 위치로 되돌아갑니다."},{"op":"move_cards","from":"to_remove","to":"remove_area","when":{"fact":"vars.to_remove.count","operator":"greater_than","value":0}},{"op":"return_unselected_to_deck_top","from":"seen","selectedVariable":"to_remove"}],"reviewNotes":{"sourceText":"【相手ターン中】【場からリムーブされた時】デッキの上のカードを1枚確認し、それをリムーブエリアに置いてもよい。置かなかった場合、元の位置に戻す。","rationale":"상대 턴 중 현장에서 리무브될 때 덱 맨 위 한 장을 비공개로 확인한다. 선택하면 리무브하고, 선택하지 않으면 확인한 카드를 덱 맨 위에 원래 순서대로 복귀시키는 전용 연산을 사용한다."}},{"effectId":"card-1162-hirameki-solution-stun-action-character","cardIds":["1162"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"evidence.card_removed","timing":"after"},"conditions":[{"fact":"player.case_phase","operator":"equals","value":"solution"}],"steps":[{"op":"stun_action_character"}],"reviewNotes":{"sourceText":"【ひらめき】【解決編】行動中のキャラを1枚まで選び、スタンさせる。","rationale":"해결편 중 이 카드가 증거에서 리무브되면, 해당 증거 제거를 유발한 진행 중 액션의 캐릭터를 스턴한다. 증거 제거 이벤트 문맥에 액션 캐릭터 인스턴스를 전달해 대상을 특정한다."}},{"effectId":"card-1164-case-solution-discard-hand","cardIds":["1164"],"cardNameJa":"警察学校の風呂掃除","cardNameKo":"경찰학교의 목욕탕 청소","trigger":{"event":"case.solution_entered","timing":"after"},"conditions":[{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}],"steps":[{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","prompt":"사건이 해결편이 되었으므로 손패 1장을 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area"}],"reviewNotes":{"sourceText":"이 사건이 해결편이 되었을 때, 나는 패 1장을 리무브한다.","rationale":"PR320 사건이 사건편에서 해결편으로 전환되는 시점에 손패가 있을 경우 1장을 필수로 선택해 리무브한다."}},{"effectId":"card-1164-police-academy-case-effect","cardIds":["1164"],"cardNameJa":"警察学校の風呂掃除","cardNameKo":"경찰학교의 목욕탕 청소","trigger":{"event":"case.activated_ability","timing":"after"},"activationTiming":"turn","activationLabelKo":"경찰학교의 목욕탕 청소 효과","oncePerTurn":true,"conditions":[{"fact":"player.case_phase","operator":"equals","value":"solution"},{"fact":"player.field.has_card_name","operator":"equals","value":"降谷零"},{"fact":"player.evidence.facedown_count","operator":"greater_than_or_equal","value":2}],"steps":[{"op":"select_cards","from":"evidence_area","min":2,"max":2,"optional":false,"saveAs":"evidence_to_flip","filter":{"field":"face_up","operator":"equals","value":false},"prompt":"앞면으로 뒤집을 뒷면 증거 2장을 선택하세요."},{"op":"flip_evidence","from":"vars.evidence_to_flip","count":2},{"op":"peek_top_cards","count":2,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"saveAs":"selected","displayVariable":"seen","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"anyOf":[{"field":"card_name","operator":"name_matches","value":"降谷零"},{"field":"card_name","operator":"name_matches","value":"諸伏景光"},{"field":"card_name","operator":"name_matches","value":"伊達航"},{"field":"card_name","operator":"name_matches","value":"萩原研二"},{"field":"card_name","operator":"name_matches","value":"松田陣平"}]}]},"prompt":"공개하여 패에 추가할 경찰학교 동기 캐릭터를 최대 1장 선택하세요."},{"op":"reveal_cards","from":"selected","to":["opponent"],"awaitAcknowledgement":true,"when":{"fact":"vars.selected.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"selected","to":"hand","when":{"fact":"vars.selected.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","from":"seen","to":"remove_area","selectedVariable":"selected","order":"preserve"}],"reviewNotes":{"sourceText":"【解決編】【宣言】【ターン1】裏向きの証拠2つを表向きにする。デッキの上から2枚を確認し、その中から「降谷零」「諸伏景光」「伊達航」「萩原研二」「松田陣平」のいずれか1枚まで公開して手札に加え、残りをリムーブエリアに置く。自分の現場に「降谷零」がいる場合に宣言できる。","rationale":"해결편에서 턴 1회, 뒷면 증거 2장을 선택해 앞면으로 바꾼 뒤 덱 위 2장을 확인한다. 경찰학교 동기 캐릭터를 최대 1장 공개하여 손패에 넣고 나머지는 리무브한다. 후루야 레이의 현장 존재 조건을 활성화 가능 조건으로 검사."}}]$defs$::jsonb;
BEGIN
  UPDATE public.private_card_effect_catalog_v1 c
  SET definitions=coalesce(c.definitions,'[]'::jsonb)||coalesce((
    SELECT jsonb_agg(n.value)
    FROM jsonb_array_elements(v_new_defs) n(value)
    WHERE NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) e(value)
      WHERE e.value->>'effectId'=n.value->>'effectId'
    )
  ),'[]'::jsonb),
  updated_at=now()
  WHERE c.catalog_id='main';
  IF NOT FOUND THEN RAISE EXCEPTION 'Main card effect catalog was not found.'; END IF;
END
$catalog$;

DO $functions$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure) INTO v_definition;
  v_old := $old$    ELSIF v_op='disable_original_abilities' THEN$old$;
  v_new := $new$    ELSIF v_op='stun_action_character' THEN
      v_target_owner:=nullif(v_effect_context->>'action_character_user_id','')::uuid;
      v_target_id:=coalesce(nullif(v_effect_context->>'action_character_instance_id',''),
        nullif(v_effect_context->>'attacker_instance_id',''));
      IF v_target_owner IS NOT NULL AND v_target_id IS NOT NULL THEN
        SELECT e.value INTO v_card
        FROM public.room_player_turn_boards b
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
        WHERE b.room_id=p_room_id AND b.user_id=v_target_owner
          AND e.value->>'instance_id'=v_target_id LIMIT 1;
        IF v_card IS NOT NULL AND public.private_card_effect_is_character_v1(v_card)
          AND lower(coalesce(v_card->>'status','')) NOT IN ('stunned','stun','스턴') THEN
          PERFORM public.private_card_effect_patch_card_v1(
            p_room_id,v_target_owner,v_target_id,jsonb_build_object('rested',false,'status','stunned')
          );
        END IF;
      END IF;

    ELSIF v_op='return_unselected_to_deck_top' THEN
      v_from:=coalesce(v_step->>'from','');
      v_path:=string_to_array(replace(v_from,'vars.',''),'.');
      v_data:=v_vars #> v_path;
      v_selected_ids:='{}'::text[];
      v_remaining:='[]'::jsonb;
      IF nullif(v_step->>'selectedVariable','') IS NOT NULL THEN
        v_path:=string_to_array(replace(v_step->>'selectedVariable','vars.',''),'.');
        v_current:=v_vars #> v_path;
        FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_current,'[]'::jsonb)) LOOP
          v_card:=coalesce(v_item->'card',v_item);
          v_selected_ids:=array_append(v_selected_ids,coalesce(v_card->>'instance_id',v_item->>'instance_id',''));
        END LOOP;
      END IF;
      FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
        v_card:=coalesce(v_item->'card',v_item);
        IF NOT (coalesce(v_card->>'instance_id',v_item->>'instance_id','')=ANY(v_selected_ids)) THEN
          v_remaining:=v_remaining||jsonb_build_array(v_item);
        END IF;
      END LOOP;
      IF jsonb_array_length(coalesce(v_remaining,'[]'::jsonb))>0 THEN
        v_target_owner:=coalesce(nullif(v_remaining->0->>'owner_user_id','')::uuid,v_owner);
        SELECT coalesce(jsonb_agg(coalesce(e.value->'card',e.value) ORDER BY e.ordinality),'[]'::jsonb)
          INTO v_ordered
        FROM jsonb_array_elements(v_remaining) WITH ORDINALITY e(value,ordinality);
        UPDATE public.room_player_game_states
          SET deck_order=coalesce(v_ordered,'[]'::jsonb)||coalesce(deck_order,'[]'::jsonb),updated_at=now()
        WHERE room_id=p_room_id AND user_id=v_target_owner;
      END IF;
      UPDATE public.private_card_effect_runs_v1
        SET step_index=step_index+1,updated_at=now()
      WHERE room_id=p_room_id;
      CONTINUE;

    ELSIF v_op='disable_original_abilities' THEN$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('stun_action_character' IN v_definition)=0 OR position('return_unselected_to_deck_top' IN v_definition)=0 THEN
      RAISE EXCEPTION 'Card effect runner insertion point was not found.';
    END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure) INTO v_definition;
  v_old := $old$'watch_user_id',coalesce(v_trigger_owner,v_evidence_owner)::text$old$;
  v_new := $new$'watch_user_id',coalesce(v_trigger_owner,v_evidence_owner)::text,
             'action_character_user_id',coalesce(nullif(v_before_pending->>'attacker_user_id',''),v_trigger_owner::text),
             'action_character_instance_id',coalesce(nullif(v_before_pending->>'attacker_instance_id',''),nullif(v_before_pending->>'attacker_id',''))$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('action_character_instance_id' IN v_definition)=0 THEN RAISE EXCEPTION 'Evidence-removal action context insertion point was not found.'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;

  v_old := $old$     ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
       v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     ELSE
       v_case_internal_id:=NULL;$old$;
  v_new := $new$     ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
       v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     ELSIF v_case_key IN ('PR320','PR320P','1164') OR coalesce(v_new_board.event_rule_code,'')='police_academy_1164' THEN
       v_case_internal_id:='1164'; v_case_name:='경찰학교의 목욕탕 청소';
     ELSE
       v_case_internal_id:=NULL;$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('PR320' IN v_definition)=0 THEN RAISE EXCEPTION 'PR320 solution-entry mapping insertion point was not found.'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;

  v_old := $old$   ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
     v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     v_case_effect_id:='card-1120-antique-tray-case-effect';
   ELSE
     RAISE EXCEPTION '이 사건 카드에는 아직 선언형 효과가 등록되어 있지 않습니다.';$old$;
  v_new := $new$   ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
     v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     v_case_effect_id:='card-1120-antique-tray-case-effect';
   ELSIF v_case_key IN ('PR320','PR320P','1164') OR coalesce(v_new_board.event_rule_code,'')='police_academy_1164' THEN
     v_case_internal_id:='1164'; v_case_name:='경찰학교의 목욕탕 청소';
     v_case_effect_id:='card-1164-police-academy-case-effect';
   ELSE
     RAISE EXCEPTION '이 사건 카드에는 아직 선언형 효과가 등록되어 있지 않습니다.';$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('card-1164-police-academy-case-effect' IN v_definition)=0 THEN RAISE EXCEPTION 'PR320 case activation mapping insertion point was not found.'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.get_private_card_effect_activations_v1(uuid)'::regprocedure) INTO v_definition;
  v_old := $old$ ELSE
   v_case_id:=NULL;
 END IF;
 IF v_case_id IS NOT NULL$old$;
  v_new := $new$ ELSIF v_case_key IN ('PR320','PR320P','1164') OR coalesce(v_board.event_rule_code,'')='police_academy_1164' THEN
   v_case_id:='1164'; v_case_name:='경찰학교의 목욕탕 청소';
 ELSE
   v_case_id:=NULL;
 END IF;
 IF v_case_id IS NOT NULL$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('PR320' IN v_definition)=0 THEN RAISE EXCEPTION 'Human PR320 activation mapping insertion point was not found.'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure) INTO v_definition;
  v_old := $old$ ELSE
   v_case_id:=NULL;
 END IF;

 IF v_case_id IS NOT NULL$old$;
  v_new := $new$ ELSIF v_case_key IN ('PR320','PR320P','1164') OR coalesce(v_board.event_rule_code,'')='police_academy_1164' THEN
   v_case_id:='1164'; v_case_name:='경찰학교의 목욕탕 청소';
 ELSE
   v_case_id:=NULL;
 END IF;

 IF v_case_id IS NOT NULL$new$;
  IF position(v_old IN v_definition)=0 THEN
    IF position('PR320' IN v_definition)=0 THEN RAISE EXCEPTION 'AI PR320 activation mapping insertion point was not found.'; END IF;
  ELSE
    v_definition:=replace(v_definition,v_old,v_new);
  END IF;
  EXECUTE v_definition;
END
$functions$;
