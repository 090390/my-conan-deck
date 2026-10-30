-- Prevent an event from being moved to the remove area before its catalog effect finishes.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_anchor := $old$  if p_action = 'finish_event' then
    v_id := nullif(p_payload ->> 'instance_id', '');
$old$;
  v_replacement := $new$  if p_action = 'finish_event' then
    if exists(select 1 from public.private_card_effect_runs_v1 where room_id=p_room_id)
       or (v_match.pending_action is not null and v_match.pending_action->>'type' like 'card_effect_%') then
      raise exception '이벤트 카드 효과 처리가 끝난 뒤 리무브할 수 있습니다.';
    end if;
    v_id := nullif(p_payload ->> 'instance_id', '');
$new$;

  IF position(v_anchor IN v_definition)=0 THEN
    IF position(v_replacement IN v_definition)=0 THEN
      RAISE EXCEPTION 'finish_event effect-running guard anchor missing';
    END IF;
  ELSE
    v_definition:=replace(v_definition,v_anchor,v_replacement);
  END IF;
  EXECUTE v_definition;
END
$migration$;
