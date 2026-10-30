-- Correct step indexes for the opponent-field selectors; preserve the following move_cards source variable.
UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT jsonb_agg(
    CASE
      WHEN d->>'effectId' IN (
        'card-0808-on-enter-remove-level7',
        'card-1124-on-enter-remove-ap8000'
      ) THEN
        jsonb_set(
          jsonb_set(d,'{steps,0,from}',to_jsonb('opponent_field'::text),true),
          '{steps,1,from}',to_jsonb('target'::text),true
        )
      WHEN d->>'effectId'='card-0703-on-enter-partner-yellow-reveal-and-remove' THEN
        jsonb_set(d,'{steps,1,from}',to_jsonb('opponent_field'::text),true)
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
    'card-0703-on-enter-partner-yellow-reveal-and-remove',
    'card-0808-on-enter-remove-level7',
    'card-1124-on-enter-remove-ap8000'
  )
);
