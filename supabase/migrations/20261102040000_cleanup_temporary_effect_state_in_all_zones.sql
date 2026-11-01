
CREATE OR REPLACE FUNCTION public.private_card_effect_prune_temporary_card_state_v1(
 p_card jsonb,p_turn_number integer
) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=public AS $$
DECLARE
 v_card jsonb:=p_card;
 v_keywords jsonb;
BEGIN
 IF p_card IS NULL THEN RETURN NULL; END IF;
 IF coalesce(nullif(p_card->>'dsl_original_abilities_disabled_until_turn','')::integer,-1)<coalesce(p_turn_number,0) THEN
   v_card:=v_card-'dsl_original_abilities_disabled'-'dsl_original_abilities_disabled_until_turn';
 END IF;
 IF v_card ? 'dsl_keywords' THEN
   SELECT coalesce(jsonb_agg(k.value ORDER BY k.ordinality),'[]'::jsonb) INTO v_keywords
   FROM jsonb_array_elements(coalesce(v_card->'dsl_keywords','[]'::jsonb)) WITH ORDINALITY k(value,ordinality)
   WHERE coalesce(nullif(k.value->>'expires_turn_number','')::integer,2147483647)>=coalesce(p_turn_number,0);
   v_card:=jsonb_set(v_card,'{dsl_keywords}',coalesce(v_keywords,'[]'::jsonb),true);
 END IF;
 RETURN v_card;
END;
$$;

