DO $patch_private_card_effect_runtime$
DECLARE
  v_definition text;
  v_original text;
  v_old_select text := $old_select$
     v_waiting:=jsonb_build_object('kind','selection','save_as',v_step->>'saveAs','options',v_options,
       'min',v_min_select,'max',v_max_select,
       'unique_by',v_step->>'uniqueBy','prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'));
$old_select$;
  v_new_select text := $new_select$
     v_target_owner:=v_owner;
     IF coalesce(v_step->>'chooser','self')='opponent' THEN
       SELECT user_id INTO v_target_owner
       FROM public.room_players
       WHERE room_id=p_room_id AND user_id<>v_owner
       ORDER BY seat LIMIT 1;
       IF v_target_owner IS NULL THEN RAISE EXCEPTION '효과 대상을 선택할 상대 플레이어가 없습니다.'; END IF;
     END IF;
     v_waiting:=jsonb_build_object('kind','selection','save_as',v_step->>'saveAs','options',v_options,
       'min',v_min_select,'max',v_max_select,
       'chooser_user_id',v_target_owner,
       'unique_by',v_step->>'uniqueBy','prompt',coalesce(v_step->>'prompt','효과 대상을 선택하세요.'));
$new_select$;
  v_old_pending text := $old_pending$
     v_pending:=jsonb_build_object('type','card_effect_selection','effect_id',v_effect_id,
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_owner,
$old_pending$;
  v_new_pending text := $new_pending$
     v_pending:=jsonb_build_object('type','card_effect_selection','effect_id',v_effect_id,
       'source_instance_id',v_effect_source_instance_id,'chooser_user_id',v_target_owner,
$new_pending$;
  v_old_attach text := $old_attach$
   ELSIF v_op='attach_top_card' THEN
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
     v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
     IF v_card ? 'instance_id' THEN
       UPDATE public.room_player_game_states
         SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_card->>'instance_id'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
       IF v_current IS NULL THEN RAISE EXCEPTION '카드를 겹칠 현장 캐릭터를 찾지 못했습니다.'; END IF;
       v_patch:=jsonb_build_object('under_cards',coalesce(v_current->'under_cards','[]'::jsonb)||jsonb_build_array(v_card-'rested'-'status'-'ap_bonus'-'summoned_this_turn'));
       PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_source_user,v_effect_source_instance_id,v_patch);
     END IF;

   ELSIF v_op='win_game' THEN
$old_attach$;
  v_new_attach text := $new_attach$
   ELSIF v_op='attach_top_card' THEN
     -- Attach the top deck card to the host selected in the target variable.
     -- set_cards is the same field used by the existing manual SET action.
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_contact_instance:=coalesce(v_item->>'instance_id',v_item#>>'{card,instance_id}');
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       IF v_contact_instance IS NULL THEN RAISE EXCEPTION '세트할 현장 캐릭터의 식별 정보가 없습니다.'; END IF;

       SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_owner FOR UPDATE;
       v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);
       IF v_card ? 'instance_id' THEN
         v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_contact_instance);
         IF v_current IS NULL THEN RAISE EXCEPTION '덱 카드를 세트할 대상 캐릭터가 현장에 없습니다.'; END IF;
         UPDATE public.room_player_game_states
         SET deck_order=public.private_card_effect_remove_from_array_v1(deck_order,v_card->>'instance_id'),updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_owner;
         v_patch:=jsonb_build_object(
           'set_cards',coalesce(v_current->'set_cards','[]'::jsonb)||jsonb_build_array(
             (v_card-'rested'-'status'-'ap_bonus'-'level_bonus'-'summoned_this_turn'-'resolving')
             ||jsonb_build_object('face_up',coalesce((v_step->>'faceUp')::boolean,false),
               'set_owner_user_id',v_owner,'host_instance_id',v_contact_instance)
           )
         );
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_contact_instance,v_patch);
       END IF;
     END LOOP;

   ELSIF v_op='win_game' THEN
$new_attach$;
BEGIN
  v_definition:=pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  v_original:=v_definition;
  IF position(v_old_select in v_definition)=0 THEN RAISE EXCEPTION 'select_cards chooser anchor not found'; END IF;
  v_definition:=replace(v_definition,v_old_select,v_new_select);
  IF position(v_old_pending in v_definition)=0 THEN RAISE EXCEPTION 'select_cards pending anchor not found'; END IF;
  v_definition:=replace(v_definition,v_old_pending,v_new_pending);
  IF position(v_old_attach in v_definition)=0 THEN RAISE EXCEPTION 'attach_top_card anchor not found'; END IF;
  v_definition:=replace(v_definition,v_old_attach,v_new_attach);
  IF v_definition IS DISTINCT FROM v_original THEN EXECUTE v_definition; END IF;
END
$patch_private_card_effect_runtime$;
