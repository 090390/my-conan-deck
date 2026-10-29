-- Add an event-played DSL trigger and connect the two level-one color search events.
BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_color_v1(p_card jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v text;
BEGIN
  v := lower(coalesce(p_card ->> 'color', p_card ->> 'color_key', p_card ->> 'colorKey',
    p_card #>> '{sourceData,color}', p_card #>> '{raw,color}', ''));
  IF v IN ('red','赤','적') OR position('赤' in v)>0 OR position('적' in v)>0 OR v LIKE '%red%' THEN RETURN 'red'; END IF;
  IF v IN ('blue','青','청') OR position('青' in v)>0 OR position('청' in v)>0 OR v LIKE '%blue%' THEN RETURN 'blue'; END IF;
  IF v IN ('green','緑','녹') OR position('緑' in v)>0 OR position('녹' in v)>0 OR v LIKE '%green%' THEN RETURN 'green'; END IF;
  IF v IN ('white','白','백') OR position('白' in v)>0 OR position('백' in v)>0 OR v LIKE '%white%' THEN RETURN 'white'; END IF;
  IF v IN ('black','黒','黑','흑') OR position('黒' in v)>0 OR position('黑' in v)>0 OR position('흑' in v)>0 OR v LIKE '%black%' THEN RETURN 'black'; END IF;
  IF v IN ('yellow','黄','황') OR position('黄' in v)>0 OR position('황' in v)>0 OR v LIKE '%yellow%' THEN RETURN 'yellow'; END IF;
  RETURN nullif(v,'');
END
$function$;

CREATE OR REPLACE FUNCTION public.private_card_effect_filter_matches_v1(p_room_id uuid, p_card jsonb, p_owner_user uuid, p_source_user uuid, p_filter jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE part jsonb; f text; op text; expected jsonb; actual jsonb; v_num numeric;
BEGIN
 IF p_filter IS NULL OR jsonb_typeof(p_filter)<>'object' THEN RETURN true; END IF;
 IF p_filter ? 'allOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'allOf') LOOP
    IF NOT public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,part) THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
 END IF;
 IF p_filter ? 'anyOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'anyOf') LOOP
    IF public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,part) THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
 END IF;
 f:=p_filter->>'field'; op:=p_filter->>'operator'; expected:=p_filter->'value';
 IF jsonb_typeof(expected)='object' AND expected ? 'fact' THEN
   expected:=public.private_card_effect_fact_v1(p_room_id,p_owner_user,p_source_user,p_card,'{}'::jsonb,'{}'::jsonb,expected->>'fact');
 END IF;
 actual:='null'::jsonb;
 CASE f
  WHEN 'card_type' THEN actual:=to_jsonb(CASE WHEN public.private_card_effect_is_character_v1(p_card) THEN 'character' ELSE lower(coalesce(p_card->>'card_type',p_card->>'type','')) END);
  WHEN 'level' THEN actual:=to_jsonb(public.private_card_effect_level_v1(p_card));
  WHEN 'color' THEN actual:=to_jsonb(public.private_card_effect_color_v1(p_card));
  WHEN 'card_name' THEN
    IF op='name_matches' THEN RETURN public.private_card_effect_name_matches_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_name_v1(p_card));
  WHEN 'trait' THEN
    IF op='has_trait' THEN RETURN public.private_card_effect_has_trait_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_has_trait_v1(p_card,trim(both '"' from expected::text)));
  WHEN 'keyword' THEN
    IF op='has_keyword' THEN RETURN public.private_card_effect_has_keyword_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_has_keyword_v1(p_card,trim(both '"' from expected::text)));
  WHEN 'ap_current' THEN actual:=to_jsonb(coalesce(nullif(p_card->>'ap','')::numeric,0)+coalesce(nullif(p_card->>'ap_bonus','')::numeric,0));
  WHEN 'is_active' THEN actual:=to_jsonb(public.private_card_effect_is_active_v1(p_card));
  WHEN 'status' THEN actual:=to_jsonb(coalesce(p_card->>'status',CASE WHEN coalesce((p_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END));
  WHEN 'controller' THEN actual:=to_jsonb(CASE WHEN p_owner_user=p_source_user THEN 'self' ELSE 'opponent' END);
  ELSE actual:=coalesce(p_card->f,'null'::jsonb);
 END CASE;
 IF op='equals' THEN RETURN actual=expected; END IF;
 IF op='in' THEN RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(expected,'[]'::jsonb)) e(value) WHERE e.value=actual); END IF;
 IF op='less_than' THEN RETURN (actual#>>'{}')::numeric < (expected#>>'{}')::numeric; END IF;
 IF op='less_than_or_equal' THEN RETURN (actual#>>'{}')::numeric <= (expected#>>'{}')::numeric; END IF;
 IF op='greater_than' THEN RETURN (actual#>>'{}')::numeric > (expected#>>'{}')::numeric; END IF;
 IF op='greater_than_or_equal' THEN RETURN (actual#>>'{}')::numeric >= (expected#>>'{}')::numeric; END IF;
 RETURN false;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN false;
END
$function$;

CREATE OR REPLACE FUNCTION public.perform_private_turn_action_v2(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
 v_user uuid:=auth.uid(); v_match public.room_match_states%rowtype; v_before_match public.room_match_states%rowtype;
 v_before_boards jsonb; v_before_board jsonb; v_new_board public.room_player_turn_boards%rowtype;
 v_before_pending jsonb; v_result jsonb; v_source_card jsonb; v_old_card jsonb; v_new_card jsonb;
 v_owner uuid; v_instance_id text; v_first_entry boolean; v_turn integer; v_old_field jsonb;
 v_old_board jsonb; v_old_entry jsonb; v_current_field jsonb; v_current_remove jsonb; v_removed boolean;
 v_before_base_character_played boolean:=false; v_first_entry_already boolean:=false;
 v_pending_actor uuid; v_context jsonb; v_event_source_user uuid;
 v_old_action text:=p_action;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user) THEN
   RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
 END IF;

 IF p_action='card_effect_continue' THEN
   PERFORM public.private_card_effect_continue_v1(p_room_id,coalesce(p_payload,'{}'::jsonb));
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 IF p_action='activate_card_effect' THEN
   SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
   IF NOT FOUND OR v_match.phase<>'playing' OR v_match.game_over THEN RAISE EXCEPTION '진행 중인 게임에서만 효과를 발동할 수 있습니다.'; END IF;
   IF v_match.current_turn_user_id IS DISTINCT FROM v_user THEN RAISE EXCEPTION '자신의 턴에만 이 능력을 발동할 수 있습니다.'; END IF;
   IF coalesce(v_match.turn_step,'') NOT IN ('begin','file','main') THEN RAISE EXCEPTION '본인 턴 중 능력을 발동할 수 있는 단계가 아닙니다.'; END IF;
   IF v_match.pending_action IS NOT NULL OR EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
     RAISE EXCEPTION '먼저 진행 중인 선택/응답을 완료해 주세요.';
   END IF;
   v_instance_id:=nullif(p_payload->>'source_instance_id','');
   SELECT e.value INTO v_source_card FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_user AND e.value->>'instance_id'=v_instance_id LIMIT 1 FOR UPDATE;
   IF v_source_card IS NULL THEN RAISE EXCEPTION '효과를 발동할 자신의 현장 캐릭터를 찾을 수 없습니다.'; END IF;
   PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_source_card,
     'character.activated_ability',jsonb_build_object('turn_number',v_match.turn_number),
     p_payload->>'effect_id',true);
   PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
   RETURN public.get_private_turn_state_v2(p_room_id);
 END IF;

 SELECT * INTO v_before_match FROM public.room_match_states WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_before_match.phase<>'playing' OR v_before_match.game_over THEN
   RAISE EXCEPTION '진행 중인 게임이 아닙니다.';
 END IF;
 v_before_pending:=v_before_match.pending_action;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',b.user_id,'field_cards',coalesce(b.field_cards,'[]'::jsonb),'partner_mr_card',b.partner_mr_card)
   ORDER BY b.seat),'[]'::jsonb) INTO v_before_boards
 FROM public.room_player_turn_boards b WHERE b.room_id=p_room_id;
 v_turn:=v_before_match.turn_number;
 SELECT coalesce(base_character_played_this_turn,false), first_character_entered_this_turn IS NOT NULL
   INTO v_before_base_character_played, v_first_entry_already
   FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_user;

 v_result:=public.perform_private_turn_action_v2_legacy(p_room_id,p_action,coalesce(p_payload,'{}'::jsonb));

 IF p_action='begin_turn' THEN
   UPDATE public.room_player_turn_boards SET first_character_entered_this_turn=NULL, updated_at=now()
   WHERE room_id=p_room_id AND user_id=v_user;
 END IF;

 IF p_action='play_character' THEN
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
       'method','manual','is_first_character_this_turn',v_first_entry,'source',v_source_card),
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
           'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
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
         'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
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
         'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false);
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
          'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false
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
     FOR v_new_card IN SELECT value FROM jsonb_array_elements(coalesce(v_current_field,'[]'::jsonb)) UNION ALL
       SELECT v_old_card WHERE v_old_card IS NOT NULL LOOP
       PERFORM public.private_card_effect_start_event_v1(p_room_id,v_user,v_user,v_new_card,
         'player.turn_ended',jsonb_build_object('turn_number',v_turn,'ending_turn_number',v_turn),NULL,false);
       IF EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN EXIT; END IF;
     END LOOP;
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

 PERFORM public.private_card_effect_recalculate_continuous_v1(p_room_id);
 RETURN public.get_private_turn_state_v2(p_room_id);
