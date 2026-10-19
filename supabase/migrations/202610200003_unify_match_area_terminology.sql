-- Keep Korean user-facing match-area messages consistent with the site's "에이리어" terminology.
-- This rewrites only known match RPC function definitions; no card/game data is changed.

DO $unify_match_area_terminology$
DECLARE
  v_signature text;
  v_definition text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.auto_store_departed_mr_partner_v2(uuid,uuid,jsonb)',
    'public.remove_replaced_mr_partner_on_new_mr_v2(uuid,uuid,text)',
    'public.move_private_mr_partner_to_zone_v1(uuid,uuid,text,text)',
    'public.move_private_field_mr_to_partner_v1(uuid,uuid,text)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
      CONTINUE;
    END IF;

    SELECT pg_get_functiondef(to_regprocedure(v_signature))
      INTO v_definition;

    IF v_definition IS NOT NULL AND position('영역' IN v_definition) > 0 THEN
      v_definition := replace(v_definition, '영역', '에이리어');
      EXECUTE v_definition;
    END IF;
  END LOOP;
END
$unify_match_area_terminology$;
