-- Nested effect selections may belong to a triggered card different from the outer run source.
-- Permit the authorized chooser to fetch options when the current queued effect source matches.
DO $migration$
DECLARE
  v_definition text;
  v_old_source_check text := $old$AND v_run.source_instance_id IS DISTINCT FROM v_pending->>'source_instance_id'$old$;
  v_new_source_check text := $new$AND coalesce(
         nullif(v_run.effect_queue->v_run.effect_index->>'__source_instance_id',''),
         nullif(v_run.effect_queue->v_run.effect_index->'__source_card'->>'instance_id',''),
         nullif(v_run.effect_queue->v_run.effect_index->'__context'->'entry'->'source'->>'instance_id',''),
         v_run.source_instance_id
       ) IS DISTINCT FROM v_pending->>'source_instance_id'$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_private_card_effect_options_v1(uuid)'::regprocedure
  ) INTO v_definition;

  IF position(v_new_source_check IN v_definition)=0 THEN
    IF position(v_old_source_check IN v_definition)=0 THEN
      RAISE EXCEPTION 'Could not locate the card-effect options source check';
    END IF;
    v_definition := replace(v_definition,v_old_source_check,v_new_source_check);
    EXECUTE v_definition;
  END IF;
END
$migration$;

-- If a selection step has no legal candidates, allow an empty confirmation to
-- skip only that step. A non-empty candidate list still enforces min/max and
-- every submitted ID must still belong to the server-generated option list.
DO $migration$
DECLARE
  v_definition text;
  v_old_min_guard text := $old$IF v_count<v_min OR v_count>v_max THEN RAISE EXCEPTION '선택 장수가 허용 범위를 벗어났습니다. (%~%장)',v_min,v_max; END IF;$old$;
  v_new_min_guard text := $new$IF (v_count<v_min AND NOT (v_count=0 AND jsonb_array_length(coalesce(v_wait->'options','[]'::jsonb))=0))
      OR v_count>v_max THEN
     RAISE EXCEPTION '선택 장수가 허용 범위를 벗어났습니다. (%~%장)',v_min,v_max;
   END IF;$new$;
  v_old_save_anchor text := $old$v_save:=v_wait->>'save_as';

   -- Special continuation: discard one card to allow the effect targeting Mouri Ran.$old$;
  v_new_save_anchor text := $new$v_save:=v_wait->>'save_as';

   -- An unavailable mandatory choice must not leave the match locked behind a modal.
   -- Empty selection is accepted only when the server's real candidate list is empty.
   IF v_count=0 AND jsonb_array_length(coalesce(v_options,'[]'::jsonb))=0
      AND coalesce(v_save,'') <> '__mouri_ran_protection_cost' THEN
     IF coalesce(v_save,'') <> '' THEN
       v_vars:=jsonb_set(v_vars,ARRAY[v_save],'[]'::jsonb,true);
     END IF;
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now()
       WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=NULL,state_version=state_version+1,
           last_action_label='조건에 맞는 선택 대상이 없어 해당 카드 효과 선택 단계를 건너뛰었습니다.'
       WHERE room_id=p_room_id;
     PERFORM public.private_card_effect_run_v1(p_room_id);
     IF NOT EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
       PERFORM public.private_card_effect_process_scheduled_returns_v1(p_room_id);
     END IF;
     RETURN;
   END IF;

   -- Special continuation: discard one card to allow the effect targeting Mouri Ran.$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_continue_v1(uuid,jsonb)'::regprocedure
  ) INTO v_definition;

  IF position(v_new_min_guard IN v_definition)=0 THEN
    IF position(v_old_min_guard IN v_definition)=0 THEN
      RAISE EXCEPTION 'Could not locate the card-effect selection min/max guard';
    END IF;
    v_definition := replace(v_definition,v_old_min_guard,v_new_min_guard);
  END IF;

  IF position('조건에 맞는 선택 대상이 없어 해당 카드 효과 선택 단계를 건너뛰었습니다.' IN v_definition)=0 THEN
    IF position(v_old_save_anchor IN v_definition)=0 THEN
      RAISE EXCEPTION 'Could not locate the card-effect save variable insertion point';
    END IF;
    v_definition := replace(v_definition,v_old_save_anchor,v_new_save_anchor);
  END IF;

  EXECUTE v_definition;
END
$migration$;
