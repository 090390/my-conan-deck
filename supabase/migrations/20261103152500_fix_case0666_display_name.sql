BEGIN;
CREATE OR REPLACE FUNCTION public.perform_private_turn_action_v2(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_match public.room_match_states%rowtype; v_before_match public.room_match_states%rowtype;
 v_before_boards jsonb; v_before_board jsonb; v_new_board public.room_player_turn_boards%rowtype;
 v_before_pending jsonb; v_after_pending jsonb; v_before_evidence jsonb; v_after_evidence jsonb;
 v_result jsonb; v_source_card jsonb; v_old_card jsonb; v_new_card jsonb; v_old_evidence_card jsonb;
 v_owner uuid; v_instance_id text; v_first_entry boolean; v_turn integer; v_old_field jsonb;
 v_old_board jsonb; v_old_entry jsonb; v_current_field jsonb; v_current_remove jsonb; v_removed boolean;
 v_before_base_character_played boolean:=false; v_first_entry_already boolean:=false;
 v_pending_actor uuid; v_context jsonb; v_event_source_user uuid; v_case_card jsonb; v_case_started boolean;
 v_case_effect_id text; v_case_key text; v_case_internal_id text; v_case_name text; v_case_uses jsonb;
 v_evidence_owner uuid; v_trigger_owner uuid; v_disguise_id text; v_effect_definition jsonb; v_effect_started boolean; v_use_key text;
 v_old_action text:=p_action;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;

 IF p_action='solve_case' THEN
   SELECT * INTO v_match
   FROM public.room_match_states
   WHERE room_id=p_room_id
   FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN
     RAISE EXCEPTION '진행 중인 게임에서만 사건을 해결할 수 있습니다.';
   END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user
      OR coalesce(v_match.turn_step,'')<>'main' THEN
     RAISE EXCEPTION '자신의 메인 단계에서만 사건을 해결할 수 있습니다.';
   END IF;
   IF v_match.pending_action IS NOT NULL
      OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '진행 중인 선택/응답을 먼저 완료해 주세요.';
   END IF;
   SELECT * INTO v_new_board
   FROM public.room_player_turn_boards
   WHERE room_id=p_room_id AND user_id=v_user
   FOR UPDATE;
   IF NOT FOUND THEN
     RAISE EXCEPTION '자신의 보드를 찾을 수 없습니다.';
   END IF;
   IF coalesce(v_new_board.case_phase,v_match.case_phase,'incident')<>'solution' THEN
     RAISE EXCEPTION '해결편에서만 사건을 해결할 수 있습니다.';
   END IF;
   v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''),'[^A-Za-z0-9]','','g'));
   IF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_new_board.event_rule_code,'')='culprits_1046' THEN
     RAISE EXCEPTION '범인들의 범행은 일반 사건 해결 대신 사건 선언 효과를 발동해야 합니다.';
   END IF;
   IF v_case_key IN ('B11098','B11098P','1261')
      OR coalesce(v_new_board.event_rule_code,'')='conan_vs_kid_1261' THEN
     IF v_match.first_player_user_id=v_user THEN
       IF coalesce(v_new_board.evidence_count,0)<8 THEN
         RAISE EXCEPTION '이 사건의 해결에는 증거 8장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     ELSE
       IF coalesce(v_new_board.evidence_count,0)<7 THEN
         RAISE EXCEPTION '이 사건의 해결에는 증거 7장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     END IF;
   ELSE
     IF v_match.first_player_user_id=v_user THEN
       IF coalesce(v_new_board.evidence_count,0)<7 THEN
         RAISE EXCEPTION '사건 해결에는 증거 7장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     ELSE
       IF coalesce(v_new_board.evidence_count,0)<6 THEN
         RAISE EXCEPTION '사건 해결에는 증거 6장이 필요합니다. 현재 %장입니다.',
           coalesce(v_new_board.evidence_count,0);
       END IF;
     END IF;
   END IF;
   UPDATE public.room_match_states
   SET game_over=true,
       winner_user_id=v_user,
       winner_turn_number=v_match.turn_number,
       last_action_label='사건 해결 성공! 승리 선언이 완료되었습니다.',
       state_version=state_version+1
   WHERE room_id=p_room_id;
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='activate_case_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 사건 효과를 발동할 수 있습니다.'; END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user OR v_match.turn_step<>'main' THEN
     RAISE EXCEPTION '자신의 메인 단계에서만 사건 효과를 발동할 수 있습니다.';
   END IF;
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   IF coalesce(v_new_board.case_phase,'incident')<>'solution' THEN RAISE EXCEPTION '해결편에서만 사건 효과를 발동할 수 있습니다.'; END IF;
   v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''),'[^A-Za-z0-9]','','g'));
   IF v_case_key IN ('B10083P','1139','B10083') THEN
     v_case_internal_id:='1139';
     v_case_name:='돌아오지 않는 형사';
     v_case_effect_id:='card-1139-returning-detective-case-effect';
   ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
     v_case_internal_id:='1261';
     v_case_name:='코난 VS 괴도 키드';
     v_case_effect_id:='card-1261-conan-vs-kid-case-effect';
   ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
     v_case_internal_id:='0806';
     v_case_name:='흔들리는 마음';
     v_case_effect_id:='card-0806-case-solution-activated-flip-evidence-level-down';
   ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_new_board.event_rule_code,'')='culprits_1046' THEN
     v_case_internal_id:='1046';
     v_case_name:='범인들의 범행';
     v_case_effect_id:='card-1046-culprits-crime-case-effect';
   ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
     v_case_internal_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
     v_case_effect_id:='card-0666-case-solution-flip-two-search-heiji-kazuha';
   ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
     v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     v_case_effect_id:='card-1120-antique-tray-case-effect';
   ELSE
     RAISE EXCEPTION '이 사건 카드에는 아직 선언형 효과가 등록되어 있지 않습니다.';
   END IF;
   IF nullif(p_payload->>'effect_id','') IS NOT NULL AND p_payload->>'effect_id'<>v_case_effect_id THEN
     RAISE EXCEPTION '현재 사건 카드에 등록된 효과와 요청한 효과가 일치하지 않습니다.';
   END IF;
   v_case_uses:=coalesce(v_new_board.case_effect_uses,'{}'::jsonb);
   IF coalesce(v_case_uses->>v_case_effect_id,'')=v_match.turn_number::text THEN
     RAISE EXCEPTION '이 턴에는 이미 해당 사건 효과를 사용했습니다.';
   END IF;
   v_case_card:=jsonb_build_object(
     'instance_id','case:'||v_new_board.event_key,'key',v_new_board.event_key,
     'card_id',v_case_internal_id,'card_num',v_new_board.event_key,
     'database_id',v_new_board.event_key,'card_type','event','type','event','name',v_case_name
   );
   v_case_started:=public.private_card_effect_start_event_v1(
     p_room_id,v_user,v_user,v_case_card,'case.activated_ability',
     jsonb_build_object('turn_number',v_match.turn_number,'case_key',v_new_board.event_key),
     v_case_effect_id,true
   );
   IF NOT coalesce(v_case_started,false) THEN
     RAISE EXCEPTION '사건 효과 조건이 충족되지 않았거나 아직 발동 가능한 효과가 아닙니다.';
   END IF;
   UPDATE public.room_player_turn_boards
     SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_case_effect_id],to_jsonb(v_match.turn_number::text),true),
         updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='card_effect_continue' THEN
   PERFORM public.private_card_effect_continue_v1(p_room_id,coalesce(p_payload,'{}'::jsonb));
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='activate_card_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 효과를 발동할 수 있습니다.'; END IF;
   -- Turn ownership is checked after the card effect timing is loaded.
   -- Turn-step eligibility is checked after the card effect timing is loaded.
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT * INTO v_new_board FROM public.room_player_turn_boards
     WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
   IF v_source_card IS NULL AND v_new_board.partner_mr_card->>'instance_id'=v_instance_id THEN
     v_source_card:=v_new_board.partner_mr_card;
   END IF;
   IF v_source_card IS NULL THEN
     SELECT p.value INTO v_source_card
     FROM jsonb_array_elements(coalesce(v_new_board.partner_non_mr_cards,'[]'::jsonb)) p(value)
     WHERE p.value->>'instance_id'=v_instance_id
     LIMIT 1;
   END IF;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 또는 MR 파트너 카드를 찾을 수 없습니다.'; END IF;
    IF coalesce((v_source_card->>'dsl_original_abilities_disabled')::boolean,false) THEN
      RAISE EXCEPTION '원래 능력이 턴 종료 시까지 무효화된 캐릭터입니다.';
    END IF;
   SELECT d.value INTO v_effect_definition
   FROM public.private_card_effect_catalog_v1 c
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
   WHERE c.catalog_id='main' AND d.value->>'effectId'=p_payload->>'effect_id'
     AND public.private_card_effect_matches_id_v1(v_source_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LIMIT 1;
   IF v_effect_definition IS NULL THEN RAISE EXCEPTION '이 캐릭터에 등록된 효과를 찾을 수 없습니다.'; END IF;
   IF v_new_board.partner_mr_card->>'instance_id'=v_instance_id
      AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 MR 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;
   IF EXISTS (
       SELECT 1 FROM jsonb_array_elements(coalesce(v_new_board.partner_non_mr_cards,'[]'::jsonb)) p(value)
       WHERE p.value->>'instance_id'=v_instance_id
     ) AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;
 
IF NOT public.private_card_effect_is_active_v1(v_source_card)
   AND (
     coalesce((v_effect_definition->>'requiresActiveSource')::boolean,false)
     OR NOT (
       (
         (
           coalesce((v_effect_definition->>'allowRestedSource')::boolean,false)
           OR EXISTS (
             SELECT 1 FROM jsonb_array_elements(coalesce(v_effect_definition->'steps','[]'::jsonb)) step(value)
             WHERE step.value->>'op'='ready_source_character'
           )
         )
         AND (
           coalesce((v_source_card->>'rested')::boolean,false)
           OR lower(coalesce(v_source_card->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
         )
         AND NOT (
           coalesce((v_source_card->>'stunned')::boolean,false)
           OR coalesce((v_source_card->>'stun')::boolean,false)
           OR coalesce((v_source_card->>'is_stunned')::boolean,false)
           OR lower(coalesce(v_source_card->>'status','')) IN ('stunned','stun','스턴')
         )
       )
       OR (
         coalesce((v_effect_definition->>'allowStunnedSource')::boolean,false)
         AND (
           coalesce((v_source_card->>'stunned')::boolean,false)
           OR coalesce((v_source_card->>'stun')::boolean,false)
           OR coalesce((v_source_card->>'is_stunned')::boolean,false)
           OR lower(coalesce(v_source_card->>'status','')) IN ('stunned','stun','스턴')
         )
       )
     )
   ) THEN
  RAISE EXCEPTION '이 카드 효과는 현재 캐릭터 상태에서 발동할 수 없습니다.';
END IF;
IF coalesce(v_effect_definition->>'activationTiming','') <> 'any' THEN
  IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN
    RAISE EXCEPTION '자신의 턴에만 이 능력을 발동할 수 있습니다.';
  END IF;
  IF coalesce(v_match.turn_step,'') NOT IN ('begin','file','main') THEN
    RAISE EXCEPTION '본인 턴 중 능력을 발동할 수 있는 단계가 아닙니다.';
  END IF;
END IF;

   v_use_key:=coalesce(p_payload->>'effect_id','')||':'||v_instance_id;
   SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
   IF coalesce((v_effect_definition->>'oncePerTurn')::boolean,false)
      AND coalesce(v_new_board.case_effect_uses->>v_use_key,'')=v_match.turn_number::text THEN
     RAISE EXCEPTION '이 턴에는 이미 해당 능력을 사용했습니다.';
   END IF;
   v_effect_started:=public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
     'character.activated_ability',jsonb_build_object('turn_number',v_match.turn_number),
     p_payload->>'effect_id',true);
   IF NOT coalesce(v_effect_started,false) THEN
     RAISE EXCEPTION '능력의 발동 조건을 충족하지 않습니다.';
   END IF;
   IF coalesce((v_effect_definition->>'oncePerTurn')::boolean,false) THEN
     UPDATE public.room_player_turn_boards
       SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_use_key],to_jsonb(v_match.turn_number::text),true),
           updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_user;
   END IF;
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 SELECT * INTO v_before_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_before_match.phase<>'playing' OR v_before_match.game_over THEN
   RAISE EXCEPTION '진행 중인 게임이 아닙니다.';
 END IF;
 v_before_pending:=v_before_match.pending_action;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'user_id',b.user_id,'field_cards',coalesce(b.field_cards,'[]'::jsonb),'partner_mr_card',b.partner_mr_card,
     'case_phase',b.case_phase,'event_key',b.event_key,'event_rule_code',b.event_rule_code,'file_count',b.file_count
   ) ORDER BY b.seat),'[]'::jsonb) INTO v_before_boards
 FROM public.room_player_turn_boards b WHERE b.room_id=p_room_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',gs.user_id,'evidence_cards',coalesce(gs.evidence_cards,'[]'::jsonb))),'[]'::jsonb)
   INTO v_before_evidence FROM public.room_player_game_states gs WHERE gs.room_id=p_room_id;
 v_turn:=v_before_match.turn_number;
 SELECT coalesce(base_character_played_this_turn,false), first_character_entered_this_turn IS NOT NULL
   INTO v_before_base_character_played, v_first_entry_already
   FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;

 
