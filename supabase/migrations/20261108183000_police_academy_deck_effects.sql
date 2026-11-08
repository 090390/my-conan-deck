
-- Police Academy deck: card definitions and the missing execution plumbing.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
  v_definitions jsonb := $defs$[{"effectId":"card-1121-field-watch-remove-level9-on-police-academy-enter","cardIds":["1121"],"cardNameJa":"松田陣平＆萩原研二","cardNameKo":"마츠다 진페이＆하기와라 켄지","trigger":{"event":"character.entered_field","scope":"field_watch","timing":"after"},"oncePerTurn":true,"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"},{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"entry.controller_is_source_controller","operator":"equals","value":true},{"fact":"entry.source.card_name","operator":"in","value":["降谷零","諸伏景光","伊達航","萩原研二","松田陣平"]},{"fact":"source.instance_id","operator":"not_equals","value":{"fact":"entry.source.instance_id"}}],"steps":[{"op":"select_cards","from":"both_fields","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":9}]},"prompt":"리무브할 레벨 9 이하 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"target","to":"remove_area","when":{"fact":"vars.target.count","operator":"greater_than","value":0}}],"reviewNotes":{"rationale":"파트너가 황이고 자신의 턴에 경찰학교 동기 5인 중 이 카드 이외의 캐릭터가 자신의 현장에 등장하면 턴당 1회, 양쪽 현장의 레벨 9 이하 캐릭터를 최대 1장 리무브한다.","sourceText":"【パートナー黄】【自分ターン中】【ターン1】自分の現場にこのキャラ以外のカード名［降谷零］か［諸伏景光］か［伊達航］か［萩原研二］か［松田陣平］が登場したとき、レベル9以下のキャラを1枚まで選び、リムーブする。"}},{"effectId":"card-1121-bond-furuya-end-turn-recover-police","cardIds":["1121"],"cardNameJa":"松田陣平＆萩原研二","cardNameKo":"마츠다 진페이＆하기와라 켄지","trigger":{"event":"player.turn_ended","timing":"after"},"conditions":[{"fact":"player.field.has_card_name","operator":"equals","value":"降谷零"}],"steps":[{"op":"select_cards","from":"hand","min":0,"max":1,"optional":true,"saveAs":"hand_cost","prompt":"손패 1장을 리무브하면 레벨 3 이하 경찰 캐릭터를 등장시킬 수 있습니다."},{"op":"move_cards","from":"hand_cost","to":"remove_area","when":{"fact":"vars.hand_cost.count","operator":"greater_than","value":0}},{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"recovered","when":{"fact":"vars.hand_cost.count","operator":"greater_than","value":0},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":3},{"field":"trait","operator":"has_trait","value":"警察"}]},"prompt":"등장시킬 레벨 3 이하 경찰 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"recovered","to":"field","when":{"fact":"vars.recovered.count","operator":"greater_than","value":0},"entryMethod":"character_ability","rested":true}],"reviewNotes":{"rationale":"인연 [후루야 레이]가 성립한 상태에서 자신의 턴 종료 시 손패 1장을 임의로 리무브할 수 있으며, 지불한 경우 리무브 에이리어의 레벨 3 이하 경찰 캐릭터를 최대 1장 슬립 상태로 등장시킨다.","sourceText":"【絆［降谷零］】自分のターン終了時、手札を1枚リムーブしてもよい。そうした場合、自分のリムーブエリアにあるレベル3以下の特徴［警察］のキャラを1枚まで選び、スリープ状態で登場させる。"}},{"effectId":"card-1121-activated-bond-target-ap-plus-2000","cardIds":["1121"],"cardNameJa":"松田陣平＆萩原研二","cardNameKo":"마츠다 진페이＆하기와라 켄지","trigger":{"event":"character.activated_ability","timing":"immediate"},"oncePerTurn":true,"allowPartnerArea":true,"activationTiming":"turn","activationLabelKo":"선언 · 후루야 레이/모로후시 히로미츠/다테 와타루 AP +2000","conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true}],"steps":[{"op":"select_cards","from":"field","min":0,"max":1,"optional":true,"saveAs":"ap_target","filter":{"allOf":[{"field":"controller","operator":"equals","value":"self"},{"field":"card_type","operator":"equals","value":"character"},{"field":"card_name","operator":"in","value":["降谷零","諸伏景光","伊達航"]}]},"prompt":"턴 종료 시까지 AP를 2000 올릴 후루야 레이/모로후시 히로미츠/다테 와타루를 최대 1장 선택하세요."},{"op":"modify_stat","stat":"ap","target":"ap_target","amount":2000,"duration":"turn_end","stacking":"additive","when":{"fact":"vars.ap_target.count","operator":"greater_than","value":0}}],"reviewNotes":{"rationale":"턴당 1회 자신의 턴에 선언하여 후루야 레이, 모로후시 히로미츠 또는 다테 와타루 1장의 AP를 턴 종료까지 2000 올린다. 파트너 에이리어에서도 선언할 수 있다.","sourceText":"【宣言】【ターン1】自分の現場にいるカード名［降谷零］か［諸伏景光］か［伊達航］を1枚まで選び、ターン終了時までAP＋2000する。この能力はパートナーエリアでも宣言できる。"}},{"effectId":"card-1122-partner-yellow-charge","cardIds":["1122"],"cardNameJa":"伊達航","cardNameKo":"다테 와타루","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"}],"steps":[{"op":"grant_keyword","target":"source_character","keyword":"charge","duration":"turn_end","displayNameKo":"돌격"}],"reviewNotes":{"rationale":"파트너 색상이 황이면 등장한 턴부터 액션할 수 있도록 턴 종료까지 돌격을 부여한다.","sourceText":"【パートナー黄】このキャラは突撃を得る。"}},{"effectId":"card-1122-contact-removed-bond-followup-remove-level7","cardIds":["1122"],"cardNameJa":"伊達航","cardNameKo":"다테 와타루","trigger":{"event":"character.contact_removed_opponent","timing":"after"},"oncePerTurn":true,"conditions":[{"fact":"player.field.has_card_name","operator":"equals","value":"降谷零"}],"steps":[{"op":"select_cards","from":"hand","min":0,"max":1,"optional":true,"saveAs":"bond_cost","filter":{"field":"card_name","operator":"in","value":["諸伏景光","萩原研二","松田陣平"]},"prompt":"손패에서 모로후시 히로미츠/하기와라 켄지/마츠다 진페이 중 1장을 리무브할 수 있습니다."},{"op":"move_cards","from":"bond_cost","to":"remove_area","when":{"fact":"vars.bond_cost.count","operator":"greater_than","value":0}},{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"followup_target","when":{"fact":"vars.bond_cost.count","operator":"greater_than","value":0},"filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"level","operator":"less_than_or_equal","value":7}]},"prompt":"리무브할 레벨 7 이하 상대 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"followup_target","to":"remove_area","when":{"fact":"vars.followup_target.count","operator":"greater_than","value":0},"targetOwner":"opponent"}],"reviewNotes":{"rationale":"인연 [후루야 레이]가 성립한 상태에서 이 캐릭터와의 컨택으로 상대 캐릭터가 리무브되면 턴당 1회, 손패의 히로미츠/켄지/진페이 중 1장을 리무브하고 레벨 7 이하 상대 캐릭터를 추가로 최대 1장 리무브할 수 있다.","sourceText":"【絆［降谷零］】【ターン1】相手の現場にいるキャラがこのキャラとのコンタクトによってリムーブされたとき、手札からカード名［諸伏景光］か［萩原研二］か［松田陣平］を1枚リムーブしてもよい。そうした場合、レベル7以下のキャラを1枚まで選び、リムーブする。"}},{"effectId":"card-1123-continuous-charge","cardIds":["1123"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[],"steps":[{"op":"set_continuous_keyword","target":"source_character","keyword":"charge","duration":"while_condition_true","modifierId":"police-academy-1123-printed-charge"}],"reviewNotes":{"rationale":"카드에 상시 표기된 돌격 키워드를 필드에 있는 동안 적용한다.","sourceText":"突撃"}},{"effectId":"card-1123-bond-date-ready-at-turn-end","cardIds":["1123"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"player.turn_ended","timing":"after"},"conditions":[{"fact":"player.field.has_card_name","operator":"equals","value":"伊達航"}],"steps":[{"op":"ready_source_character"}],"reviewNotes":{"rationale":"인연 [다테 와타루]가 성립하면 자신의 턴 종료 시 후루야 레이를 액티브화한다.","sourceText":"【絆［伊達航］】自分のターン終了時、このキャラをアクティブにする。"}},{"effectId":"card-1123-bond-hagiwara-ap-plus-1000","cardIds":["1123"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.field.has_card_name","operator":"equals","value":"萩原研二"}],"steps":[{"op":"set_continuous_stat","stat":"ap","target":"source_character","amount":1000,"duration":"while_condition_true","modifierId":"police-academy-1123-bond-hagiwara-ap"}],"reviewNotes":{"rationale":"인연 [하기와라 켄지]가 성립한 자신의 턴 중 AP를 1000 올린다.","sourceText":"【絆［萩原研二］】【自分ターン中】AP＋1000。"}},{"effectId":"card-1123-bond-matsuda-ap-plus-1000","cardIds":["1123"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.field.has_card_name","operator":"equals","value":"松田陣平"}],"steps":[{"op":"set_continuous_stat","stat":"ap","target":"source_character","amount":1000,"duration":"while_condition_true","modifierId":"police-academy-1123-bond-matsuda-ap"}],"reviewNotes":{"rationale":"인연 [마츠다 진페이]가 성립한 자신의 턴 중 AP를 1000 올린다.","sourceText":"【絆［松田陣平］】【自分ターン中】AP＋1000。"}},{"effectId":"card-1129-solution-character-ability-entry-draw","cardIds":["1129"],"cardNameJa":"鬼塚八蔵","cardNameKo":"오니즈카 하치조","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.case_phase","operator":"equals","value":"solution"},{"fact":"entry.method","operator":"equals","value":"character_ability"}],"steps":[{"op":"draw_cards","count":1,"destination":"hand"}],"reviewNotes":{"rationale":"해결편 중 자신의 캐릭터 능력으로 등장한 경우 카드를 1장 드로우한다. 일반 수동 등장이나 이벤트 효과 등장에는 발동하지 않는다.","sourceText":"【解決編】【登場時】自分のキャラの能力によって登場した場合、カードを1枚引く。"}},{"effectId":"card-1129-hirameki-recover-police-academy-character","cardIds":["1129"],"cardNameJa":"鬼塚八蔵","cardNameKo":"오니즈카 하치조","trigger":{"event":"evidence.card_removed","timing":"after"},"steps":[{"op":"select_cards","from":"remove_area","min":0,"max":1,"optional":true,"saveAs":"recovered","filter":{"field":"card_name","operator":"in","value":["降谷零","諸伏景光","伊達航","萩原研二","松田陣平"]},"prompt":"패에 추가할 경찰학교 동기 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"recovered","to":"hand","when":{"fact":"vars.recovered.count","operator":"greater_than","value":0}}],"reviewNotes":{"rationale":"이 카드가 증거에서 리무브되면 리무브 에이리어의 경찰학교 동기 캐릭터 5종 중 1장까지 패로 회수한다.","sourceText":"【ヒラメキ】自分のリムーブエリアにあるカード名［降谷零］か［諸伏景光］か［伊達航］か［萩原研二］か［松田陣平］を1枚まで選び、手札に加える。"}},{"effectId":"card-1133-bond-matsuda-ap-plus-1000","cardIds":["1133"],"cardNameJa":"萩原研二","cardNameKo":"하기와라 켄지","trigger":{"event":"continuous.recalculate","timing":"continuous"},"continuous":true,"conditions":[{"fact":"turn.is_source_controller_turn","operator":"equals","value":true},{"fact":"player.field.has_card_name","operator":"equals","value":"松田陣平"}],"steps":[{"op":"set_continuous_stat","stat":"ap","target":"source_character","amount":1000,"duration":"while_condition_true","modifierId":"police-academy-1133-bond-matsuda-ap"}],"reviewNotes":{"rationale":"인연 [마츠다 진페이]가 성립한 자신의 턴 중 AP를 1000 올린다.","sourceText":"【絆［松田陣平］】【自分ターン中】AP＋1000。"}},{"effectId":"card-1133-on-enter-search-police-academy","cardIds":["1133"],"cardNameJa":"萩原研二","cardNameKo":"하기와라 켄지","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"peek_top_cards","count":3,"saveAs":"seen","allowFewer":true},{"op":"select_cards","from":"seen","min":0,"max":1,"optional":true,"saveAs":"selected","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"field":"card_name","operator":"in","value":["降谷零","諸伏景光","伊達航","萩原研二","松田陣平"]}]},"prompt":"공개하여 패에 추가할 경찰학교 동기 캐릭터를 최대 1장 선택하세요.","displayVariable":"seen"},{"op":"reveal_cards","to":["opponent"],"from":"selected","when":{"fact":"vars.selected.count","operator":"greater_than","value":0},"awaitAcknowledgement":true},{"op":"move_cards","to":"hand","from":"selected","when":{"fact":"vars.selected.count","operator":"greater_than","value":0}},{"op":"move_unselected_to_zone","to":"remove_area","from":"seen","order":"preserve","selectedVariable":"selected"}],"reviewNotes":{"rationale":"등장 시 덱 위 3장을 확인하고 경찰학교 동기 캐릭터 5종 중 1장까지 공개하여 패에 추가한다. 선택하지 않은 카드는 리무브 에이리어로 옮긴다.","sourceText":"【登場時】自分のデッキの上から3枚を見る。その中からカード名［降谷零］か［諸伏景光］か［伊達航］か［萩原研二］か［松田陣平］を1枚まで公開して手札に加え、残りをリムーブエリアに移す。"}},{"effectId":"card-0911-on-enter-investigate-three-and-grant-keywords","cardIds":["0911"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[],"steps":[{"op":"select_trait","saveAs":"selected_trait","prompt":"상대 덱을 조사할 특징을 하나 지정하세요."},{"op":"investigate_opponent_deck","count":3,"saveAs":"investigated","traitVariable":"selected_trait","destination":"deck_bottom","prompt":"상대는 덱 위 3장을 공개한 뒤 원하는 순서로 덱 아래에 놓습니다."},{"op":"grant_keyword","target":"source_character","keyword":"charge_character","duration":"turn_end","displayNameKo":"돌격[캐릭터]","when":{"fact":"vars.investigated.match_count","operator":"greater_than_or_equal","value":1}},{"op":"grant_keyword","target":"source_character","keyword":"charge","duration":"turn_end","displayNameKo":"돌격","when":{"fact":"vars.investigated.match_count","operator":"greater_than_or_equal","value":2}},{"op":"grant_keyword","target":"source_character","keyword":"haya","duration":"turn_end","displayNameKo":"신속","when":{"fact":"vars.investigated.match_count","operator":"greater_than_or_equal","value":3}}],"reviewNotes":{"rationale":"등장 시 특징을 하나 지정하고 상대 덱 위 3장을 조사한다. 상대는 공개한 카드를 원하는 순서로 덱 아래에 놓으며, 지정한 특징이 나온 장수에 따라 돌격[캐릭터](1장 이상), 돌격(2장 이상), 신속(3장)을 턴 종료까지 얻는다.","sourceText":"【登場時】特徴を1つ指定し、捜査3（相手はデッキのカードを上から3枚公開し、好きな順番でデッキの下に移す）。指定した特徴を持つカードが公開された枚数に応じて、ターン終了時までこのキャラは以下の能力を持つ。1枚以上：突撃［キャラ］、2枚以上：突撃、3枚以上：迅速。"}},{"effectId":"card-0148-partner-yellow-swift","cardIds":["0148"],"cardNameJa":"降谷零","cardNameKo":"후루야 레이","trigger":{"event":"character.entered_field","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"}],"steps":[{"op":"grant_keyword","target":"source_character","keyword":"haya","duration":"turn_end","displayNameKo":"신속"}],"reviewNotes":{"rationale":"파트너 색상이 황이면 등장한 턴부터 바로 추리 또는 액션할 수 있도록 턴 종료까지 신속을 부여한다.","sourceText":"【パートナー黄】迅速。"}},{"effectId":"card-0356-event-stun-or-remove-character","cardIds":["0356"],"cardNameJa":"ヤンチャな5人組","cardNameKo":"장난꾸러기 5인조","trigger":{"event":"event.played","timing":"after"},"conditions":[{"fact":"player.partner.color","operator":"equals","value":"yellow"}],"steps":[{"op":"select_cards","from":"opponent_field","min":0,"max":1,"optional":true,"saveAs":"target","filter":{"allOf":[{"field":"card_type","operator":"equals","value":"character"},{"not":{"field":"status","operator":"equals","value":"stunned"}}]},"prompt":"스턴 또는 리무브할 상대 캐릭터를 최대 1장 선택하세요."},{"op":"move_cards","from":"target","to":"remove_area","targetOwner":"opponent","when":{"allOf":[{"fact":"vars.target.count","operator":"greater_than","value":0},{"fact":"player.field.character.count","operator":"greater_than_or_equal","value":5}]}},{"op":"stun_cards","target":"target","when":{"allOf":[{"fact":"vars.target.count","operator":"greater_than","value":0},{"fact":"player.field.character.count","operator":"less_than","value":5}]}}],"reviewNotes":{"rationale":"파트너 황 조건. 상대 캐릭터를 최대 1장 선택한다. 자신의 현장 캐릭터가 5장 이상이면 해당 캐릭터를 리무브하고, 5장 미만이면 스턴한다. 스턴된 캐릭터가 액티브화될 때는 슬립으로 대신 처리하는 기존 전역 스턴 규칙을 사용한다.","sourceText":"【パートナー黄】相手の現場にいるキャラを1枚まで選び、スタンさせる。（スタン状態のキャラをアクティブにする場合、代わりにスリープさせる）自分の現場にキャラが5枚以上いる場合、代わりにそのキャラをリムーブする。"}}]$defs$::jsonb;
BEGIN
  -- 1) The DSL runner: player-selected trait and three-card opponent-deck investigation.
  v_definition := pg_get_functiondef('public.private_card_effect_run_v1(uuid)'::regprocedure);

  v_old := $old$v_keyword text; v_deck jsonb; v_seen jsonb; v_match_filter jsonb; v_name text;$old$;
  v_new := $new$v_keyword text; v_deck jsonb; v_seen jsonb; v_match_filter jsonb; v_name text; v_trait text; v_match_count integer;$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'card effect runner declaration anchor missing';
  END IF;

  v_old := $old$   ELSIF v_op='select_cards' THEN$old$;
  v_new := $new$   ELSIF v_op='select_trait' THEN
     v_waiting:=jsonb_build_object(
       'kind','trait','save_as',coalesce(v_step->>'saveAs','selected_trait'),
       'chooser_user_id',v_owner
     );
     v_pending:=jsonb_build_object(
       'type','card_effect_trait_selection','effect_id',v_effect_id,
       'source_instance_id',v_effect_source_instance_id,'source_user_id',v_owner,
       'chooser_user_id',v_owner,
       'prompt',coalesce(v_step->>'prompt','조사할 특징을 하나 지정하세요.')
     );
     UPDATE public.private_card_effect_runs_v1
       SET waiting=v_waiting,updated_at=now() WHERE room_id=p_room_id;
     UPDATE public.room_match_states
       SET pending_action=v_pending||jsonb_build_object(
         'source_card',coalesce(v_effect_source_card,'{}'::jsonb),
         'source_card_name',coalesce(v_effect_source_card->>'name','')
       ),
       state_version=state_version+1,
       last_action_label='카드 효과: 조사할 특징을 지정해 주세요.'
       WHERE room_id=p_room_id;
     RETURN;

   ELSIF v_op='select_cards' THEN$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'select_trait runner insertion anchor missing';
  END IF;

  v_old := $old$     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1 FOR UPDATE;
     v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);$old$;
  v_new := $new$     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id<>v_owner ORDER BY seat LIMIT 1 FOR UPDATE;
     v_n:=least(greatest(0,coalesce(nullif(v_step->>'count','')::integer,1)),
       jsonb_array_length(coalesce(v_game.deck_order,'[]'::jsonb)));
     IF v_n>1 THEN
       SELECT coalesce(jsonb_agg(jsonb_build_object(
         'instance_id',e.value->>'instance_id','owner_user_id',v_game.user_id,
         'zone','opponent_deck','card',e.value
       ) ORDER BY e.ordinality),'[]'::jsonb)
       INTO v_selected
       FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb))
         WITH ORDINALITY e(value,ordinality)
       WHERE e.ordinality<=v_n;
       SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality)
         FILTER(WHERE e.ordinality>v_n),'[]'::jsonb)
       INTO v_deck
       FROM jsonb_array_elements(coalesce(v_game.deck_order,'[]'::jsonb))
         WITH ORDINALITY e(value,ordinality);
       UPDATE public.room_player_game_states
         SET deck_order=v_deck,updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_game.user_id;

       v_waiting:=jsonb_build_object(
         'kind','order','options',v_selected,
         'save_as','__opponent_deck_inspection_order',
         'result_save_as',coalesce(v_step->>'saveAs','investigated'),
         'trait_variable',coalesce(v_step->>'traitVariable','selected_trait'),
         'destination',coalesce(v_step->>'destination','deck_bottom'),
         'chooser_user_id',v_game.user_id,
         'prompt',coalesce(v_step->>'prompt','공개한 카드를 원하는 순서로 덱 아래에 놓으세요.')
       );
       v_pending:=jsonb_build_object(
         'type','card_effect_order','effect_id',v_effect_id,
         'source_instance_id',v_effect_source_instance_id,
         'source_user_id',v_owner,'chooser_user_id',v_game.user_id,
         'prompt',coalesce(v_step->>'prompt','공개한 카드를 원하는 순서로 덱 아래에 놓으세요.'),
         'options_count',jsonb_array_length(v_selected),
         'revealed_cards',v_selected
       );
       UPDATE public.private_card_effect_runs_v1
         SET variables=v_vars,waiting=v_waiting,updated_at=now()
         WHERE room_id=p_room_id;
       UPDATE public.room_match_states
         SET pending_action=v_pending||jsonb_build_object(
           'source_card',coalesce(v_effect_source_card,'{}'::jsonb),
           'source_card_name',coalesce(v_effect_source_card->>'name','')
         ),
         state_version=state_version+1,
         last_action_label='카드 효과: 상대 덱 위 카드 공개 및 순서 지정을 기다립니다.'
         WHERE room_id=p_room_id;
       RETURN;
     END IF;
     v_card:=coalesce(v_game.deck_order->0,'{}'::jsonb);$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'multi-card opponent deck investigation anchor missing';
  END IF;

  -- Preserve entry type and support a rested deployment (e.g. Matsuda & Hagiwara's bond).
  v_old := $old$v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_to:=coalesce(v_step->>'to','');$old$;
  v_new := $new$v_card:=coalesce(v_item->'card',v_item);
       v_target_owner:=coalesce(nullif(v_item->>'owner_user_id','')::uuid,v_owner);
       v_to:=coalesce(v_step->>'to','');
       IF v_to='field' AND nullif(v_step->>'entryMethod','') IS NOT NULL THEN
         v_card:=v_card||jsonb_build_object('entry_method',v_step->>'entryMethod');
       END IF;
       IF v_to='field' AND coalesce((v_step->>'rested')::boolean,false) THEN
         v_card:=v_card||jsonb_build_object('rested',true,'status','rested');
       END IF;$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'move_cards entry metadata anchor missing';
  END IF;

  EXECUTE v_definition;

  -- 2) The continuation handler: accept trait input and return the inspected cards to the bottom.
  v_definition := pg_get_functiondef('public.private_card_effect_continue_v1(uuid,jsonb)'::regprocedure);
  v_old := $old$v_choice text; v_vars jsonb; v_ordered jsonb; v_cards jsonb; v_index integer; v_next jsonb;$old$;
  v_new := $new$v_choice text; v_vars jsonb; v_ordered jsonb; v_cards jsonb; v_index integer; v_next jsonb; v_trait text; v_match_count integer;$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'continue declaration anchor missing';
  END IF;

  v_old := $old$ ELSIF v_wait->>'kind'='order' THEN
   v_ids:=coalesce(p_payload->'selected_instance_ids','[]'::jsonb);$old$;
  v_new := $new$ ELSIF v_wait->>'kind'='trait' THEN
   v_trait:=btrim(coalesce(p_payload->>'trait',''));
   IF v_trait='' OR length(v_trait)>80 THEN
     RAISE EXCEPTION '조사할 특징을 1~80자 사이로 입력해 주세요.';
   END IF;
   v_vars:=jsonb_set(v_vars,ARRAY[coalesce(v_wait->>'save_as','selected_trait')],to_jsonb(v_trait),true);
   UPDATE public.private_card_effect_runs_v1
     SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now()
     WHERE room_id=p_room_id;

 ELSIF v_wait->>'kind'='order' THEN
   v_ids:=coalesce(p_payload->'selected_instance_ids','[]'::jsonb);$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'trait continuation insertion anchor missing';
  END IF;

  v_old := $old$   v_save:=coalesce(v_wait->>'save_as','__ordered_unselected');
   v_vars:=jsonb_set(v_vars,ARRAY[v_save],coalesce(v_ordered,'[]'::jsonb),true);
   UPDATE public.private_card_effect_runs_v1 SET variables=v_vars,waiting=NULL,updated_at=now() WHERE room_id=p_room_id;$old$;
  v_new := $new$   v_save:=coalesce(v_wait->>'save_as','__ordered_unselected');
   IF v_save='__opponent_deck_inspection_order' THEN
     v_target_owner:=coalesce(nullif(v_ordered->0->>'owner_user_id','')::uuid,v_run.actor_user_id);
     SELECT * INTO v_game FROM public.room_player_game_states
       WHERE room_id=p_room_id AND user_id=v_target_owner FOR UPDATE;
     SELECT coalesce(jsonb_agg(coalesce(e.value->'card',e.value) ORDER BY e.ordinality),'[]'::jsonb)
       INTO v_cards
       FROM jsonb_array_elements(coalesce(v_ordered,'[]'::jsonb))
         WITH ORDINALITY e(value,ordinality);
     IF coalesce(v_wait->>'destination','deck_bottom')='deck_bottom' THEN
       UPDATE public.room_player_game_states
         SET deck_order=coalesce(deck_order,'[]'::jsonb)||coalesce(v_cards,'[]'::jsonb),
             updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_target_owner;
     ELSE
       UPDATE public.room_player_game_states
         SET deck_order=coalesce(v_cards,'[]'::jsonb)||coalesce(deck_order,'[]'::jsonb),
             updated_at=now()
         WHERE room_id=p_room_id AND user_id=v_target_owner;
     END IF;
     v_trait:=coalesce(v_vars->>coalesce(v_wait->>'trait_variable','selected_trait'),'');
     SELECT count(*)::integer INTO v_match_count
       FROM jsonb_array_elements(coalesce(v_cards,'[]'::jsonb)) e(value)
       WHERE public.private_card_effect_has_trait_v1(e.value,v_trait);
     v_vars:=jsonb_set(v_vars,ARRAY[coalesce(v_wait->>'result_save_as','investigated')],
       jsonb_build_object('match_count',coalesce(v_match_count,0)),true);
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,step_index=step_index+1,waiting=NULL,updated_at=now()
       WHERE room_id=p_room_id;
   ELSE
     v_vars:=jsonb_set(v_vars,ARRAY[v_save],coalesce(v_ordered,'[]'::jsonb),true);
     UPDATE public.private_card_effect_runs_v1
       SET variables=v_vars,waiting=NULL,updated_at=now()
       WHERE room_id=p_room_id;
   END IF;$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'special deck-order continuation anchor missing';
  END IF;
  EXECUTE v_definition;

  -- 3) Extend facts consumed by the new Police Academy definitions.
  v_definition := pg_get_functiondef(
    'public.private_card_effect_fact_v1(uuid,uuid,uuid,jsonb,jsonb,jsonb,text)'::regprocedure
  );
  v_old := $old$ IF p_fact='source.status' THEN$old$;
  v_new := $new$ IF p_fact='player.case_phase' THEN
   RETURN to_jsonb(coalesce(v_board.case_phase,'incident'));
 END IF;
 IF p_fact='source.instance_id' THEN
   RETURN to_jsonb(coalesce(p_source_card->>'instance_id',''));
 END IF;
 IF p_fact='entry.source.card_name' THEN
   RETURN to_jsonb(public.private_card_effect_name_v1(coalesce(p_context#>'{entry,source}','{}'::jsonb)));
 END IF;
 IF p_fact='entry.source.instance_id' THEN
   RETURN coalesce(p_context#>'{entry,source,instance_id}','null'::jsonb);
 END IF;
 IF p_fact='entry.controller_is_source_controller' THEN
   RETURN to_jsonb(coalesce(p_context#>>'{entry,controller_user_id}',p_source_user::text)=p_source_user::text);
 END IF;
 IF p_fact='contact.source.ap' THEN
   IF p_context#>'{contact,source_ap}' IS NOT NULL THEN
     RETURN p_context#>'{contact,source_ap}';
   ELSIF nullif(p_context#>>'{contact,attacker_user_id}','')::uuid=p_source_user THEN
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,attacker_ap}','')::numeric,0));
   ELSE
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,target_ap}','')::numeric,0));
   END IF;
 END IF;
 IF p_fact='contact.target.ap' THEN
   IF p_context#>'{contact,target_ap}' IS NOT NULL THEN
     RETURN p_context#>'{contact,target_ap}';
   ELSIF nullif(p_context#>>'{contact,attacker_user_id}','')::uuid=p_source_user THEN
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,target_ap}','')::numeric,0));
   ELSE
     RETURN to_jsonb(coalesce(nullif(p_context#>>'{contact,attacker_ap}','')::numeric,0));
   END IF;
 END IF;
 IF p_fact='source.status' THEN$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'fact helper insertion anchor missing';
  END IF;
  EXECUTE v_definition;

  -- 4) Preserve the entering controller on manually played characters, so field-watch effects distinguish own/enemy entries.
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2(uuid,text,jsonb)'::regprocedure);
  v_old := $old$'method','manual','is_first_character_this_turn',v_first_entry,'source',v_source_card),$old$;
  v_new := $new$'method','manual','is_first_character_this_turn',v_first_entry,'source',v_source_card,'controller_user_id',v_user::text),$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'manual character-entry controller anchor missing';
  END IF;
  EXECUTE v_definition;

  -- 5) Furuya's Bond with Hiromitsu permits contacting an active character of any level.
  v_definition := pg_get_functiondef('public.perform_private_turn_action_v2_legacy(uuid,text,jsonb)'::regprocedure);
  v_old := $old$       and NOT (
         public.private_card_effect_matches_id_v1(v_attacker,'["0938"]'::jsonb)
         AND public.private_card_effect_level_v1(v_target)>=7
       ) then$old$;
  v_new := $new$       and NOT (
         (
           public.private_card_effect_matches_id_v1(v_attacker,'["0938"]'::jsonb)
           AND public.private_card_effect_level_v1(v_target)>=7
         )
         OR (
           public.private_card_effect_matches_id_v1(v_attacker,'["1123"]'::jsonb)
           AND EXISTS(
             SELECT 1
             FROM jsonb_array_elements(coalesce(v_board.field_cards,'[]'::jsonb)) bond_card(value)
             WHERE public.private_card_effect_name_matches_v1(bond_card.value,'諸伏景光')
           )
         )
       ) then$new$;
  IF position(v_old in v_definition) > 0 THEN
    v_definition := replace(v_definition, v_old, v_new);
  ELSIF position(v_new in v_definition) = 0 THEN
    RAISE EXCEPTION 'active-contact bond rule anchor missing';
  END IF;
  EXECUTE v_definition;

  -- 6) Synchronize the runtime catalog idempotently.
  UPDATE public.private_card_effect_catalog_v1 c
    SET definitions=(
      SELECT coalesce(jsonb_agg(e.value),'[]'::jsonb)
      FROM jsonb_array_elements(coalesce(c.definitions,'[]'::jsonb)) e(value)
      WHERE NOT (e.value->>'effectId'=ANY(ARRAY[
        'card-1121-field-watch-remove-level9-on-police-academy-enter',
        'card-1121-bond-furuya-end-turn-recover-police',
        'card-1121-activated-bond-target-ap-plus-2000',
        'card-1122-partner-yellow-charge',
        'card-1122-contact-removed-bond-followup-remove-level7',
        'card-1123-continuous-charge',
        'card-1123-bond-date-ready-at-turn-end',
        'card-1123-bond-hagiwara-ap-plus-1000',
        'card-1123-bond-matsuda-ap-plus-1000',
        'card-1129-solution-character-ability-entry-draw',
        'card-1129-hirameki-recover-police-academy-character',
        'card-1133-bond-matsuda-ap-plus-1000',
        'card-1133-on-enter-search-police-academy',
        'card-0911-on-enter-investigate-three-and-grant-keywords',
        'card-0148-partner-yellow-swift',
        'card-0356-event-stun-or-remove-character'
      ]))
    ) || v_definitions,
    updated_at=now()
    WHERE c.catalog_id='main';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'main card effect catalog row was not found';
  END IF;
END
$migration$;
