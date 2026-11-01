
DO $$
DECLARE v_definition text; v_old text; v_new text;
BEGIN
  v_definition:=pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  v_old:=$old$v_is_stunned:=coalesce((v_current->>'stunned')::boolean,false)
          OR coalesce((v_current->>'stun')::boolean,false)
          OR coalesce((v_current->>'is_stunned')::boolean,false)
          OR lower(coalesce(v_current->>'status','')) IN ('stunned','stun','스턴');$old$;
  v_new:=$new$v_is_stunned:=lower(coalesce(v_current->>'status','')) IN ('stunned','stun','스턴');$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'ready_cards stun-status anchor missing'; END IF;

  v_old:=$old$jsonb_build_object('stunned',true,'stun',true,'is_stunned',true,'rested',false,'status','stunned')$old$;
  v_new:=$new$jsonb_build_object('rested',false,'status','stunned')$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'stun_cards status anchor missing'; END IF;
  EXECUTE v_definition;

  v_definition:=pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure);
  v_old:=$old$else e.value || jsonb_build_object('status','rested','rested',true,'summoned_this_turn',false,'ap_bonus',0)$old$;
  v_new:=$new$else (e.value-'stunned'-'stun'-'is_stunned') || jsonb_build_object('status','rested','rested',true,'summoned_this_turn',false,'ap_bonus',0)$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'ordinary stun expiry cleanup anchor missing'; END IF;

  v_old:=$old$|| jsonb_build_object(
        'rested',true,'status','rested',
        'ap_bonus',coalesce(nullif(v_target->>'ap_bonus','')::numeric,0),$old$;
  v_new:=$new$|| jsonb_build_object(
        'rested',true,'status',CASE
          WHEN lower(coalesce(v_target->>'status','')) IN ('stunned','stun','스턴') THEN 'stunned'
          ELSE 'rested' END,
        'ap_bonus',coalesce(nullif(v_target->>'ap_bonus','')::numeric,0),$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'disguise status-preservation anchor missing'; END IF;

  v_old:=$old$'under_cards',coalesce(v_target->'under_cards','[]'::jsonb),$old$;
  v_new:=$new$'set_cards',coalesce(v_target->'set_cards','[]'::jsonb),
        'under_cards',coalesce(v_target->'under_cards','[]'::jsonb),$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'disguise set-card carry-over anchor missing'; END IF;

  v_old:=$old$'stacked_cards',coalesce(v_target->'stacked_cards','[]'::jsonb),$old$;
  v_new:=$new$'stacked_cards',coalesce(v_target->'stacked_cards','[]'::jsonb),
        'dsl_original_abilities_disabled',coalesce(v_target->'dsl_original_abilities_disabled',false),
        'dsl_original_abilities_disabled_until_turn',v_target->'dsl_original_abilities_disabled_until_turn',$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'disguise suppression carry-over anchor missing'; END IF;

  v_old:=$old$- 'under_cards' - 'stacked_cards' - 'dsl_keywords' - 'dsl_continuous_keywords'$old$;
  v_new:=$new$- 'set_cards' - 'under_cards' - 'stacked_cards' - 'dsl_keywords' - 'dsl_continuous_keywords'
              - 'dsl_original_abilities_disabled' - 'dsl_original_abilities_disabled_until_turn'
              - 'stunned' - 'stun' - 'is_stunned'$new$;
  IF position(v_old in v_definition)>0 THEN v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN RAISE EXCEPTION 'disguise old-card cleanup anchor missing'; END IF;
  EXECUTE v_definition;
END $$;
