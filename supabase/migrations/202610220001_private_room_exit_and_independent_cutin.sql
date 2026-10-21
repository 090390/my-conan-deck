-- Allow each contact participant to use one cut-in independently, and leave a private room before mulligan.
-- Apply this migration to the linked Supabase database after it is committed.

DO $patch_independent_contact_cutin$
DECLARE
  v_definition text;
  v_start integer;
  v_tail text;
  v_rel integer;
  v_end integer;
  v_block text;
  v_patched_block text;
  v_guard text := $guard$if (
  (
    v_user::text = (v_match.pending_action ->> 'target_user_id')
    AND (
      COALESCE(NULLIF(v_match.pending_action ->> 'target_cut_in_used','')::boolean,false)
      OR COALESCE(NULLIF(v_match.pending_action ->> 'target_cut_in_passed','')::boolean,false)
    )
  )
  OR
  (
    v_user::text = (v_match.pending_action ->> 'attacker_user_id')
    AND (
      COALESCE(NULLIF(v_match.pending_action ->> 'attacker_cut_in_used','')::boolean,false)
      OR COALESCE(NULLIF(v_match.pending_action ->> 'attacker_cut_in_passed','')::boolean,false)
    )
  )
) then$guard$;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Independent cut-in migration stopped: action function was not found';
  END IF;
  v_definition := replace(v_definition, chr(13), '');

  v_start := position('if p_action = ''contact_use_cutin'' then' in lower(v_definition));
  IF v_start = 0 THEN
    RAISE EXCEPTION 'Independent cut-in migration stopped: contact_use_cutin action was not found';
  END IF;

  v_tail := substring(v_definition from v_start);
  v_rel := position('if p_action = ' in lower(substring(v_tail from length('if p_action = ''contact_use_cutin'' then') + 1)));
  IF v_rel = 0 THEN
    RAISE EXCEPTION 'Independent cut-in migration stopped: end of contact_use_cutin action was not found';
  END IF;
  v_end := v_start + length('if p_action = ''contact_use_cutin'' then') + v_rel - 1;
  v_block := substring(v_definition from v_start for v_end - v_start);

  IF position(lower(v_guard) in lower(v_block)) = 0 THEN
    v_patched_block := regexp_replace(
      v_block,
      'if[[:space:]]+[^;]*cut_in_used[^;]*then',
      v_guard,
      'gi'
    );
    IF v_patched_block = v_block THEN
      RAISE EXCEPTION 'Independent cut-in migration stopped: global cut_in_used guard did not match the deployed action';
    END IF;
    v_definition := substring(v_definition from 1 for v_start - 1)
      || v_patched_block
      || substring(v_definition from v_end);
    EXECUTE v_definition;
  END IF;
END
$patch_independent_contact_cutin$;

REVOKE ALL ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perform_private_turn_action_v2(uuid,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.leave_private_room_before_mulligan_v1(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $leave_private_room$
DECLARE
  v_user uuid := auth.uid();
  v_match_state jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION '로그인 정보가 없습니다.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.room_players
    WHERE room_id = p_room_id AND user_id = v_user
  ) THEN
    RAISE EXCEPTION '현재 대기실 참가자만 나갈 수 있습니다.';
  END IF;

  v_match_state := public.get_private_match_state(p_room_id);
  IF lower(coalesce(v_match_state ->> 'phase','waiting')) <> 'waiting' THEN
    RAISE EXCEPTION '멀리건이 시작된 뒤에는 대기실에서 나갈 수 없습니다.';
  END IF;

  DELETE FROM public.room_players
  WHERE room_id = p_room_id AND user_id = v_user;

  IF NOT FOUND THEN
    RAISE EXCEPTION '대기실 참가 상태를 정리하지 못했습니다.';
  END IF;

  RETURN jsonb_build_object('ok', true, 'left', true, 'room_id', p_room_id);
END
$leave_private_room$;

REVOKE ALL ON FUNCTION public.leave_private_room_before_mulligan_v1(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_private_room_before_mulligan_v1(uuid) TO authenticated;
