-- Field-only status does not travel with a card when it leaves the field.
-- The 3-argument event.played entrypoint must use the canonical DSL queue shape.
-- Next Hint requires a basic card play, not merely any action that sets base_action_done.

DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$v_card:=v_card-'zone'-'owner_user_id'-'resolving'-'dsl_remove_trigger_queued'-'attached_to_instance_id'-'parent_instance_id';$old$;
  v_new text := $new$v_card:=v_card-'zone'-'owner_user_id'-'resolving'-'dsl_remove_trigger_queued'-'attached_to_instance_id'-'parent_instance_id';
 IF p_from_zone='field' AND p_to_zone<>'field' THEN
   v_card:=v_card-'rested'-'status'-'stunned'-'stun'-'is_stunned'
     -'ap_bonus'-'summoned_this_turn'-'rested_until_turn'-'stun_until_turn';
 END IF;$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_move_card_v1(uuid,uuid,text,jsonb,text,uuid)'::regprocedure
  ) INTO v_definition;

  IF position($$IF p_from_zone='field' AND p_to_zone<>'field' THEN$$ IN v_definition)=0 THEN
    IF position(v_old IN v_definition)=0 THEN
      RAISE EXCEPTION '현장 이탈 카드 정규화 위치를 찾지 못했습니다.';
    END IF;
    v_definition:=replace(v_definition,v_old,v_new);
    v_definition:=replace(v_definition,E'END\n$function$',E'END;\n$function$');
    v_definition:=v_definition||';';
    EXECUTE v_definition;
  END IF;
END;
$migration$;

-- Delegate normal event play to the canonical 8-argument DSL execution path.
CREATE OR REPLACE FUNCTION public.private_card_effect_start_event_v1(
  p_room_id uuid,
  p_actor uuid,
  p_event_card jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF p_event_card IS NULL
     OR lower(coalesce(p_event_card->>'card_type',p_event_card->>'type','')) NOT IN ('event','이벤트','イベント') THEN
    RAISE EXCEPTION '이벤트 카드 정보가 올바르지 않습니다.';
  END IF;

  PERFORM public.private_card_effect_start_event_v1(
    p_room_id,
    p_actor,
    p_actor,
    p_event_card,
    'event.played',
    jsonb_build_object('entry',jsonb_build_object('method','event_play')),
    NULL,
    false
  );
END
$function$;

-- The 3-argument overload is internal to the SECURITY DEFINER turn-action
-- pipeline. Do not expose it as a direct anonymous/authenticated RPC.
REVOKE ALL ON FUNCTION public.private_card_effect_start_event_v1(uuid,uuid,jsonb)
  FROM PUBLIC, anon, authenticated;

-- Partner assist/deduction and other main actions can set base_action_done.
-- Next Hint itself must only unlock after the normal basic character/event play.
DO $migration$
DECLARE
  v_definition text;
  v_old_take text := $old$if not v_board.base_action_done then raise exception '먼저 기본 행동을 완료해야 넥스트 힌트를 사용할 수 있습니다.'; end if;$old$;
  v_new_take text := $new$if not coalesce(v_board.base_card_played_this_turn,false) then raise exception '기본 캐릭터 또는 이벤트 카드를 먼저 사용해야 넥스트 힌트를 사용할 수 있습니다.'; end if;$new$;
  v_old_continue text := $old2$if not v_board.base_action_done or not coalesce(v_board.next_hint_pending,false) then raise exception '먼저 넥스트 힌트를 선언하고 파일 카드를 손패로 가져와야 합니다.'; end if;$old2$;
  v_new_continue text := $new2$if not coalesce(v_board.base_card_played_this_turn,false) or not coalesce(v_board.next_hint_pending,false) then raise exception '기본 카드를 사용한 뒤 넥스트 힌트를 선언하고 파일 카드를 손패로 가져와야 합니다.'; end if;$new2$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position(v_new_take IN v_definition)=0 THEN
    IF position(v_old_take IN v_definition)=0 OR position(v_old_continue IN v_definition)=0 THEN
      RAISE EXCEPTION '넥스트 힌트 기본 카드 사용 검사 코드를 찾지 못했습니다.';
    END IF;
    v_definition:=replace(v_definition,v_old_take,v_new_take);
    v_definition:=replace(v_definition,v_old_continue,v_new_continue);
    v_definition:=replace(v_definition,E'END\n$function$',E'END;\n$function$');
    v_definition:=v_definition||';';
    EXECUTE v_definition;
  END IF;
END;
$migration$;
