-- [신속]만 등장 턴 즉시 추리를 허용한다.
-- [돌격[사건]]은 상대 증거 에이리어 공격용이며 추리 예외가 아니다.
-- 기존의 ID:0390 크로스턴 특례와 [신속]의 상대 턴 처리는 유지한다.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$IN ('charge_case','돌격[사건]','돌격［事件］','突撃[事件]','突撃［事件］')$old$;
  v_new text := $new$IN ('haya','swift','신속','迅速','질풍','疾風')$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Cannot find the legacy same-turn Charge[Case] investigate exception';
  END IF;

  v_definition := replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$migration$;
