-- The live catalog stores `definitions` as a JSON array, not as an object
-- containing a nested `definitions` array. Keep chained enter/remove triggers on that shape.
DO $patch_nested_trigger_catalog_shape$
DECLARE
  v_definition text;
  v_old text := $old$jsonb_array_elements(coalesce(v_catalog->'definitions','[]'::jsonb))$old$;
  v_new text := $new$jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb))$new$;
BEGIN
  v_definition:=pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  IF position(v_old in v_definition)>0 THEN
    v_definition:=replace(v_definition,v_old,v_new);
  ELSIF (length(v_definition)-length(replace(v_definition,v_new,''))) / length(v_new) < 2 THEN
    RAISE EXCEPTION 'Nested trigger catalog-shape anchors not found';
  END IF;
  IF position(v_old in v_definition)>0 THEN
    RAISE EXCEPTION 'Nested trigger catalog-shape patch did not replace all occurrences';
  END IF;
  EXECUTE v_definition;
END
$patch_nested_trigger_catalog_shape$;
