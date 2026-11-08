-- ID:0356: the field-capacity replacement removes even an already-stunned target.
DO $migration$
DECLARE
  v_definition_count integer;
  v_steps jsonb := $steps$[
    {
      "op":"select_cards",
      "from":"opponent_field",
      "min":0,
      "max":1,
      "optional":true,
      "saveAs":"remove_target",
      "when":{"fact":"player.field.character.count","operator":"greater_than_or_equal","value":5},
      "filter":{"field":"card_type","operator":"equals","value":"character"},
      "prompt":"리무브할 상대 캐릭터를 최대 1장 선택하세요."
    },
    {
      "op":"select_cards",
      "from":"opponent_field",
      "min":0,
      "max":1,
      "optional":true,
      "saveAs":"stun_target",
      "when":{"fact":"player.field.character.count","operator":"less_than","value":5},
      "filter":{"allOf":[
        {"field":"card_type","operator":"equals","value":"character"},
        {"not":{"field":"status","operator":"equals","value":"stunned"}}
      ]},
      "prompt":"스턴할 상대 캐릭터를 최대 1장 선택하세요."
    },
    {
      "op":"move_cards",
      "from":"remove_target",
      "to":"remove_area",
      "targetOwner":"opponent",
      "when":{"allOf":[
        {"fact":"vars.remove_target.count","operator":"greater_than","value":0},
        {"fact":"player.field.character.count","operator":"greater_than_or_equal","value":5}
      ]}
    },
    {
      "op":"stun_cards",
      "target":"stun_target",
      "when":{"allOf":[
        {"fact":"vars.stun_target.count","operator":"greater_than","value":0},
        {"fact":"player.field.character.count","operator":"less_than","value":5}
      ]}
    }
  ]$steps$::jsonb;
BEGIN
  SELECT count(*) INTO v_definition_count
  FROM public.private_card_effect_catalog_v1 c,
       jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
  WHERE c.catalog_id='main'
    AND d.value->>'effectId'='card-0356-event-stun-or-remove-character';

  IF v_definition_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one ID:0356 effect definition, found %', v_definition_count;
  END IF;

  UPDATE public.private_card_effect_catalog_v1 c
  SET definitions=(
    SELECT jsonb_agg(
      CASE WHEN d.value->>'effectId'='card-0356-event-stun-or-remove-character'
        THEN jsonb_set(d.value,'{steps}',v_steps,false)
        ELSE d.value
      END
      ORDER BY d.ordinality
    )
    FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
         WITH ORDINALITY d(value,ordinality)
  ),
  updated_at=now()
  WHERE c.catalog_id='main';
END
$migration$;
