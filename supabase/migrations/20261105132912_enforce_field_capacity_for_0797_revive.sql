BEGIN;
CREATE OR REPLACE FUNCTION public.private_card_effect_fact_v1(
 p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb,
 p_context jsonb, p_vars jsonb, p_fact text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_match public.room_match_states%rowtype; v_game public.room_player_game_states%rowtype;
 v_board public.room_player_turn_boards%rowtype; v_other_game public.room_player_game_states%rowtype;
 v_cards jsonb; v_result jsonb; v_kw text; v_path text[]; v_bool boolean; v_count integer;
BEGIN
 SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_other_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id<>p_actor ORDER BY seat LIMIT 1;
 IF p_fact='player.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.field.character.count' THEN
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
   WHERE public.private_card_effect_is_character_v1(e.value);
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='opponent.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_other_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.deck.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb))); END IF;
 IF p_fact='player.partner.color' THEN RETURN to_jsonb(public.private_card_effect_partner_color_v1(p_room_id,p_actor)); END IF;
 IF p_fact='turn.is_source_controller_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id=p_source_user); END IF;
 IF p_fact='turn.is_opponent_turn' THEN RETURN to_jsonb(v_match.current_turn_user_id IS DISTINCT FROM p_source_user); END IF;
 IF p_fact='entry.method' THEN RETURN coalesce(p_context#>'{entry,method}','null'::jsonb); END IF;
 IF p_fact='entry.is_first_character_this_turn' THEN RETURN coalesce(p_context#>'{entry,is_first_character_this_turn}','false'::jsonb); END IF;
 IF p_fact='entry.source.level' THEN RETURN to_jsonb(public.private_card_effect_level_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb))); END IF;
 IF p_fact='entry.source.card_type' THEN RETURN coalesce(p_context#>'{entry,source,card_type}',p_context#>'{entry,source,type}','null'::jsonb); END IF;
 IF p_fact='source.status' THEN
   RETURN to_jsonb(coalesce(p_source_card->>'status',CASE WHEN coalesce((p_source_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END));
 END IF;
 IF p_fact='source.is_active' THEN RETURN to_jsonb(public.private_card_effect_is_active_v1(p_source_card)); END IF;
 IF p_fact='source.under_cards.count' THEN
   RETURN to_jsonb(jsonb_array_length(coalesce(p_source_card->'stacked_cards',p_source_card->'under_cards','[]'::jsonb)));
 END IF;
 IF p_fact='player.field.has_card_name' THEN RETURN 'null'::jsonb; END IF;
 IF p_fact='player.remove_area.count_matching_trait' THEN RETURN 'null'::jsonb; END IF;
 IF p_fact LIKE 'player.field.has_keyword.%' THEN
   v_kw := substr(p_fact,length('player.field.has_keyword.')+1);
   SELECT EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     WHERE public.private_card_effect_has_keyword_v1(e.value,v_kw)
   ) INTO v_bool;
   RETURN to_jsonb(v_bool);
 END IF;
 IF p_fact LIKE 'vars.%' THEN
   v_path := string_to_array(substr(p_fact,6),'.');
   IF array_length(v_path,1)>1 AND v_path[array_length(v_path,1)]='count' THEN
     v_path := v_path[1:array_length(v_path,1)-1];
     v_result := p_vars #> v_path;
     IF jsonb_typeof(v_result)='array' THEN RETURN to_jsonb(jsonb_array_length(v_result)); END IF;
     IF jsonb_typeof(v_result)='object' THEN RETURN to_jsonb((SELECT count(*) FROM jsonb_object_keys(v_result))); END IF;
     RETURN to_jsonb(0);
   END IF;
   IF p_fact LIKE 'vars.%.has_level_at_least_8' THEN
     v_path := string_to_array(substr(p_fact,6),'.');
     v_path := v_path[1:array_length(v_path,1)-1];
     v_cards := p_vars #> v_path;
     RETURN to_jsonb(EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_level_v1(coalesce(e.value->'card',e.value))>=8));
   END IF;
   RETURN coalesce(p_vars #> v_path,'null'::jsonb);
 END IF;
 RETURN 'null'::jsonb;
END
$function$;
UPDATE public.private_card_effect_catalog_v1 c
SET definitions=(SELECT coalesce(jsonb_agg(CASE WHEN e.value->>'effectId'='card-0797-on-enter-revive-red-level5' THEN jsonb_set(e.value,'{steps}',$steps$[{"op":"filter_cards","from":"remove_area","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":5}]},"saveAs":"available_deployments"},{"op":"offer_reaction","reactionId":"card-0797-revive-red-level5","actor":"controller","choices":["yes","no"],"saveAs":"revive_choice","when":{"allOf":[{"fact":"vars.available_deployments.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}]},"prompt":"하네다 슈키치를 슬립시키고 손패 1장을 리무브해 적 레벨 5 이하 캐릭터를 재등장시킬까요?"},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"},"prompt":"비용으로 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"field","targetController":"self","min":1,"max":1,"optional":false,"saveAs":"field_slot_cost","filter":{"field":"card_type","operator":"equals","value":"character"},"prompt":"현장이 캐릭터 5장으로 가득 찼습니다. 재등장 자리를 만들기 위해 자신의 현장 캐릭터 1장을 리무브하세요.","when":{"fact":"player.field.character.count","operator":"greater_than_or_equal","value":5}},{"op":"move_cards","from":"field_slot_cost","to":"remove_area","when":{"fact":"player.field.character.count","operator":"greater_than_or_equal","value":5}},{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"deployment","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":5}]},"prompt":"리무브 에이리어에서 레벨 5 이하 적 캐릭터를 최대 1장 선택해 등장시키세요."},{"op":"move_cards","from":"deployment","to":"field","entryMethod":"character_ability","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]}},{"op":"rest_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]}},{"op":"ready_source_character","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}},{"op":"ready_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}}]$steps$::jsonb,true) ELSE e.value END ORDER BY e.ordinality),'[]'::jsonb) FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)),updated_at=now()
WHERE c.catalog_id='main' AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) x(value) WHERE x.value->>'effectId'='card-0797-on-enter-revive-red-level5');
COMMIT;
