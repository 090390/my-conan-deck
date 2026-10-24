-- Populate the ID:0301 opponent-field lock flag before the turn-start status conversion.

DO $patch$
DECLARE
  v_definition text;
  v_old_anchor text := $old_anchor$select coalesce(jsonb_agg(
      case when e.value ->> 'status' = 'stunned'$old_anchor$;
  v_new_anchor text := $new_anchor$select exists (
      select 1
      from public.room_player_turn_boards opponent
      cross join lateral jsonb_array_elements(coalesce(opponent.field_cards, '[]'::jsonb)) other_card(value)
      where opponent.room_id = p_room_id
        and opponent.user_id <> v_user
        and exists (
          select 1
          from unnest(array[
            other_card.value ->> 'key',
            other_card.value ->> 'databaseId',
            other_card.value ->> 'database_id',
            other_card.value ->> 'cardId',
            other_card.value ->> 'card_id',
            other_card.value ->> 'cardNum',
            other_card.value ->> 'card_num',
            other_card.value ->> 'id',
            other_card.value #>> '{sourceData,id}',
            other_card.value #>> '{sourceData,databaseId}',
            other_card.value #>> '{sourceData,database_id}',
            other_card.value #>> '{sourceData,cardId}',
            other_card.value #>> '{sourceData,card_id}',
            other_card.value #>> '{sourceData,cardNum}',
            other_card.value #>> '{sourceData,card_num}',
            other_card.value #>> '{raw,id}',
            other_card.value #>> '{raw,databaseId}',
            other_card.value #>> '{raw,database_id}',
            other_card.value #>> '{raw,cardId}',
            other_card.value #>> '{raw,card_id}',
            other_card.value #>> '{raw,cardNum}',
            other_card.value #>> '{raw,card_num}'
          ]) candidate(value)
          where coalesce(nullif(ltrim(btrim(candidate.value), '0'), ''), '0') = '301'
        )
    ) into v_kid_stun_lock;

    select coalesce(jsonb_agg(
      case when e.value ->> 'status' = 'stunned'$new_anchor$;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  IF position('into v_kid_stun_lock;' IN v_definition) = 0 THEN
    IF position(v_old_anchor IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Could not find the begin-turn field status conversion anchor.';
    END IF;
    v_definition := replace(v_definition, v_old_anchor, v_new_anchor);
  END IF;

  EXECUTE v_definition;
END
$patch$;
