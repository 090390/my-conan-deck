-- Fix evidence.card_removed dispatch so the removed evidence card owns
-- its own effect, while field_watch effects are evaluated for the opponent.
-- Also correct ID 0704 (Matsuda Jinpei): its Hirameki is a source-card effect,
-- not a field watcher.

DO $migration$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(
    'public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean)'::regprocedure
  ) INTO v_def;

  -- Add a watcher controller distinct from the removed-card effect actor.
  IF position('v_watch_actor uuid;' IN v_def) = 0 THEN
    v_old := ' v_watch_card jsonb;
 v_watch_board public.room_player_turn_boards%rowtype;';
    v_new := ' v_watch_card jsonb;
 v_watch_board public.room_player_turn_boards%rowtype;
 v_watch_actor uuid;';
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate card-effect watcher declaration';
    END IF;
    v_def := replace(v_def, v_old, v_new);

    v_old := '     SELECT * INTO v_watch_board FROM public.room_player_turn_boards
       WHERE room_id=p_room_id AND user_id=p_actor_user_id;';
    v_new := '     v_watch_actor:=coalesce(nullif(p_context->>''watch_user_id'','''')::uuid,p_actor_user_id);
     SELECT * INTO v_watch_board FROM public.room_player_turn_boards
       WHERE room_id=p_room_id AND user_id=v_watch_actor;';
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate card-effect watcher board lookup';
    END IF;
    v_def := replace(v_def, v_old, v_new);

    v_old := '         p_room_id,p_actor_user_id,p_source_user_id,v_watch_card,v_context,';
    v_new := '         p_room_id,v_watch_actor,v_watch_actor,v_watch_card,v_context,';
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate card-effect watcher condition call';
    END IF;
    v_def := replace(v_def, v_old, v_new);

    v_old := '         v_existing:=public.private_card_effect_get_card_v1(p_room_id,p_source_user_id,v_watch_card->>''instance_id'');';
    v_new := '         v_existing:=public.private_card_effect_get_card_v1(p_room_id,v_watch_actor,v_watch_card->>''instance_id'');';
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate card-effect watcher card lookup';
    END IF;
    v_def := replace(v_def, v_old, v_new);

    v_old := '           p_room_id,p_source_user_id,v_watch_card->>''instance_id'',';
    v_new := '           p_room_id,v_watch_actor,v_watch_card->>''instance_id'',';
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate card-effect watcher card patch';
    END IF;
    v_def := replace(v_def, v_old, v_new);

    v_old := '''__definition'',v_def,''__actor_user_id'',p_actor_user_id,''__source_user_id'',p_source_user_id,';
    v_new := '''__definition'',v_def,''__actor_user_id'',v_watch_actor,''__source_user_id'',v_watch_actor,';
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate card-effect watcher queue entry';
    END IF;
    v_def := replace(v_def, v_old, v_new);
    EXECUTE v_def;
  END IF;

  SELECT pg_get_functiondef(
    'public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure
  ) INTO v_def;

  -- When an evidence card is removed, first execute that removed card's own
  -- Hirameki under its owner. Field-watch effects use watch_user_id to inspect
  -- the opposing player's field and are queued separately by the effect runner.
  IF position('watch_user_id' IN v_def) = 0 THEN
    v_old := $old$
         SELECT user_id INTO v_trigger_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_evidence_owner
           ORDER BY seat LIMIT 1;
         IF v_trigger_owner IS NOT NULL THEN
           PERFORM public.private_card_effect_start_event_v1(
             p_room_id,v_trigger_owner,v_trigger_owner,v_old_evidence_card,'evidence.card_removed',
             jsonb_build_object(
               'turn_number',v_turn,
               'evidence_removed_instance_id',v_old_evidence_card->>'instance_id',
               'evidence_owner_user_id',v_evidence_owner::text,
               'removed_evidence_card',v_old_evidence_card
             ),NULL,false
           );
         END IF;
$old$;
    v_new := $new$
         SELECT user_id INTO v_trigger_owner
           FROM public.room_players
           WHERE room_id=p_room_id AND user_id<>v_evidence_owner
           ORDER BY seat LIMIT 1;
         PERFORM public.private_card_effect_start_event_v1(
           p_room_id,v_evidence_owner,v_evidence_owner,v_old_evidence_card,'evidence.card_removed',
           jsonb_build_object(
             'turn_number',v_turn,
             'evidence_removed_instance_id',v_old_evidence_card->>'instance_id',
             'evidence_owner_user_id',v_evidence_owner::text,
             'removed_evidence_card',v_old_evidence_card,
             'watch_user_id',coalesce(v_trigger_owner,v_evidence_owner)::text
           ),NULL,false
         );
$new$;
    IF position(v_old IN v_def) = 0 THEN
      RAISE EXCEPTION 'Could not locate evidence.card_removed dispatch';
    END IF;
    v_def := replace(v_def, v_old, v_new);
    EXECUTE v_def;
  END IF;

  -- ID 0704's Hirameki belongs to the card removed from evidence itself.
  UPDATE public.private_card_effect_catalog_v1
  SET definitions = (
    SELECT jsonb_agg(
      CASE
        WHEN e.value->>'effectId'='card-0704-hirameki-rest-character'
          THEN jsonb_set(e.value,'{trigger}',(e.value->'trigger')-'scope')
        ELSE e.value
      END ORDER BY e.ordinality
    )
    FROM jsonb_array_elements(definitions) WITH ORDINALITY e(value,ordinality)
  ),
  updated_at=now()
  WHERE catalog_id='main'
    AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(definitions) e(value)
      WHERE e.value->>'effectId'='card-0704-hirameki-rest-character'
        AND e.value->'trigger' ? 'scope'
    );
END
$migration$;
