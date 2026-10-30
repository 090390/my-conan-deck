-- Only [신속] (haya/swift) permits an immediate investigation; [돌격] is attack-only.
do $$
declare
  v_def text;
  v_old text := "IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')";
  v_new text := "IN ('haya','swift','신속','질풍','疾風')";
begin
  v_def := pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'Legacy investigate timing predicate was not found';
  end if;
  execute replace(v_def, v_old, v_new);

  v_def := pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure);
  if position(v_old in v_def) = 0 then
    raise exception 'AI investigate timing predicate was not found';
  end if;
  execute replace(v_def, v_old, v_new);
end $$;
