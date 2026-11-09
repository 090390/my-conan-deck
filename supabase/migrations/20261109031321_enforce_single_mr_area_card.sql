-- Enforce one MR/MRP across the field and the MR partner area.
-- A newly entering MR/MRP replaces every other MR/MRP directly into Remove.
BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_rarity_for_mr_rule_v1(
  p_room_id uuid,
  p_user_id uuid,
  p_card jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_rarity text;
BEGIN
  v_rarity := coalesce(
    nullif(upper(trim(p_card->>'rarity')),''),
    nullif(upper(trim(p_card->>'rarity_code')),''),
    nullif(upper(trim(p_card->>'rarityCode')),''),
    nullif(upper(trim(p_card#>>'{sourceData,rarity}')),''),
    nullif(upper(trim(p_card#>>'{raw,rarity}')),'')
  );

  IF v_rarity IS NOT NULL THEN
    RETURN v_rarity;
  END IF;

  SELECT upper(nullif(trim(d.value->>'rarity'),''))
  INTO v_rarity
  FROM public.room_player_decks deck
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(deck.main_deck,'[]'::jsonb)) d(value)
  WHERE deck.room_id=p_room_id
    AND deck.user_id=p_user_id
    AND d.value->>'key'=p_card->>'key'
  LIMIT 1;

  RETURN coalesce(v_rarity,'');
END
$function$;

REVOKE ALL ON FUNCTION public.private_card_rarity_for_mr_rule_v1(uuid,uuid,jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.enforce_single_mr_area_card_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_old_field jsonb := '[]'::jsonb;
  v_old_partner jsonb;
  v_new_partner_id text;
  v_keep_id text;
  v_keep_in_partner boolean := false;
  v_candidate record;
  v_card jsonb;
  v_field_new jsonb := '[]'::jsonb;
  v_removed jsonb := '[]'::jsonb;
  v_clean jsonb;
  v_removed_count integer := 0;
  v_game_found boolean := false;
  v_label text;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF NEW.field_cards IS NOT DISTINCT FROM OLD.field_cards
       AND NEW.partner_mr_card IS NOT DISTINCT FROM OLD.partner_mr_card THEN
      RETURN NEW;
    END IF;
    v_old_field := coalesce(OLD.field_cards,'[]'::jsonb);
    v_old_partner := OLD.partner_mr_card;
  ELSE
    v_old_partner := NULL;
  END IF;

  -- A replacement entering the MR partner area is the newest MR/MRP.
  IF NEW.partner_mr_card IS NOT NULL
     AND public.private_card_rarity_for_mr_rule_v1(
       NEW.room_id,NEW.user_id,NEW.partner_mr_card
     ) IN ('MR','MRP')
     AND (
       TG_OP='INSERT'
       OR NEW.partner_mr_card->>'instance_id'
          IS DISTINCT FROM v_old_partner->>'instance_id'
     ) THEN
    v_keep_id := NEW.partner_mr_card->>'instance_id';
    v_keep_in_partner := true;
  ELSE
    -- Otherwise keep the newest MR/MRP newly added to the field.
    -- field_cards is appended in play order, so the last new entry wins.
    FOR v_candidate IN
      SELECT e.value,e.ordinality
      FROM jsonb_array_elements(coalesce(NEW.field_cards,'[]'::jsonb))
        WITH ORDINALITY e(value,ordinality)
      WHERE public.private_card_rarity_for_mr_rule_v1(
              NEW.room_id,NEW.user_id,e.value
            ) IN ('MR','MRP')
        AND (
          TG_OP='INSERT'
          OR NOT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(v_old_field) old_card(value)
            WHERE old_card.value->>'instance_id'=e.value->>'instance_id'
          )
        )
      ORDER BY e.ordinality DESC
    LOOP
      v_keep_id := v_candidate.value->>'instance_id';
      EXIT;
    END LOOP;
  END IF;

  -- No new MR/MRP entered either allowed area in this update.
  -- In particular, do not intercept the first half of a field-to-partner move.
  IF coalesce(v_keep_id,'')='' THEN
    RETURN NEW;
  END IF;

  FOR v_candidate IN
    SELECT e.value,e.ordinality
    FROM jsonb_array_elements(coalesce(NEW.field_cards,'[]'::jsonb))
      WITH ORDINALITY e(value,ordinality)
    ORDER BY e.ordinality
  LOOP
    v_card := v_candidate.value;
    IF public.private_card_rarity_for_mr_rule_v1(
         NEW.room_id,NEW.user_id,v_card
       ) IN ('MR','MRP') THEN
      IF NOT v_keep_in_partner
         AND v_card->>'instance_id'=v_keep_id THEN
        v_field_new := v_field_new||jsonb_build_array(v_card);
      ELSIF v_card->>'instance_id' IS DISTINCT FROM v_keep_id THEN
        v_clean := v_card
          - 'rested' - 'status' - 'stunned' - 'stun' - 'is_stunned'
          - 'ap_bonus' - 'level_bonus' - 'summoned_this_turn'
          - 'resolving' - 'rested_until_turn' - 'stun_until_turn';
        IF NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_removed) existing(value)
          WHERE existing.value->>'instance_id'=v_card->>'instance_id'
        ) THEN
          v_removed := v_removed||jsonb_build_array(v_clean);
        END IF;
      END IF;
    ELSE
      v_field_new := v_field_new||jsonb_build_array(v_card);
    END IF;
  END LOOP;

  -- When the incoming card is a field card, any old MR partner is also replaced.
  IF NOT v_keep_in_partner
     AND NEW.partner_mr_card IS NOT NULL
     AND public.private_card_rarity_for_mr_rule_v1(
       NEW.room_id,NEW.user_id,NEW.partner_mr_card
     ) IN ('MR','MRP') THEN
    IF NEW.partner_mr_card->>'instance_id' IS DISTINCT FROM v_keep_id THEN
      v_clean := NEW.partner_mr_card
        - 'rested' - 'status' - 'stunned' - 'stun' - 'is_stunned'
        - 'ap_bonus' - 'level_bonus' - 'summoned_this_turn'
        - 'resolving' - 'rested_until_turn' - 'stun_until_turn';
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_removed) existing(value)
        WHERE existing.value->>'instance_id'=NEW.partner_mr_card->>'instance_id'
      ) THEN
        v_removed := v_removed||jsonb_build_array(v_clean);
      END IF;
    END IF;
    NEW.partner_mr_card := NULL;
  ELSIF v_keep_in_partner THEN
    -- A duplicate copy of the incoming partner card must not remain in the field.
    NULL;
  END IF;

  v_removed_count := jsonb_array_length(v_removed);
  NEW.field_cards := v_field_new;

  IF v_removed_count>0 THEN
    UPDATE public.room_player_game_states gs
    SET remove_cards=coalesce(gs.remove_cards,'[]'::jsonb)||v_removed,
        updated_at=now()
    WHERE gs.room_id=NEW.room_id AND gs.user_id=NEW.user_id;
    GET DIAGNOSTICS v_removed_count = ROW_COUNT;
    IF v_removed_count=0 THEN
      RAISE EXCEPTION '교체된 MR/MRP를 리무브 에이리어로 보낼 플레이어 상태가 없습니다.';
    END IF;

    v_removed_count := jsonb_array_length(v_removed);
    NEW.remove_count := coalesce(NEW.remove_count,0)+v_removed_count;
    NEW.updated_at := now();

    v_label := format(
      '새 MR/MRP %s가 들어와 기존 MR/MRP %s장을 리무브 에이리어로 바로 이동했습니다.',
      coalesce(
        CASE WHEN v_keep_in_partner THEN NEW.partner_mr_card->>'key' ELSE
          (SELECT e.value->>'key'
           FROM jsonb_array_elements(coalesce(NEW.field_cards,'[]'::jsonb)) e(value)
           WHERE e.value->>'instance_id'=v_keep_id LIMIT 1)
        END,
        '카드'
      ),
      v_removed_count
    );
    UPDATE public.room_match_states m
    SET state_version=state_version+1,last_action_label=v_label
    WHERE m.room_id=NEW.room_id;
  END IF;

  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.enforce_single_mr_area_card_v1()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS room_turn_board_enforce_single_mr_area_card
  ON public.room_player_turn_boards;

CREATE TRIGGER room_turn_board_enforce_single_mr_area_card
BEFORE INSERT OR UPDATE OF field_cards,partner_mr_card
ON public.room_player_turn_boards
FOR EACH ROW
EXECUTE FUNCTION public.enforce_single_mr_area_card_v1();

-- A stale UI "departed MR" recovery must not put an older card back into the
-- partner area after the new global MR slot has already been occupied.
DO $patch_auto_store$
DECLARE
  v_definition text;
  v_anchor text;
  v_insert text;
BEGIN
  SELECT pg_get_functiondef(
    'public.auto_store_departed_mr_partner_v2(uuid,uuid,jsonb)'::regprocedure
  ) INTO v_definition;

  v_definition := replace(v_definition,E'\r\n',E'\n');
  v_anchor := $anchor$  -- If an MR is already in the partner area, a newly departed MR replaces it and the previous one moves to remove.$anchor$;

  v_insert := $insert$  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) field_card(value)
    WHERE field_card.value->>'instance_id' IS DISTINCT FROM v_card_id
      AND public.private_card_rarity_for_mr_rule_v1(
        p_room_id,p_owner_user_id,field_card.value
      ) IN ('MR','MRP')
  ) OR (
    v_existing IS NOT NULL
    AND coalesce(v_existing->>'instance_id','')<>v_card_id
    AND public.private_card_rarity_for_mr_rule_v1(
      p_room_id,p_owner_user_id,v_existing
    ) IN ('MR','MRP')
  ) THEN
    -- Another MR/MRP already occupies the shared field + partner slot.
    -- Keep this departed card in Remove; never restore it to the MR partner area.
    v_clean_card := p_card
      - 'rested' - 'status' - 'stunned' - 'stun' - 'is_stunned'
      - 'ap_bonus' - 'level_bonus' - 'summoned_this_turn' - 'resolving'
      - 'rested_until_turn' - 'stun_until_turn'
      - 'host_instance_id' - 'set_owner_user_id';
    UPDATE public.room_player_game_states gs
      SET remove_cards=coalesce(gs.remove_cards,'[]'::jsonb)||jsonb_build_array(v_clean_card),
          updated_at=now()
      WHERE gs.room_id=p_room_id AND gs.user_id=p_owner_user_id;
    UPDATE public.room_player_turn_boards
      SET remove_count=coalesce(remove_count,0)+1,updated_at=now()
      WHERE room_id=p_room_id AND user_id=p_owner_user_id;
    UPDATE public.room_match_states
      SET state_version=state_version+1,
          last_action_label=format(
            '새 MR/MRP가 이미 존재하여 현장을 떠난 기존 MR/MRP %s를 MR 파트너 에이리어를 거치지 않고 리무브로 이동했습니다.',
            coalesce(p_card->>'key','카드')
          )
      WHERE room_id=p_room_id;
    RETURN public.get_private_turn_state_v2(p_room_id);
  END IF;

$insert$;

  IF position(v_anchor IN v_definition)=0 THEN
    IF position('현장을 떠난 기존 MR/MRP' IN v_definition)>0 THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'auto_store_departed_mr_partner_v2 patch anchor was not found.';
  END IF;

  v_definition := replace(v_definition,v_anchor,v_insert||v_anchor);
  EXECUTE v_definition;
END
$patch_auto_store$;

COMMIT;