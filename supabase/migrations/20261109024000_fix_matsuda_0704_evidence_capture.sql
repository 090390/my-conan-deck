-- Correct ID:0704 Matsuda Jinpei's MR/MRP substitution and face-up evidence gain.
BEGIN;

DO $catalog$
DECLARE
  v_new_definition jsonb;
  v_changed integer;
BEGIN
  v_new_definition := jsonb_build_object(
    'effectId', 'card-0704-activated-opponent-evidence-and-character',
    'cardIds', jsonb_build_array('0704'),
    'cardNameJa', '松田陣平',
    'cardNameKo', '마츠다 진페이',
    'trigger', jsonb_build_object('event', 'character.activated_ability', 'timing', 'immediate'),
    'conditions', jsonb_build_array(
      jsonb_build_object('fact', 'player.partner.color', 'operator', 'equals', 'value', 'yellow'),
      jsonb_build_object('fact', 'turn.is_source_controller_turn', 'operator', 'equals', 'value', true),
      jsonb_build_object('fact', 'source.is_active', 'operator', 'equals', 'value', true)
    ),
    'oncePerTurn', true,
    'activationTiming', 'turn',
    'activationLabelKo', '선언 · 슬립: 상대 증거 1장 덱 맨 아래 이동 · AP 8000 이하 캐릭터를 앞면 증거로 확보',
    'steps', jsonb_build_array(
      jsonb_build_object('op', 'pay_cost', 'cost', 'sleep_source_character'),
      jsonb_build_object(
        'op', 'select_cards', 'from', 'opponent_evidence', 'min', 0, 'max', 1,
        'optional', true, 'saveAs', 'evidence_to_bottom',
        'prompt', '덱 맨 아래로 옮길 상대 증거를 최대 1장 선택하세요. 앞면·뒷면 및 증거의 위치와 관계없이 선택할 수 있습니다.'
      ),
      jsonb_build_object('op', 'move_cards', 'from', 'evidence_to_bottom', 'to', 'deck_bottom'),
      jsonb_build_object(
        'op', 'select_cards', 'from', 'opponent_field', 'min', 0, 'max', 1,
        'optional', true, 'saveAs', 'target',
        'filter', jsonb_build_object('allOf', jsonb_build_array(
          jsonb_build_object('field', 'card_type', 'operator', 'equals', 'value', 'character'),
          jsonb_build_object('field', 'ap_current', 'operator', 'less_than_or_equal', 'value', 8000)
        )),
        'prompt', '상대가 앞면 증거로 얻을 AP 8000 이하 현장 캐릭터를 최대 1장 선택하세요.'
      ),
      jsonb_build_object(
        'op', 'move_cards', 'from', 'target', 'to', 'evidence_area', 'faceUp', true,
        'when', jsonb_build_object('fact', 'vars.target.count', 'operator', 'greater_than', 'value', 0)
      ),
      jsonb_build_object(
        'op', 'gain_evidence', 'count', 1, 'faceUp', true, 'targetOwner', 'opponent',
        'when', jsonb_build_object('fact', 'vars.target.has_rarity_mr', 'operator', 'equals', 'value', true)
      )
    ),
    'reviewNotes', jsonb_build_object(
      'sourceText', '【파트너 황】【선언】【턴 1】【슬립】 - 상대의 증거를 1개까지 선택하여 덱의 맨 아래로 옮긴다. 상대방 현장에 있는 AP 8000 이하의 캐릭터를 1장까지 선택하면, 상대방은 그 카드를 앞면이 보이도록 한 채 증거로 얻는다. 상대방 현장에 있는 MR 캐릭터를 선택한 경우, 상대방은 덱의 카드 중 맨 위 1장을 앞면이 보이도록 한 채 증거로 얻는다.',
      'rationale', '자신의 파트너 색상이 황인 자신의 턴에, 이 캐릭터가 액티브 상태일 때 턴당 1회 선언한다. 비용으로 이 캐릭터를 슬립시킨 뒤 상대 증거 중 앞면/뒷면이나 배열 위치에 관계없이 1장까지 골라 상대 덱 맨 아래로 옮긴다. 이어 상대 현장의 현재 AP 8000 이하 캐릭터를 1장까지 선택해 앞면 증거로 이동한다. 선택한 캐릭터가 MR 또는 MRP이면 공통 카드 이동 함수가 해당 카드를 상대 MR 파트너 에이리어로 보낸다. 이 경우 선택한 카드 대신 상대 덱 맨 위 카드 1장을 앞면 증거로 얻는다. MR/MRP 판별은 선택 변수 배열 안의 실제 카드 rarity 메타데이터를 검사한다.'
    )
  );

  UPDATE public.private_card_effect_catalog_v1 c
  SET definitions = (
    SELECT coalesce(
      jsonb_agg(
        CASE
          WHEN e.value->>'effectId' = v_new_definition->>'effectId' THEN v_new_definition
          ELSE e.value
        END
        ORDER BY e.ordinality
      ),
      '[]'::jsonb
    )
    FROM jsonb_array_elements(coalesce(c.definitions, '[]'::jsonb))
      WITH ORDINALITY e(value, ordinality)
  ),
  updated_at = now()
  WHERE c.catalog_id = 'main'
    AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(coalesce(c.definitions, '[]'::jsonb)) e(value)
      WHERE e.value->>'effectId' = 'card-0704-activated-opponent-evidence-and-character'
    );

  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed <> 1 THEN
    RAISE EXCEPTION 'ID:0704 activated effect definition was not found in the main catalog.';
  END IF;
