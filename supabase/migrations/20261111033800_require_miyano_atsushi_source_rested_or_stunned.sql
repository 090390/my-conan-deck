BEGIN;

-- ID:1228 may be activated only while Miyano Atsushi himself is rested or stunned.
CREATE OR REPLACE FUNCTION public.private_card_effect_source_is_rested_or_stunned_v1(p_card jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT
    coalesce((p_card->>'rested')::boolean,false)
    OR coalesce((p_card->>'is_rested')::boolean,false)
    OR coalesce((p_card->>'sleeping')::boolean,false)
    OR coalesce((p_card->>'is_sleeping')::boolean,false)
    OR lower(coalesce(p_card->>'status','')) IN (
      'rested','sleep','slumber','sleeping','슬립','スリープ',
      'stunned','stun','스턴','スタン'
    )
    OR coalesce((p_card->>'stunned')::boolean,false)
    OR coalesce((p_card->>'stun')::boolean,false)
    OR coalesce((p_card->>'is_stunned')::boolean,false)
$function$;
REVOKE ALL ON FUNCTION public.private_card_effect_source_is_rested_or_stunned_v1(jsonb) FROM PUBLIC,anon,authenticated;

-- The manual activation list must not offer the ability while its source is active.
DO $patch_manual_activations$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.get_private_card_effect_activations_v1(uuid)'::regprocedure) INTO v_source;
  v_old:=$old$AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)$old$;
  v_new:=$new$AND (
         NOT coalesce((value->>'requiresRestedOrStunnedSource')::boolean,false)
         OR public.private_card_effect_source_is_rested_or_stunned_v1(v_card)
       )
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'ID1228 manual activation filter anchor not found'; END IF;
  v_source:=replace(v_source,v_old,v_new);
  EXECUTE v_source;
END
$patch_manual_activations$;

-- The AI activation feed uses the same explicit source-state restriction.
DO $patch_ai_activations$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure) INTO v_source;
  v_old:=$old$AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)$old$;
  v_new:=$new$AND (
         NOT coalesce((d.value->>'requiresRestedOrStunnedSource')::boolean,false)
         OR public.private_card_effect_source_is_rested_or_stunned_v1(v_card)
       )
       AND NOT coalesce((v_card->>'dsl_original_abilities_disabled')::boolean,false)$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'ID1228 AI activation filter anchor not found'; END IF;
  v_source:=replace(v_source,v_old,v_new);
  EXECUTE v_source;
END
$patch_ai_activations$;

-- Server-side validation prevents direct RPC calls from bypassing the UI gate.
DO $patch_turn_action$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure) INTO v_source;
  v_old:=$old$IF v_effect_definition IS NULL THEN RAISE EXCEPTION '이 캐릭터에 등록된 효과를 찾을 수 없습니다.'; END IF;$old$;
  v_new:=$new$IF v_effect_definition IS NULL THEN RAISE EXCEPTION '이 캐릭터에 등록된 효과를 찾을 수 없습니다.'; END IF;
   IF coalesce((v_effect_definition->>'requiresRestedOrStunnedSource')::boolean,false)
      AND NOT public.private_card_effect_source_is_rested_or_stunned_v1(v_source_card) THEN
     RAISE EXCEPTION '미야노 아츠시의 이 능력은 본인이 슬립 또는 스턴 상태일 때만 선언할 수 있습니다.';
   END IF;$new$;
  IF position(v_old in v_source)=0 THEN RAISE EXCEPTION 'ID1228 turn-action validation anchor not found'; END IF;
  EXECUTE replace(v_source,v_old,v_new);
END
$patch_turn_action$;

-- Store the new declarative restriction with the card effect definition.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(
  SELECT coalesce(jsonb_agg(
    CASE WHEN d.value->>'effectId'='card-1228-activated-remove-ap-eight-thousand-rested-or-stunned-source'
      THEN jsonb_set(d.value,'{requiresRestedOrStunnedSource}','true'::jsonb,true)
      ELSE d.value
    END ORDER BY d.ordinality
  ),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
),updated_at=now()
WHERE c.catalog_id='main';

COMMIT;
