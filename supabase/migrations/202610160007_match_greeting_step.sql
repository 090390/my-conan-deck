-- Conan TCG: add a shared 30-second greeting step after mulligan.
CREATE TABLE IF NOT EXISTS public.private_match_greetings (
  room_id uuid PRIMARY KEY,
  started_at timestamptz NOT NULL DEFAULT now(),
  seat1_message text,
  seat2_message text,
  completed_at timestamptz
);

ALTER TABLE public.private_match_greetings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_match_greetings FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_private_match_greeting_v1(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $get_private_match_greeting_v1$
DECLARE
  v_user uuid := auth.uid();
  v_seat integer;
  v_greeting public.private_match_greetings%ROWTYPE;
  v_seat1_name text;
  v_seat2_name text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  SELECT seat INTO v_seat FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user;
  IF v_seat IS NULL THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  IF (SELECT count(*) FROM public.room_players WHERE room_id=p_room_id) <> 2 THEN
    RAISE EXCEPTION '두 플레이어가 있는 방에서만 인사를 진행할 수 있습니다.';
  END IF;
  INSERT INTO public.private_match_greetings(room_id) VALUES (p_room_id)
    ON CONFLICT (room_id) DO NOTHING;
  SELECT * INTO v_greeting FROM public.private_match_greetings WHERE room_id=p_room_id FOR UPDATE;
  IF v_greeting.completed_at IS NULL AND now() >= v_greeting.started_at + interval '30 seconds' THEN
    UPDATE public.private_match_greetings
      SET seat1_message=coalesce(seat1_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          seat2_message=coalesce(seat2_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          completed_at=now()
      WHERE room_id=p_room_id
      RETURNING * INTO v_greeting;
  ELSIF v_greeting.completed_at IS NULL AND v_greeting.seat1_message IS NOT NULL AND v_greeting.seat2_message IS NOT NULL THEN
    UPDATE public.private_match_greetings SET completed_at=now() WHERE room_id=p_room_id RETURNING * INTO v_greeting;
  END IF;
  SELECT coalesce(nullif(trim(temporary_nickname),''),'플레이어 '||seat::text) INTO v_seat1_name
    FROM public.room_players WHERE room_id=p_room_id AND seat=1;
  SELECT coalesce(nullif(trim(temporary_nickname),''),'플레이어 '||seat::text) INTO v_seat2_name
    FROM public.room_players WHERE room_id=p_room_id AND seat=2;
  RETURN jsonb_build_object(
    'started_at',v_greeting.started_at,
    'seat1_message',v_greeting.seat1_message,
    'seat2_message',v_greeting.seat2_message,
    'seat1_name',coalesce(v_seat1_name,'플레이어 1'),
    'seat2_name',coalesce(v_seat2_name,'플레이어 2'),
    'my_seat',v_seat,
    'completed_at',v_greeting.completed_at,
    'is_complete',v_greeting.completed_at IS NOT NULL,
    'seconds_left',greatest(0,ceil(extract(epoch FROM (v_greeting.started_at + interval '30 seconds' - now())))::integer)
  );
END;
$get_private_match_greeting_v1$;

CREATE OR REPLACE FUNCTION public.submit_private_match_greeting_v1(p_room_id uuid, p_message text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  SELECT seat INTO v_seat FROM public.room_players WHERE room_id=p_room_id AND user_id=v_user;
  IF v_seat IS NULL THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  INSERT INTO public.private_match_greetings(room_id) VALUES (p_room_id)
    ON CONFLICT (room_id) DO NOTHING;
  SELECT * INTO v_greeting FROM public.private_match_greetings WHERE room_id=p_room_id FOR UPDATE;
  IF v_greeting.completed_at IS NOT NULL THEN RETURN public.get_private_match_greeting_v1(p_room_id); END IF;
  IF now() >= v_greeting.started_at + interval '30 seconds' THEN
    UPDATE public.private_match_greetings
      SET seat1_message=coalesce(seat1_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          seat2_message=coalesce(seat2_message,'안녕하세요. 이번 게임 잘 부탁드리겠습니다.'),
          completed_at=now()
      WHERE room_id=p_room_id;
    RETURN public.get_private_match_greeting_v1(p_room_id);
  END IF;
  IF v_seat=1 THEN
    UPDATE public.private_match_greetings SET seat1_message=v_message WHERE room_id=p_room_id;
  ELSE
    UPDATE public.private_match_greetings SET seat2_message=v_message WHERE room_id=p_room_id;
  END IF;
  SELECT * INTO v_greeting FROM public.private_match_greetings WHERE room_id=p_room_id;
  IF v_greeting.seat1_message IS NOT NULL AND v_greeting.seat2_message IS NOT NULL THEN
    UPDATE public.private_match_greetings SET completed_at=now() WHERE room_id=p_room_id AND completed_at IS NULL;
  END IF;
  RETURN public.get_private_match_greeting_v1(p_room_id);
END;
$submit_private_match_greeting_v1$;

REVOKE ALL ON FUNCTION public.get_private_match_greeting_v1(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_private_match_greeting_v1(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_private_match_greeting_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_private_match_greeting_v1(uuid,text) TO authenticated;
