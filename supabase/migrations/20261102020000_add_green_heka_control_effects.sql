-- Green Hattori/Kazuha control deck: initial playable effect definitions and runtime hooks.
-- This migration is idempotent for both an empty catalog and a partially populated catalog.

UPDATE public.private_card_effect_catalog_v1 c
SET definitions = coalesce(c.definitions,'[]'::jsonb) || coalesce((
  SELECT jsonb_agg(incoming.definition ORDER BY incoming.ordinality)
  FROM jsonb_array_elements('[{"effectId":"card-0652-enter-swap-evidence-hand","cardIds":["0652"],"cardNameJa":"ヘビ男","cardNameKo":"뱀남자","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"evidence_area","min":0,"max":1,"optional":true,"saveAs":"evidence","prompt":"자신의 증거에서 패에 추가할 카드 1장을 선택할 수 있습니다."},{"op":"move_cards","from":"evidence","to":"hand","when":{"fact":"vars.evidence.count","operator":"greater_than","value":0}},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"face_down_evidence","when":{"fact":"vars.evidence.count","operator":"greater_than","value":0},"prompt":"패에서 뒷면으로 증거 에이리어에 놓을 카드 1장을 선택하세요."},{"op":"move_cards","from":"face_down_evidence","to":"evidence_area","faceUp":false,"when":{"fact":"vars.evidence.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"【登場時】自分の証拠を1つ選び、手札に加えてもよい。そうした場合、手札から1枚を裏向きで証拠にする。","interpretation":"증거 1장을 패에 넣었을 때에만 손패 1장을 뒷면 증거로 둡니다."}},{"effectId":"card-0652-hirameki-rest-character","cardIds":["0652"],"cardNameJa":"ヘビ男","cardNameKo":"뱀남자","trigger":{"event":"evidence.card_removed","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"both_fields","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"field":"card_type","operator":"equals","value":"character"},"prompt":"슬립시킬 캐릭터를 최대 1장 선택하세요."},{"op":"rest_cards","target":"vars.target","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"【ヒラメキ】キャラを1体まで選び、レストする。","interpretation":"뱀남자 카드가 증거에서 리무브될 때 발동하는 히라메키입니다."}},{"effectId":"card-0661-contact-remove-draw","cardIds":["0661"],"cardNameJa":"鬼丸猛","cardNameKo":"오니마루 타케시","trigger":{"event":"character.contact_removed_opponent","timing":"after"},"conditions":[],"steps":[{"op":"draw_cards","destination":"hand","count":1}],"reviewNotes":{"sourceText":"相手の現場のキャラがこのキャラとのコンタクトによってリムーブされたとき、カードを1枚引く。"}},{"effectId":"card-0661-event-action-opponent-discards","cardIds":["0661"],"cardNameJa":"鬼丸猛","cardNameKo":"오니마루 타케시","trigger":{"event":"character.acted","timing":"after"},"conditions":[{"fact":"entry.action_type","operator":"equals","value":"investigate"}],"steps":[{"op":"select_cards","from":"opponent_hand","targetController":"opponent","chooser":"opponent","min":1,"max":1,"optional":false,"saveAs":"opponent_discard","prompt":"오니마루 타케시의 사건 액션으로 증거를 얻었습니다. 손패 1장을 선택해 리무브하세요."},{"op":"move_cards","from":"opponent_discard","to":"remove_area"}],"reviewNotes":{"sourceText":"このキャラのアクション【事件】で証拠を得たとき、相手は手札を1枚リムーブする。","interpretation":"【事件】 액션은 조사(investigate)로 기록하고, 리무브할 손패는 상대가 직접 선택합니다."}},{"effectId":"card-0860-enter-search-green-event","cardIds":["0860"],"cardNameJa":"遠山和葉","cardNameKo":"토야마 카즈하","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"peek_top_cards","count":4,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"saveAs":"chosen_event","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"event"},{"field":"color","operator":"equals","value":"green"}]},"prompt":"공개해 패에 추가할 녹색 이벤트를 최대 1장 선택하세요."},{"op":"reveal_cards","from":"chosen_event","to":["all"],"awaitAcknowledgement":true,"when":{"fact":"vars.chosen_event.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"chosen_event","to":"hand","when":{"fact":"vars.chosen_event.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_deck_bottom","from":"seen","selectedVariable":"chosen_event","order":"player_choice","orderPrompt":"나머지 카드를 덱 아래에 둘 순서를 정하세요."},{"op":"select_cards","from":"hand","min":1,"max":1,"optional":false,"saveAs":"hand_cost","when":{"fact":"vars.chosen_event.count","operator":"greater_than","value":0},"prompt":"이벤트를 패에 추가했다면, 리무브할 손패 1장을 선택하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.chosen_event.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"【登場時】自分のデッキの上から4枚を見る。その中から【緑】のイベントを1枚まで公開して手札に加え、残りを好きな順番でデッキの下に置く。手札に加えた場合、手札を1枚リムーブする。"}},{"effectId":"card-0860-after-own-green-event-resolves-remove-character","cardIds":["0860"],"cardNameJa":"遠山和葉","cardNameKo":"토야마 카즈하","trigger":{"event":"event.resolved","timing":"after","scope":"field_watch"},"conditions":[{"fact":"entry.source.card_type","operator":"equals","value":"event"},{"fact":"entry.source.color","operator":"equals","value":"green"},{"fact":"entry.controller_is_source_controller","operator":"equals","value":true}],"steps":[{"op":"select_cards","from":"opponent_field","targetController":"opponent","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":8000}]},"prompt":"AP 8000 이하인 상대 캐릭터를 최대 1장 선택해 리무브하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"oncePerTurn":true,"reviewNotes":{"sourceText":"【自分のターン中】【ターン1】自分が【緑】のイベントを使用したとき、AP8000以下のキャラを1体まで選び、リムーブする。（イベントを解決した後にキャラを選ぶ）"}},{"effectId":"card-0861-continuous-kazuha-bond-ap-plus-2000","cardIds":["0861"],"cardNameJa":"服部平次","cardNameKo":"핫토리 헤이지","trigger":{"event":"continuous.recalculate","timing":"continuous"},"conditions":[{"fact":"player.field.has_card_name","operator":"equals","value":"遠山和葉"},{"fact":"turn.is_source_controller_turn","operator":"equals","value":true}],"steps":[{"op":"set_continuous_stat","target":"source_character","stat":"ap","amount":2000,"modifierId":"card-0861-kazuha-bond-turn-ap","duration":"while_condition_true"}],"continuous":true,"reviewNotes":{"sourceText":"【絆：遠山和葉】【自分のターン中】AP＋2000"}},{"effectId":"card-0861-hirameki-recover-heiji","cardIds":["0861"],"cardNameJa":"服部平次","cardNameKo":"핫토리 헤이지","trigger":{"event":"evidence.card_removed","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"heiji","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"card_name","operator":"name_matches","value":"服部平次"}]},"prompt":"리무브 에이리어에서 핫토리 헤이지를 최대 1장 선택해 패에 추가하세요."},{"op":"move_cards","from":"heiji","to":"hand","when":{"fact":"vars.heiji.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"【ヒラメキ】自分のリムーブエリアにある《服部平次》を1枚まで手札に加える。"}},{"effectId":"card-0404-solution-enter-remove-rested-opponent-level7","cardIds":["0404"],"cardNameJa":"服部平次","cardNameKo":"핫토리 헤이지","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.case_phase","operator":"equals","value":"solution"}],"steps":[{"op":"filter_cards","from":"opponent_field","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"status","operator":"in","value":["rested","stunned"]}]},"saveAs":"opponent_rest_or_stun"},{"op":"select_cards","from":"opponent_field","targetController":"opponent","min":0,"max":1,"optional":true,"saveAs":"target","when":{"fact":"vars.opponent_rest_or_stun.count","operator":"greater_than_or_equal","value":2},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"status","operator":"equals","value":"rested"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"상대 현장에 슬립/스턴 캐릭터가 합계 2장 이상 있습니다. 레벨 7 이하 슬립 캐릭터를 최대 1장 선택해 리무브하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"【解決編】【登場時】相手の現場にレストまたはスタン状態のキャラが合計2体以上いる場合、レベル7以下のレスト状態のキャラを1体まで選び、リムーブする。"}},{"effectId":"card-1090-enter-rest-recover-green-event","cardIds":["1090"],"cardNameJa":"国末照明","cardNameKo":"쿠니스에 테루아키","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"anyOf":[{"fact":"player.field.has_card_name","operator":"equals","value":"服部平次"},{"fact":"player.field.has_card_name","operator":"equals","value":"遠山和葉"}]}],"steps":[{"op":"filter_cards","from":"remove_area","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"event"},{"field":"color","operator":"equals","value":"green"}]},"saveAs":"available_events"},{"op":"offer_reaction","actor":"controller","choices":["yes","no"],"reactionId":"b10029-rest-to-recover-event","saveAs":"recover_choice","prompt":"자신의 현장에 핫토리 헤이지 또는 토야마 카즈하가 있습니다. 쿠니스에 테루아키를 슬립시켜 리무브 에이리어의 녹색 이벤트를 회수할까요?","when":{"fact":"vars.available_events.count","operator":"greater_than","value":0}},{"op":"pay_cost","cost":"sleep_source_character","when":{"fact":"vars.recover_choice","operator":"equals","value":"yes"}},{"op":"select_cards","from":"remove_area","min":1,"max":1,"optional":false,"saveAs":"event_to_hand","when":{"fact":"vars.recover_choice","operator":"equals","value":"yes"},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"event"},{"field":"color","operator":"equals","value":"green"}]},"prompt":"패에 추가할 녹색 이벤트 1장을 선택하세요."},{"op":"move_cards","from":"event_to_hand","to":"hand","when":{"fact":"vars.recover_choice","operator":"equals","value":"yes"}}],"reviewNotes":{"sourceText":"【登場時】自分の現場に《服部平次》または《遠山和葉》がいる場合、このキャラをレストにしてもよい。そうした場合、自分のリムーブエリアにある【緑】のイベントを1枚まで手札に加える。"}},{"effectId":"card-0427-solution-event-remove-ap-high-and-low","cardIds":["0427"],"cardNameJa":"「後ろの女に一言遺したろ思てなァ…」","cardNameKo":"뒤에 있는 여자에게 한마디 남길까 생각했지…","trigger":{"event":"event.played","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"green"},{"fact":"player.case_phase","operator":"equals","value":"solution"},{"fact":"player.file.count","operator":"less_than_or_equal","value":5}],"steps":[{"op":"select_cards","from":"opponent_field","targetController":"opponent","min":1,"max":1,"optional":false,"saveAs":"high_ap","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"greater_than_or_equal","value":7000}]},"prompt":"상대 현장에서 AP 7000 이상 캐릭터 1장을 선택하세요."},{"op":"select_cards","from":"opponent_field","targetController":"opponent","min":1,"max":1,"optional":false,"saveAs":"low_ap","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"ap_current","operator":"less_than_or_equal","value":5000}]},"prompt":"상대 현장에서 AP 5000 이하 캐릭터 1장을 선택하세요."},{"op":"move_cards","from":"high_ap","to":"remove_area"},{"op":"move_cards","from":"low_ap","to":"remove_area"}],"reviewNotes":{"sourceText":"このイベントは自分のファイルエリアのカードが5枚以下のときに使用できる。【パートナー緑】【解決編】AP7000以上のキャラ1体とAP5000以下のキャラ1体を選び、リムーブする。"}},{"effectId":"card-0729-event-remove-top-three-deploy-level6","cardIds":["0729"],"cardNameJa":"「助けて平次ィ!!!」","cardNameKo":"도와줘, 헤이지!!!","trigger":{"event":"event.played","timing":"after"},"conditions":[],"steps":[{"op":"peek_top_cards","count":3,"allowFewer":false,"saveAs":"top_three","when":{"fact":"player.deck.count","operator":"greater_than_or_equal","value":3}},{"op":"move_cards","from":"top_three","to":"remove_area","when":{"fact":"vars.top_three.count","operator":"greater_than_or_equal","value":3}},{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"deployment","when":{"fact":"vars.top_three.count","operator":"greater_than_or_equal","value":3},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":6}]},"prompt":"리무브 에이리어에서 레벨 6 이하 캐릭터를 최대 1장 선택해 등장시킬 수 있습니다."},{"op":"move_cards","from":"deployment","to":"field","when":{"allOf":[{"fact":"vars.top_three.count","operator":"greater_than_or_equal","value":3},{"fact":"vars.deployment.count","operator":"greater_than","value":0}]},"entryMethod":"event_effect"}],"reviewNotes":{"sourceText":"自分のデッキの上から3枚をリムーブしてもよい。そうした場合、自分のリムーブエリアにあるレベル6以下のキャラを1体まで選び、登場させる。"}},{"effectId":"card-0666-case-solution-enter-discard-hand","cardIds":["0666"],"cardNameJa":"恋と推理の剣道大会","cardNameKo":"사랑과 추리의 검도 대회","trigger":{"event":"case.solution_entered","timing":"after"},"conditions":[],"steps":[{"op":"select_cards","from":"hand","min":0,"max":1,"optional":true,"saveAs":"hand_cost","prompt":"사건이 해결편으로 넘어갔습니다. 리무브할 손패 1장을 선택하세요."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.hand_cost.count","operator":"greater_than","value":0}}],"reviewNotes":{"sourceText":"この事件が解決編になったとき、自分は手札を1枚リムーブする。"}},{"effectId":"card-0666-case-solution-flip-two-search-heiji-kazuha","cardIds":["0666"],"cardNameJa":"恋と推理の剣道大会","cardNameKo":"사랑과 추리의 검도 대회","trigger":{"event":"case.activated_ability","timing":"after"},"conditions":[{"anyOf":[{"fact":"player.field.has_card_name","operator":"equals","value":"服部平次"},{"fact":"player.field.has_card_name","operator":"equals","value":"遠山和葉"}]}],"steps":[{"op":"select_cards","from":"evidence_area","min":2,"max":2,"optional":false,"saveAs":"evidence_to_flip","filter":{"field":"face_up","operator":"equals","value":false},"prompt":"뒷면 증거 2장을 선택해 앞면으로 뒤집으세요."},{"op":"flip_evidence","from":"vars.evidence_to_flip","count":2},{"op":"peek_top_cards","count":3,"allowFewer":true,"saveAs":"seen"},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"saveAs":"chosen","filter":{"anyOf":[{"field":"card_name","operator":"name_matches","value":"服部平次"},{"field":"card_name","operator":"name_matches","value":"遠山和葉"}]},"prompt":"공개해 패에 추가할 핫토리 헤이지 또는 토야마 카즈하를 최대 1장 선택하세요."},{"op":"reveal_cards","from":"chosen","to":["all"],"awaitAcknowledgement":true,"when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_cards","from":"chosen","to":"hand","when":{"fact":"vars.chosen.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_deck_bottom","from":"seen","selectedVariable":"chosen","order":"player_choice","orderPrompt":"남은 카드의 덱 아래 순서를 정하세요."}],"oncePerTurn":true,"reviewNotes":{"sourceText":"【解決編】【宣言】【ターン1】〚裏向きの証拠2つを表向きにする〛：自分のデッキの上から3枚を見る。その中から《服部平次》または《遠山和葉》を1枚まで公開して手札に加え、残りを好きな順番でデッキの下に置く。この能力は自分の現場に《服部平次》または《遠山和葉》がいる場合に宣言できる。"}}]'::jsonb) WITH ORDINALITY incoming(definition, ordinality)
  WHERE NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) existing
    WHERE existing->>'effectId'=incoming.definition->>'effectId'
  )
),'[]'::jsonb),
updated_at=now()
WHERE c.catalog_id='main';