END
$function$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
  WHERE e.value->>'effectId' NOT IN ('card-0158-on-play-private-eye','card-0130-on-play-ladies-gentlemen')
) || $dsldefs$[{"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"color","value":"yellow","operator":"equals"}]},"prompt":"공개하여 패에 추가할 황 캐릭터를 최대 1장 선택하세요.","saveAs":"selected","optional":true},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_deck_bottom","from":"seen","order":"player_choice","selectedVariable":"selected"},{"op":"select_cards","max":1,"min":0,"from":"hand","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"color","value":"yellow","operator":"equals"},{"field":"level","value":{"fact":"player.file.count"},"operator":"less_than_or_equal"}]},"prompt":"자신의 파일 수 이하 레벨인 황 캐릭터를 최대 1장 등장시킬 수 있습니다.","saveAs":"deployment","optional":true},{"op":"move_cards","to":"field","from":"deployment","when":{"fact":"vars.deployment.count","value":0,"operator":"greater_than"},"entryMethod":"event_effect"}],"cardIds":["0158"],"trigger":{"event":"event.played","timing":"after"},"effectId":"card-0158-on-play-private-eye","cardNameJa":"プライベート・アイ","cardNameKo":"프라이빗 아이","conditions":[],"reviewNotes":{"rationale":"덱에 적격 황 캐릭터가 없고 손패에도 등장 가능한 캐릭터가 없으면 검색한 카드만 손패에 넣고 이벤트 처리를 마친다.","sourceText":"덱 위 3장을 확인하고 황 캐릭터를 최대 1장 공개해 패에 추가한다. 나머지는 원하는 순서로 덱 아래에 둔 뒤 파일 수 이하 레벨의 황 캐릭터를 최대 1장 등장시킨다."}},{"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"color","value":"white","operator":"equals"}]},"prompt":"공개하여 패에 추가할 백 캐릭터를 최대 1장 선택하세요.","saveAs":"selected","optional":true},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_deck_bottom","from":"seen","order":"player_choice","selectedVariable":"selected"},{"op":"select_cards","max":1,"min":0,"from":"hand","filter":{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"color","value":"white","operator":"equals"},{"field":"level","value":{"fact":"player.file.count"},"operator":"less_than_or_equal"}]},"prompt":"자신의 파일 수 이하 레벨인 백 캐릭터를 최대 1장 등장시킬 수 있습니다.","saveAs":"deployment","optional":true},{"op":"move_cards","to":"field","from":"deployment","when":{"fact":"vars.deployment.count","value":0,"operator":"greater_than"},"entryMethod":"event_effect"}],"cardIds":["0130"],"trigger":{"event":"event.played","timing":"after"},"effectId":"card-0130-on-play-ladies-gentlemen","cardNameJa":"“Ladies♡ and… Gentlemen!!”","cardNameKo":"“Ladies♡ and… Gentlemen!!”","conditions":[],"reviewNotes":{"rationale":"프라이빗 아이와 같은 순서이며 대상 카드 색상만 백색으로 다르다.","sourceText":"덱 위 3장을 확인하고 백 캐릭터를 최대 1장 공개해 패에 추가한다. 나머지는 원하는 순서로 덱 아래에 둔 뒤 파일 수 이하 레벨의 백 캐릭터를 최대 1장 등장시킨다."}}]$dsldefs$::jsonb,
updated_at=now()
WHERE c.catalog_id='main';

COMMIT;
