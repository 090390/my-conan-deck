import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const AI_EMAIL = "conan-tcg-ai-bot@my-conan-deck.invalid";
const AI_ACTION_DELAY_MS = 2500;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders });
}
function cardCost(card: any) {
  const value = Number(card?.cost);
  return Number.isFinite(value) ? value : 999;
}
function cardAp(card: any) {
  const value = Number(card?.ap) + Number(card?.ap_bonus || 0);
  return Number.isFinite(value) ? value : 0;
}
function isCharacter(card: any) {
  return String(card?.card_type || "").toLowerCase() === "character";
}
function isEvent(card: any) {
  return String(card?.card_type || "").toLowerCase() === "event";
}
function isActive(card: any) {
  return !card?.rested && String(card?.status || "active") === "active";
}
function cardStrength(card: any) {
  return cardAp(card) * 2 + Math.max(0, 4 - cardCost(card)) * 250 + Number(card?.lp || 0) * 20;
}
function chooseMulligan(hand: any[]) {
  const cheapCharacters = hand.filter((card) => isCharacter(card) && cardCost(card) <= 3).length;
  if (cheapCharacters >= 2) {
    return hand.filter((card) => cardCost(card) >= 6 && (!isCharacter(card) || Number(card?.ap || 0) < 2000))
      .map((card) => card.instance_id);
  }
  return hand.filter((card) => cardCost(card) >= 5).map((card) => card.instance_id);
}
function chooseResponse(state: any, aiId: string) {
  const pending = state?.pending_action;
  const boards = Array.isArray(state?.boards) ? state.boards : [];
  const me = boards.find((board: any) => board.user_id === aiId);
  const field = Array.isArray(me?.field_cards) ? me.field_cards : [];
  const hand = Array.isArray(state?.my_hand) ? state.my_hand : [];
  if (!pending) return null;
  if (pending.type === "culprits_crime_reveal") {
    const acknowledged = Array.isArray(pending.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
    return acknowledged.includes(aiId) ? null : { action: "acknowledge_culprits_crime" };
  }
  if (pending.type === "character_contact_guard" && pending.target_user_id === aiId) {
    const attackerPower = Number(pending.attacker_ap || 0) + Number(pending.attacker_bonus || 0);
    const guard = field.filter((card: any) => isCharacter(card) && isActive(card)
      && card.instance_id !== pending.target_instance_id)
      .sort((a: any, b: any) => cardAp(b) - cardAp(a))[0];
    return guard && cardAp(guard) >= attackerPower
      ? { action: "guard_contact_with_character", payload: { instance_id: guard.instance_id } }
      : { action: "decline_contact_guard" };
  }
  if (pending.type === "evidence_attack" && pending.target_user_id === aiId) {
    const attackerPower = Number(pending.attacker_ap || 0) + Number(pending.attacker_bonus || 0);
    const guard = field.filter((card: any) => isCharacter(card) && isActive(card))
      .sort((a: any, b: any) => cardAp(b) - cardAp(a))[0];
    return guard && cardAp(guard) >= attackerPower
      ? { action: "guard_with_character", payload: { instance_id: guard.instance_id } }
      : { action: "decline_guard" };
  }
  if (pending.type === "mislead_response" && pending.target_user_id === aiId) {
    const candidate = field.filter((card: any) => Number(card?.mislead_value || 0) > 0 && isActive(card))
      .sort((a: any, b: any) => Number(b.mislead_value) - Number(a.mislead_value))[0];
    return candidate
      ? { action: "resolve_mislead", payload: { instance_id: candidate.instance_id } }
      : { action: "pass_mislead" };
  }
  if (pending.type === "character_contact" && pending.next_responder_user_id === aiId) {
    const myAp = pending.attacker_user_id === aiId
      ? Number(pending.attacker_ap || 0) + Number(pending.attacker_bonus || 0)
      : Number(pending.target_ap || 0) + Number(pending.target_bonus || 0);
    const opponentAp = pending.attacker_user_id === aiId
      ? Number(pending.target_ap || 0) + Number(pending.target_bonus || 0)
      : Number(pending.attacker_ap || 0) + Number(pending.attacker_bonus || 0);
    const needed = Math.max(0, opponentAp - myAp + 1);
    const cutin = hand.filter((card: any) => Number(card?.cut_in_bonus || 0) >= needed
      && Number(card?.cut_in_bonus || 0) > 0)
      .sort((a: any, b: any) => Number(a.cut_in_bonus) - Number(b.cut_in_bonus))[0];
    if (cutin && needed > 0) {
      return { action: "contact_use_cutin", payload: { instance_id: cutin.instance_id } };
    }
    return { action: "contact_pass_cutin" };
  }
  if (pending.type === "deck_remove_reveal") return { action: "acknowledge_deck_remove" };
  if (pending.type === "file_remove_reveal") return { action: "acknowledge_file_remove" };
  if (pending.type === "evidence_attack_reveal" && pending.attacker_user_id === aiId) {
    return { action: "resolve_evidence_attack" };
  }
  if (pending.type === "hand_reveal") return { action: "acknowledge_hand_reveal" };
  if (pending.type === "evidence_remove_reveal") return { action: "acknowledge_evidence_remove" };
  if (pending.type === "shared_deck_peek" && pending.target_user_id === aiId) {
    return { action: "acknowledge_shared_deck_peek" };
  }
  return null;
}
function chooseTurnAction(state: any, aiId: string, lastNextHintTurnNumber: number | null = null) {
  const response = chooseResponse(state, aiId);
  if (response) return response;
  if (state?.pending_action) return null;

  const boards = Array.isArray(state?.boards) ? state.boards : [];
  const me = boards.find((board: any) => board.user_id === aiId);
  const opponent = boards.find((board: any) => board.user_id !== aiId);
  if (!me || !opponent) return null;

  const hand = Array.isArray(state?.my_hand) ? state.my_hand : [];
  const field = Array.isArray(me.field_cards) ? me.field_cards : [];
  const enemyField = Array.isArray(opponent.field_cards) ? opponent.field_cards : [];
  const activeAttackers = field.filter((card: any) => isCharacter(card) && isActive(card) && !card.summoned_this_turn)
    .sort((a: any, b: any) => cardAp(b) - cardAp(a));
  const characterCount = field.filter((card: any) => isCharacter(card)).length;
  const level = Math.max(0, Number(me.file_count || 0)) + (me.partner_assist_used ? 1 : 0);
  const basePlayed = Boolean(me.base_card_played_this_turn || me.character_played_this_turn);
  const turnNumber = Number(state?.turn_number || 0);
  const nextHintAlreadyUsedThisTurn = turnNumber > 0 && Number(lastNextHintTurnNumber) === turnNumber;

  if (state.turn_step === "begin") return { action: "begin_turn" };
  if (state.turn_step === "file") return { action: "place_files" };
  if (state.turn_step !== "main") return null;

  if (me.next_hint_pending) {
    const nextCard = hand.filter((card: any) => isCharacter(card) && cardAllowedByEvent(card)
      && cardCost(card) <= level + 1 && characterCount < 5)
      .sort((a: any, b: any) => cardStrength(b) - cardStrength(a))[0];
    return nextCard
      ? { action: "next_hint", payload: { instance_id: nextCard.instance_id } }
      : { action: "cancel_next_hint" };
  }

  if (!basePlayed) {
    const play = hand.filter((card: any) => isCharacter(card) && cardAllowedByEvent(card)
      && cardCost(card) <= level && characterCount < 5)
      .sort((a: any, b: any) => cardStrength(b) - cardStrength(a))[0];
    if (play) return { action: "play_character", payload: { instance_id: play.instance_id } };
  }

  if (!me.partner_rested && !me.partner_assist_used && me.partner_key) {
    const unlocksCard = hand.some((card: any) => isCharacter(card) && cardAllowedByEvent(card)
      && cardCost(card) > level && cardCost(card) <= level + 1 && characterCount < 5);
    if (unlocksCard) return { action: "partner_assist" };
  }

  if (!me.partner_rested && !me.partner_deduction_used && me.partner_key && Number(me.evidence_count || 0) < 2) {
    return { action: "partner_deduce", payload: { evidence_count: 1 } };
  }

  // 넥스트 힌트는 해결편에서만, 파일 소모 후에도 실제로 등장 가능한 카드가
  // 확인되고 이번 턴에 아직 사용하지 않은 경우에 한해 선언합니다.
  const isSolution = String(me.case_phase || "incident").toLocaleLowerCase() === "solution";
  if (me.base_action_done && !me.next_hint_used && !nextHintAlreadyUsedThisTurn
      && isSolution && Number(me.file_count || 0) >= 4 && characterCount < 5) {
    const canContinue = hand.some((card: any) => isCharacter(card) && cardAllowedByEvent(card)
      && cardCost(card) <= level && characterCount < 5);
    if (canContinue) return { action: "next_hint_take_file" };
  }

  const restedTarget = enemyField.filter((card: any) => isCharacter(card) && !isActive(card))
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (activeAttackers.length && restedTarget) {
    return {
      action: "declare_contact",
      payload: {
        attacker_instance_id: activeAttackers[0].instance_id,
        target_user_id: opponent.user_id,
        target_instance_id: restedTarget.instance_id,
        allow_active_target: false,
        allow_newly_played: false,
      },
    };
  }
  if (activeAttackers.length && Number(opponent.evidence_count || 0) > 0) {
    return {
      action: "attack_evidence",
      payload: {
        attacker_instance_id: activeAttackers[0].instance_id,
        target_user_id: opponent.user_id,
        allow_newly_played: false,
      },
    };
  }

  const resolvingEvent = field.find((card: any) => isEvent(card) && card.resolving);
  if (resolvingEvent) return { action: "finish_event", payload: { instance_id: resolvingEvent.instance_id } };
  return { action: "end_turn" };
}


async function ensureBotAccount(service: any) {
  const { data, error } = await service.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (error) throw error;
  const existing = (data?.users || []).find((user: any) => String(user.email || "").toLowerCase() === AI_EMAIL);
  if (existing) return existing.id;
  const { data: created, error: createError } = await service.auth.admin.createUser({
    email: AI_EMAIL,
    email_confirm: true,
    user_metadata: { display_name: "AI 탐정" },
    app_metadata: { role: "conan_tcg_ai_bot" },
  });
  if (createError) throw createError;
  if (!created?.user?.id) throw new Error("AI 계정을 생성하지 못했습니다.");
  return created.user.id;
}

async function driveAiTurns(service: any, roomId: string, humanId: string) {
  const { data: battle, error: battleError } = await service.from("private_ai_battles")
    .select("human_user_id,ai_user_id,last_next_hint_turn_number").eq("room_id", roomId).maybeSingle();
  if (battleError) throw battleError;
  if (!battle) return { is_ai: false };

  const { data: claimed, error: claimError } = await service.rpc("claim_private_ai_battle_worker_v1", {
    p_room_id: roomId, p_human_user_id: humanId,
  });
  if (claimError) throw claimError;
  if (claimed !== true) return { is_ai: true, busy: true, actions: [] };

  try {
    const { data: state, error: stateError } = await service.rpc("get_private_ai_turn_state_v1", { p_room_id: roomId });
    if (stateError) throw stateError;
    if (!state || state.game_over) return { is_ai: true, actions: [] };

    const requestedBy = Array.isArray(state.cancel_requested_by) ? state.cancel_requested_by : [];
    if (requestedBy.includes(humanId)) {
      const { error } = await service.rpc("respond_private_ai_cancel_v1", { p_room_id: roomId });
      if (error) throw error;
      return { is_ai: true, actions: ["respond_private_ai_cancel_v1"], message: "AI 탐정: 중도 종료 제안을 확인하고 게임을 종료하겠습니다." };
    }

    if (state.phase === "mulligan") {
      if (state.my_mulligan_done !== true) {
        const hand = Array.isArray(state.my_hand) ? state.my_hand : [];
        const returnIds = chooseMulligan(hand);
        const returnedNames = hand.filter((card: any) => returnIds.includes(card.instance_id)).map(cardName);
        const { error } = await service.rpc("submit_private_ai_mulligan_v1", {
          p_room_id: roomId, p_return_instance_ids: returnIds,
        });
        if (error) throw error;
        return {
          is_ai: true,
          actions: ["submit_private_ai_mulligan"],
          message: returnedNames.length
            ? `AI 탐정: 시작 손패를 살펴보고 ${returnedNames.join(", ")}을 덱에 돌려보내 멀리건하겠습니다.`
            : "AI 탐정: 시작 손패를 검토했습니다. 이번에는 멀리건하지 않고 그대로 시작하겠습니다.",
        };
      }
      return { is_ai: true, actions: [] };
    }

    if (state.phase !== "playing") return { is_ai: true, actions: [] };
    const { data: greeting, error: greetingError } = await service.rpc("prepare_private_ai_greeting_v1", { p_room_id: roomId });
    if (greetingError) throw greetingError;
    if (greeting && greeting.is_complete !== true) return { is_ai: true, actions: [] };

    const pending = state.pending_action || null;
    const aiMustRespond = Boolean(pending && (
      pending.target_user_id === battle.ai_user_id
      || pending.next_responder_user_id === battle.ai_user_id
      || (pending.type === "culprits_crime_reveal" && pending.initiator_user_id === battle.ai_user_id)
      || (pending.type === "evidence_attack_reveal" && pending.attacker_user_id === battle.ai_user_id)
    ));
    if (state.current_turn_user_id !== battle.ai_user_id && !aiMustRespond) return { is_ai: true, actions: [] };

    const decision = chooseTurnAction(state, battle.ai_user_id, battle.last_next_hint_turn_number);
    if (!decision) return { is_ai: true, actions: [] };
    const message = describeAction(decision, state, battle.ai_user_id);
    let { error: actionError } = await service.rpc("perform_private_ai_turn_action_v1", {
      p_room_id: roomId, p_action: decision.action, p_payload: decision.payload || {},
    });

    // 안전 장치: 넥스트 힌트 선언/등장이 규칙 검사에 막히면 AI의 턴이 영구 정지하지 않도록
    // 선언 단계는 턴 종료로, 이미 선언한 단계는 응급 취소로 복구를 시도합니다.
    if (actionError && decision.action === "next_hint_take_file") {
      const fallback = await service.rpc("perform_private_ai_turn_action_v1", {
        p_room_id: roomId, p_action: "end_turn", p_payload: {},
      });
      if (!fallback.error) {
        return { is_ai: true, actions: ["end_turn"], message: "AI 탐정: 넥스트 힌트의 후속 전개를 안전하게 진행할 수 없어, 파일을 더 소모하지 않고 턴을 종료하겠습니다." };
      }
      actionError = fallback.error;
    } else if (actionError && decision.action === "next_hint") {
      const fallback = await service.rpc("perform_private_ai_turn_action_v1", {
        p_room_id: roomId, p_action: "cancel_next_hint", p_payload: {},
      });
      if (!fallback.error) {
        return { is_ai: true, actions: ["cancel_next_hint"], message: "AI 탐정: 넥스트 힌트로 가져온 카드의 등장이 처리되지 않아 응급 취소로 진행을 복구하겠습니다." };
      }
      actionError = fallback.error;
    }
    if (actionError) {
      return {
        is_ai: true,
        actions: [],
        blocked_action: decision.action,
        message: `AI 탐정: ${decision.action} 행동이 규칙 검사에서 거부되어 진행을 멈췄습니다. ${actionError.message || "상태를 다시 확인해 주세요."}`,
      };
    }

    if (decision.action === "next_hint_take_file") {
      const turnNumber = Number(state.turn_number || 0);
      if (turnNumber > 0) {
        const { error: markerError } = await service.from("private_ai_battles")
          .update({ last_next_hint_turn_number: turnNumber }).eq("room_id", roomId);
        if (markerError) console.error("failed to mark AI Next Hint use", markerError);
      }
    }
    return { is_ai: true, actions: [decision.action], action: decision.action, message };
  } finally {
    await service.rpc("release_private_ai_battle_worker_v1", { p_room_id: roomId, p_human_user_id: humanId });
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST 요청만 지원합니다." }, 405);
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "로그인이 필요합니다." }, 401);

  const url = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (!url || !anonKey || !serviceKey) return json({ error: "Supabase 서버 설정을 확인해 주세요." }, 500);

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  try {
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    const user = userData?.user;
    if (userError || !user) return json({ error: "로그인 세션을 확인할 수 없습니다." }, 401);
    const body = await req.json();

    if (body.action === "create") {
      const humanDeck = Array.isArray(body.main_deck) ? body.main_deck : [];
      const aiDeck = body.ai_deck || {};
      if (!humanDeck.length || !body.partner_key || !body.event_key
        || !Array.isArray(aiDeck.main_deck) || !aiDeck.partner_key || !aiDeck.event_key) {
        return json({ error: "AI 대전에 필요한 덱, 파트너, 사건 카드가 충분하지 않습니다." }, 400);
      }
      const { data: newRoom, error: roomError } = await userClient.rpc("create_private_room");
      if (roomError) throw roomError;
      const room = Array.isArray(newRoom) ? newRoom[0] : newRoom;
      if (!room?.out_room_id || !room?.out_invite_code) throw new Error("AI 대전용 방을 생성하지 못했습니다.");

      const { error: deckError } = await userClient.rpc("submit_private_room_deck", {
        p_room_id: room.out_room_id,
        p_main_deck: humanDeck,
        p_partner_key: String(body.partner_key),
        p_event_key: String(body.event_key),
        p_event_rule_code: String(body.event_rule_code || ""),
      });
      if (deckError) throw deckError;

      const botId = await ensureBotAccount(service);
      const { error: battleError } = await service.rpc("create_private_ai_battle_v1", {
        p_room_id: room.out_room_id,
        p_human_user_id: user.id,
        p_ai_user_id: botId,
        p_ai_main_deck: aiDeck.main_deck,
        p_ai_partner_key: String(aiDeck.partner_key),
        p_ai_event_key: String(aiDeck.event_key),
        p_ai_event_rule_code: String(aiDeck.event_rule_code || ""),
      });
      if (battleError) throw battleError;

      const initial = await driveAiTurns(service, room.out_room_id, user.id);
      return json({ room_id: room.out_room_id, invite_code: room.out_invite_code, initial_ai: initial });
    }

    if (body.action === "step") {
      const roomId = String(body.room_id || "");
      if (!roomId) return json({ error: "대전 방 ID가 없습니다." }, 400);
      const { data: isAi, error: isAiError } = await userClient.rpc("is_private_ai_battle_v1", { p_room_id: roomId });
      if (isAiError) throw isAiError;
      if (isAi !== true) return json({ is_ai: false });
      return json(await driveAiTurns(service, roomId, user.id));
    }

    return json({ error: "지원하지 않는 AI 대전 요청입니다." }, 400);
  } catch (error) {
    console.error("ai-battle error", error);
    return json({ error: error instanceof Error ? error.message : "AI 대전을 처리하지 못했습니다." }, 500);
  }
});
