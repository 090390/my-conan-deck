-- Add an explicit case-trait fact for B11049P2's Detective vs Kid condition.
BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_fact_v1(p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb, p_context jsonb, p_vars jsonb, p_fact text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_match public.room_match_states%rowtype; v_game public.room_player_game_states%rowtype;
 v_board public.room_player_turn_boards%rowtype; v_other_game public.room_player_game_states%rowtype;
 v_cards jsonb; v_result jsonb; v_kw text; v_path text[]; v_bool boolean;
BEGIN
 SELECT * INTO v_match FROM public.room_match_states WHERE room_id=p_room_id;
 SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
 SELECT * INTO v_other_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id<>p_actor ORDER BY seat LIMIT 1;

 IF p_fact='player.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='opponent.hand.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_other_game.hand,'[]'::jsonb))); END IF;
 IF p_fact='player.deck.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb))); END IF;
 IF p_fact='player.file.count' THEN RETURN to_jsonb(coalesce(v_board.file_count,0)); END IF;
 IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_board.case_phase,v_match.case_phase,'incident'));
 END IF;
 IF p_fact='player.event.has_non_blue_color' THEN
   SELECT d.event_has_non_blue_color INTO v_bool
   FROM public.room_player_decks d
   WHERE d.room_id=p_room_id AND d.user_id=p_actor;
   RETURN coalesce(to_jsonb(v_bool),'null'::jsonb);
 END IF;
 IF p_fact='player.event.has_detective_vs_kid_trait' THEN
   RETURN to_jsonb(coalesce(v_board.event_rule_code,'')='conan_vs_kid_1261');
 END IF;
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
SET definitions = (
 SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality),'[]'::jsonb)
 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
 WHERE e.value->>'effectId' <> 'card-1215-on-play-detective-kid-cycle'
) || $dsldefs$[{"effectId":"card-1215-on-play-detective-kid-cycle","cardIds":["1215"],"cardNameKo":"탐정은 그 흔적을 보고 이래저래 트집을 잡는…… 단순한 비평가에 지나지 않는다고?","cardNameJa":"探偵はその痕跡を見てあれこれ難癖をつける……単なる批評家にすぎないと？","trigger":{"event":"event.played","timing":"after"},"conditions":[{"fact":"player.event.has_detective_vs_kid_trait","operator":"equals","value":true},{"fact":"player.partner.color","operator":"equals","value":"white"}],"steps":[{"op":"draw_cards","count":2,"destination":"hand"},{"op":"select_cards","from":"hand","min":2,"max":2,"optional":false,"prompt":"리무브할 손패 2장을 선택하세요.","saveAs":"hand_to_remove"},{"op":"move_cards","from":"hand_to_remove","to":"remove_area"},{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":7},{"anyOf":[{"field":"color","operator":"equals","value":"blue"},{"field":"color","operator":"equals","value":"white"}]}]},"prompt":"리무브 에이리어에서 등장시킬 레벨 7 이하 청/백 캐릭터를 최대 1장 선택하세요.","saveAs":"character_to_field"},{"op":"move_cards","from":"character_to_field","to":"field","entryMethod":"event_effect","when":{"fact":"vars.character_to_field.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"사건의 특징에 [탐정 VS 괴도]가 있고 파트너 카드의 색상이 백일 경우, 덱에서 카드 2장을 뽑고 손패에서 카드 2장을 리무브한다. 이어서 리무브 에이리어의 레벨 7 이하 청/백 캐릭터를 최대 1장 선택해 등장시킬 수 있다.","rationale":"사건의 특성은 현재 사건 규칙 코드 conan_vs_kid_1261로 판별한다. 드로우 뒤 손패 2장을 리무브하고, 방금 리무브한 카드도 포함한 리무브 에이리어에서 적격 청/백 캐릭터를 선택해 등장시킨다."}}]$dsldefs$::jsonb,
updated_at=now()
WHERE c.catalog_id='main';

COMMIT;
