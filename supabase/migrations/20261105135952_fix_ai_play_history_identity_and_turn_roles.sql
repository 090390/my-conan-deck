-- Keep the AI opponent identity stable throughout game and history logs.
-- Persist the actual turn owner in post-game snapshots.
CREATE OR REPLACE FUNCTION public.capture_private_match_play_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_snapshot jsonb;
  v_actor_name text;
  v_ai_user_id uuid;
begin
  if new.state_version is not distinct from old.state_version then return new; end if;
  select b.ai_user_id into v_ai_user_id from public.private_ai_battles b where b.room_id=new.room_id;
  select case when rp.user_id=v_ai_user_id then 'AI 탐정' else coalesce(nullif(rp.temporary_nickname,''),new.end_display_names ->> auth.uid()::text,'플레이어 '||rp.seat::text) end
    into v_actor_name from public.room_players rp where rp.room_id=new.room_id and rp.user_id=auth.uid() limit 1;
  select jsonb_build_object(
    'first_player_user_id',new.first_player_user_id::text,
    'current_turn_user_id',new.current_turn_user_id::text,
    'turn_user_id',new.current_turn_user_id::text,
    'active_player_user_id',new.current_turn_user_id::text,
    'ai_user_id',v_ai_user_id::text,
    'players',coalesce(jsonb_agg(jsonb_build_object(
      'user_id',rp.user_id::text,'seat',rp.seat,
      'display_name',case when rp.user_id=v_ai_user_id then 'AI 탐정' else coalesce(nullif(rp.temporary_nickname,''),new.end_display_names ->> rp.user_id::text,'플레이어 '||rp.seat::text) end,
      'deck_count',jsonb_array_length(coalesce(gs.deck_order,'[]'::jsonb)),
      'hand_count',jsonb_array_length(coalesce(gs.hand,'[]'::jsonb)),
      'file_count',coalesce(tb.file_count,jsonb_array_length(coalesce(gs.file_cards,'[]'::jsonb)),0),
      'evidence_count',coalesce(tb.evidence_count,jsonb_array_length(coalesce(gs.evidence_cards,'[]'::jsonb)),0),
      'remove_count',coalesce(tb.remove_count,jsonb_array_length(coalesce(gs.remove_cards,'[]'::jsonb)),0),
      'field_cards',coalesce(tb.field_cards,'[]'::jsonb),
      'hand_cards',coalesce(gs.hand,'[]'::jsonb),
      'file_cards',coalesce(gs.file_cards,'[]'::jsonb),
      'evidence_cards',coalesce(gs.evidence_cards,'[]'::jsonb),
      'remove_cards',coalesce(gs.remove_cards,'[]'::jsonb)
    ) order by rp.seat),'[]'::jsonb)
  ) into v_snapshot
  from public.room_players rp
  left join public.room_player_game_states gs on gs.room_id=rp.room_id and gs.user_id=rp.user_id
  left join public.room_player_turn_boards tb on tb.room_id=rp.room_id and tb.user_id=rp.user_id
  where rp.room_id=new.room_id;
  insert into public.room_match_play_history(room_id,turn_number,actor_user_id,actor_name,action_label,snapshot)
  values(new.room_id,coalesce(new.turn_number,0),auth.uid(),coalesce(v_actor_name,'시스템'),coalesce(new.last_action_label,''),coalesce(v_snapshot,'{}'::jsonb));
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION public.get_private_match_action_log_v1(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.room_players
    WHERE room_id = p_room_id AND user_id = v_user
  ) THEN
    RAISE EXCEPTION '이 방의 참가자만 게임 행동 로그를 확인할 수 있습니다.';
  END IF;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', entries.id,
        'room_id', entries.room_id,
        'turn_number', entries.turn_number,
        'actor_user_id', entries.actor_user_id,
        'actor_seat', entries.actor_seat,
        'actor_display_name', entries.actor_display_name,
        'action_label', entries.action_label,
        'created_at', entries.created_at
      )
      ORDER BY entries.created_at DESC, entries.id DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM (
    SELECT
      l.id,
      l.room_id,
      l.turn_number,
      l.actor_user_id,
      l.action_label,
      l.created_at,
      rp.seat AS actor_seat,
      coalesce(
        CASE WHEN ai.ai_user_id = l.actor_user_id THEN 'AI 탐정' END,
        nullif(trim(rp.temporary_nickname), ''),
        CASE
          WHEN rp.seat IS NOT NULL THEN '플레이어 ' || rp.seat::text
          ELSE '알 수 없는 플레이어'
        END
      ) AS actor_display_name
    FROM public.private_match_action_logs l
    LEFT JOIN public.room_players rp
      ON rp.room_id = l.room_id AND rp.user_id = l.actor_user_id
    LEFT JOIN public.private_ai_battles ai
      ON ai.room_id = l.room_id
    WHERE l.room_id = p_room_id
  ) entries;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$function$
;
WITH inferred_turns AS (
  SELECT
    h.id,
    coalesce(
      nullif(h.snapshot->>'current_turn_user_id',''),
      nullif(h.snapshot->>'turn_user_id',''),
      CASE
        WHEN coalesce(h.turn_number,0) > 0 AND mod(h.turn_number,2)=1
          THEN nullif(h.snapshot->>'first_player_user_id','')
        WHEN coalesce(h.turn_number,0) > 0 AND mod(h.turn_number,2)=0
          THEN (
            SELECT p.value->>'user_id'
            FROM jsonb_array_elements(coalesce(h.snapshot->'players','[]'::jsonb)) p(value)
            WHERE p.value->>'user_id' IS DISTINCT FROM h.snapshot->>'first_player_user_id'
            ORDER BY (p.value->>'seat')::integer
            LIMIT 1
          )
        ELSE h.actor_user_id::text
      END,
      h.actor_user_id::text
    ) AS turn_user_id
  FROM public.room_match_play_history h
)
UPDATE public.room_match_play_history h
SET snapshot =
  jsonb_set(
    jsonb_set(
      jsonb_set(h.snapshot,'{current_turn_user_id}',to_jsonb(i.turn_user_id),true),
      '{turn_user_id}',to_jsonb(i.turn_user_id),true
    ),
    '{active_player_user_id}',to_jsonb(i.turn_user_id),true
  )
FROM inferred_turns i
WHERE h.id=i.id
  AND (h.snapshot->>'current_turn_user_id' IS NULL
       OR h.snapshot->>'turn_user_id' IS NULL
       OR h.snapshot->>'active_player_user_id' IS NULL);

UPDATE public.room_match_play_history h
SET snapshot = jsonb_set(
  jsonb_set(
    h.snapshot,
    '{ai_user_id}',
    to_jsonb(b.ai_user_id::text),
    true
  ),
  '{players}',
  (
    SELECT coalesce(jsonb_agg(
      CASE
        WHEN p.value->>'user_id'=b.ai_user_id::text
          THEN p.value || jsonb_build_object('display_name','AI 탐정')
        ELSE p.value
      END ORDER BY p.ordinality
    ),'[]'::jsonb)
    FROM jsonb_array_elements(coalesce(h.snapshot->'players','[]'::jsonb))
      WITH ORDINALITY p(value,ordinality)
  ),
  true
),
actor_name=CASE WHEN h.actor_user_id=b.ai_user_id THEN 'AI 탐정' ELSE h.actor_name END
FROM public.private_ai_battles b
WHERE b.room_id=h.room_id
  AND jsonb_typeof(h.snapshot->'players')='array';
