-- Preserve full printed-card identity and effect metadata on every in-game card instance.

CREATE OR REPLACE FUNCTION public.enrich_turn_card_instances(p_cards jsonb, p_main_deck jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT coalesce(jsonb_agg(
    c.card || jsonb_strip_nulls(jsonb_build_object(
      'card_type', coalesce(nullif(d.value ->> 'card_type', ''), nullif(c.card ->> 'card_type', ''), 'unknown'),
      'card_id', coalesce(nullif(c.card ->> 'card_id', ''), nullif(d.value ->> 'card_id', '')),
      'card_num', coalesce(nullif(c.card ->> 'card_num', ''), nullif(d.value ->> 'card_num', '')),
      'database_id', coalesce(nullif(c.card ->> 'database_id', ''), nullif(d.value ->> 'database_id', '')),
      'name', coalesce(nullif(c.card ->> 'name', ''), nullif(d.value ->> 'name', '')),
      'name_ja', coalesce(nullif(c.card ->> 'name_ja', ''), nullif(d.value ->> 'name_ja', '')),
      'color', coalesce(nullif(c.card ->> 'color', ''), nullif(d.value ->> 'color', '')),
      'rarity', coalesce(nullif(c.card ->> 'rarity', ''), nullif(d.value ->> 'rarity', '')),
      'cost', case when coalesce(d.value ->> 'cost', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (d.value ->> 'cost')::numeric else coalesce(nullif(c.card ->> 'cost','')::numeric,0) end,
      'ap', case when coalesce(d.value ->> 'ap', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (d.value ->> 'ap')::numeric else coalesce(nullif(c.card ->> 'ap','')::numeric,0) end,
      'lp', case when coalesce(d.value ->> 'lp', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (d.value ->> 'lp')::numeric else coalesce(nullif(c.card ->> 'lp','')::numeric,0) end,
      'cut_in_bonus', case when coalesce(d.value ->> 'cut_in_bonus', '') ~ '^[0-9]+$' then (d.value ->> 'cut_in_bonus')::integer else coalesce(nullif(c.card ->> 'cut_in_bonus','')::integer,0) end,
      'cut_in_effect', coalesce(nullif(c.card ->> 'cut_in_effect',''), nullif(d.value ->> 'cut_in_effect','')),
      'traits', case when jsonb_typeof(d.value -> 'traits') = 'array' then d.value -> 'traits' else coalesce(c.card -> 'traits','[]'::jsonb) end,
      'category1', coalesce(nullif(d.value ->> 'category1',''), c.card ->> 'category1',''),
      'category2', coalesce(nullif(d.value ->> 'category2',''), c.card ->> 'category2',''),
      'category3', coalesce(nullif(d.value ->> 'category3',''), c.card ->> 'category3','')
    )) order by c.ordinality
  ), '[]'::jsonb)
  FROM jsonb_array_elements(coalesce(p_cards, '[]'::jsonb)) WITH ORDINALITY AS c(card, ordinality)
  LEFT JOIN LATERAL (
    SELECT entry.value
    FROM jsonb_array_elements(coalesce(p_main_deck, '[]'::jsonb)) AS entry(value)
    WHERE entry.value ->> 'key' = c.card ->> 'key'
    LIMIT 1
  ) d ON true;
$function$;

-- Return legal scripted event plays as well as activated field abilities.

CREATE OR REPLACE FUNCTION public.get_private_ai_card_effect_activations_v1(p_room_id uuid, p_ai_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_catalog jsonb;
 v_board public.room_player_turn_boards%rowtype;
 v_card jsonb;
 v_def jsonb;
 v_used jsonb;
 v_turn integer; v_is_own_turn boolean; v_turn_step text;
 v_items jsonb := '[]'::jsonb;
 v_event_items jsonb := '[]'::jsonb;
 v_game public.room_player_game_states%rowtype;
 v_context jsonb := '{}'::jsonb;

 v_case_key text; v_case_id text; v_case_name text; v_case_card jsonb;
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM public.private_ai_battles b
   WHERE b.room_id = p_room_id AND b.ai_user_id = p_ai_user_id
 ) THEN
   RAISE EXCEPTION 'AI 대전 정보를 찾을 수 없습니다.';
 END IF;

 SELECT m.turn_number, m.current_turn_user_id=p_ai_user_id, m.turn_step INTO v_turn, v_is_own_turn, v_turn_step
 FROM public.room_match_states m
 WHERE m.room_id = p_room_id
   
   AND m.phase = 'playing'
   AND NOT m.game_over
   
   AND m.pending_action IS NULL;

 IF NOT FOUND OR (coalesce(v_is_own_turn,false) AND coalesce(v_turn_step,'') NOT IN ('file','main')) OR EXISTS (
   SELECT 1 FROM public.private_card_effect_runs_v1 r WHERE r.room_id = p_room_id
 ) THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb, 'event_candidates', '[]'::jsonb);
 END IF;

 SELECT definitions INTO v_catalog
 FROM public.private_card_effect_catalog_v1
 WHERE catalog_id = 'main';

 SELECT * INTO v_board
 FROM public.room_player_turn_boards
 WHERE room_id = p_room_id AND user_id = p_ai_user_id;

 IF NOT FOUND THEN
   RETURN jsonb_build_object('activations', '[]'::jsonb, 'event_candidates', '[]'::jsonb);
 END IF;

 FOR v_card IN
   SELECT value FROM jsonb_array_elements(coalesce(v_board.field_cards, '[]'::jsonb))
 LOOP
   IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;
   FOR v_def IN
     SELECT d.value
     FROM jsonb_array_elements(coalesce(v_catalog, '[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event' = 'character.activated_ability'
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean, false)
       AND public.private_card_effect_matches_id_v1(v_card, coalesce(d.value->'cardIds', '[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean, false) THEN
       v_used := coalesce(v_card->'dsl_effect_uses', '[]'::jsonb);
       IF EXISTS (
         SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id' = v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number', '')::integer, -1) = v_turn
       ) THEN
         CONTINUE;
       END IF;
     END IF;

     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id, p_ai_user_id, p_ai_user_id, v_card, v_context, '{}'::jsonb,
       coalesce(v_def->'conditions', '[]'::jsonb)
     ) THEN
       CONTINUE;
     END IF;

     v_items := v_items || jsonb_build_array(jsonb_build_object(
       'source_instance_id', v_card->>'instance_id',
       'effect_id', v_def->>'effectId',
       'label', coalesce(v_def->>'activationLabelKo', v_def->>'effectId', '카드 효과'),
       'definition', v_def
     ));
   END LOOP;
 END LOOP;


 IF coalesce(v_is_own_turn,false)
    AND coalesce(v_turn_step,'')='main'
    AND NOT coalesce(v_board.base_card_played_this_turn,false)
    AND NOT coalesce(v_board.character_played_this_turn,false) THEN
   SELECT * INTO v_game
   FROM public.room_player_game_states
   WHERE room_id=p_room_id AND user_id=p_ai_user_id;

   v_context:=jsonb_build_object(
     'entry',jsonb_build_object('method','event_play'),
     'turn_number',v_turn
   );
   FOR v_card IN
     SELECT value
     FROM jsonb_array_elements(coalesce(v_game.hand,'[]'::jsonb))
     WHERE lower(coalesce(value->>'card_type',''))='event'
   LOOP
     FOR v_def IN
       SELECT d.value
       FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
       WHERE d.value->'trigger'->>'event'='event.played'
         AND NOT coalesce((d.value->>'continuous')::boolean,false)
         AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
     LOOP
       IF public.private_card_effect_conditions_match_v1(
         p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,
         coalesce(v_def->'conditions','[]'::jsonb)
       ) THEN
         v_event_items:=v_event_items||jsonb_build_array(jsonb_build_object(
           'source_instance_id',v_card->>'instance_id',
           'effect_id',v_def->>'effectId',
           'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','이벤트 효과'),
           'definition',v_def
         ));
       END IF;
     END LOOP;
   END LOOP;
   v_context:='{}'::jsonb;
 END IF;

 v_case_key:=upper(regexp_replace(coalesce(v_board.event_key,''),'[^A-Za-z0-9]','','g'));
 IF v_case_key IN ('B10083P','B10083','1139') THEN
   v_case_id:='1139'; v_case_name:='돌아오지 않는 형사';
 ELSIF v_case_key IN ('B11098','B11098P','1261') THEN
   v_case_id:='1261'; v_case_name:='코난 VS 괴도 키드';
 ELSE
   v_case_id:=NULL;
 END IF;

 IF v_case_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.room_match_states m
      WHERE m.room_id=p_room_id AND m.current_turn_user_id=p_ai_user_id
        AND m.phase='playing' AND NOT m.game_over AND m.turn_step='main'
        AND m.pending_action IS NULL
    ) THEN
   v_case_card:=jsonb_build_object(
     'instance_id','case:'||v_board.event_key,
     'key',v_board.event_key,
     'card_id',v_case_id,
     'card_num',v_board.event_key,
     'database_id',v_board.event_key,
     'card_type','event',
     'type','event',
     'name',v_case_name
   );
   FOR v_def IN
     SELECT d.value
     FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='case.activated_ability'
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_case_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce(v_board.case_effect_uses->>(v_def->>'effectId'),'')=v_turn::text THEN
       CONTINUE;
     END IF;
     IF NOT public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_case_card,v_context,'{}'::jsonb,
       coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       CONTINUE;
     END IF;
     v_items:=v_items||jsonb_build_array(jsonb_build_object(
       'source_instance_id','case:'||v_board.event_key,
       'source_kind','case',
       'effect_id',v_def->>'effectId',
       'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','사건 효과'),
       'definition',v_def
     ));
   END LOOP;
 END IF;
 RETURN jsonb_build_object('activations', v_items, 'event_candidates', v_event_items);
