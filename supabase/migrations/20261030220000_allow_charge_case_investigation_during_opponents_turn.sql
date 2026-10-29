DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
  v_replacement text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;

  v_anchor := 'if v_match.current_turn_user_id <> v_user or v_match.turn_step <> ''main'' or v_match.pending_action is not null then raise exception ''자신의 메인 단계에서만 추리할 수 있습니다.''; end if;';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate legacy investigate step guard'; END IF;

  v_replacement := $guard$
if ((v_match.current_turn_user_id <> v_user) AND NOT EXISTS (
      SELECT 1
      FROM public.room_player_turn_boards b
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) c(value)
      CROSS JOIN LATERAL jsonb_array_elements(
        coalesce(c.value->'dsl_keywords','[]'::jsonb)
        || coalesce(c.value->'dsl_continuous_keywords','[]'::jsonb)
      ) k(value)
      WHERE b.room_id=p_room_id AND b.user_id=v_user
        AND c.value->>'instance_id'=p_payload->>'instance_id'
        AND lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
          IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')
    )) OR v_match.turn_step <> 'main' OR v_match.pending_action is not null then
  raise exception '자신의 메인 단계 또는 돌격[사건]의 즉시 추리에서만 추리할 수 있습니다.';
end if;
$guard$;
  v_definition:=replace(v_definition,v_anchor,v_replacement);

  v_anchor := 'if coalesce((v_card ->> ''summoned_this_turn'')::boolean, false) and coalesce((p_payload ->> ''allow_newly_played'')::boolean, false) is not true then raise exception ''이번 턴에 등장한 캐릭터는 기본적으로 행동할 수 없습니다. 효과 예외 옵션을 켜 주세요.''; end if;';
  IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'Cannot locate newly played investigate guard'; END IF;

  v_replacement := $guard$
if coalesce((v_card ->> 'summoned_this_turn')::boolean, false)
   and coalesce((p_payload ->> 'allow_newly_played')::boolean, false) is not true
   and NOT EXISTS (
     SELECT 1
     FROM jsonb_array_elements(
       coalesce(v_card->'dsl_keywords','[]'::jsonb)
       || coalesce(v_card->'dsl_continuous_keywords','[]'::jsonb)
     ) k(value)
     WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
       IN ('charge_case','돌격[사건]','돌격［事件］','突撃[事件]','突撃［事件］')
   ) then
  raise exception '이번 턴에 등장한 캐릭터는 기본적으로 추리할 수 없습니다.';
end if;
$guard$;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  EXECUTE v_definition;
END
$migration$;
