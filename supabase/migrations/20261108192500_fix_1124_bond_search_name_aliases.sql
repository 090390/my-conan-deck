DO $migration$
DECLARE
 v_updates jsonb := '[{"steps":[{"op":"peek_top_cards","count":2,"saveAs":"seen","allowFewer":true},{"op":"select_cards","max":1,"min":0,"from":"seen","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"anyOf":[{"field":"card_name","operator":"name_matches","value":"降谷零"},{"field":"card_name","operator":"name_matches","value":"諸伏景光"},{"field":"card_name","operator":"name_matches","value":"伊達航"},{"field":"card_name","operator":"name_matches","value":"萩原研二"},{"field":"card_name","operator":"name_matches","value":"松田陣平"}]}]},"prompt":"공개하여 패에 추가할 경찰학교 동기 캐릭터를 최대 1장 선택하세요.","saveAs":"selected","optional":true,"displayVariable":"seen"},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","value":0,"operator":"greater_than"}},{"op":"move_unselected_to_zone","to":"remove_area","from":"seen","order":"preserve","selectedVariable":"selected"}],"cardIds":["1124"],"trigger":{"event":"player.turn_ended","timing":"after"},"effectId":"card-1124-end-turn-search-police-academy","cardNameJa":"諸伏景光","cardNameKo":"모로후시 히로미츠","conditions":[{"fact":"player.field.has_card_name","value":"降谷零","operator":"equals"}]}]'::jsonb;
BEGIN
 UPDATE public.private_card_effect_catalog_v1 c
 SET definitions=(
   SELECT coalesce(jsonb_agg(
     CASE WHEN u.value IS NOT NULL THEN u.value ELSE d.value END
     ORDER BY d.ordinality
   ),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY d(value,ordinality)
   LEFT JOIN LATERAL (
     SELECT x.value FROM jsonb_array_elements(v_updates) x(value)
     WHERE x.value->>'effectId'=d.value->>'effectId'
   ) u ON true
 ),
 updated_at=now()
 WHERE c.catalog_id='main';
 IF NOT FOUND THEN RAISE EXCEPTION 'main effect catalog is missing'; END IF;
END
$migration$;