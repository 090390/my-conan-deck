-- Match greeting review now requires both players to confirm.
-- Also record the existing automatic deck refresh as a timestamped match action.

ALTER TABLE public.private_match_greetings
  ADD COLUMN IF NOT EXISTS seat1_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS seat2_confirmed_at timestamptz;

CREATE OR REPLACE FUNCTION public.get_private_match_greeting_v1(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $get_private_match_greeting_v1$
DECLARE
  v_user uuid := auth.uid();
  v_seat integer;
  v_greeting public.private_match_greetings%ROWTYPE;
  v_seat1_name text;
  v_seat2_name text;
  v_my_confirmed boolean;
  v_opponent_confirmed boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  SELECT seat INTO v_seat
    FROM public.room_players
    WHERE room_id=p_room_id AND user_id=v_user;
  IF v_seat IS NULL THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  IF (SELECT count(*) FROM public.room_players WHERE room_id=p_room_id) <> 2 THEN
    RAISE EXCEPTION '두 플레이어가 있는 방에서만 인사를 진행할 수 있습니다.';
  END IF;

  INSERT INTO public.private_match_greetings(room_id) VALUES (p_room_id)
    ON CONFLICT (room_id) DO NOTHING;
  SELECT * INTO v_greeting
    FROM public.private_match_greetings
    WHERE room_id=p_room_id
    FOR UPDATE;

  -- Keep the original 30-second fallback for players who do not enter a greeting.
  -- This fills missing messages only; it never dismisses the review screen.
  IF v_greeting.completed_at IS NULL
     AND now() >= v_greeting.started_at + interval '30 seconds'
     AND (v_greeting.seat1_message IS NULL OR v_greeting.seat2_message IS NULL) THEN
    UPDATE public.private_match_greetings
      SET seat1_message=coalesce(seat1_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          seat2_message=coalesce(seat2_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.')
      WHERE room_id=p_room_id
      RETURNING * INTO v_greeting;
  END IF;

  -- A race-safe completion check; completion means both players reviewed and confirmed.
  IF v_greeting.completed_at IS NULL
     AND v_greeting.seat1_confirmed_at IS NOT NULL
     AND v_greeting.seat2_confirmed_at IS NOT NULL THEN
    UPDATE public.private_match_greetings
      SET completed_at=now()
      WHERE room_id=p_room_id
      RETURNING * INTO v_greeting;
  END IF;

  SELECT coalesce(nullif(trim(temporary_nickname),''),'플레이어 '||seat::text)
    INTO v_seat1_name FROM public.room_players WHERE room_id=p_room_id AND seat=1;
  SELECT coalesce(nullif(trim(temporary_nickname),''),'플레이어 '||seat::text)
    INTO v_seat2_name FROM public.room_players WHERE room_id=p_room_id AND seat=2;

  v_my_confirmed := CASE WHEN v_seat=1
    THEN v_greeting.seat1_confirmed_at IS NOT NULL
    ELSE v_greeting.seat2_confirmed_at IS NOT NULL END;
  v_opponent_confirmed := CASE WHEN v_seat=1
    THEN v_greeting.seat2_confirmed_at IS NOT NULL
    ELSE v_greeting.seat1_confirmed_at IS NOT NULL END;

  RETURN jsonb_build_object(
    'started_at',v_greeting.started_at,
    'seat1_message',v_greeting.seat1_message,
    'seat2_message',v_greeting.seat2_message,
    'seat1_name',coalesce(v_seat1_name,'플레이어 1'),
    'seat2_name',coalesce(v_seat2_name,'플레이어 2'),
    'my_seat',v_seat,
    'seat1_confirmed',v_greeting.seat1_confirmed_at IS NOT NULL,
    'seat2_confirmed',v_greeting.seat2_confirmed_at IS NOT NULL,
    'my_confirmed',v_my_confirmed,
    'opponent_confirmed',v_opponent_confirmed,
    'is_ready_for_review',v_greeting.seat1_message IS NOT NULL AND v_greeting.seat2_message IS NOT NULL,
    'completed_at',v_greeting.completed_at,
    'is_complete',v_greeting.completed_at IS NOT NULL,
    'seconds_left',CASE
      WHEN v_greeting.seat1_message IS NOT NULL AND v_greeting.seat2_message IS NOT NULL THEN 0
      ELSE greatest(0,ceil(extract(epoch FROM (v_greeting.started_at + interval '30 seconds' - now())))::integer)
    END
  );
END;
$get_private_match_greeting_v1$;

CREATE OR REPLACE FUNCTION public.submit_private_match_greeting_v1(p_room_id uuid, p_message text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $submit_private_match_greeting_v1$
DECLARE
  v_user uuid := auth.uid();
  v_seat integer;
  v_message text := trim(coalesce(p_message,''));
  v_greeting public.private_match_greetings%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF length(v_message) < 1 THEN RAISE EXCEPTION '인사말을 입력해 주세요.'; END IF;
  IF length(v_message) > 140 THEN RAISE EXCEPTION '인사말은 140자까지 입력할 수 있습니다.'; END IF;

  SELECT seat INTO v_seat FROM public.room_players
    WHERE room_id=p_room_id AND user_id=v_user;
  IF v_seat IS NULL THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  INSERT INTO public.private_match_greetings(room_id) VALUES (p_room_id)
    ON CONFLICT (room_id) DO NOTHING;
  SELECT * INTO v_greeting FROM public.private_match_greetings
    WHERE room_id=p_room_id FOR UPDATE;
  IF v_greeting.completed_at IS NOT NULL THEN
    RETURN public.get_private_match_greeting_v1(p_room_id);
  END IF;

  IF now() >= v_greeting.started_at + interval '30 seconds' THEN
    UPDATE public.private_match_greetings
      SET seat1_message=coalesce(seat1_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          seat2_message=coalesce(seat2_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.')
      WHERE room_id=p_room_id;
    RETURN public.get_private_match_greeting_v1(p_room_id);
  END IF;

  IF v_seat=1 THEN
    UPDATE public.private_match_greetings SET seat1_message=v_message WHERE room_id=p_room_id;
  ELSE
    UPDATE public.private_match_greetings SET seat2_message=v_message WHERE room_id=p_room_id;
  END IF;

  -- Do not set completed_at here. Both players must separately confirm the review screen.
  RETURN public.get_private_match_greeting_v1(p_room_id);
END;
$submit_private_match_greeting_v1$;

CREATE OR REPLACE FUNCTION public.confirm_private_match_greeting_v1(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $confirm_private_match_greeting_v1$
DECLARE
  v_user uuid := auth.uid();
  v_seat integer;
  v_greeting public.private_match_greetings%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  SELECT seat INTO v_seat FROM public.room_players
    WHERE room_id=p_room_id AND user_id=v_user;
  IF v_seat IS NULL THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  SELECT * INTO v_greeting FROM public.private_match_greetings
    WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '인사말을 먼저 입력해 주세요.'; END IF;
  IF v_greeting.completed_at IS NOT NULL THEN
    RETURN public.get_private_match_greeting_v1(p_room_id);
  END IF;

  IF now() >= v_greeting.started_at + interval '30 seconds'
     AND (v_greeting.seat1_message IS NULL OR v_greeting.seat2_message IS NULL) THEN
    UPDATE public.private_match_greetings
      SET seat1_message=coalesce(seat1_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          seat2_message=coalesce(seat2_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.')
      WHERE room_id=p_room_id
      RETURNING * INTO v_greeting;
  END IF;

  IF v_greeting.seat1_message IS NULL OR v_greeting.seat2_message IS NULL THEN
    RAISE EXCEPTION '두 플레이어의 인사말이 준비될 때까지 기다려 주세요.';
  END IF;

  IF v_seat=1 THEN
    UPDATE public.private_match_greetings
      SET seat1_confirmed_at=coalesce(seat1_confirmed_at,now())
      WHERE room_id=p_room_id;
  ELSE
    UPDATE public.private_match_greetings
      SET seat2_confirmed_at=coalesce(seat2_confirmed_at,now())
      WHERE room_id=p_room_id;
  END IF;

  SELECT * INTO v_greeting FROM public.private_match_greetings WHERE room_id=p_room_id;
  IF v_greeting.seat1_confirmed_at IS NOT NULL
     AND v_greeting.seat2_confirmed_at IS NOT NULL
     AND v_greeting.completed_at IS NULL THEN
    UPDATE public.private_match_greetings
      SET completed_at=now()
      WHERE room_id=p_room_id;
  END IF;

  RETURN public.get_private_match_greeting_v1(p_room_id);
END;
$confirm_private_match_greeting_v1$;

REVOKE ALL ON FUNCTION public.get_private_match_greeting_v1(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_private_match_greeting_v1(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_private_match_greeting_v1(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_private_match_greeting_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_private_match_greeting_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_private_match_greeting_v1(uuid) TO authenticated;

-- Ensure the append-only action log exists before installing its refresh trigger.
CREATE TABLE IF NOT EXISTS public.private_match_action_logs (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  room_id uuid NOT NULL,
  turn_number integer,
  actor_user_id uuid,
  action_label text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS private_match_action_logs_room_created_idx
  ON public.private_match_action_logs(room_id, created_at DESC, id DESC);
ALTER TABLE public.private_match_action_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_match_action_logs FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.log_private_auto_deck_refresh_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $log_private_auto_deck_refresh_v1$
DECLARE
  v_old jsonb := to_jsonb(OLD);
  v_new jsonb := to_jsonb(NEW);
  v_old_deck jsonb;
  v_new_deck jsonb;
  v_old_remove jsonb;
  v_new_remove jsonb;
  v_key text;
  v_old_remove_count integer := 0;
  v_new_remove_count integer := 0;
  v_old_deck_count integer := 0;
  v_new_deck_count integer := 0;
  v_turn_number integer;
  v_actor uuid := auth.uid();
BEGIN
  v_old_deck := CASE WHEN jsonb_typeof(v_old -> 'deck_order')='array' THEN v_old -> 'deck_order' ELSE '[]'::jsonb END;
  v_new_deck := CASE WHEN jsonb_typeof(v_new -> 'deck_order')='array' THEN v_new -> 'deck_order' ELSE '[]'::jsonb END;
  v_old_deck_count := jsonb_array_length(v_old_deck);
  v_new_deck_count := jsonb_array_length(v_new_deck);

  -- Different deployed schema revisions may use a different JSONB remove-pile column name.
  FOR v_key IN
    SELECT key
    FROM jsonb_each(v_old)
    WHERE key ILIKE '%remove%'
      AND key NOT ILIKE '%count%'
      AND jsonb_typeof(value)='array'
    ORDER BY CASE WHEN key='remove_cards' THEN 0 WHEN key ILIKE '%remove%cards%' THEN 1 ELSE 2 END, key
  LOOP
    v_old_remove := v_old -> v_key;
    v_new_remove := CASE WHEN jsonb_typeof(v_new -> v_key)='array' THEN v_new -> v_key ELSE '[]'::jsonb END;
    EXIT;
  END LOOP;

  IF v_old_remove IS NOT NULL THEN
    v_old_remove_count := jsonb_array_length(v_old_remove);
    v_new_remove_count := jsonb_array_length(coalesce(v_new_remove,'[]'::jsonb));
  END IF;

  -- A refresh empties the remove pile into a newly shuffled deck after the player's deck runs out.
  -- Requiring a changed, non-empty deck distinguishes this from simply taking the final remove card into hand.
  IF v_old_remove_count > 0
     AND v_new_remove_count = 0
     AND v_new_deck_count > 0
     AND v_old_deck IS DISTINCT FROM v_new_deck THEN
    SELECT turn_number INTO v_turn_number
      FROM public.room_match_states
      WHERE room_id=NEW.room_id;

    INSERT INTO public.private_match_action_logs(room_id,turn_number,actor_user_id,action_label,created_at)
    VALUES (
      NEW.room_id,
      v_turn_number,
      v_actor,
      '리프레시: 덱이 소진되어 리무브 에이리어의 카드를 셔플해 덱으로 되돌렸고, 상대에게 증거 1장을 추가했습니다.',
      now()
    );
  END IF;

  RETURN NEW;
END;
$log_private_auto_deck_refresh_v1$;

DROP TRIGGER IF EXISTS private_auto_deck_refresh_action_log ON public.room_player_game_states;
CREATE TRIGGER private_auto_deck_refresh_action_log
  AFTER UPDATE ON public.room_player_game_states
  FOR EACH ROW
  EXECUTE FUNCTION public.log_private_auto_deck_refresh_v1();

REVOKE ALL ON FUNCTION public.log_private_auto_deck_refresh_v1() FROM PUBLIC, anon, authenticated;