IF p_action='declare_contact' THEN
  v_instance_id:=coalesce(
    nullif(p_payload->>'attacker_instance_id',''),
    nullif(p_payload->>'attacker_id',''),
    nullif(p_payload->>'source_instance_id',''),
    nullif(p_payload->>'instance_id','')
  );
  v_source_card:=NULL;
  SELECT e.value INTO v_source_card
  FROM public.room_player_turn_boards b
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
  WHERE b.room_id=p_room_id AND b.user_id=v_user
    AND e.value->>'instance_id'=v_instance_id
  LIMIT 1;

  IF v_source_card IS NOT NULL AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(
      coalesce(v_source_card->'dsl_keywords','[]'::jsonb)
      || coalesce(v_source_card->'dsl_continuous_keywords','[]'::jsonb)
    ) k(value)
    WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
      IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')
  ) THEN
    RAISE EXCEPTION '돌격[사건] 상태의 캐릭터는 캐릭터를 대상으로 컨택할 수 없습니다.';
  END IF;

  v_owner:=nullif(p_payload->>'target_user_id','')::uuid;
  v_disguise_id:=coalesce(nullif(p_payload->>'target_instance_id',''),nullif(p_payload->>'target_id',''));
  v_old_card:=NULL;
  IF v_owner IS NOT NULL AND v_disguise_id IS NOT NULL THEN
    SELECT e.value INTO v_old_card
    FROM public.room_player_turn_boards b
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
    WHERE b.room_id=p_room_id AND b.user_id=v_owner
      AND e.value->>'instance_id'=v_disguise_id
    LIMIT 1;
  END IF;

  IF v_source_card IS NOT NULL
     AND public.private_card_effect_matches_id_v1(v_source_card,'["0938"]'::jsonb)
     AND v_old_card IS NOT NULL
     AND public.private_card_effect_is_active_v1(v_old_card) THEN
    IF public.private_card_effect_level_v1(v_old_card)<7 THEN
      RAISE EXCEPTION 'D11007은 레벨 7 이상 액티브 캐릭터만 액티브 대상 컨택으로 지정할 수 있습니다.';
    END IF;
    p_payload:=jsonb_set(coalesce(p_payload,'{}'::jsonb),'{allow_active_target}','true'::jsonb,true);
  END IF;
