-- Preserve variables in recursive allOf/anyOf/not card filter branches.
CREATE OR REPLACE FUNCTION public.private_card_effect_filter_matches_with_vars_v1(p_room_id uuid, p_card jsonb, p_owner_user uuid, p_source_user uuid, p_filter jsonb, p_vars jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE part jsonb; f text; op text; expected jsonb; actual jsonb; v_num numeric;
BEGIN
 IF p_filter IS NULL OR jsonb_typeof(p_filter)<>'object' OR p_filter='{}'::jsonb THEN RETURN true; END IF;
 IF p_filter ? 'allOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'allOf') LOOP
    IF NOT public.private_card_effect_filter_matches_with_vars_v1(p_room_id,p_card,p_owner_user,p_source_user,part,p_vars) THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
 END IF;
 IF p_filter ? 'anyOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'anyOf') LOOP
    IF public.private_card_effect_filter_matches_with_vars_v1(p_room_id,p_card,p_owner_user,p_source_user,part,p_vars) THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
 END IF;
 IF p_filter ? 'not' THEN
   RETURN NOT public.private_card_effect_filter_matches_with_vars_v1(p_room_id,p_card,p_owner_user,p_source_user,p_filter->'not',p_vars);
 END IF;
 f:=p_filter->>'field'; op:=p_filter->>'operator'; expected:=p_filter->'value';
 IF jsonb_typeof(expected)='object' AND expected ? 'fact' THEN
   expected:=public.private_card_effect_fact_v1(p_room_id,p_owner_user,p_source_user,p_card,'{}'::jsonb,coalesce(p_vars,'{}'::jsonb),expected->>'fact');
 END IF;
 actual:='null'::jsonb;
 CASE f
  WHEN 'card_type' THEN actual:=to_jsonb(CASE WHEN public.private_card_effect_is_character_v1(p_card) THEN 'character' ELSE lower(coalesce(p_card->>'card_type',p_card->>'type','')) END);
  WHEN 'level' THEN actual:=to_jsonb(public.private_card_effect_level_v1(p_card));
  WHEN 'color' THEN actual:=to_jsonb(public.private_card_effect_color_v1(p_card));
  WHEN 'card_name' THEN
    IF op='name_matches' THEN RETURN public.private_card_effect_name_matches_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_name_v1(p_card));
  WHEN 'card_id' THEN actual:=coalesce(p_card->'card_id',p_card->'cardId',p_card->'database_id',p_card->'databaseId',p_card->'card_num',p_card->'cardNum',p_card->'key',p_card->'id','null'::jsonb);
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
 IF op='not_equals' THEN RETURN actual IS DISTINCT FROM expected; END IF;
 IF op='in' THEN RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(expected,'[]'::jsonb)) e(value) WHERE e.value=actual); END IF;
 IF op='less_than' THEN RETURN (actual#>>'{}')::numeric < (expected#>>'{}')::numeric; END IF;
 IF op='less_than_or_equal' THEN RETURN (actual#>>'{}')::numeric <= (expected#>>'{}')::numeric; END IF;
 IF op='greater_than' THEN RETURN (actual#>>'{}')::numeric > (expected#>>'{}')::numeric; END IF;
 IF op='greater_than_or_equal' THEN RETURN (actual#>>'{}')::numeric >= (expected#>>'{}')::numeric; END IF;
 RETURN false;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN false;
END
$function$
;
DO $$
DECLARE v_vars jsonb := '{"to_hand":[{"card":{"instance_id":"top-1"}}]}'::jsonb;
BEGIN
  IF public.private_card_effect_filter_matches_with_vars_v1(
    NULL,'{"instance_id":"top-1","card_type":"character"}'::jsonb,NULL,NULL,
    '{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"instance_id","value":{"fact":"vars.to_hand.0.card.instance_id"},"operator":"not_equals"}]}'::jsonb,
    v_vars
  ) THEN
    RAISE EXCEPTION 'allOf filter must preserve p_vars and exclude the selected card';
  END IF;

  IF NOT public.private_card_effect_filter_matches_with_vars_v1(
    NULL,'{"instance_id":"top-2","card_type":"character"}'::jsonb,NULL,NULL,
    '{"allOf":[{"field":"card_type","value":"character","operator":"equals"},{"field":"instance_id","value":{"fact":"vars.to_hand.0.card.instance_id"},"operator":"not_equals"}]}'::jsonb,
    v_vars
  ) THEN
    RAISE EXCEPTION 'allOf filter must keep the different card eligible';
  END IF;

  IF NOT public.private_card_effect_filter_matches_with_vars_v1(
    NULL,'{"instance_id":"top-2","card_type":"character"}'::jsonb,NULL,NULL,
    '{"anyOf":[{"field":"card_type","value":"event","operator":"equals"},{"field":"instance_id","value":{"fact":"vars.to_hand.0.card.instance_id"},"operator":"not_equals"}]}'::jsonb,
    v_vars
  ) THEN
    RAISE EXCEPTION 'anyOf filter must preserve p_vars';
  END IF;

  IF NOT public.private_card_effect_filter_matches_with_vars_v1(
    NULL,'{"instance_id":"top-1","card_type":"character"}'::jsonb,NULL,NULL,
    '{"not":{"field":"instance_id","value":{"fact":"vars.to_hand.0.card.instance_id"},"operator":"not_equals"}}'::jsonb,
    v_vars
  ) THEN
    RAISE EXCEPTION 'not filter must preserve p_vars';
  END IF;

  IF public.private_card_effect_filter_matches_with_vars_v1(
    NULL,'{"instance_id":"top-2","card_type":"character"}'::jsonb,NULL,NULL,
    '{"not":{"field":"instance_id","value":{"fact":"vars.to_hand.0.card.instance_id"},"operator":"not_equals"}}'::jsonb,
    v_vars
  ) THEN
    RAISE EXCEPTION 'not filter must exclude a different card';
  END IF;
END $$;
