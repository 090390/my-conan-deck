-- ID:0627 (犯人) cut-in gains AP +2000 for each 犯人 card already in the user's Remove area.
-- Compute the bonus server-side before placing the cut-in card into Remove, so the card being used
-- does not count itself toward its own bonus.
DO $culprit_cut_in_bonus$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT replace(pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure), chr(13), '')
    INTO v_definition;

  v_old := $old$v_bonus := greatest(0,coalesce(nullif(v_card ->> 'cut_in_bonus','')::integer,0));$old$;
  v_new := $new$v_bonus := greatest(0,coalesce(nullif(v_card ->> 'cut_in_bonus','')::integer,0));
    IF EXISTS (
      SELECT 1
      FROM unnest(ARRAY[
        v_card ->> 'key',
        v_card ->> 'databaseId', v_card ->> 'database_id',
        v_card ->> 'cardId', v_card ->> 'card_id',
        v_card ->> 'cardNum', v_card ->> 'card_num',
        v_card ->> 'cardNumber', v_card ->> 'card_number',
        v_card ->> 'id',
        v_card #>> '{sourceData,id}',
        v_card #>> '{sourceData,databaseId}', v_card #>> '{sourceData,database_id}',
        v_card #>> '{sourceData,cardId}', v_card #>> '{sourceData,card_id}',
        v_card #>> '{sourceData,cardNum}', v_card #>> '{sourceData,card_num}',
        v_card #>> '{sourceData,cardNumber}', v_card #>> '{sourceData,card_number}',
        v_card #>> '{source_data,id}',
        v_card #>> '{source_data,databaseId}', v_card #>> '{source_data,database_id}',
        v_card #>> '{source_data,cardId}', v_card #>> '{source_data,card_id}',
        v_card #>> '{source_data,cardNum}', v_card #>> '{source_data,card_num}',
        v_card #>> '{raw,id}', v_card #>> '{raw,cardId}', v_card #>> '{raw,card_id}'
      ]) AS cutin_ids(identifier)
      WHERE nullif(ltrim(regexp_replace(coalesce(cutin_ids.identifier,''), '[^0-9]', '', 'g'), '0'), '') = '627'
    ) THEN
      SELECT count(*)::integer
        INTO v_count
      FROM jsonb_array_elements(coalesce(v_game.remove_cards, '[]'::jsonb)) AS removed(value)
      WHERE
        EXISTS (
          SELECT 1
          FROM unnest(ARRAY[
            removed.value ->> 'name', removed.value ->> 'nameKo', removed.value ->> 'name_ko',
            removed.value ->> 'originalName', removed.value ->> 'original_name',
            removed.value ->> 'translatedName', removed.value ->> 'cardName', removed.value ->> 'card_name',
            removed.value #>> '{sourceData,name}', removed.value #>> '{sourceData,nameKo}',
            removed.value #>> '{sourceData,name_ko}', removed.value #>> '{sourceData,originalName}',
            removed.value #>> '{source_data,name}', removed.value #>> '{source_data,nameKo}',
            removed.value #>> '{raw,name}', removed.value #>> '{raw,nameKo}'
          ]) AS names(card_name)
          WHERE lower(btrim(coalesce(names.card_name,''))) IN ('범인','犯人')
        )
        OR (
          NOT EXISTS (
            SELECT 1
            FROM unnest(ARRAY[
              removed.value ->> 'name', removed.value ->> 'nameKo', removed.value ->> 'name_ko',
              removed.value ->> 'originalName', removed.value ->> 'original_name',
              removed.value ->> 'translatedName', removed.value ->> 'cardName', removed.value ->> 'card_name',
              removed.value #>> '{sourceData,name}', removed.value #>> '{sourceData,nameKo}',
              removed.value #>> '{sourceData,name_ko}', removed.value #>> '{sourceData,originalName}',
              removed.value #>> '{source_data,name}', removed.value #>> '{source_data,nameKo}',
              removed.value #>> '{raw,name}', removed.value #>> '{raw,nameKo}'
            ]) AS names(card_name)
            WHERE nullif(btrim(coalesce(names.card_name,'')), '') IS NOT NULL
          )
          AND EXISTS (
            SELECT 1
            FROM unnest(ARRAY[
              removed.value ->> 'key',
              removed.value ->> 'databaseId', removed.value ->> 'database_id',
              removed.value ->> 'cardId', removed.value ->> 'card_id',
              removed.value ->> 'cardNum', removed.value ->> 'card_num',
              removed.value ->> 'cardNumber', removed.value ->> 'card_number',
              removed.value ->> 'id',
              removed.value #>> '{sourceData,id}',
              removed.value #>> '{sourceData,databaseId}', removed.value #>> '{sourceData,database_id}',
              removed.value #>> '{sourceData,cardId}', removed.value #>> '{sourceData,card_id}',
              removed.value #>> '{sourceData,cardNum}', removed.value #>> '{sourceData,card_num}',
              removed.value #>> '{sourceData,cardNumber}', removed.value #>> '{sourceData,card_number}',
              removed.value #>> '{source_data,id}',
              removed.value #>> '{source_data,databaseId}', removed.value #>> '{source_data,database_id}',
              removed.value #>> '{source_data,cardId}', removed.value #>> '{source_data,card_id}',
              removed.value #>> '{source_data,cardNum}', removed.value #>> '{source_data,card_num}',
              removed.value #>> '{raw,id}', removed.value #>> '{raw,cardId}', removed.value #>> '{raw,card_id}'
            ]) AS remove_ids(identifier)
            WHERE nullif(ltrim(regexp_replace(coalesce(remove_ids.identifier,''), '[^0-9]', '', 'g'), '0'), '') IN ('627','1039')
          )
        );
      v_bonus := 2000 * greatest(coalesce(v_count,0),0);
    END IF;$new$;

  IF position(v_old IN v_definition) = 0 THEN
    IF position(v_new IN v_definition) = 0 THEN
      RAISE EXCEPTION 'Culprit cut-in migration stopped: cut-in bonus calculation anchor was not found.';
    END IF;
  ELSE
    v_definition := replace(v_definition, v_old, v_new);
  END IF;

  IF v_definition IS NULL OR length(btrim(v_definition)) = 0 THEN
    RAISE EXCEPTION 'Culprit cut-in migration stopped: gameplay function definition is empty.';
  END IF;
  EXECUTE v_definition;
END
$culprit_cut_in_bonus$;