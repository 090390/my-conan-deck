-- Mask facedown opponent evidence in effect selection responses.
-- Keep the real card instance in the private effect run so the selected
-- instance can still be moved, while both human and AI selectors see only
-- a facedown evidence back.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_private_card_effect_options_v1(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_run public.private_card_effect_runs_v1%rowtype;
  v_pending jsonb;
  v_expected_type text;
  v_options jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_players
    WHERE room_id = p_room_id AND user_id = v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자가 아닙니다.';
  END IF;

  SELECT pending_action INTO v_pending
  FROM public.room_match_states
  WHERE room_id = p_room_id;

  SELECT * INTO v_run
  FROM public.private_card_effect_runs_v1
  WHERE room_id = p_room_id;

  IF NOT FOUND OR v_run.waiting IS NULL THEN
    RETURN jsonb_build_object('options', '[]'::jsonb);
  END IF;

  v_expected_type := CASE v_run.waiting->>'kind'
    WHEN 'selection' THEN 'card_effect_selection'
    WHEN 'order' THEN 'card_effect_order'
    WHEN 'ack' THEN 'card_effect_reveal_ack'
    WHEN 'sequence' THEN 'card_effect_reveal_sequence'
    WHEN 'reaction' THEN 'card_effect_reaction'
    ELSE NULL
  END;

  IF v_expected_type IS NULL
     OR coalesce(v_pending->>'type', '') IS DISTINCT FROM v_expected_type
     OR coalesce(v_pending->>'chooser_user_id', '') IS DISTINCT FROM v_user::text
     OR (
       nullif(v_pending->>'source_instance_id', '') IS NOT NULL
       AND coalesce(
         nullif(v_run.effect_queue->v_run.effect_index->>'__source_instance_id',''),
         nullif(v_run.effect_queue->v_run.effect_index->'__source_card'->>'instance_id',''),
         nullif(v_run.effect_queue->v_run.effect_index->'__context'->'entry'->'source'->>'instance_id',''),
         v_run.source_instance_id
       ) IS DISTINCT FROM v_pending->>'source_instance_id'
     ) THEN
    RAISE EXCEPTION '카드 효과의 선택 후보는 지정된 선택자만 볼 수 있습니다.';
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE
      WHEN coalesce(o.value->>'zone','')='evidence_area'
       AND coalesce(o.value->>'owner_user_id','') <> v_user::text
       AND NOT coalesce(
         nullif(coalesce(o.value#>>'{card,face_up}',o.value#>>'{card,faceUp}'),'')::boolean,
         false
       )
      THEN o.value || jsonb_build_object(
        'card', jsonb_build_object(
          'instance_id', coalesce(o.value->>'instance_id',o.value#>>'{card,instance_id}'),
          'card_type', 'evidence',
          'type', 'evidence',
          'key', '뒷면 증거',
          'name', '뒷면 증거',
          'face_up', false,
          'is_hidden_evidence', true
        ),
        'is_hidden_evidence', true
      )
      ELSE o.value
    END
    ORDER BY o.ordinality
  ), '[]'::jsonb)
  INTO v_options
  FROM jsonb_array_elements(coalesce(v_run.waiting->'options','[]'::jsonb))
    WITH ORDINALITY o(value,ordinality);

  RETURN jsonb_build_object(
    'options', coalesce(v_options,'[]'::jsonb),
    'display_options', coalesce(v_run.waiting->'display_options', '[]'::jsonb),
    'kind', v_run.waiting->>'kind',
    'prompt', v_run.waiting->>'prompt'
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.get_private_card_effect_options_for_ai_v1(p_room_id uuid, p_ai_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_run public.private_card_effect_runs_v1%rowtype;
  v_battle public.private_ai_battles%rowtype;
  v_state public.room_match_states%rowtype;
  v_pending_type text;
  v_pending_source_instance_id text;
  v_active_effect_source_instance_id text;
  v_options jsonb;
BEGIN
  SELECT * INTO v_battle
  FROM public.private_ai_battles
  WHERE room_id = p_room_id;

  IF NOT FOUND OR v_battle.ai_user_id IS DISTINCT FROM p_ai_user_id THEN
    RAISE EXCEPTION 'AI 대전에서 효과 선택 권한을 확인할 수 없습니다.';
  END IF;

  SELECT * INTO v_state
  FROM public.room_match_states
  WHERE room_id = p_room_id;

  v_pending_type := coalesce(v_state.pending_action->>'type', '');
  v_pending_source_instance_id := v_state.pending_action->>'source_instance_id';

  IF NOT FOUND
     OR v_state.pending_action IS NULL
     OR v_state.pending_action->>'chooser_user_id' IS DISTINCT FROM p_ai_user_id::text
     OR v_pending_type NOT IN ('card_effect_selection', 'card_effect_order') THEN
    RAISE EXCEPTION 'AI에게 배정된 카드 효과 선택 단계가 없습니다.';
  END IF;

  SELECT * INTO v_run
  FROM public.private_card_effect_runs_v1
  WHERE room_id = p_room_id;

  IF NOT FOUND
     OR v_run.waiting IS NULL
     OR coalesce(v_run.waiting->>'kind', '') NOT IN ('selection', 'order') THEN
    RAISE EXCEPTION 'AI가 처리할 카드 효과 선택 데이터가 없습니다.';
  END IF;

  IF jsonb_typeof(v_run.effect_queue) = 'array' THEN
    v_active_effect_source_instance_id :=
      v_run.effect_queue -> v_run.effect_index ->> '__source_instance_id';
  END IF;

  IF v_pending_source_instance_id IS NOT NULL
     AND coalesce(v_active_effect_source_instance_id, v_run.source_instance_id)
         IS DISTINCT FROM v_pending_source_instance_id THEN
    RAISE EXCEPTION 'AI가 처리할 카드 효과 선택 데이터가 없습니다.';
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE
      WHEN coalesce(o.value->>'zone','')='evidence_area'
       AND coalesce(o.value->>'owner_user_id','') <> p_ai_user_id::text
       AND NOT coalesce(
         nullif(coalesce(o.value#>>'{card,face_up}',o.value#>>'{card,faceUp}'),'')::boolean,
         false
       )
      THEN o.value || jsonb_build_object(
        'card', jsonb_build_object(
          'instance_id', coalesce(o.value->>'instance_id',o.value#>>'{card,instance_id}'),
          'card_type', 'evidence',
          'type', 'evidence',
          'key', '뒷면 증거',
          'name', '뒷면 증거',
          'face_up', false,
          'is_hidden_evidence', true
        ),
        'is_hidden_evidence', true
      )
      ELSE o.value
    END
    ORDER BY o.ordinality
  ), '[]'::jsonb)
  INTO v_options
  FROM jsonb_array_elements(coalesce(v_run.waiting->'options','[]'::jsonb))
    WITH ORDINALITY o(value,ordinality);

  RETURN jsonb_build_object(
    'options', coalesce(v_options,'[]'::jsonb),
    'kind', v_run.waiting->>'kind',
    'prompt', v_run.waiting->>'prompt'
  );
END
$function$;

COMMIT;
