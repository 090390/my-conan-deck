DO $patch$
DECLARE
  v_definition text;
  v_old text := $old$   v_data:=coalesce(v_game.remove_cards,'[]'::jsonb);
   v_owner:=v_game.user_id; v_zone:='remove_area';$old$;
  v_new text := $new$   v_data:=coalesce(v_game.remove_cards,'[]'::jsonb);
   v_owner:=v_game.user_id; v_zone:='remove_area';
   FOR e IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
     v_card:=e.value;
     IF public.private_card_effect_filter_matches_with_vars_v1(p_room_id,v_card,v_owner,p_source_user,p_filter,coalesce(p_vars,'{}'::jsonb)) THEN
       v_name:=CASE WHEN p_unique_by='level' THEN public.private_card_effect_level_v1(v_card)::text ELSE lower(public.private_card_effect_name_v1(v_card)) END;
       IF p_unique_by IS NULL OR NOT(v_name=ANY(v_seen_names)) THEN
         v_out:=v_out||jsonb_build_array(jsonb_build_object('instance_id',v_card->>'instance_id','owner_user_id',v_owner,'zone',v_zone,'card',v_card));
         IF p_unique_by IN ('card_name','level') THEN v_seen_names:=array_append(v_seen_names,v_name); END IF;
       END IF;
     END IF;
   END LOOP;
   RETURN v_out;$new$;
BEGIN
  v_definition := pg_get_functiondef('public.private_card_effect_get_candidates_v1(uuid,uuid,uuid,text,jsonb,text,text,jsonb)'::regprocedure);
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'opponent_remove_area branch not found; aborting migration';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END
$patch$;