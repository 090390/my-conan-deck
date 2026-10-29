-- Fix service-role detection when PostgREST exposes the role in request.jwt.claims JSON.
-- Keep this server-only RPC inaccessible to anon/authenticated callers.
CREATE OR REPLACE FUNCTION public.get_private_ai_card_effect_activations_v1(p_room_id uuid, p_ai_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_catalog jsonb;
 v_board public.room_player_turn_boards%rowtype;
 v_card jsonb;
 v_def jsonb;
 v_used jsonb;
 v_turn integer;
 v_items jsonb := '[]'::jsonb;
 v_context jsonb := '{}'::jsonb;
 v_claim_role text;
 v_claims text;
BEGIN
 v_claim_role := coalesce(current_setting('request.jwt.claim.role', true), '');
 v_claims := nullif(current_setting('request.jwt.claims', true), '');
 IF v_claim_role <> 'service_role'
    AND coalesce((v_claims::jsonb ->> 'role'), '') <> 'service_role' THEN
   RAISE EXCEPTION 'AI 능력 목록은 서버에서만 조회할 수 있습니다.';
 END IF;

 IF NOT EXISTS (
   SELECT 1 FROM public.private_ai_battles b
   WHERE b.room_id = p_room_id AND b.ai_user_id = p_ai_user_id
 ) THEN
   RAISE EXCEPTION 'AI 대전 정보를 찾을 수 없습니다.';
 END IF;

 SELECT m.turn_number INTO v_turn
 FROM public.room_match_states m
 WHERE m.room_id = p_room_id
   AND m.current_turn_user_id = p_ai_user_id
   AND m.phase = 'playing'
   AND NOT m.game_over
   AND m.turn_step IN ('file', 'main')
   AND m.pending_action IS NULL;

 IF NOT FOUND OR EXISTS (
   SELECT 1 FROM public.private_card_effect_runs_v1 r WHERE r.room_id = p_room_id
 ) THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb);
 END IF;

 SELECT definitions INTO v_catalog
 FROM public.private_card_effect_catalog_v1
 WHERE catalog_id = 'main';

 SELECT * INTO v_board
 FROM public.room_player_turn_boards
 WHERE room_id = p_room_id AND user_id = p_ai_user_id;

 IF NOT FOUND THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb);
 END IF;

 FOR v_card IN
   SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb))
 LOOP
   FOR v_def IN
     SELECT d.value
     FROM jsonb_array_elements(coalesce(v_catalog, '[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event' = 'character.activated_ability'
       AND NOT coalesce((d.value->>'continuous')::boolean, false)
       AND public.private_card_effect_matches_id_v1(v_card, coalesce(d.value->'cardIds', '[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean, false) THEN
       v_used := coalesce(v_card->'dsl_effect_uses', '[]'::jsonb);
       IF EXISTS (
         SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id' = v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number', '')::integer, -1) = v_turn
       ) THEN
         CONTINUE;
       END IF;
     END IF;

     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id, p_ai_user_id, p_ai_user_id, v_card, v_context, '{}'::jsonb,
       coalesce(v_def->'conditions', '[]'::jsonb)
     ) THEN
       CONTINUE;
     END IF;

     v_items := v_items || jsonb_build_array(jsonb_build_object(
       'source_instance_id', v_card->>'instance_id',
       'effect_id', v_def->>'effectId',
       'label', coalesce(v_def->>'activationLabelKo', v_def->>'effectId', '카드 효과'),
       'definition', v_def
     ));
   END LOOP;
 END LOOP;

 RETURN jsonb_build_object('activations', v_items);
END
$function$;

REVOKE ALL ON FUNCTION public.get_private_ai_card_effect_activations_v1(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_private_ai_card_effect_activations_v1(uuid, uuid) TO service_role;
