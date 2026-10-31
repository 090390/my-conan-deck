-- Keep all rest effects from selecting characters that are already resting/stunned.
-- Kaito Kid's ready-source activated ability remains usable from a rested state,
-- but no other activated ability is unlocked for a resting/stunned source.

BEGIN;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE WHEN e.value->>'effectId' IN (
      'card-0211-hirameki-rest-character',
      'card-0691-hirameki-rest-character',
      'card-0704-hirameki-rest-character',
      'card-1197-activated-ready-ap-minus2000-and-rest-character'
    ) THEN jsonb_set(
      e.value,
      '{steps}',
      (
        SELECT jsonb_agg(
          CASE WHEN s.value->>'op'='select_cards'
            AND s.value->>'saveAs' IN ('hirameki_target','rest_target')
            AND s.value->>'from'='both_fields'
            AND NOT coalesce(s.value->'filter'->'allOf','[]'::jsonb)
              @> '[{"field":"is_active","operator":"equals","value":true}]'::jsonb
          THEN jsonb_set(
            s.value,
            '{filter}',
            jsonb_build_object(
              'allOf',
              jsonb_build_array(
                coalesce(s.value->'filter','{}'::jsonb),
                jsonb_build_object('field','is_active','operator','equals','value',true)
              )
            ),
            true
          )
          ELSE s.value END
          ORDER BY s.ordinality
        )
        FROM jsonb_array_elements(coalesce(e.value->'steps','[]'::jsonb))
          WITH ORDINALITY s(value,ordinality)
      ),
      true
    )
    ELSE e.value END
    ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(value,ordinality)
)
WHERE c.catalog_id='main';

DO $patch$
DECLARE
  v_def text;
  v_old_guard text := $old$IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;$old$;
  v_human_where text := $human$WHERE value->'trigger'->>'event'='character.activated_ability'
        AND (
          public.private_card_effect_is_active_v1(v_card)
          OR (
            EXISTS (
              SELECT 1
              FROM jsonb_array_elements(coalesce(value->'steps','[]'::jsonb)) step(value)
              WHERE step.value->>'op'='ready_source_character'
            )
            AND (
              coalesce((v_card->>'rested')::boolean,false)
              OR lower(coalesce(v_card->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
            )
            AND NOT (
              coalesce((v_card->>'stunned')::boolean,false)
              OR coalesce((v_card->>'stun')::boolean,false)
              OR coalesce((v_card->>'is_stunned')::boolean,false)
              OR lower(coalesce(v_card->>'status','')) IN ('stunned','stun','스턴')
            )
          )
        )
$human$;
  v_ai_where text := $ai$WHERE d.value->'trigger'->>'event' = 'character.activated_ability'
       AND (
         public.private_card_effect_is_active_v1(v_card)
         OR (
           EXISTS (
             SELECT 1
             FROM jsonb_array_elements(coalesce(d.value->'steps','[]'::jsonb)) step(value)
             WHERE step.value->>'op'='ready_source_character'
           )
           AND (
             coalesce((v_card->>'rested')::boolean,false)
             OR lower(coalesce(v_card->>'status','')) IN ('rested','sleep','slumber','sleeping','슬립')
           )
           AND NOT (
             coalesce((v_card->>'stunned')::boolean,false)
             OR coalesce((v_card->>'stun')::boolean,false)
             OR coalesce((v_card->>'is_stunned')::boolean,false)
             OR lower(coalesce(v_card->>'status','')) IN ('stunned','stun','스턴')
           )
         )
       )
$ai$;
BEGIN
  SELECT pg_get_functiondef('public.get_private_card_effect_activations_v1(uuid)'::regprocedure)
    INTO v_def;

  IF position('ready_source_character' IN v_def)=0 THEN
    v_def:=replace(v_def,v_old_guard,'');
    v_def:=replace(
      v_def,
      $where$WHERE value->'trigger'->>'event'='character.activated_ability'
$where$,
      v_human_where
    );
    EXECUTE v_def;
  END IF;

  SELECT pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure)
    INTO v_def;

  IF position('ready_source_character' IN v_def)=0 THEN
    v_def:=replace(v_def,v_old_guard,'');
    v_def:=replace(
      v_def,
      $where$WHERE d.value->'trigger'->>'event' = 'character.activated_ability'
$where$,
      v_ai_where
    );
    EXECUTE v_def;
  END IF;
END
$patch$;

COMMIT;
