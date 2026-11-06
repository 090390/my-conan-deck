-- Do not describe Charge[Case] as an immediate-investigation exception.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$자신의 메인 단계 또는 돌격[사건]의 즉시 추리에서만 추리할 수 있습니다.$old$;
  v_new text := $new$자신의 메인 단계가 아니면 해당 카드의 별도 즉시 추리 효과가 필요합니다.$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION 'Cannot find the outdated investigate error message';
  END IF;

  v_definition := replace(v_definition,v_old,v_new);
  EXECUTE v_definition;
END
$migration$;
