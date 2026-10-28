-- Restore the trusted AI action wrapper without event-color restrictions.
CREATE OR REPLACE FUNCTION public.perform_private_ai_turn_action_v1(p_room_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_battle public.private_ai_battles%rowtype;
  v_match public.room_match_states%rowtype;
  v_old_sub text := current_setting('request.jwt.claim.sub', true);
  v_old_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  select * into v_battle from public.private_ai_battles
  where room_id = p_room_id;
  if not found then raise exception 'AI 대전 정보를 찾을 수 없습니다.'; end if;

  if p_action not in (
    'begin_turn','place_files','play_character','play_event','next_hint_take_file',
    'next_hint','cancel_next_hint','partner_assist','partner_deduce','end_turn',
    'declare_contact','attack_evidence','guard_with_character','decline_guard',
    'guard_contact_with_character','decline_contact_guard','contact_use_cutin',
    'contact_pass_cutin','contact_use_disguise','resolve_mislead','pass_mislead',
    'resolve_evidence_attack','acknowledge_evidence_remove','acknowledge_culprits_crime',
    'acknowledge_hand_reveal','acknowledge_deck_remove','acknowledge_file_remove',
    'acknowledge_shared_deck_peek','finish_event','solve_case','declare_solution',
    'rest_partner_manual','refresh_deck','return_deck_peek','share_deck_peek_card',
    'take_deck_peek_card','remove_deck_peek_card','shuffle_deck'
  ) then
    raise exception 'AI 대전에서 허용되지 않은 행동입니다.';
  end if;

  select * into v_match from public.room_match_states
  where room_id = p_room_id for update;
  if not found or v_match.game_over then
    raise exception '이미 종료된 AI 대전입니다.';
  end if;

  if cardinality(coalesce(v_match.cancel_requested_by, '{}'::uuid[])) > 0 then
    raise exception 'AI 대전은 중도 종료 응답을 기다리는 동안 일시 중지되어 있습니다.';
  end if;

  if v_match.current_turn_user_id is distinct from v_battle.ai_user_id
    and coalesce(v_match.pending_action ->> 'target_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'next_responder_user_id', '') <> v_battle.ai_user_id::text
    and coalesce(v_match.pending_action ->> 'initiator_user_id', '') <> v_battle.ai_user_id::text then
    raise exception '현재 AI가 행동할 차례가 아닙니다.';
  end if;

  perform set_config('request.jwt.claim.sub', v_battle.ai_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_battle.ai_user_id::text,
    'role', 'authenticated',
    'email', 'conan-tcg-ai-bot@my-conan-deck.invalid'
  )::text, true);

  v_result := public.perform_private_turn_action_v2(
    p_room_id, p_action, coalesce(p_payload, '{}'::jsonb)
  );

  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  return v_result;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(v_old_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_old_claims, ''), true);
  raise;
end;
$function$