END IF;


IF p_action='guard_contact_with_character'
   AND coalesce(v_before_pending->>'type','')='character_contact_guard' THEN
   IF EXISTS (
     SELECT 1
     FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) a(value)
     CROSS JOIN LATERAL jsonb_array_elements(
       coalesce(a.value->'dsl_keywords','[]'::jsonb)
       || coalesce(a.value->'dsl_continuous_keywords','[]'::jsonb)
     ) k(value)
     WHERE b.room_id=p_room_id
       AND b.user_id=nullif(v_before_pending->>'attacker_user_id','')::uuid
       AND a.value->>'instance_id'=v_before_pending->>'attacker_instance_id'
       AND lower(coalesce(k.value->>'keyword',k.value#>>'{}','')) IN ('bullet','브렛','ブレット')
   ) THEN
     RAISE EXCEPTION '브렛을 가진 캐릭터의 액션은 가드할 수 없습니다.';
   END IF;
END IF;

 v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));

 IF p_action='declare_contact' THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   IF coalesce(v_after_pending->>'type','')='character_contact_guard' THEN
     SELECT e.value INTO v_source_card
     FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id
       AND b.user_id=nullif(v_after_pending->>'attacker_user_id','')::uuid
       AND e.value->>'instance_id'=v_after_pending->>'attacker_instance_id'
     LIMIT 1;
     IF v_source_card IS NOT NULL AND EXISTS (
       SELECT 1 FROM jsonb_array_elements(
         coalesce(v_source_card->'dsl_keywords','[]'::jsonb)
         || coalesce(v_source_card->'dsl_continuous_keywords','[]'::jsonb)
       ) k(value)
       WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}','')) IN ('bullet','브렛','ブレット')
     ) THEN
       v_after_pending:=jsonb_set(v_after_pending,'{type}',to_jsonb('character_contact'::text));
       v_after_pending:=v_after_pending||jsonb_build_object(
         'cut_in_priority_user_id',
         CASE WHEN coalesce(nullif(v_after_pending->>'target_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'target_bonus','')::numeric,0)
                 <=coalesce(nullif(v_after_pending->>'attacker_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'attacker_bonus','')::numeric,0)
           THEN v_after_pending->>'target_user_id' ELSE v_after_pending->>'attacker_user_id' END,
         'next_responder_user_id',
         CASE WHEN coalesce(nullif(v_after_pending->>'target_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'target_bonus','')::numeric,0)
                 <=coalesce(nullif(v_after_pending->>'attacker_ap','')::numeric,0)+coalesce(nullif(v_after_pending->>'attacker_bonus','')::numeric,0)
           THEN v_after_pending->>'target_user_id' ELSE v_after_pending->>'attacker_user_id' END,
         'attacker_cut_in_used',false,'target_cut_in_used',false,
         'attacker_cut_in_passed',false,'target_cut_in_passed',false,
         'cut_in_used',false,'guarded_contact',false
       );
       UPDATE public.room_match_states
       SET pending_action=v_after_pending,state_version=state_version+1,
           last_action_label=format('브렛: %s의 액션은 가드할 수 없습니다. 컷인 선택으로 진행합니다.',
             coalesce(v_source_card->>'name',v_source_card->>'key','캐릭터'))
       WHERE room_id=p_room_id;
     END IF;
   END IF;
 END IF;


 IF p_action='declare_contact'
    AND v_before_match.current_turn_user_id=v_user
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   IF v_after_pending->>'type'='character_contact'
      AND nullif(v_after_pending->>'attacker_user_id','')::uuid=v_user THEN
     v_instance_id:=coalesce(v_after_pending->>'attacker_instance_id',v_after_pending->>'attacker_id');
     v_owner:=nullif(v_after_pending->>'target_user_id','')::uuid;
     v_disguise_id:=nullif(v_after_pending->>'target_instance_id','');
     SELECT e.value INTO v_source_card
       FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL AND public.private_card_effect_matches_id_v1(v_source_card,'["0938"]'::jsonb) THEN
       SELECT e.value INTO v_old_card
         FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
         WHERE b.room_id=p_room_id AND b.user_id=v_owner AND e.value->>'instance_id'=v_disguise_id LIMIT 1;
       v_use_key:='card-0938-contact-start-discard-for-ap-3000:'||v_instance_id;
       SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user FOR UPDATE;
       IF v_old_card IS NOT NULL
          AND coalesce(v_new_board.case_effect_uses->>v_use_key,'')<>v_before_match.turn_number::text
          AND coalesce(v_before_match.current_turn_user_id,v_user)=v_user THEN
         v_context:=jsonb_build_object(
           'turn_number',v_before_match.turn_number,
           'resume_pending',v_after_pending,
           'contact',jsonb_build_object(
             'source_ap',coalesce(nullif(v_source_card->>'ap','')::numeric,0)+coalesce(nullif(v_source_card->>'ap_bonus','')::numeric,0),
             'target_ap',coalesce(nullif(v_old_card->>'ap','')::numeric,0)+coalesce(nullif(v_old_card->>'ap_bonus','')::numeric,0)
           )
         );
         IF (v_context#>>'{contact,target_ap}')::numeric>(v_context#>>'{contact,source_ap}')::numeric THEN
           PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
             'character.contact_started',v_context,'card-0938-contact-start-discard-for-ap-3000',true);
           UPDATE public.room_player_turn_boards
             SET case_effect_uses=jsonb_set(coalesce(case_effect_uses,'{}'::jsonb),ARRAY[v_use_key],to_jsonb(v_before_match.turn_number::text),true),
                 updated_at=now()
           WHERE room_id=p_room_id AND user_id=v_user;
         END IF;
       END IF;
     END IF;
   END IF;
 END IF;

 IF p_action='declare_contact'
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   IF v_after_pending->>'type'='character_contact'
      AND nullif(v_after_pending->>'attacker_user_id','')::uuid=v_user THEN
     v_instance_id:=coalesce(v_after_pending->>'attacker_instance_id',v_after_pending->>'attacker_id');
     SELECT e.value INTO v_source_card
       FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(
         p_room_id,v_user,v_user,v_source_card,'character.contact_started',
         jsonb_build_object('turn_number',v_turn,'contact',v_after_pending),NULL,false
       );
     END IF;
   END IF;
 END IF;

 IF p_action='contact_use_disguise'
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT pending_action INTO v_after_pending FROM public.room_match_states WHERE room_id=p_room_id;
   v_disguise_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card
   FROM public.room_player_turn_boards b
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
   WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_disguise_id LIMIT 1;
   IF v_source_card IS NOT NULL AND v_after_pending->>'type'='character_contact' THEN
     PERFORM public.private_card_effect_start_event_v1(
       p_room_id,v_user,v_user,v_source_card,'character.disguised',
       jsonb_build_object('turn_number',v_turn,'resume_pending',v_after_pending,
         'contact',v_after_pending,'disguised_instance_id',v_disguise_id),NULL,false
     );
   END IF;
 END IF;

 IF p_action='begin_turn' THEN
   UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=NULL, updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
   UPDATE public.room_player_turn_boards b SET
     field_cards=coalesce((SELECT jsonb_agg(CASE WHEN coalesce(nullif(e.value->>'dsl_temporary_level_bonus','')::numeric,0)<>0
       THEN e.value||jsonb_build_object('level_bonus',
         coalesce(nullif(e.value->>'level_bonus','')::numeric,0)-coalesce(nullif(e.value->>'dsl_temporary_level_bonus','')::numeric,0),
         'dsl_temporary_level_bonus',0)
       ELSE e.value END ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
     partner_mr_card=CASE WHEN b.partner_mr_card IS NULL THEN NULL
       WHEN coalesce(nullif(b.partner_mr_card->>'dsl_temporary_level_bonus','')::numeric,0)<>0
       THEN b.partner_mr_card||jsonb_build_object('level_bonus',
         coalesce(nullif(b.partner_mr_card->>'level_bonus','')::numeric,0)-coalesce(nullif(b.partner_mr_card->>'dsl_temporary_level_bonus','')::numeric,0),
         'dsl_temporary_level_bonus',0)
       ELSE b.partner_mr_card END,
     updated_at=now()
   WHERE b.room_id=p_room_id;
 END IF;

 IF p_action='declare_solution'
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   SELECT value INTO v_before_board FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb))
     WHERE value->>'user_id'=v_user::text LIMIT 1;
   SELECT * INTO v_new_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
   IF coalesce(v_before_board->>'case_phase','incident')<>'solution'
      AND coalesce(v_new_board.case_phase,'incident')='solution' THEN
     v_case_key:=upper(regexp_replace(coalesce(v_new_board.event_key,''),'[^A-Za-z0-9]','','g'));
     IF v_case_key IN ('B10083P','1139','B10083') THEN
       v_case_internal_id:='1139'; v_case_name:='돌아오지 않는 형사';
     ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
       v_case_internal_id:='1261'; v_case_name:='코난 VS 괴도 키드';
     ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
       v_case_internal_id:='0806'; v_case_name:='흔들리는 마음';
     ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
       v_case_internal_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
     ELSIF v_case_key IN ('B10061P','B10061','1120') THEN
       v_case_internal_id:='1120'; v_case_name:='골동품 쟁반은 숨길 수 없다';
     ELSE
       v_case_internal_id:=NULL;
     END IF;
     IF v_case_internal_id IS NOT NULL THEN
       v_case_card:=jsonb_build_object(
         'instance_id','case:'||v_new_board.event_key,'key',v_new_board.event_key,
         'card_id',v_case_internal_id,'card_num',v_new_board.event_key,
         'database_id',v_new_board.event_key,'card_type','event','type','event','name',v_case_name
       );
       PERFORM public.private_card_effect_start_event_v1(
         p_room_id,v_user,v_user,v_case_card,'case.solution_entered',
         jsonb_build_object('turn_number',v_turn,'case_key',v_new_board.event_key),NULL,false
       );
     END IF;
   END IF;
 END IF;

 IF p_action IN ('play_character','next_hint') THEN
   v_instance_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
   IF v_source_card IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     SELECT value INTO v_before_board FROM jsonb_array_elements(v_before_boards) WHERE value->>'user_id'=v_user::text LIMIT 1;
     v_old_field:=coalesce(v_before_board->'field_cards','[]'::jsonb);
     v_first_entry:=NOT v_first_entry_already;
     IF v_first_entry THEN
       UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=v_instance_id,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_user AND first_character_entered_this_turn IS NULL;
     END IF;
     v_context:=jsonb_build_object('entry',jsonb_build_object(
       'method',CASE WHEN p_action='next_hint' THEN 'next_hint' ELSE 'manual' END,
       'is_first_character_this_turn',v_first_entry,'source',v_source_card,
       'controller_user_id',v_user::text),
       'turn_number',v_turn);
     PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
       'character.entered_field',v_context,NULL,false);
   END IF;
 END IF;

 IF p_action='play_event' AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_instance_id:=nullif(p_payload->>'instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user
       AND e.value->>'instance_id'=v_instance_id AND lower(coalesce(e.value->>'card_type',''))='event' LIMIT 1;
   IF v_source_card IS NOT NULL THEN
     PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
       'event.played',jsonb_build_object('entry',jsonb_build_object('method','event_play'),'turn_number',v_turn),NULL,false);
   END IF;
 END IF;

 IF p_action IN ('investigate','attack_character','attack_evidence','declare_contact') THEN
   IF NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
      AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     v_instance_id:=coalesce(nullif(p_payload->>'instance_id',''),nullif(p_payload->>'attacker_instance_id',''));
     IF v_instance_id IS NOT NULL THEN
       SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
         CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
         WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
       IF v_source_card IS NOT NULL THEN
         PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
           'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false);
       END IF;
     END IF;
   END IF;
 END IF;

 IF p_action IN ('pass_mislead','resolve_mislead') AND v_before_pending->>'type'='mislead_response'
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'investigator_user_id','')::uuid;
   v_instance_id:=v_before_pending->>'investigator_instance_id';
   IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_event_source_user,v_event_source_user,v_source_card,
         'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false);
     END IF;
   END IF;
 END IF;

 IF p_action IN ('contact_pass_cutin','contact_use_cutin','contact_use_disguise','resolve_character_contact')
    AND v_before_pending IS NOT NULL
    AND v_before_pending->>'type' IN ('character_contact','character_contact_guard')
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
   v_instance_id:=coalesce(v_before_pending->>'attacker_instance_id',v_before_pending->>'attacker_id');
   v_owner:=nullif(v_before_pending->>'target_user_id','')::uuid;
   v_disguise_id:=nullif(v_before_pending->>'target_instance_id','');
   IF v_event_source_user IS NOT NULL AND v_owner IS NOT NULL AND v_instance_id IS NOT NULL AND v_disguise_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NULL THEN
       SELECT e.value INTO v_source_card FROM jsonb_array_elements(coalesce(
         (SELECT value->'field_cards' FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb))
          WHERE value->>'user_id'=v_event_source_user::text LIMIT 1),'[]'::jsonb)) e(value)
       WHERE e.value->>'instance_id'=v_instance_id LIMIT 1;
     END IF;
     SELECT coalesce(field_cards,'[]'::jsonb) INTO v_current_field FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_owner;
     SELECT coalesce(remove_cards,'[]'::jsonb) INTO v_current_remove FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner;
     IF v_source_card IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_disguise_id)
        AND (EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_disguise_id) OR EXISTS(SELECT 1 FROM public.room_player_turn_boards pb WHERE pb.room_id=p_room_id AND pb.user_id=v_owner AND pb.partner_mr_card->>'instance_id'=v_disguise_id)) THEN
       PERFORM public.private_card_effect_start_event_v1(
         p_room_id,v_event_source_user,v_event_source_user,v_source_card,'character.contact_removed_opponent',
         jsonb_build_object('turn_number',v_turn,'target_card_id',v_disguise_id),NULL,false
       );
     END IF;
   END IF;
 END IF;

 IF p_action IN ('contact_pass_cutin','contact_use_cutin','contact_use_disguise','resolve_character_contact')
    AND v_before_pending IS NOT NULL
    AND v_before_pending->>'type' IN ('character_contact','character_contact_guard')
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
   v_instance_id:=coalesce(v_before_pending->>'attacker_instance_id',v_before_pending->>'attacker_id');
   IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
     SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
       CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user AND e.value->>'instance_id'=v_instance_id LIMIT 1;
     IF v_source_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_event_source_user,v_event_source_user,v_source_card,
         'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false);
     END IF;
   END IF;
 END IF;

 IF p_action='resolve_evidence_attack'
     AND v_before_pending IS NOT NULL
     AND v_before_pending->>'type'='evidence_attack_reveal'
     AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL)
     AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
    v_event_source_user:=nullif(v_before_pending->>'attacker_user_id','')::uuid;
    v_instance_id:=nullif(v_before_pending->>'attacker_instance_id','');
    IF v_event_source_user IS NOT NULL AND v_instance_id IS NOT NULL THEN
      SELECT e.value INTO v_source_card
        FROM public.room_player_turn_boards b
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
        WHERE b.room_id=p_room_id AND b.user_id=v_event_source_user
          AND e.value->>'instance_id'=v_instance_id LIMIT 1;
      IF v_source_card IS NOT NULL THEN
        PERFORM public.private_card_effect_start_event_v1(
          p_room_id,v_event_source_user,v_event_source_user,v_source_card,
          'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false
        );
      END IF;
    END IF;
  END IF;

  IF p_action='end_turn' THEN
   UPDATE public.room_player_turn_boards b
    SET field_cards=coalesce((SELECT jsonb_agg(
       e.value||jsonb_build_object('ap_bonus',0,'dsl_ap_bonus',0,
         'dsl_keywords',coalesce((SELECT jsonb_agg(k.value) FROM jsonb_array_elements(coalesce(e.value->'dsl_keywords','[]'::jsonb)) k(value)
          WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>v_turn),'[]'::jsonb))
       ORDER BY e.ordinality)
      FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),'[]'::jsonb),
       partner_mr_card=CASE WHEN b.partner_mr_card IS NULL THEN NULL ELSE b.partner_mr_card||jsonb_build_object('ap_bonus',0,'dsl_ap_bonus',0,
         'dsl_keywords',coalesce((SELECT jsonb_agg(k.value) FROM jsonb_array_elements(coalesce(b.partner_mr_card->'dsl_keywords','[]'::jsonb)) k(value)
          WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>v_turn),'[]'::jsonb)) END,
       updated_at=now()
    WHERE b.room_id=p_room_id AND b.user_id=v_user;

   IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     SELECT field_cards,partner_mr_card INTO v_current_field,v_old_card FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;
     FOR v_new_card IN SELECT value FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) LOOP
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_new_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn,'source_area','field'),NULL,false);
       IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
     END LOOP;
     IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) AND v_old_card IS NOT NULL THEN
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_old_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn,'source_area','partner'),NULL,false);
     END IF;
   END IF;
 END IF;

 -- Detect field cards that actually entered an owner's remove area during this action.
 IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL) THEN
   FOR v_old_board IN SELECT value FROM jsonb_array_elements(coalesce(v_before_boards,'[]'::jsonb)) LOOP
     v_owner:=nullif(v_old_board->>'user_id','')::uuid;
     FOR v_old_card IN SELECT value FROM jsonb_array_elements(coalesce(v_old_board->'field_cards','[]'::jsonb)) LOOP
       v_instance_id:=v_old_card->>'instance_id';
       IF v_instance_id IS NULL OR v_instance_id='' THEN CONTINUE; END IF;
       SELECT coalesce(field_cards,'[]'::jsonb) INTO v_current_field FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_owner;
       SELECT coalesce(remove_cards,'[]'::jsonb) INTO v_current_remove FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_owner;
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) e(value) WHERE e.value->>'instance_id'=v_instance_id)
         AND (
           EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_current_remove,'[]'::jsonb)) e(value)
             WHERE e.value->>'instance_id'=v_instance_id AND NOT coalesce((e.value->>'dsl_remove_trigger_queued')::boolean,false))
           OR EXISTS(SELECT 1 FROM public.room_player_turn_boards pb
             WHERE pb.room_id=p_room_id AND pb.user_id=v_owner AND pb.partner_mr_card->>'instance_id'=v_instance_id
               AND NOT coalesce((pb.partner_mr_card->>'dsl_remove_trigger_queued')::boolean,false))
         ) THEN
         PERFORM public.private_card_effect_start_event_v1(p_room_id,v_owner,v_owner,v_old_card,
           'character.removed_from_field',jsonb_build_object('turn_number',v_turn,'removed_on_turn_user_id',v_before_match.current_turn_user_id),NULL,false);
         IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
       END IF;
     END LOOP;
     IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
   END LOOP;
 END IF;

 IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id)
    AND NOT EXISTS(SELECT 1 FROM public.room_match_states WHERE room_id=p_room_id AND pending_action IS NOT NULL) THEN
   FOR v_old_board IN SELECT value FROM jsonb_array_elements(coalesce(v_before_evidence,'[]'::jsonb)) LOOP
     v_evidence_owner:=nullif(v_old_board->>'user_id','')::uuid;
     SELECT coalesce(evidence_cards,'[]'::jsonb) INTO v_after_evidence
       FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=v_evidence_owner;
     FOR v_old_evidence_card IN SELECT value FROM jsonb_array_elements(coalesce(v_old_board->'evidence_cards','[]'::jsonb)) LOOP
       IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_after_evidence,'[]'::jsonb)) e(value)
         WHERE e.value->>'instance_id'=v_old_evidence_card->>'instance_id')
         AND EXISTS(
           SELECT 1 FROM public.room_player_game_states gs
           CROSS JOIN LATERAL jsonb_array_elements(coalesce(gs.remove_cards,'[]'::jsonb)) removed(value)
           WHERE gs.room_id=p_room_id AND gs.user_id=v_evidence_owner
             AND removed.value->>'instance_id'=v_old_evidence_card->>'instance_id'
         ) THEN
         SELECT user_id INTO v_trigger_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_evidence_owner
           ORDER BY seat LIMIT 1;
         PERFORM public.private_card_effect_start_event_v1(
           p_room_id,v_evidence_owner,v_evidence_owner,v_old_evidence_card,'evidence.card_removed',
           jsonb_build_object(
             'turn_number',v_turn,
             'evidence_removed_instance_id',v_old_evidence_card->>'instance_id',
             'evidence_owner_user_id',v_evidence_owner::text,
             'removed_evidence_card',v_old_evidence_card,
             'watch_user_id',coalesce(v_trigger_owner,v_evidence_owner)::text
           ),NULL,false
         );
         IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
       END IF;
     END LOOP;
     IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
   END LOOP;
 END IF;

 IF p_action='end_turn' AND NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   PERFORM public.private_card_effect_process_scheduled_returns_v1(p_room_id);
 END IF;
 PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
 RETURN public.get_private_turn_state_v2(p_room_id);
END
$function$
;
COMMIT;