CREATE OR REPLACE FUNCTION public.private_card_effect_recalculate_continuous_v1(p_room_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_catalog jsonb; v_board public.room_player_turn_boards%rowtype;
 v_target_wrap jsonb; v_source_wrap jsonb; v_target_card jsonb; v_source_card jsonb;
 v_def jsonb; v_step jsonb; v_ap numeric; v_old_ap numeric; v_lp numeric; v_old_lp numeric;
 v_level numeric; v_old_level numeric; v_keywords jsonb; v_context jsonb:='{}'::jsonb;
 v_vars jsonb:='{}'::jsonb; v_owner uuid; v_target_owner uuid;
 v_target_id text; v_source_id text; v_target_is_partner boolean; v_current jsonb; v_multiplier numeric:=1; v_turn integer;
BEGIN
 SELECT coalesce(turn_number,0) INTO v_turn FROM public.room_match_states WHERE room_id=p_room_id;
 UPDATE public.room_player_turn_boards b
 SET field_cards=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     partner_mr_card=public.private_card_effect_prune_temporary_card_state_v1(b.partner_mr_card,coalesce(v_turn,0)),
     partner_non_mr_cards=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(b.partner_non_mr_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     updated_at=now()
 WHERE b.room_id=p_room_id;

 UPDATE public.room_player_game_states gs
 SET hand=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(gs.hand,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     deck_order=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(gs.deck_order,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     remove_cards=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(gs.remove_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     file_cards=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(gs.file_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     evidence_cards=coalesce((
       SELECT jsonb_agg(public.private_card_effect_prune_temporary_card_state_v1(e.value,coalesce(v_turn,0)) ORDER BY e.ordinality)
       FROM jsonb_array_elements(coalesce(gs.evidence_cards,'[]'::jsonb)) WITH ORDINALITY e(value,ordinality)
     ),'[]'::jsonb),
     updated_at=now()
 WHERE gs.room_id=p_room_id;
 SELECT definitions INTO v_catalog FROM public.private_card_effect_catalog_v1 WHERE catalog_id='main';
 FOR v_board IN SELECT * FROM public.room_player_turn_boards WHERE room_id=p_room_id LOOP
   v_owner:=v_board.user_id;
   FOR v_target_wrap IN
     SELECT jsonb_build_object('card',e.value,'owner_user_id',v_owner,'is_partner',false)
       FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
     UNION ALL SELECT jsonb_build_object('card',v_board.partner_mr_card,'owner_user_id',v_owner,'is_partner',true)
       WHERE v_board.partner_mr_card IS NOT NULL
     UNION ALL SELECT jsonb_build_object('card',e.value,'owner_user_id',b.user_id,'is_partner',false)
       FROM public.room_player_turn_boards b CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.field_cards,'[]'::jsonb)) e(value)
       WHERE b.room_id=p_room_id AND b.user_id<>v_owner
   LOOP
     v_target_card:=v_target_wrap->'card';
     v_target_owner:=nullif(v_target_wrap->>'owner_user_id','')::uuid;
     v_target_id:=v_target_card->>'instance_id';
     v_target_is_partner:=coalesce((v_target_wrap->>'is_partner')::boolean,false);
     v_ap:=0; v_lp:=0; v_level:=0; v_keywords:='[]'::jsonb;
     FOR v_source_wrap IN
       SELECT jsonb_build_object('card',e.value) FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) e(value)
       UNION ALL SELECT jsonb_build_object('card',v_board.partner_mr_card) WHERE v_board.partner_mr_card IS NOT NULL
     LOOP
       v_source_card:=v_source_wrap->'card';
       v_source_id:=v_source_card->>'instance_id';
       FOR v_def IN SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
         WHERE coalesce((d.value->>'continuous')::boolean,false)
           AND NOT coalesce((v_source_card->>'dsl_original_abilities_disabled')::boolean,false)
          AND public.private_card_effect_matches_id_v1(v_source_card,coalesce(d.value->'cardIds','[]'::jsonb))
       LOOP
         IF NOT public.private_card_effect_conditions_match_v1(
           p_room_id,v_owner,v_owner,v_source_card,v_context,v_vars,coalesce(v_def->'conditions','[]'::jsonb)
         ) THEN CONTINUE; END IF;
         FOR v_step IN SELECT value FROM jsonb_array_elements(coalesce(v_def->'steps','[]'::jsonb)) LOOP
           IF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='ap' THEN
             IF coalesce(v_step->>'target','source_character')='source_character'
                AND v_target_owner=v_owner AND v_target_id=v_source_id THEN
               v_multiplier:=1;
               IF coalesce((v_step->>'amountPerUnderCard')::boolean,false) THEN
                 v_multiplier:=jsonb_array_length(coalesce(v_source_card->'under_cards',v_source_card->'stacked_cards','[]'::jsonb));
               END IF;
               v_ap:=v_ap+coalesce((v_step->>'amount')::numeric,0)*v_multiplier;
             ELSIF v_step->>'target'='own_field_characters_except_source'
                AND v_target_owner=v_owner AND NOT v_target_is_partner AND v_target_id IS DISTINCT FROM v_source_id THEN
               v_ap:=v_ap+coalesce((v_step->>'amount')::numeric,0);
             END IF;
           ELSIF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='lp'
             AND coalesce(v_step->>'target','source_character')='source_character'
             AND v_target_owner=v_owner AND v_target_id=v_source_id THEN
             v_lp:=v_lp+coalesce((v_step->>'amount')::numeric,0);
           ELSIF v_step->>'op'='set_continuous_stat' AND v_step->>'stat'='level'
             AND v_step->>'target'='opponent_field_characters'
             AND v_target_owner<>v_owner AND NOT v_target_is_partner THEN
             v_level:=v_level+coalesce((v_step->>'amount')::numeric,0);
           ELSIF v_step->>'op'='set_continuous_keyword'
             AND coalesce(v_step->>'target','source_character')='source_character'
             AND v_target_owner=v_owner AND v_target_id=v_source_id THEN
             v_keywords:=v_keywords||jsonb_build_array(jsonb_build_object(
               'effect_id',v_def->>'effectId','keyword',v_step->>'keyword'
             ));
           END IF;
         END LOOP;
       END LOOP;
     END LOOP;
     v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_target_id);
     IF v_current IS NULL THEN CONTINUE; END IF;
     v_old_ap:=coalesce(nullif(v_current->>'dsl_ap_bonus','')::numeric,0);
     v_old_lp:=coalesce(nullif(v_current->>'dsl_lp_bonus','')::numeric,0);
     v_old_level:=coalesce(nullif(v_current->>'dsl_continuous_level_bonus','')::numeric,0);
     PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_target_id,jsonb_build_object(
       'ap_bonus',coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)-v_old_ap+v_ap,'dsl_ap_bonus',v_ap,
       'lp_bonus',coalesce(nullif(v_current->>'lp_bonus','')::numeric,0)-v_old_lp+v_lp,'dsl_lp_bonus',v_lp,
       'level_bonus',coalesce(nullif(v_current->>'level_bonus','')::numeric,0)-v_old_level+v_level,
       'dsl_continuous_level_bonus',v_level,'dsl_continuous_keywords',v_keywords
     ));
   END LOOP;
 END LOOP;
END
$function$;
