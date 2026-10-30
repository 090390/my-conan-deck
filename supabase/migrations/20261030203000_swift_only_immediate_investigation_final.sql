-- Immediate investigation is granted by [신속], not by [돌격[사건]].
do $$
declare
  v_def text;
  v_old text := $old$IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')$old$;
  v_new text := $new$IN ('haya','swift','신속','질풍','疾風')$new$;
begin
  v_def := pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure);
  if position(v_old in v_def)=0 then
    raise exception 'Legacy immediate investigation charge-case predicate not found';
  end if;
  execute replace(v_def,v_old,v_new);

  v_def := pg_get_functiondef('public.perform_private_ai_turn_action_v1(uuid,text,jsonb)'::regprocedure);
  if position(v_old in v_def)=0 then
    raise exception 'AI immediate investigation charge-case predicate not found';
  end if;
  execute replace(v_def,v_old,v_new);
end $$;
