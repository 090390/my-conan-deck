BEGIN;

-- ID:0798's FILE8 ability pays a real sleep cost. The final three DSL steps
-- incorrectly rested the revived character, then readied both it and the source.
-- Keep only the printed cost, hand/file removal, selection, and deployment.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(
  SELECT coalesce(jsonb_agg(
    CASE WHEN d.value->>'effectId'='card-0798-activated-revive-red-from-remove-file8' THEN
      jsonb_set(
        d.value,
        '{steps}',
        coalesce((
          SELECT jsonb_agg(s.value ORDER BY s.ordinality)
          FROM jsonb_array_elements(coalesce(d.value->'steps','[]'::jsonb))
            WITH ORDINALITY s(value,ordinality)
          WHERE s.ordinality<=6
        ),'[]'::jsonb),
        true
      ) || jsonb_build_object(
        'reviewNotes', jsonb_build_object(
          'interpretation','FILE8 비용으로 혼도 히데미 본인을 슬립시키고, 손패 1장과 FILE 맨 위 카드 1장을 리무브한 뒤 리무브 에이리어의 레벨 7 이하 적 캐릭터를 최대 1장 액티브 상태로 등장시킵니다. 이 효과는 혼도 히데미를 다시 액티브로 만들거나 등장 캐릭터를 슬립시키지 않습니다.'
        )
      )
    ELSE d.value END
    ORDER BY d.ordinality
  ),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
    WITH ORDINALITY d(value,ordinality)
),updated_at=now()
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) x(value)
    WHERE x.value->>'effectId'='card-0798-activated-revive-red-from-remove-file8'
  );

COMMIT;