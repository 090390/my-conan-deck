-- Resolve the DSL built-in source_character target in modify_stat.
-- This fixes ID:1197 Kaito Kid's AP -2000 effect and the same target used by ID:1071.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$ELSIF v_op='modify_stat' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_data:=v_vars #> v_path; v_amount:=coalesce((v_step->>'amount')::integer,0);
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NOT NULL AND v_step->>'stat'='ap' THEN
         v_new_ap:=coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)+v_amount;
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('ap_bonus',v_new_ap));
       END IF;
     END LOOP;$old$;
  v_new text := $new$ELSIF v_op='modify_stat' THEN
     v_path:=string_to_array(replace(coalesce(v_step->>'target',''),'vars.',''),'.');
     v_amount:=coalesce((v_step->>'amount')::integer,0);
     -- "source_character" is a built-in target: resolve the effect's source
     -- card directly instead of looking for a nonexistent vars.source_character.
     IF replace(coalesce(v_step->>'target',''),'vars.','')='source_character' THEN
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_source_user,v_effect_source_instance_id);
       IF v_current IS NULL THEN
         RAISE EXCEPTION 'AP를 변경할 효과 발동 캐릭터를 찾지 못했습니다.';
       END IF;
       v_data:=jsonb_build_array(jsonb_build_object(
         'owner_user_id',v_source_user,'zone','field',
         'instance_id',v_effect_source_instance_id,'card',v_current
       ));
     ELSE
       v_data:=v_vars #> v_path;
     END IF;
     FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_data,'[]'::jsonb)) LOOP
       v_card:=coalesce(v_item->'card',v_item); v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_source_user);
       v_current:=public.private_card_effect_get_card_v1(p_room_id,v_target_owner,v_card->>'instance_id');
       IF v_current IS NOT NULL AND v_step->>'stat'='ap' THEN
         v_new_ap:=coalesce(nullif(v_current->>'ap_bonus','')::numeric,0)+v_amount;
         PERFORM public.private_card_effect_patch_card_v1(p_room_id,v_target_owner,v_card->>'instance_id',jsonb_build_object('ap_bonus',v_new_ap));
       END IF;
     END LOOP;$new$;
BEGIN
  SELECT pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure)
    INTO v_definition;

  IF position(v_old IN v_definition)=0 THEN
    RAISE EXCEPTION '기존 modify_stat 실행 코드를 찾을 수 없습니다.';
  END IF;

  v_definition := replace(v_definition,v_old,v_new);
  v_definition := replace(v_definition,E'END\n$function$',E'END;\n$function$');
  v_definition := v_definition || ';';
  EXECUTE v_definition;
END;
$migration$;
