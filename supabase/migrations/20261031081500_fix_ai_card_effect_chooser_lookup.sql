-- The card effect runner stores its options in waiting, while the acting user
-- is stored in room_match_states.pending_action. Read the chooser from the
-- authoritative pending action instead of looking for a field that is not
-- present in private_card_effect_runs_v1.waiting.
CREATE OR REPLACE FUNCTION public.get_private_card_effect_options_for_ai_v1(
  p_room_id uuid,
  p_ai_user_id uuid
)
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
BEGIN
  SELECT *
    INTO v_battle
    FROM public.private_ai_battles
   WHERE room_id = p_room_id;

  IF NOT FOUND OR v_battle.ai_user_id IS DISTINCT FROM p_ai_user_id THEN
    RAISE EXCEPTION 'AI 대전에서 효과 선택 권한을 확인할 수 없습니다.';
  END IF;

  SELECT *
    INTO v_state
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

  SELECT *
    INTO v_run
    FROM public.private_card_effect_runs_v1
   WHERE room_id = p_room_id;

  IF NOT FOUND
     OR v_run.waiting IS NULL
     OR coalesce(v_run.waiting->>'kind', '') NOT IN ('selection', 'order')
     OR (
       v_pending_source_instance_id IS NOT NULL
       AND v_run.source_instance_id IS DISTINCT FROM v_pending_source_instance_id
     ) THEN
    RAISE EXCEPTION 'AI가 처리할 카드 효과 선택 데이터가 없습니다.';
  END IF;

  RETURN jsonb_build_object(
    'options', coalesce(v_run.waiting->'options', '[]'::jsonb),
    'kind', v_run.waiting->>'kind',
    'prompt', v_run.waiting->>'prompt'
  );
END
$function$;