DO $$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  -- A completed event is now a field-watch trigger. This is needed for Kazuha 0860.
  v_definition:=pg_get_functiondef('public.private_card_effect_start_event_v1(uuid,uuid,uuid,jsonb,text,jsonb,text,boolean)'::regprocedure);
  v_old:=$old$IF p_trigger_event NOT IN ('character.entered_field','character.contact_started','evidence.card_removed','hand.card_revealed_for_cost','player.turn_ended') THEN CONTINUE; END IF;$old$;
  v_new:=$new$IF p_trigger_event NOT IN ('character.entered_field','character.contact_started','evidence.card_removed','hand.card_revealed_for_cost','player.turn_ended','event.resolved') THEN CONTINUE; END IF;$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'field-watch event whitelist anchor is missing';
  END IF;

  -- move_cards can explicitly place a card face-down in the evidence area.
  v_definition:=pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);
  v_old:=$old$v_to:=coalesce(v_step->>'to','');
       PERFORM public.private_card_effect_move_card_v1$old$;
  v_new:=$new$v_to:=coalesce(v_step->>'to','');
       IF v_to='evidence_area' AND v_step ? 'faceUp' THEN
         v_card:=v_card||jsonb_build_object('face_up',coalesce(nullif(v_step->>'faceUp','')::boolean,false));
       END IF;
       PERFORM public.private_card_effect_move_card_v1$new$;
  IF position(v_old in v_definition)>0 THEN
    v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'move_cards faceUp anchor is missing';
  END IF;

  -- Expose reactionId to the AI policy so it can choose the right cost branch.
  v_old:=$old$v_pending:=jsonb_build_object('type','card_effect_reaction','effect_id',v_effect_id,
       'chooser_user_id',v_owner$old$;
  v_new:=$new$v_pending:=jsonb_build_object('type','card_effect_reaction','effect_id',v_effect_id,
       'reaction_id',nullif(v_step->>'reactionId',''),
       'chooser_user_id',v_owner$new$;
  IF position(v_old in v_definition)>0 THEN
    v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'reaction_id anchor is missing';
  END IF;
  IF position(v_old in pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure))>0 THEN
    EXECUTE v_definition;
  ELSIF position(v_new in pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'reaction_id replacement did not apply';
  END IF;

  -- Preserve explicit face_up=false for evidence placed by an effect.
  v_definition:=pg_get_functiondef('public.private_card_effect_move_card_v1(uuid,uuid,text,jsonb,text,uuid)'::regprocedure);
  v_old:=$old$jsonb_build_array(v_card||jsonb_build_object('face_up',true))$old$;
  v_new:=$new$jsonb_build_array(v_card||jsonb_build_object('face_up',coalesce(nullif(v_card->>'face_up','')::boolean,true)))$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'evidence face_up anchor is missing';
  END IF;

  -- Notify field-watch cards after an event finishes and has moved to the remove area.
  v_definition:=pg_get_functiondef('public.private_card_effect_move_event_to_remove_v1(uuid,uuid,text)'::regprocedure);
  v_old:=$old$UPDATE public.room_match_states
     SET state_version=state_version+1,
         last_action_label='이벤트 효과 처리가 완료되어 리무브 에이리어로 이동했습니다.'
   WHERE room_id=p_room_id;

  RETURN true;$old$;
  v_new:=$new$UPDATE public.room_match_states
     SET state_version=state_version+1,
         last_action_label='이벤트 효과 처리가 완료되어 리무브 에이리어로 이동했습니다.'
   WHERE room_id=p_room_id;

  PERFORM public.private_card_effect_start_event_v1(
    p_room_id,p_owner_user_id,p_owner_user_id,v_card-'resolving','event.resolved',
    jsonb_build_object('entry',jsonb_build_object(
      'method','event_resolved','source',v_card-'resolving',
      'controller_user_id',p_owner_user_id::text
    )),NULL,false
  );

  RETURN true;$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'event.resolved hook anchor is missing';
  END IF;

  -- New normalized event facts used by Kazuha 0860 and Onimaru 0661.
  v_definition:=pg_get_functiondef('public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure);
  v_old:=$old$IF p_fact='entry.source.card_type' THEN RETURN coalesce(p_context#>'{entry,source,card_type}',p_context#>'{entry,source,type}','null'::jsonb); END IF;$old$;
  v_new:=$new$IF p_fact='entry.source.color' THEN
   RETURN to_jsonb(public.private_card_effect_color_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb)));
 END IF;
 IF p_fact='entry.action_type' THEN
   RETURN coalesce(p_context#>'{entry,action_type}','null'::jsonb);
 END IF;
 IF p_fact='entry.source.card_type' THEN RETURN coalesce(p_context#>'{entry,source,card_type}',p_context#>'{entry,source,type}','null'::jsonb); END IF;$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'event fact anchor is missing';
  END IF;

  -- Case card 0666 is available to human and AI declared ability flows.
  v_definition:=pg_get_functiondef('public.get_private_card_effect_activations_v1(uuid)'::regprocedure);
  v_old:=$old$ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_board.event_rule_code,'')='culprits_1046' THEN
   v_case_id:='1046'; v_case_name:='범인들의 범행';
 ELSE$old$;
  v_new:=$new$ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_board.event_rule_code,'')='culprits_1046' THEN
   v_case_id:='1046'; v_case_name:='범인들의 범행';
 ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
   v_case_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
 ELSE$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'human case map anchor is missing';
  END IF;

  v_definition:=pg_get_functiondef('public.get_private_ai_card_effect_activations_v1(uuid,uuid)'::regprocedure);
  v_old:=$old$ELSIF v_case_key IN ('B09107P','B09107','1046') THEN
   v_case_id:='1046'; v_case_name:='범인들의 범행';
 ELSE$old$;
  v_new:=$new$ELSIF v_case_key IN ('B09107P','B09107','1046') THEN
   v_case_id:='1046'; v_case_name:='범인들의 범행';
 ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
   v_case_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
 ELSE$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'AI case map anchor is missing';
  END IF;

  -- Fire ID 0666's case.solution_entered and bind its declared effect ID.
  v_definition:=pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  v_old:=$old$ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
       v_case_internal_id:='0806'; v_case_name:='흔들리는 마음';
     ELSE
       v_case_internal_id:=NULL;$old$;
  v_new:=$new$ELSIF v_case_key IN ('B07077P','B07077','0806') THEN
       v_case_internal_id:='0806'; v_case_name:='흔들리는 마음';
     ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
       v_case_internal_id:='0666'; v_case_name:='사랑과 추리의 검도 대회';
     ELSE
       v_case_internal_id:=NULL;$new$;
  IF position(v_old in v_definition)>0 THEN
    v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'solution-entered case map anchor is missing';
  END IF;
  v_old:=$old$ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_new_board.event_rule_code,'')='culprits_1046' THEN
     v_case_internal_id:='1046';
     v_case_name:='범인들의 범행';
     v_case_effect_id:='card-1046-culprits-crime-case-effect';
   ELSE$old$;
  v_new:=$new$ELSIF v_case_key IN ('B09107P','B09107','1046') OR coalesce(v_new_board.event_rule_code,'')='culprits_1046' THEN
     v_case_internal_id:='1046';
     v_case_name:='범인들의 범행';
     v_case_effect_id:='card-1046-culprits-crime-case-effect';
   ELSIF v_case_key IN ('B06043P','B06043','0666') THEN
     v_case_internal_id:='0666';
     v_case_name:='사랑과 추리의 검도 대회';
     v_case_effect_id:='card-0666-case-solution-flip-two-search-heiji-kazuha';
   ELSE$new$;
  IF position(v_old in v_definition)>0 THEN
    v_definition:=replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'activate-case map anchor is missing';
  END IF;
  v_old:=$old$'character.acted',jsonb_build_object('turn_number',v_turn),NULL,false$old$;
  v_new:=$new$'character.acted',jsonb_build_object('turn_number',v_turn,'entry',jsonb_build_object('action_type',p_action)),NULL,false$new$;
  IF position(v_old in v_definition)>0 THEN
    EXECUTE replace(v_definition,v_old,v_new);
  ELSIF position(v_new in v_definition)=0 THEN
    RAISE EXCEPTION 'character.acted event context anchor is missing';
  END IF;
END $$;
