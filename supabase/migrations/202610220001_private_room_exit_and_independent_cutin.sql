-- Allow each contact participant to use one cut-in independently, and leave a private room before mulligan.
-- Apply this migration to the linked Supabase database after it is committed.

DO $verify_independent_contact_cutin$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure)
    INTO v_definition;
  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Independent cut-in check stopped: perform_private_turn_action_v2 was not found';
  END IF;

  -- The supplied live function definition already checks usage separately for each participant.
  -- Validate those exact actor-specific checks rather than trying to replace a legacy shared guard
  -- that is no longer present in the deployed function.
  IF position('v_user::text = (v_match.pending_action ->> ''target_user_id'')' in v_definition) = 0
     OR position('v_match.pending_action ->> ''target_cut_in_used''' in v_definition) = 0
     OR position('v_match.pending_action ->> ''target_cut_in_passed''' in v_definition) = 0
     OR position('v_user::text = (v_match.pending_action ->> ''attacker_user_id'')' in v_definition) = 0
     OR position('v_match.pending_action ->> ''attacker_cut_in_used''' in v_definition) = 0
     OR position('v_match.pending_action ->> ''attacker_cut_in_passed''' in v_definition) = 0 THEN
    RAISE EXCEPTION 'Independent cut-in check stopped: the deployed function does not contain both participants'' separate used/passed checks. The live function definition must be reviewed before changing it.';
  END IF;
END
$verify_independent_contact_cutin$;

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
  IF lower(coalesce(v_match_state ->> 'phase','waiting')) NOT IN ('waiting','mulligan') THEN
    RAISE EXCEPTION '게임이 본격적으로 진행된 뒤에는 대기실에서 나갈 수 없습니다.';
  END IF;

  IF lower(coalesce(v_match_state ->> 'phase','waiting')) = 'mulligan'
     AND (
       COALESCE(NULLIF(v_match_state ->> 'seat1_mulligan_done','')::boolean,false)
       OR COALESCE(NULLIF(v_match_state ->> 'seat2_mulligan_done','')::boolean,false)
     ) THEN
    RAISE EXCEPTION '한 명이라도 멀리건을 확정한 뒤에는 대기실에서 나갈 수 없습니다.';
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
