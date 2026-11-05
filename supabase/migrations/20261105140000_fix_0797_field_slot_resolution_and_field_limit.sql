BEGIN;

CREATE OR REPLACE FUNCTION public.private_card_effect_move_card_v1(p_room_id uuid, p_owner_user uuid, p_from_zone text, p_card jsonb, p_to_zone text, p_target_user uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_source_user uuid:=p_owner_user; v_target_user uuid:=coalesce(p_target_user,p_owner_user);
 v_id text:=p_card->>'instance_id'; v_card jsonb:=p_card;
 v_game public.room_player_game_states%rowtype; v_board public.room_player_turn_boards%rowtype;
 v_old_partner jsonb; v_rarity text; v_character_count integer;
BEGIN
 IF v_id IS NULL OR v_id='' THEN RAISE EXCEPTION '카드 효과 이동에 instance_id가 없습니다.'; END IF;
 IF p_from_zone NOT IN ('peek','variable','') THEN
   IF p_from_zone='field' THEN
     SELECT * INTO v_board FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF NOT FOUND THEN RAISE EXCEPTION '카드 이동 원본 현장을 찾을 수 없습니다.'; END IF;
     UPDATE public.room_player_turn_boards SET field_cards=public.private_card_effect_remove_from_array_v1(field_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='hand' THEN
     UPDATE public.room_player_game_states SET hand=public.private_card_effect_remove_from_array_v1(hand,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='remove_area' THEN
     UPDATE public.room_player_game_states SET remove_cards=public.private_card_effect_remove_from_array_v1(remove_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
     UPDATE public.room_player_turn_boards SET remove_count=greatest(0,remove_count-1),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='deck' THEN
     UPDATE public.room_player_game_states SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='evidence_area' THEN
     UPDATE public.room_player_game_states SET evidence_cards=public.private_card_effect_remove_from_array_v1(evidence_cards,v_id),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
     UPDATE public.room_player_turn_boards SET evidence_count=greatest(0,evidence_count-1),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSIF p_from_zone='attachment' THEN
     UPDATE public.room_player_turn_boards b
       SET field_cards=coalesce((
         SELECT jsonb_agg(CASE WHEN e.value->>'instance_id'=p_card->>'attached_to_instance_id' THEN
           jsonb_set(jsonb_set(e.value,'{under_cards}',coalesce((
             SELECT jsonb_agg(a.value ORDER BY a.ordinality) FROM jsonb_array_elements(coalesce(e.value->'under_cards','[]'::jsonb)) WITH ORDINALITY a(value,ordinality)
             WHERE a.value->>'instance_id' IS DISTINCT FROM v_id),'[]'::jsonb),true),
           '{stacked_cards}',coalesce((
             SELECT jsonb_agg(a.value ORDER BY a.ordinality) FROM jsonb_array_elements(coalesce(e.value->'stacked_cards','[]'::jsonb)) WITH ORDINALITY a(value,ordinality)
             WHERE a.value->>'instance_id' IS DISTINCT FROM v_id),'[]'::jsonb),true)
         ELSE e.value END ORDER BY e.ordinality)
         FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
       ),'[]'::jsonb),updated_at=now()
     WHERE b.room_id=p_room_id AND b.user_id=v_source_user;
      UPDATE public.room_player_turn_boards b
        SET field_cards=coalesce((
          SELECT jsonb_agg(CASE WHEN e.value->>'instance_id'=p_card->>'attached_to_instance_id'
            THEN jsonb_set(e.value,'{set_cards}',coalesce((
              SELECT jsonb_agg(a.value ORDER BY a.ordinality)
              FROM jsonb_array_elements(coalesce(e.value->'set_cards','[]'::jsonb)) WITH ORDINALITY a(value,ordinality)
              WHERE a.value->>'instance_id' IS DISTINCT FROM v_id
            ),'[]'::jsonb),true)
            ELSE e.value END ORDER BY e.ordinality)
          FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
        ),'[]'::jsonb),updated_at=now()
      WHERE b.room_id=p_room_id AND b.user_id=v_source_user;
   END IF;
 END IF;

 v_card:=v_card-'zone'-'owner_user_id'-'resolving'-'dsl_remove_trigger_queued'-'attached_to_instance_id'-'parent_instance_id';
 IF p_from_zone='field' AND p_to_zone<>'field' THEN
   v_card:=v_card-'rested'-'status'-'stunned'-'stun'-'is_stunned'
     -'ap_bonus'-'level_bonus'-'summoned_this_turn'-'rested_until_turn'-'stun_until_turn';
 END IF;
 IF p_from_zone='field' AND p_to_zone='remove_area' THEN v_card:=v_card||jsonb_build_object('dsl_remove_trigger_queued',true); END IF;
 IF p_to_zone='hand' THEN
   UPDATE public.room_player_game_states SET hand=coalesce(hand,'[]'::jsonb)||jsonb_build_array(v_card),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSIF p_to_zone='remove_area' THEN
   v_rarity:=upper(coalesce(v_card->>'rarity',v_card->>'rarity_code',v_card#>>'{sourceData,rarity}',v_card#>>'{raw,rarity}',''));
   IF p_from_zone='field' AND v_rarity IN ('MR','MRP') THEN
     SELECT partner_mr_card INTO v_old_partner FROM public.room_player_turn_boards WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF v_old_partner IS NOT NULL AND v_old_partner->>'instance_id' IS DISTINCT FROM v_id THEN
       UPDATE public.room_player_game_states SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_old_partner-'rested'-'status'-'ap_bonus'-'level_bonus'-'summoned_this_turn'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
       UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now() WHERE room_id=p_room_id AND user_id=v_source_user;
     END IF;
     UPDATE public.room_player_turn_boards SET partner_mr_card=v_card||jsonb_build_object('rested',false,'status','active','ap_bonus',0,'level_bonus',0,'summoned_this_turn',false),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSE
     UPDATE public.room_player_game_states SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'level_bonus'-'summoned_this_turn'),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
     UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
   END IF;
 ELSIF p_to_zone='deck_bottom' THEN
   UPDATE public.room_player_game_states SET deck_order=coalesce(deck_order,'[]'::jsonb)||jsonb_build_array(v_card-'dsl_return_to_deck_bottom_turn'-'dsl_return_to_deck_bottom_after_user_id'),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSIF p_to_zone='evidence_area' THEN
   v_rarity:=upper(coalesce(v_card->>'rarity',v_card->>'rarity_code',v_card#>>'{sourceData,rarity}',v_card#>>'{raw,rarity}',''));
   IF p_from_zone='field' AND v_rarity IN ('MR','MRP') THEN
     SELECT partner_mr_card INTO v_old_partner FROM public.room_player_turn_boards
       WHERE room_id=p_room_id AND user_id=v_source_user FOR UPDATE;
     IF v_old_partner IS NOT NULL AND v_old_partner->>'instance_id' IS DISTINCT FROM v_id THEN
       UPDATE public.room_player_game_states
         SET remove_cards=coalesce(remove_cards,'[]'::jsonb)||jsonb_build_array(v_old_partner-'rested'-'status'-'ap_bonus'-'level_bonus'-'summoned_this_turn'),
             updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
       UPDATE public.room_player_turn_boards SET remove_count=remove_count+1,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_source_user;
     END IF;
     UPDATE public.room_player_turn_boards
       SET partner_mr_card=v_card||jsonb_build_object('rested',false,'status','active','ap_bonus',0,'level_bonus',0,'summoned_this_turn',false),
           updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_source_user;
   ELSE
     UPDATE public.room_player_game_states SET evidence_cards=coalesce(evidence_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object('face_up',coalesce(nullif(v_card->>'face_up','')::boolean,true))),updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
     UPDATE public.room_player_turn_boards SET evidence_count=evidence_count+1,updated_at=now()
       WHERE room_id=p_room_id AND user_id=v_target_user;
   END IF;
 ELSIF p_to_zone='field' THEN
   IF public.private_card_effect_is_character_v1(v_card) THEN
     SELECT count(*)::integer INTO v_character_count
     FROM public.room_player_turn_boards b
     CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
     WHERE b.room_id=p_room_id AND b.user_id=v_target_user
       AND public.private_card_effect_is_character_v1(e.value);
     IF v_character_count >= 5 THEN
       RAISE EXCEPTION '현장 캐릭터는 최대 5장까지 배치할 수 있습니다. 먼저 현장 캐릭터를 리무브하세요.';
     END IF;
   END IF;
   UPDATE public.room_player_turn_boards SET field_cards=coalesce(field_cards,'[]'::jsonb)||jsonb_build_array(v_card||jsonb_build_object(
     'rested',coalesce((v_card->>'rested')::boolean,false),
     'status',coalesce(v_card->>'status',CASE WHEN coalesce((v_card->>'rested')::boolean,false) THEN 'rested' ELSE 'active' END),
     'summoned_this_turn',true,'ap_bonus',0,'entry_method',coalesce(v_card->>'entry_method','event_effect'))),updated_at=now()
     WHERE room_id=p_room_id AND user_id=v_target_user;
 ELSE
   RAISE EXCEPTION '카드 효과 이동 목적지 %는 아직 지원하지 않습니다.',p_to_zone;
 END IF;
 IF p_from_zone='field' AND p_to_zone='remove_area' AND v_rarity NOT IN ('MR','MRP')
    AND public.private_card_effect_is_character_v1(p_card)
    AND EXISTS(SELECT 1 FROM public.private_card_effect_runs_v1 WHERE room_id=p_room_id) THEN
   PERFORM public.private_card_effect_queue_field_removal_triggers_v1(p_room_id,v_source_user,p_card);
 END IF;
END;
$function$;

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = (
  SELECT coalesce(jsonb_agg(
    CASE
      WHEN e.value->>'effectId'='card-0797-on-enter-revive-red-level5'
        THEN jsonb_set(e.value,'{steps}',$steps$[{"op":"filter_cards","from":"remove_area","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":5}]},"saveAs":"available_deployments"},{"op":"offer_reaction","reactionId":"card-0797-revive-red-level5","actor":"controller","choices":["yes","no"],"saveAs":"revive_choice","when":{"allOf":[{"fact":"vars.available_deployments.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"greater_than_or_equal","value":1}]},"prompt":"하네다 슈키치를 슬립시키고 손패 1장을 리무브해 적 레벨 5 이하 캐릭터를 재등장시킬까요?"},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"},"prompt":"비용으로 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"field","targetController":"self","min":1,"max":1,"optional":false,"saveAs":"field_slot_cost","filter":{"field":"card_type","operator":"equals","value":"character"},"prompt":"현장이 캐릭터 5장으로 가득 찼습니다. 재등장 자리를 만들기 위해 자신의 현장 캐릭터 1장을 리무브하세요.","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"player.field.character.count","operator":"greater_than_or_equal","value":5}]}},{"op":"move_cards","from":"field_slot_cost","to":"remove_area","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.field_slot_cost.count","operator":"greater_than","value":0}]}},{"op":"select_cards","from":"vars.available_deployments","min":0,"max":1,"optional":true,"saveAs":"deployment","when":{"fact":"vars.revive_choice","operator":"equals","value":"yes"},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"color","operator":"equals","value":"red"},{"field":"level","operator":"less_than_or_equal","value":5}]},"prompt":"리무브 에이리어에서 레벨 5 이하 적 캐릭터를 최대 1장 선택해 등장시키세요."},{"op":"move_cards","from":"deployment","to":"field","entryMethod":"character_ability","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]}},{"op":"rest_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]}},{"op":"ready_source_character","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}},{"op":"ready_cards","target":"vars.deployment","when":{"allOf":[{"fact":"vars.revive_choice","operator":"equals","value":"yes"},{"fact":"vars.deployment.count","operator":"greater_than","value":0},{"fact":"player.hand.count","operator":"less_than_or_equal","value":2}]}}]$steps$::jsonb,true)
      ELSE e.value
    END ORDER BY e.ordinality
  ),'[]'::jsonb)
  FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb))
       WITH ORDINALITY e(value,ordinality)
),
updated_at=now()
WHERE c.catalog_id='main'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) x(value)
    WHERE x.value->>'effectId'='card-0797-on-enter-revive-red-level5'
  );

COMMIT;