END
$function$;

-- Let the AI acknowledge public card reveals even when the human owns the current turn.

CREATE OR REPLACE FUNCTION public.perform_private_ai_turn_action_v1(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  select * into v_battle from public.private_ai_battles
  where room_id = p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  if p_action not in (
    'begin_turn','place_files','play_character','play_event','next_hint_take_file',
    'next_hint','cancel_next_hint','partner_assist','partner_deduce','end_turn',
    'declare_contact','attack_evidence','guard_with_character','decline_guard',
    'guard_contact_with_character','decline_contact_guard','contact_use_cutin',
    'contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead',
    'resolve_evidence_attack','acknowledge_evidence_remove','acknowledge_culprits_crime',
    'acknowledge_hand_reveal','acknowledge_deck_remove','acknowledge_file_remove',
    'acknowledge_shared_deck_peek','finish_event','solve_case','declare_solution',
    'rest_partner_manual','refresh_deck','return_deck_peek','share_deck_peek_card',
    'take_deck_peek_card','remove_deck_peek_card','shuffle_deck','card_effect_continue','activate_card_effect','activate_case_effect','investigate'
  ) then
    raise exception 'AI 대전에서 허용되지 않은 행동입니다.';
  end if;

  select * into v_match from public.room_match_states
  where room_id = p_room_id for update;
  if not found or v_match.game_over then
    raise exception '이미 종료된 AI 대전입니다.';
  end if;

  if cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 then
    raise exception 'AI 대전은 중도 종료 응답을 기다리는 동안 일시 중지되어 있습니다.';
  end if;

  if v_match.current_turn_user_id is distinct from v_battle.ai_user_id
    and coalesce(v_match.pending_action ->> 'target_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'next_responder_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'initiator_user_id', '') <> v_battle.ai_user_id::text and coalesce(v_match.pending_action ->> 'chooser_user_id', '') <> v_battle.ai_user_id::text
    
and NOT (
   p_action = CASE coalesce(v_match.pending_action->>'type','')
     WHEN 'deck_remove_reveal' THEN 'acknowledge_deck_remove'
     WHEN 'file_remove_reveal' THEN 'acknowledge_file_remove'
     WHEN 'culprits_crime_reveal' THEN 'acknowledge_culprits_crime'
     WHEN 'hand_reveal' THEN 'acknowledge_hand_reveal'
     WHEN 'evidence_remove_reveal' THEN 'acknowledge_evidence_remove'
     ELSE ''
   END
   AND coalesce(v_match.pending_action->>'source_user_id','') <> v_battle.ai_user_id::text
   AND NOT (coalesce(v_match.pending_action->'acknowledged_user_ids','[]'::jsonb)
     @> jsonb_build_array(v_battle.ai_user_id::text))
 )
 and NOT (
  (
    p_action='activate_card_effect'
    AND EXISTS (
      SELECT 1
      FROM public.private_card_effect_catalog_v1 c
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) d(value)
      JOIN public.room_player_turn_boards b ON b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
      WHERE c.catalog_id='main'
        AND d.value->>'effectId'=p_payload->>'effect_id'
        AND d.value->>'activationTiming'='any'
        AND e.value->>'instance_id'=p_payload->>'source_instance_id'
        AND public.private_card_effect_matches_id_v1(e.value,coalesce(d.value->'cardIds','[]'::jsonb))
        AND public.private_card_effect_is_active_v1(e.value)
    )
  )
  OR (
    p_action='investigate'
    AND EXISTS (
      SELECT 1
      FROM public.room_player_turn_boards b
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
      WHERE b.room_id=p_room_id AND b.user_id=v_battle.ai_user_id
        AND e.value->>'instance_id'=p_payload->>'instance_id'
        AND public.private_card_effect_is_active_v1(e.value)
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements(
            coalesce(e.value->'dsl_keywords','[]'::jsonb)
            || coalesce(e.value->'dsl_continuous_keywords','[]'::jsonb)
          ) k(value)
          WHERE lower(coalesce(k.value->>'keyword',k.value#>>'{}',''))
            IN ('charge_case','돌격[사건]','돌격［사건］','突撃[事件]','突撃［事件］')
        )
    )
  )
) then

    raise exception '현재 AI가 행동할 차례가 아닙니다.';
  end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  v_result := public.perform_private_turn_action_v2(
    p_room_id, p_action, coalesce(p_payload, '{}'::jsonb)
  );

  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  return v_result;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  raise;
end;
$function$;