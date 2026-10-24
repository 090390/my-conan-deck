-- Correct ID:0627 cut-in calculation.
-- Count only cards whose Korean card name is exactly "범인" (not every card with the [범인] trait),
-- and include the cut-in card itself as the printed card text specifies.
DO $culprit_cut_in_bonus_fix$
DECLARE
  v_definition text;
  v_start integer;
  v_end integer;
  v_old_anchor text := $anchor$v_bonus := greatest(0,coalesce(nullif(v_card ->> 'cut_in_bonus','')::integer,0));$anchor$;
  v_next_anchor text := $next$    select coalesce(jsonb_agg(e.value order by e.ordinality) filter(where e.value ->> 'instance_id'<>v_id),'[]'::jsonb) into v_hand_new$next$;
  v_new_block text := $block$v_bonus := greatest(0,coalesce(nullif(v_card ->> 'cut_in_bonus','')::integer,0));
    IF upper(coalesce(v_card ->> 'key','')) IN ('PR158','PR164')
       OR EXISTS (
         SELECT 1
         FROM unnest(ARRAY[
           v_card ->> 'cardId', v_card ->> 'card_id', v_card ->> 'cardNum', v_card ->> 'card_num',
           v_card ->> 'databaseId', v_card ->> 'database_id', v_card ->> 'id',
           v_card #>> '{sourceData,cardId}', v_card #>> '{sourceData,card_id}',
           v_card #>> '{sourceData,cardNum}', v_card #>> '{sourceData,card_num}',
           v_card #>> '{sourceData,databaseId}', v_card #>> '{sourceData,database_id}',
           v_card #>> '{sourceData,id}'
         ]) AS cutin_ids(identifier)
         WHERE nullif(ltrim(regexp_replace(coalesce(cutin_ids.identifier,''), '[^0-9]', '', 'g'), '0'), '') = '627'
       )
    THEN
      SELECT count(*)::integer
        INTO v_count
      FROM jsonb_array_elements(coalesce(v_game.remove_cards, '[]'::jsonb)) AS removed(value)
      WHERE upper(coalesce(removed.value ->> 'key','')) IN (
          'B02088','B02088P','B03126','B07102','B09100','B09101','B10094',
          'PR158','PR164','PR237','PR243',
          '0249','0375','0829','1039','1040','1149','0627','0935'
        )
        OR EXISTS (
          SELECT 1
          FROM unnest(ARRAY[
            removed.value ->> 'cardId', removed.value ->> 'card_id',
            removed.value ->> 'cardNum', removed.value ->> 'card_num',
            removed.value ->> 'databaseId', removed.value ->> 'database_id',
            removed.value #>> '{sourceData,cardId}', removed.value #>> '{sourceData,card_id}',
            removed.value #>> '{sourceData,cardNum}', removed.value #>> '{sourceData,card_num}',
            removed.value #>> '{sourceData,databaseId}', removed.value #>> '{sourceData,database_id}',
            removed.value #>> '{sourceData,id}'
          ]) AS remove_ids(identifier)
          WHERE nullif(ltrim(regexp_replace(coalesce(remove_ids.identifier,''), '[^0-9]', '', 'g'), '0'), '')
            IN ('249','375','829','1039','1040','1149','627','935')
        );
      -- The current cut-in card enters Remove as part of this action ("이 카드 포함").
      v_bonus := 2000 * (greatest(coalesce(v_count,0),0) + 1);
    END IF;$block$;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  v_start := position(v_old_anchor IN v_definition);
  IF v_start = 0 THEN
    -- Idempotent if the corrected implementation is already installed.
    IF position($corrected$ v_bonus := 2000 * (greatest(coalesce(v_count,0),0) + 1);$corrected$ IN v_definition) > 0 THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Culprit cut-in correction stopped: existing bonus block was not found.';
  END IF;

  v_end := position(v_next_anchor IN substring(v_definition FROM v_start));
  IF v_end <= 0 THEN
    RAISE EXCEPTION 'Culprit cut-in correction stopped: next hand-update anchor was not found.';
  END IF;

  v_definition := substring(v_definition FROM 1 FOR v_start - 1)
    || v_new_block || E'\n    '
    || substring(v_definition FROM v_start + v_end - 1);

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'Culprit cut-in correction stopped: gameplay function definition is empty.';
  END IF;
  EXECUTE v_definition;
END
$culprit_cut_in_bonus_fix$;