END
$catalog$;

DO $fact_function$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure
  ) INTO v_definition;

  v_old := $old$ IF p_fact LIKE 'vars.%' THEN $old$;
  v_new := $new$ IF p_fact LIKE 'vars.%.has_rarity_mr' THEN
   v_path := string_to_array(substr(p_fact,6),'.');
   v_path := v_path[1:array_length(v_path,1)-1];
   v_cards := p_vars #> v_path;
   RETURN to_jsonb(EXISTS(
     SELECT 1
     FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
     CROSS JOIN LATERAL (SELECT coalesce(e.value->'card',e.value) AS card) c
     WHERE upper(coalesce(
       c.card->>'rarity',
       c.card->>'rarity_code',
       c.card#>>'{sourceData,rarity}',
       c.card#>>'{raw,rarity}',
       ''
     )) IN ('MR','MRP')
   ));
 END IF;
 IF p_fact LIKE 'vars.%' THEN $new$;

  IF position(v_old IN v_definition) = 0 THEN
    IF position('vars.%.has_rarity_mr' IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not locate the variables fact branch for MR/MRP detection.';
    END IF;
  ELSE
    v_definition := replace(v_definition, v_old, v_new);
  END IF;

  EXECUTE v_definition;
END
$fact_function$;

DO $runner_function$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  v_old := $old$   ELSIF v_op='gain_evidence' THEN
     v_target_owner:=v_owner;
     IF v_step->>'targetOwner'='opponent' THEN
       SELECT user_id INTO v_target_owner FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     END IF;
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       PERFORM public.draw_private_turn_card(p_room_id,v_target_owner,'evidence');
     END LOOP;$old$;

  v_new := $new$   ELSIF v_op='gain_evidence' THEN
     v_target_owner:=v_owner;
     IF v_step->>'targetOwner'='opponent' THEN
       SELECT user_id INTO v_target_owner FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1;
     END IF;
     FOR v_i IN 1..coalesce((v_step->>'count')::integer,1) LOOP
       v_card:=public.draw_private_turn_card(p_room_id,v_target_owner,'evidence');
       IF coalesce(nullif(v_step->>'faceUp','')::boolean,false)
          AND coalesce(v_card->>'instance_id','')<>'' THEN
         UPDATE public.room_player_game_states g
         SET evidence_cards=coalesce((
           SELECT jsonb_agg(
             CASE
               WHEN e.value->>'instance_id'=v_card->>'instance_id'
                 THEN e.value||jsonb_build_object('face_up',true)
               ELSE e.value
             END
             ORDER BY e.ordinality
           )
           FROM jsonb_array_elements(coalesce(g.evidence_cards,'[]'::jsonb))
             WITH ORDINALITY e(value,ordinality)
         ),'[]'::jsonb),
         updated_at=now()
         WHERE g.room_id=p_room_id AND g.user_id=v_target_owner;
       END IF;
     END LOOP;$new$;

  IF position(v_old IN v_definition) = 0 THEN
    IF position('v_step->>''faceUp''' IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not locate the gain_evidence runtime branch.';
    END IF;
  ELSE
    v_definition := replace(v_definition, v_old, v_new);
  END IF;

  EXECUTE v_definition;
END
$runner_function$;

COMMIT;
