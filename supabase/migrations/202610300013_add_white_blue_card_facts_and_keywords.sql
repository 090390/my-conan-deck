CREATE OR REPLACE FUNCTION public.private_card_effect_fact_v1(p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb, p_context jsonb, p_vars jsonb, p_fact text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
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
 IF p_fact='player.evidence.count' THEN RETURN to_jsonb(jsonb_array_length(coalesce(v_game.evidence_cards,'[]'::jsonb))); END IF;
 IF p_fact='player.evidence.facedown_count' THEN
   SELECT count(*)::integer INTO v_count FROM jsonb_array_elements(coalesce(v_game.evidence_cards,'[]'::jsonb)) e(value)
   WHERE NOT coalesce((e.value->>'face_up')::boolean,false);
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='game.total_evidence_count' THEN
   SELECT coalesce(sum(evidence_count),0)::integer INTO v_count FROM public.room_player_turn_boards WHERE room_id=p_room_id;
   RETURN to_jsonb(v_count);
 END IF;
 IF p_fact='turn.number' THEN RETURN to_jsonb(coalesce(v_match.turn_number,0)); END IF;
 IF p_fact='contact.source.ap' THEN
   RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,source_ap}','')::numeric,0));
 END IF;
 IF p_fact='contact.target.ap' THEN
   RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,target_ap}','')::numeric,0));
 END IF;
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
 IF p_fact='entry.source.card_name' THEN
   RETURN coalesce(p_context#>'{entry,source,name}',p_context#>'{entry,source,name_ja}',
     p_context#>'{entry,source,nameJa}',p_context#>'{entry,source,title}',p_context#>'{entry,source,card_name}','null'::jsonb);
 END IF;
 IF p_fact='entry.source.card_id' THEN
   RETURN coalesce(p_context#>'{entry,source,card_id}',p_context#>'{entry,source,cardId}',
     p_context#>'{entry,source,database_id}',p_context#>'{entry,source,databaseId}',
     p_context#>'{entry,source,key}',p_context#>'{entry,source,id}','null'::jsonb);
 END IF;
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
$function$
;

CREATE OR REPLACE FUNCTION public.private_card_effect_condition_matches_v1(p_room_id uuid, p_actor uuid, p_source_user uuid, p_source_card jsonb, p_context jsonb, p_vars jsonb, p_condition jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_fact text:=p_condition->>'fact'; v_op text:=p_condition->>'operator';
 v_actual jsonb; v_expected jsonb; v_bool boolean;
 v_board public.room_player_turn_boards%rowtype; v_game public.room_player_game_states%rowtype;
 v_count integer; v_trait text; v_typ text;
BEGIN
 IF p_condition IS NULL OR jsonb_typeof(p_condition)<>'object' THEN RETURN false; END IF;
 v_expected:=p_condition->'value';
 IF jsonb_typeof(v_expected)='object' AND v_expected ? 'fact' THEN
   v_expected:=public.private_card_effect_fact_v1(p_room_id,p_actor,p_source_user,p_source_card,p_context,p_vars,v_expected->>'fact');
 END IF;

 IF v_fact='player.field.has_card_id' THEN
   SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
   SELECT EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     WHERE public.private_card_effect_matches_id_v1(e.value,jsonb_build_array(trim(both '"' from v_expected::text)))
   ) INTO v_bool;
   v_actual:=to_jsonb(coalesce(v_bool,false));
 ELSIF v_fact='entry.source.card_name' AND v_op='name_matches' THEN
   RETURN public.private_card_effect_name_matches_v1(
     coalesce(p_context#>'{entry,source}','{}'::jsonb),trim(both '"' from v_expected::text)
   );
 ELSIF v_fact='player.field.has_card_name' THEN
   SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=p_actor;
   SELECT EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     WHERE public.private_card_effect_name_matches_v1(e.value,trim(both '"' from v_expected::text))
   ) INTO v_bool;
   IF NOT coalesce(v_bool,false) THEN
     SELECT EXISTS(
       SELECT 1
       FROM jsonb_array_elements(coalesce(p_source_card->'dsl_bond_name_overrides','[]'::jsonb)) x(value)
       WHERE (coalesce((x.value->>'anyName')::boolean,false)
              OR lower(coalesce(x.value->>'name',''))=lower(trim(both '"' from v_expected::text)))
         AND coalesce(nullif(x.value->>'expires_turn_number','')::integer,-1)=
             (SELECT turn_number FROM public.room_match_states WHERE room_id=p_room_id)
     ) INTO v_bool;
   END IF;
   IF v_op='name_matches' THEN RETURN coalesce(v_bool,false); END IF;
   -- Backward compatibility: existing catalog definitions use equals + a card-name string.
   IF jsonb_typeof(v_expected)<>'boolean' THEN RETURN coalesce(v_bool,false); END IF;
   v_actual:=to_jsonb(v_bool);
 ELSIF v_fact='player.remove_area.count_matching_trait' THEN
   SELECT * INTO v_game FROM public.room_player_game_states WHERE room_id=p_room_id AND user_id=p_actor;
   v_trait:=coalesce(p_condition->>'trait','');
   v_typ:=coalesce(p_condition->>'cardType','character');
   SELECT count(*)::integer INTO v_count
   FROM jsonb_array_elements(coalesce(v_game.remove_cards,'[]'::jsonb)) e(value)
   WHERE (v_typ<>'character' OR public.private_card_effect_is_character_v1(e.value))
     AND public.private_card_effect_has_trait_v1(e.value,v_trait);
   v_actual:=to_jsonb(v_count);
 ELSE
   v_actual:=public.private_card_effect_fact_v1(p_room_id,p_actor,p_source_user,p_source_card,p_context,p_vars,v_fact);
 END IF;

 IF v_actual IS NULL OR v_actual='null'::jsonb THEN
   IF v_op='equals' THEN RETURN v_expected='null'::jsonb; END IF;
   RETURN false;
 END IF;
 CASE v_op
  WHEN 'equals' THEN RETURN v_actual=v_expected;
  WHEN 'not_equals' THEN RETURN v_actual IS DISTINCT FROM v_expected;
  WHEN 'name_matches' THEN RETURN false;
  WHEN 'in' THEN RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(v_expected,'[]'::jsonb)) e(value) WHERE e.value=v_actual);
  WHEN 'less_than' THEN RETURN (v_actual #>> '{}')::numeric < (v_expected #>> '{}')::numeric;
  WHEN 'less_than_or_equal' THEN RETURN (v_actual #>> '{}')::numeric <= (v_expected #>> '{}')::numeric;
  WHEN 'greater_than' THEN RETURN (v_actual #>> '{}')::numeric > (v_expected #>> '{}')::numeric;
  WHEN 'greater_than_or_equal' THEN RETURN (v_actual #>> '{}')::numeric >= (v_expected #>> '{}')::numeric;
  ELSE RETURN false;
 END CASE;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
 RETURN false;
END
$function$
;

CREATE OR REPLACE FUNCTION public.private_card_effect_filter_matches_v1(p_room_id uuid, p_card jsonb, p_owner_user uuid, p_source_user uuid, p_filter jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE part jsonb; f text; op text; expected jsonb; actual jsonb; v_num numeric;
BEGIN
 IF p_filter IS NULL OR jsonb_typeof(p_filter)<>'object' THEN RETURN true; END IF;
 IF p_filter ? 'allOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'allOf') LOOP
    IF NOT public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,part) THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
 END IF;
 IF p_filter ? 'anyOf' THEN
  FOR part IN SELECT value FROM jsonb_array_elements(p_filter->'anyOf') LOOP
    IF public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,part) THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
 END IF;
 IF p_filter ? 'not' THEN
   RETURN NOT public.private_card_effect_filter_matches_v1(p_room_id,p_card,p_owner_user,p_source_user,p_filter->'not');
 END IF;
 f:=p_filter->>'field'; op:=p_filter->>'operator'; expected:=p_filter->'value';
 IF jsonb_typeof(expected)='object' AND expected ? 'fact' THEN
   expected:=public.private_card_effect_fact_v1(p_room_id,p_owner_user,p_source_user,p_card,'{}'::jsonb,'{}'::jsonb,expected->>'fact');
 END IF;
 actual:='null'::jsonb;
 CASE f
  WHEN 'card_type' THEN actual:=to_jsonb(CASE WHEN public.private_card_effect_is_character_v1(p_card) THEN 'character' ELSE lower(coalesce(p_card->>'card_type',p_card->>'type','')) END);
  WHEN 'level' THEN actual:=to_jsonb(public.private_card_effect_level_v1(p_card));
  WHEN 'color' THEN actual:=to_jsonb(public.private_card_effect_color_v1(p_card));
  WHEN 'card_name' THEN
    IF op='name_matches' THEN RETURN public.private_card_effect_name_matches_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_name_v1(p_card));
  WHEN 'card_id' THEN actual:=coalesce(p_card->'card_id',p_card->'cardId',p_card->'database_id',p_card->'databaseId',p_card->'card_num',p_card->'cardNum',p_card->'key',p_card->'id','null'::jsonb);
  WHEN 'trait' THEN
    IF op='has_trait' THEN RETURN public.private_card_effect_has_trait_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_has_trait_v1(p_card,trim(both '"' from expected::text)));
  WHEN 'keyword' THEN
    IF op='has_keyword' THEN RETURN public.private_card_effect_has_keyword_v1(p_card,trim(both '"' from expected::text)); END IF;
    actual:=to_jsonb(public.private_card_effect_has_keyword_v1(p_card,trim(both '"' from expected::text)));
  WHEN 'ap_current' THEN actual:=to_jsonb(coalesce(nullif(p_card->>'ap','')::numeric,0)+coalesce(nullif(p_card->>'ap_bonus','')::numeric,0));
  WHEN 'is_active' THEN actual:=to_jsonb(public.private_card_effect_is_active_v1(p_card));
  WHEN 'status' THEN actual:=to_jsonb(coalesce(p_card->>'status',CASE WHEN coalesce((p_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END));
  WHEN 'controller' THEN actual:=to_jsonb(CASE WHEN p_owner_user=p_source_user THEN 'self' ELSE 'opponent' END);
  ELSE actual:=coalesce(p_card->f,'null'::jsonb);
 END CASE;
 IF op='equals' THEN RETURN actual=expected; END IF;
 IF op='not_equals' THEN RETURN actual IS DISTINCT FROM expected; END IF;
 IF op='in' THEN RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(expected,'[]'::jsonb)) e(value) WHERE e.value=actual); END IF;
 IF op='less_than' THEN RETURN (actual#>>'{}')::numeric < (expected#>>'{}')::numeric; END IF;
 IF op='less_than_or_equal' THEN RETURN (actual#>>'{}')::numeric <= (expected#>>'{}')::numeric; END IF;
 IF op='greater_than' THEN RETURN (actual#>>'{}')::numeric > (expected#>>'{}')::numeric; END IF;
 IF op='greater_than_or_equal' THEN RETURN (actual#>>'{}')::numeric >= (expected#>>'{}')::numeric; END IF;
 RETURN false;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN false;
END
$function$
;

CREATE OR REPLACE FUNCTION public.private_card_effect_has_keyword_v1(p_card jsonb, p_keyword text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  j text := lower(coalesce(p_card,'{}'::jsonb)::text);
  k text := lower(coalesce(p_keyword,''));
  v_words jsonb := coalesce(p_card->'dsl_keywords','[]'::jsonb)||coalesce(p_card->'dsl_continuous_keywords','[]'::jsonb);
BEGIN
  IF k IN ('haya','gale','질풍','疾風') THEN
    RETURN position('疾風' in j)>0 OR position('질풍' in j)>0 OR position('haya' in j)>0 OR position('gale' in j)>0
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_words) x(value)
        WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}','')) IN ('haya','gale','질풍','疾風'));
  ELSIF k IN ('charge','돌격','突撃') THEN
    RETURN position('突撃' in j)>0 OR position('돌격' in j)>0 OR position('charge' in j)>0
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_words) x(value)
        WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}','')) IN ('charge','돌격','突撃'));
  ELSIF k IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］') THEN
    RETURN position('突撃［事件］' in j)>0 OR position('突撃[事件]' in j)>0 OR position('돌격[사건]' in j)>0 OR position('돌격［사건］' in j)>0
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_words) x(value)
        WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}','')) IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］'));
  ELSIF k IN ('charge_character','돌격[캐릭터]','돌격［캐릭터］','突撃[キャラ]','突撃［キャラ］') THEN
    RETURN position('突撃［キャラ］' in j)>0 OR position('突撃[キャラ]' in j)>0 OR position('돌격[캐릭터]' in j)>0 OR position('돌격［캐릭터］' in j)>0
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_words) x(value)
        WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}','')) IN ('charge_character','돌격[캐릭터]','돌격［캐릭터］','突撃[キャラ]','突撃［キャラ］'));
  END IF;
  RETURN position(k in j)>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_words) x(value)
    WHERE lower(coalesce(x.value->>'keyword',x.value#>>'{}',''))=k);
END
$function$;