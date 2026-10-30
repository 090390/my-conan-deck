-- Allow AI and the effect engine to activate card abilities explicitly usable from
-- a non-MR partner area (e.g. Amuro & Azusa's investigation ability).
do $migration$
declare
  v_def text;
  v_anchor text;
  v_insert text;
begin
  v_def := pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure);
  v_anchor := $anchor$ IF coalesce(v_is_own_turn,false)
    AND coalesce(v_turn_step,'')='main'
    AND NOT coalesce(v_board.base_card_played_this_turn,false)$anchor$;
  v_insert := $insert$
 FOR v_card IN
   SELECT value FROM jsonb_array_elements(coalesce(v_board.partner_non_mr_cards,'[]'::jsonb))
 LOOP
   IF NOT public.private_card_effect_is_active_v1(v_card) THEN CONTINUE; END IF;
   FOR v_def IN
     SELECT d.value FROM jsonb_array_elements(coalesce(v_catalog,'[]'::jsonb)) d(value)
     WHERE d.value->'trigger'->>'event'='character.activated_ability'
       AND coalesce((d.value->>'allowPartnerArea')::boolean,false)
       AND (v_is_own_turn OR coalesce(d.value->>'activationTiming','')='any')
       AND NOT coalesce((d.value->>'continuous')::boolean,false)
       AND public.private_card_effect_matches_id_v1(v_card,coalesce(d.value->'cardIds','[]'::jsonb))
   LOOP
     IF coalesce((v_def->>'oncePerTurn')::boolean,false) THEN
       v_used:=coalesce(v_card->'dsl_effect_uses','[]'::jsonb);
       IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_used) u(value)
         WHERE u.value->>'effect_id'=v_def->>'effectId'
           AND coalesce(nullif(u.value->>'turn_number','')::integer,-1)=v_turn) THEN CONTINUE; END IF;
     END IF;
     IF public.private_card_effect_conditions_match_v1(
       p_room_id,p_ai_user_id,p_ai_user_id,v_card,v_context,'{}'::jsonb,coalesce(v_def->'conditions','[]'::jsonb)
     ) THEN
       v_items:=v_items||jsonb_build_array(jsonb_build_object(
         'source_instance_id',v_card->>'instance_id',
         'effect_id',v_def->>'effectId',
         'label',coalesce(v_def->>'activationLabelKo',v_def->>'effectId','카드 효과'),
         'definition',v_def
       ));
     END IF;
   END LOOP;
 END LOOP;
 $insert$;
  if position(v_anchor in v_def)=0 then
    raise exception 'AI activation function insertion point not found';
  end if;
  v_def := replace(v_def,v_anchor,v_insert||E'\n'||v_anchor);
  execute v_def;

  v_def := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  v_anchor := $anchor$   IF v_source_card IS NULL AND v_new_board.partner_mr_card->>'instance_id'=v_instance_id THEN
     v_source_card:=v_new_board.partner_mr_card;
   END IF;$anchor$;
  v_insert := $insert$   IF v_source_card IS NULL THEN
     SELECT p.value INTO v_source_card
     FROM jsonb_array_elements(coalesce(v_new_board.partner_non_mr_cards,'[]'::jsonb)) p(value)
     WHERE p.value->>'instance_id'=v_instance_id
     LIMIT 1;
   END IF;$insert$;
  if position(v_anchor in v_def)=0 then
    raise exception 'Turn action source lookup insertion point not found';
  end if;
  v_def := replace(v_def,v_anchor,v_anchor||E'\n'||v_insert);

  v_anchor := $anchor$   IF v_new_board.partner_mr_card->>'instance_id'=v_instance_id
      AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 MR 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;$anchor$;
  v_insert := $insert$   IF EXISTS (
       SELECT 1 FROM jsonb_array_elements(coalesce(v_new_board.partner_non_mr_cards,'[]'::jsonb)) p(value)
       WHERE p.value->>'instance_id'=v_instance_id
     ) AND NOT coalesce((v_effect_definition->>'allowPartnerArea')::boolean,false) THEN
     RAISE EXCEPTION '이 능력은 파트너 에이리어에서 발동할 수 없습니다.';
   END IF;$insert$;
  if position(v_anchor in v_def)=0 then
    raise exception 'Turn action partner-area validation insertion point not found';
  end if;
  v_def := replace(v_def,v_anchor,v_anchor||E'\n'||v_insert);
  execute v_def;
end
$migration$;
