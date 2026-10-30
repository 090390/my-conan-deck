-- SP009's top-three remove is optional. B06084 MR can activate its declared ability from the partner area.
-- Finish two Matsuda-deck definition details: optional SP009 mill and B06084 MR partner-area activation.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN d->>'effectId'='card-0619-on-enter-remove-top-three-police-charge' THEN
        jsonb_set(
          d,
          '{steps}',
          jsonb_build_array(
            jsonb_build_object(
              'op','offer_reaction',
              'saveAs','remove_top_three',
              'choices',jsonb_build_array('yes','no'),
              'prompt','덱 위 3장을 리무브할까요? 리무브한 카드 중 경찰 캐릭터가 있으면 턴 종료 시까지 돌격을 얻습니다.'
            ),
            jsonb_set(
              d->'steps'->0,
              '{when}',
              jsonb_build_object('fact','vars.remove_top_three','operator','equals','value','yes'),
              true
            ),
            jsonb_set(
              d->'steps'->1,
              '{when}',
              jsonb_build_object('fact','vars.remove_top_three','operator','equals','value','yes'),
              true
            ),
            jsonb_set(
              d->'steps'->2,
              '{when}',
              jsonb_build_object('fact','vars.remove_top_three','operator','equals','value','yes'),
              true
            ),
            d->'steps'->3
          ),
          true
        )
      WHEN d->>'effectId'='card-0703-activated-investigate-one' THEN
        d || jsonb_build_object('allowPartnerArea',true)
      ELSE d
    END
    ORDER BY e.ordinality
  )
  FROM jsonb_array_elements(c.definitions) WITH ORDINALITY e(d,ordinality)
)
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(c.definitions) d
    WHERE d->>'effectId' IN (
      'card-0619-on-enter-remove-top-three-police-charge',
      'card-0703-activated-investigate-one'
    )
  );
