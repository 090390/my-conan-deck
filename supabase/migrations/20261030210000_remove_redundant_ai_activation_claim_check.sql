DO $migration$
DECLARE
  v_definition text;
  v_guard text;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure
  ) INTO v_definition;

  v_guard := $guard$
 v_claim_role := coalesce(current_setting('request.jwt.claim.role', true), '');
 v_claims := nullif(current_setting('request.jwt.claims', true), '');
 IF v_claim_role <> 'service_role'
    AND coalesce((v_claims::jsonb ->> 'role'), '') <> 'service_role' THEN
   RAISE EXCEPTION 'AI 능력 목록은 서버에서만 조회할 수 있습니다.';
 END IF;
$guard$;

  IF position(v_guard IN v_definition) > 0 THEN
    v_definition := replace(v_definition, v_guard, '');
  ELSIF position('AI 능력 목록은 서버에서만 조회할 수 있습니다.' IN v_definition) > 0 THEN
    RAISE EXCEPTION 'AI activation role-check exists but its source pattern differs; refusing unsafe rewrite';
  END IF;

  v_definition := replace(v_definition, E' v_claim_role text;\n v_claims text;', '');
  v_definition := replace(v_definition, E' v_claim_role text;', '');
  v_definition := replace(v_definition, E' v_claims text;', '');

  EXECUTE v_definition;
  REVOKE ALL ON FUNCTION public.get_private_ai_card_effect_activations_v1(uuid,uuid) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.get_private_ai_card_effect_activations_v1(uuid,uuid) TO service_role;
END
$migration$;
