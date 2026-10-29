-- Event-color metadata is setup-time game data and must not be alterable mid-match.
CREATE OR REPLACE FUNCTION public.set_private_room_event_has_non_blue_color_v1(
  p_room_id uuid,
  p_has_non_blue_color boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth'
AS $function$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다.'; END IF;
  IF p_has_non_blue_color IS NULL THEN RAISE EXCEPTION '사건 색상 판정값이 필요합니다.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.room_players rp
    WHERE rp.room_id=p_room_id AND rp.user_id=v_user
  ) THEN RAISE EXCEPTION '이 방의 참가자가 아닙니다.'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.room_match_states m
    WHERE m.room_id=p_room_id AND m.phase='playing' AND NOT m.game_over
  ) THEN RAISE EXCEPTION '대전이 시작된 뒤에는 사건 색상 정보를 변경할 수 없습니다.'; END IF;
  UPDATE public.room_player_decks
    SET event_has_non_blue_color=p_has_non_blue_color
    WHERE room_id=p_room_id AND user_id=v_user;
  IF NOT FOUND THEN RAISE EXCEPTION '제출된 덱에서 사건 카드를 찾을 수 없습니다.'; END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.set_private_room_event_has_non_blue_color_v1(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_private_room_event_has_non_blue_color_v1(uuid,boolean) TO authenticated;
