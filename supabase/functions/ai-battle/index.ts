import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};
const AI_EMAIL = "conan-tcg-ai-bot@my-conan-deck.invalid";

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
function isBasicSearchEvent(card: any) {
  const ids = [card?.key, card?.database_id, card?.databaseId, card?.card_id, card?.card_num]
    .map((value) => String(value ?? "").trim().toLocaleUpperCase());
  return ids.some((id) => ["0158", "0130", "B04083", "D03014"].includes(id));
}
function cardStrength(card: any) {
  return cardAp(card) * 2 + Math.max(0, 4 - cardCost(card)) * 250 + Number(card?.lp || 0) * 20;
}
function cardTraits(card: any): string[] {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData
    : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const values = [card?.traits, card?.category1, card?.category2, card?.category3,
    source?.traits, source?.category1, source?.category2, source?.category3];
  return values.flatMap((value) => Array.isArray(value) ? value.map(String)
    : value == null ? [] : String(value).split(/[、,，;；|｜]/u))
    .map((value) => value.trim().toLocaleLowerCase()).filter(Boolean);
}
function cardNameText(card: any): string {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData
    : card?.raw && typeof card.raw === "object" ? card.raw : {};
  return [card?.name, card?.name_ja, card?.card_name, card?.card_id, card?.card_num,
    source?.name, source?.name_ja, source?.card_name, source?.card_id, source?.card_num]
    .map((value) => String(value ?? "")).join(" ").toLocaleLowerCase();
}
const CARD_NAME_ALIASES: Record<string, string[]> = {
  "후루야 레이": ["후루야 레이", "降谷零", "降谷 零", "furuya rei", "rei furuya"],
  "모로후시 히로미츠": ["모로후시 히로미츠", "諸伏景光", "もろふし ひろみつ", "hiromitsu morofushi"],
  "다테 와타루": ["다테 와타루", "伊達航", "wataru date"],
  "하기와라 켄지": ["하기와라 켄지", "萩原研二", "kenji hagiwara"],
  "마츠다 진페이": ["마츠다 진페이", "松田陣平", "jinpei matsuda"],
  "쿠도 신이치": ["쿠도 신이치", "工藤新一", "kudo shinichi", "kudou shinichi"],
};
function matchesCardName(card: any, expected: unknown): boolean {
  const token = String(expected ?? "").trim().toLocaleLowerCase();
  const aliases = CARD_NAME_ALIASES[token] || [token];
  const haystack = cardNameText(card);
  return aliases.some((alias) => alias && haystack.includes(alias.toLocaleLowerCase()));
}
function hasTrait(card: any, expected: unknown): boolean {
  const token = String(expected ?? "").trim().toLocaleLowerCase();
  const aliases: Record<string, string[]> = {
    "경찰": ["경찰", "警察", "police"],
    "경시청": ["경시청", "警視庁", "警視廳", "tokyo metropolitan police"],
  };
  const values = aliases[token] || [token];
  const haystack = cardTraits(card).join(" ");
  return values.some((value) => value && haystack.includes(value.toLocaleLowerCase()));
}
function matchesDslFilter(card: any, filter: any): boolean {
  if (!filter || typeof filter !== "object") return true;
  if (Array.isArray(filter.allOf)) return filter.allOf.every((part: any) => matchesDslFilter(card, part));
  if (Array.isArray(filter.anyOf)) return filter.anyOf.some((part: any) => matchesDslFilter(card, part));
  const field = String(filter.field || "");
  const op = String(filter.operator || "");
  const expected = filter.value;
  let actual: any;
  switch (field) {
    case "card_type": actual = isCharacter(card) ? "character" : String(card?.card_type || "").toLowerCase(); break;
    case "level": actual = cardCost(card); break;
    case "ap_current": actual = cardAp(card); break;
    case "is_active": actual = isActive(card); break;
    case "color": actual = String(card?.color || card?.color_key || card?.colorKo || "").toLowerCase(); break;
    case "trait": return op === "has_trait" ? hasTrait(card, expected) : false;
    case "card_name": {
      const haystack = cardNameText(card);
      if (op === "name_matches") return matchesCardName(card, expected);
      if (op === "in") return Array.isArray(expected) && expected.some((name) => matchesCardName(card, name));
      actual = String(card?.name || card?.card_name || "");
      break;
    }
    case "keyword": {
      const haystack = JSON.stringify(card || {}).toLocaleLowerCase();
      if (op === "has_keyword") return haystack.includes(String(expected ?? "").toLocaleLowerCase());
      actual = haystack;
      break;
    }
    default: actual = card?.[field];
  }
  if (op === "equals") return actual === expected;
  if (op === "in") return Array.isArray(expected) && expected.includes(actual);
  if (op === "less_than") return Number(actual) < Number(expected);
  if (op === "less_than_or_equal") return Number(actual) <= Number(expected);
  if (op === "greater_than") return Number(actual) > Number(expected);
  if (op === "greater_than_or_equal") return Number(actual) >= Number(expected);
  return false;
}
function chooseActivatedAbility(state: any, aiId: string) {
  const activations = Array.isArray(state?.ai_card_effect_activations) ? state.ai_card_effect_activations : [];
  if (!activations.length) return null;
  const boards = Array.isArray(state?.boards) ? state.boards : [];
  const me = boards.find((board: any) => board.user_id === aiId);
  const opponent = boards.find((board: any) => board.user_id !== aiId);
  if (!me || !opponent) return null;
  const ownField = Array.isArray(me.field_cards) ? me.field_cards : [];
  const enemyField = Array.isArray(opponent.field_cards) ? opponent.field_cards : [];
  const hand = Array.isArray(state?.my_hand) ? state.my_hand : [];
  const removeArea = Array.isArray(state?.my_remove_cards) ? state.my_remove_cards : [];
  for (const ability of activations) {
    const sourceId = String(ability?.source_instance_id || "");
    const source = ownField.find((card: any) => String(card?.instance_id || "") === sourceId);
    const definition = ability?.definition;
    if (!source || !isActive(source) || !definition || !Array.isArray(definition.steps)) continue;
    const selections: Array<{ step: any; targets: any[] }> = [];
    let invalid = false;
    for (const step of definition.steps.filter((candidate: any) => candidate?.op === "select_cards")) {
      let candidates: any[] = [];
      const from = String(step.from || "");
      if (from === "opponent_field") candidates = enemyField;
      else if (from === "field") candidates = ownField;
      else if (from === "remove_area") candidates = removeArea;
      else if (from === "hand") candidates = hand;
      else if (from === "deck") candidates = [];
      else if (/^vars\./u.test(from)) continue;
      else continue;
      let validTargets = candidates.filter((card: any) => matchesDslFilter(card, step.filter));
      const statStep = definition.steps.find((candidate: any) =>
        candidate?.op === "modify_stat" && String(candidate.target || "").replace(/^vars\./u, "") === String(step.saveAs || ""));
      if (statStep && from === "field") {
        // A rested source is being slept, so favor a different active teammate for an AP buff.
        const preferred = validTargets.filter((card: any) => isActive(card)
          && String(card.instance_id || "") !== sourceId);
        validTargets = preferred;
      }
      selections.push({ step, targets: validTargets });
      const min = Math.max(0, Number(step.min || 0));
      if (validTargets.length < min) { invalid = true; break; }
      if (validTargets.length === 0 && min === 0) {
        // Don't spend a sleep cost for an ability whose meaningful target is absent.
        if (definition.steps.some((candidate: any) => candidate?.op === "pay_cost")) {
          invalid = true; break;
        }
      }
    }
    if (invalid) continue;

    // If the ability selects an opponent target, spend the source sleep only when a real target exists.
    const hasOpponentTarget = selections.some(({step, targets}) => step.from === "opponent_field" && targets.length > 0);
    const hasOwnFieldTarget = selections.some(({step, targets}) => step.from === "field" && targets.length > 0);
    if (definition.steps.some((step: any) => step?.op === "pay_cost")
      && selections.length > 0 && !hasOpponentTarget && !hasOwnFieldTarget) continue;

    return { action: "activate_card_effect", payload: { source_instance_id: sourceId, effect_id: ability.effect_id } };
  }
  return null;
}
function chooseMulligan(hand: any[]) {
  const cheapCharacters = hand.filter((card) => isCharacter(card) && cardCost(card) <= 3).length;
  if (cheapCharacters >= 2) {
    return hand.filter((card) => cardCost(card) >= 6 && (!isCharacter(card) || Number(card?.ap || 0) < 2000))
      .map((card) => card.instance_id);
  }
  return hand.filter((card) => cardCost(card) >= 5).map((card) => card.instance_id);
}
function cardName(card: any) {
  return String(card?.name || card?.card_name || card?.card_id || card?.card_num || "캐릭터 카드");
}
function describeAction(decision: any, state: any, aiId: string) {
  const boards = Array.isArray(state?.boards) ? state.boards : [];
  const me = boards.find((board: any) => board.user_id === aiId);
  const opponent = boards.find((board: any) => board.user_id !== aiId);
  const hand = Array.isArray(state?.my_hand) ? state.my_hand : [];
  const field = Array.isArray(me?.field_cards) ? me.field_cards : [];
  const card = hand.find((entry: any) => entry.instance_id === decision?.payload?.instance_id);
  const cost = card ? cardCost(card) : null;
  const attacker = field.find((entry: any) => entry.instance_id === decision?.payload?.attacker_instance_id);
  const target = (Array.isArray(opponent?.field_cards) ? opponent.field_cards : [])
    .find((entry: any) => entry.instance_id === decision?.payload?.target_instance_id);
  switch (decision?.action) {
    case "begin_turn": return "AI 탐정: 제 턴을 시작했습니다.";
    case "place_files": return "AI 탐정: 턴 시작에 필요한 파일을 배치했습니다.";
    case "play_character":
      return `AI 탐정: 현재 레벨 상한에 맞는 ${cardName(card)}(코스트 ${cost})를 골라 등장시켰습니다.`;
    case "next_hint_take_file":
      return "AI 탐정: 해결편에서 합법적으로 등장시킬 수 있는 카드가 확인되어 넥스트 힌트를 선언하고 파일 1장을 소비했습니다.";
    case "next_hint":
      return `AI 탐정: 넥스트 힌트로 가져온 ${cardName(card)}(코스트 ${cost})를 등장시켰습니다.`;
    case "cancel_next_hint":
      return "AI 탐정: 파일을 소모한 뒤 등장시킬 합법적인 캐릭터가 없어 넥스트 힌트를 취소했습니다.";
    case "partner_assist":
      return "AI 탐정: 파트너를 어시스트해 이번 턴의 레벨 상한을 1 올렸습니다.";
    case "partner_deduce":
      return "AI 탐정: 파트너 추리로 증거 1장을 확보했습니다.";
    case "activate_card_effect": {
      const source = (Array.isArray(state?.boards) ? state.boards : [])
        .find((board: any) => board.user_id === aiId)?.field_cards
        ?.find((entry: any) => String(entry.instance_id || "") === String(decision?.payload?.source_instance_id || ""));
      return `AI 탐정: ${cardName(source)}의 능력을 발동했습니다.`;
    }
    case "declare_contact":
      return `AI 탐정: ${cardName(attacker)}으로 ${cardName(target)}에게 컨택을 선언했습니다.`;
    case "attack_evidence":
      return `AI 탐정: ${cardName(attacker)}으로 상대 증거 에이리어를 공격했습니다.`;
    case "guard_contact_with_character":
    case "guard_with_character":
      return `AI 탐정: ${cardName(field.find((entry: any) => entry.instance_id === decision?.payload?.instance_id))}으로 상대 공격을 가드했습니다.`;
    case "decline_contact_guard":
    case "decline_guard":
      return "AI 탐정: 공격을 막기에 적합한 캐릭터가 없어 가드를 포기했습니다.";
    case "contact_use_cutin":
      return `AI 탐정: 컷인을 사용해 AP를 ${Number(hand.find((entry: any) => entry.instance_id === decision?.payload?.instance_id)?.cut_in_bonus || 0)} 올렸습니다.`;
    case "contact_pass_cutin": return "AI 탐정: 컷인을 사용하지 않고 AP 비교를 진행했습니다.";
    case "resolve_mislead": return "AI 탐정: 사용할 수 있는 미스리드 효과를 확인해 대응했습니다.";
    case "pass_mislead": return "AI 탐정: 사용할 수 있는 미스리드 효과가 없어 대응을 넘겼습니다.";
    case "resolve_evidence_attack": return "AI 탐정: 공개된 증거 공격의 결과를 처리했습니다.";
    case "finish_event": return "AI 탐정: 이벤트 효과 처리가 끝나 해당 카드를 리무브했습니다.";
    case "end_turn":
      return "AI 탐정: 남은 행동의 이득과 파일 소모를 검토한 결과, 더 진행하지 않고 턴을 종료했습니다.";
    case "acknowledge_culprits_crime": return "AI 탐정: 공개된 범행 증거를 확인했습니다.";
    case "acknowledge_deck_remove": return "AI 탐정: 공개된 덱 리무브 결과를 확인했습니다.";
    case "acknowledge_file_remove": return "AI 탐정: 공개된 파일 리무브 결과를 확인했습니다.";
    case "acknowledge_hand_reveal": return "AI 탐정: 공개된 손패를 확인했습니다.";
    case "acknowledge_evidence_remove": return "AI 탐정: 공개된 증거 리무브 결과를 확인했습니다.";
    case "acknowledge_shared_deck_peek": return "AI 탐정: 상대에게 공개된 덱 정보를 확인했습니다.";
    default: return `AI 탐정: ${decision?.action || "다음 행동"}을 처리했습니다.`;
  }
}

const SHARED_REVEAL_ACKNOWLEDGEMENTS: Record<string, string> = {
  culprits_crime_reveal: "acknowledge_culprits_crime",
  deck_remove_reveal: "acknowledge_deck_remove",
  file_remove_reveal: "acknowledge_file_remove",
  hand_reveal: "acknowledge_hand_reveal",
  evidence_remove_reveal: "acknowledge_evidence_remove",
};

function chooseResponse(state: any, aiId: string) {
  const pending = state?.pending_action;
  const boards = Array.isArray(state?.boards) ? state.boards : [];
  const me = boards.find((board: any) => board.user_id === aiId);
  const field = Array.isArray(me?.field_cards) ? me.field_cards : [];
  const hand = Array.isArray(state?.my_hand) ? state.my_hand : [];
  if (!pending) return null;

  // Shared reveal windows always need an AI acknowledgement, even when it is not the AI's turn.
  // Once acknowledged, do not acknowledge the same window again while waiting for the human.
  const acknowledgementAction = SHARED_REVEAL_ACKNOWLEDGEMENTS[String(pending.type || "")];
  if (acknowledgementAction) {
    const acknowledged = Array.isArray(pending.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
    return acknowledged.includes(aiId) ? null : { action: acknowledgementAction };
  }
  if (pending.type === "character_contact_guard" && pending.target_user_id === aiId) {
    const attackerPower = Number(pending.attacker_ap || 0) + Number(pending.attacker_bonus || 0);
    const threatened = field.find((card: any) => card.instance_id === pending.target_instance_id);
    const guard = field.filter((card: any) => isCharacter(card) && isActive(card)
      && card.instance_id !== pending.target_instance_id)
      .sort((a: any, b: any) => cardAp(b) - cardAp(a))[0];
    // Do not spend a valuable active character to save a substantially weaker body.
    // Protect only when the threatened card's estimated value is reasonably close to the guard's.
    const worthProtecting = Boolean(threatened && guard
      && cardStrength(threatened) >= cardStrength(guard) * 0.8);
    return guard && worthProtecting && cardAp(guard) >= attackerPower
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
  if (pending.type === "evidence_attack_reveal" && pending.target_user_id === aiId) {
    return { action: "resolve_evidence_attack" };
  }
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
  const isSolution = String(me.case_phase || "incident").toLocaleLowerCase() === "solution";
  const canPlanNextHint = Boolean(
    me.base_action_done && !me.next_hint_used && !nextHintAlreadyUsedThisTurn
      && isSolution && Number(me.file_count || 0) >= 4 && characterCount < 5
  );

  if (state.turn_step === "begin") return { action: "begin_turn" };
  if (state.turn_step === "file") {
    // Ability timing is a tactical choice. Use a legal DECLARE/SLEEP ability here
    // only if its condition and a meaningful target are currently available; otherwise
    // proceed with the normal file placement.
    const earlyActivatedAbility = chooseActivatedAbility(state, aiId);
    if (earlyActivatedAbility) return earlyActivatedAbility;
    return { action: "place_files" };
  }
  if (state.turn_step !== "main") return null;

  if (me.next_hint_pending) {
    const nextCard = hand.filter((card: any) => isCharacter(card)
      && cardCost(card) <= level + 1 && characterCount < 5)
      .sort((a: any, b: any) => cardStrength(b) - cardStrength(a))[0];
    return nextCard
      ? { action: "next_hint", payload: { instance_id: nextCard.instance_id } }
      : { action: "cancel_next_hint" };
  }

  const canAssist = !me.partner_rested && !me.partner_assist_used && Boolean(me.partner_key);
  const unlocksCharacterWithAssist = hand.some((card: any) => isCharacter(card)
    && cardCost(card) > level && cardCost(card) <= level + 1 && characterCount < 5);
  // 기본 등장 전에는 어시스트로 먼저 레벨 상한을 올려 고레벨 카드를 우선 고려합니다.
  // 기본 카드가 이미 나온 뒤에는 넥스트 힌트를 이어갈 계획일 때만 어시스트합니다.
  if (canAssist && unlocksCharacterWithAssist && (!basePlayed || canPlanNextHint)) {
    return { action: "partner_assist" };
  }

  if (!basePlayed) {
    const playableCharacters = hand.filter((card: any) => isCharacter(card)
      && cardCost(card) <= level && characterCount < 5)
      .sort((a: any, b: any) => cardStrength(b) - cardStrength(a));
    if (playableCharacters[0]) {
      return { action: "play_character", payload: { instance_id: playableCharacters[0].instance_id } };
    }
    // Use the color-search events as a fallback when no character in hand is currently playable.
    const searchEvent = hand.filter((card: any) => isEvent(card) && isBasicSearchEvent(card)
      && cardCost(card) <= level)
      .sort((a: any, b: any) => cardCost(a) - cardCost(b))[0];
    if (searchEvent && characterCount < 5) {
      return { action: "play_event", payload: { instance_id: searchEvent.instance_id } };
    }
  }

  // Activated abilities are evaluated only after the basic character play has been considered.
  // The server supplies only cards whose partner/file/case/source conditions currently pass.
  const activatedAbility = chooseActivatedAbility(state, aiId);
  if (activatedAbility) return activatedAbility;

  if (!me.partner_rested && !me.partner_deduction_used && me.partner_key && Number(me.evidence_count || 0) < 2) {
    return { action: "partner_deduce", payload: { evidence_count: 1 } };
  }

  // 넥스트 힌트는 해결편에서만, 파일 소모 후에도 실제로 등장 가능한 카드가
  // 확인되고 이번 턴에 아직 사용하지 않은 경우에 한해 선언합니다.
  if (canPlanNextHint) {
    const canContinue = hand.some((card: any) => isCharacter(card)
      && cardCost(card) <= level && characterCount < 5);
    if (canContinue) return { action: "next_hint_take_file" };
  }

  const restedTarget = enemyField.filter((card: any) => isCharacter(card) && !isActive(card))
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (activeAttackers.length && restedTarget) {
    // Do not throw a lower-AP attacker into a losing contact unless a hand cut-in can
    // raise it above the target's AP during that contact.
    const attacker = activeAttackers.find((candidate: any) => {
      const attackerAp = cardAp(candidate);
      const targetAp = cardAp(restedTarget);
      return attackerAp > targetAp || hand.some((card: any) => {
        const bonus = Number(card?.cut_in_bonus || 0);
        return bonus > 0 && attackerAp + bonus > targetAp;
      });
    });
    if (attacker) {
      return {
        action: "declare_contact",
        payload: {
          attacker_instance_id: attacker.instance_id,
          target_user_id: opponent.user_id,
          target_instance_id: restedTarget.instance_id,
          allow_active_target: false,
          allow_newly_played: false,
        },
      };
    }
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
      return { is_ai: true, actions: ["respond_private_ai_cancel_v1"], message: "AI 탐정: 중도 종료 제안을 확인하고 게임을 종료했습니다." };
    }

    if (state.phase === "mulligan") {
      if (state.my_mulligan_done !== true) {
        const hand = Array.isArray(state.my_hand) ? state.my_hand : [];
        const returnIds = chooseMulligan(hand);
        const { error } = await service.rpc("submit_private_ai_mulligan_v1", {
          p_room_id: roomId, p_return_instance_ids: returnIds,
        });
        if (error) throw error;
        return {
          is_ai: true,
          actions: ["submit_private_ai_mulligan"],
          message: returnIds.length
            ? `AI 탐정: 시작 손패를 검토해 ${returnIds.length}장을 덱에 돌려보내 멀리건했습니다.`
            : "AI 탐정: 시작 손패를 검토해 멀리건하지 않았습니다.",
        };
      }
      return { is_ai: true, actions: [] };
    }

    if (state.phase !== "playing") return { is_ai: true, actions: [] };
    const { data: greeting, error: greetingError } = await service.rpc("prepare_private_ai_greeting_v1", { p_room_id: roomId });
    if (greetingError) throw greetingError;
    if (greeting && greeting.is_complete !== true) return { is_ai: true, actions: [] };

    const pending = state.pending_action || null;
    const acknowledgedIds = Array.isArray(pending?.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
    const sharedAcknowledgementAction = SHARED_REVEAL_ACKNOWLEDGEMENTS[String(pending?.type || "")];
    const needsAiAcknowledgement = Boolean(
      (sharedAcknowledgementAction && !acknowledgedIds.includes(battle.ai_user_id))
      || (pending?.type === "shared_deck_peek" && pending.target_user_id === battle.ai_user_id)
    );
    const aiMustRespond = Boolean(pending && (
      pending.target_user_id === battle.ai_user_id
      || pending.next_responder_user_id === battle.ai_user_id
      || pending.chooser_user_id === battle.ai_user_id
      || needsAiAcknowledgement
    ));
    if (state.current_turn_user_id !== battle.ai_user_id && !aiMustRespond) return { is_ai: true, actions: [] };

    if (!pending && state.current_turn_user_id === battle.ai_user_id
      && ["file", "main"].includes(String(state.turn_step || ""))) {
      // DECLARE/SLEEP is legal at any non-blocked timing in the AI's own turn.
      // Evaluate eligible activations during the file step as well as main; the planner
      // will still place files first when no useful, legal activation is available.
      const { data: activationData, error: activationError } = await service.rpc("get_private_ai_card_effect_activations_v1", {
        p_room_id: roomId,
        p_ai_user_id: battle.ai_user_id,
      });
      if (activationError) throw activationError;
      state.ai_card_effect_activations = Array.isArray(activationData?.activations) ? activationData.activations : [];
    }

    let decision: any = null;
    if (pending?.chooser_user_id === battle.ai_user_id && String(pending?.type || "").startsWith("card_effect_")) {
      if (pending.type === "card_effect_selection" || pending.type === "card_effect_order") {
        const { data: effectOptions, error: optionsError } = await service.rpc("get_private_card_effect_options_for_ai_v1", {
          p_room_id: roomId, p_ai_user_id: battle.ai_user_id,
        });
        if (optionsError) throw optionsError;
        const options = Array.isArray(effectOptions?.options) ? effectOptions.options : [];
        const ids = options.map((option: any) => String(option?.instance_id || option?.card?.instance_id || "")).filter(Boolean);
        if (pending.type === "card_effect_order") {
          decision = { action: "card_effect_continue", payload: { selected_instance_ids: ids } };
        } else {
          const min = Math.max(0, Number(pending.min || 0));
          const max = Math.max(0, Number(pending.max || 1));
          const take = Math.min(max, Math.max(min, Math.min(1, ids.length)));
          decision = { action: "card_effect_continue", payload: { selected_instance_ids: ids.slice(0, take) } };
        }
      } else if (pending.type === "card_effect_reveal_ack" || pending.type === "card_effect_reveal_sequence") {
        decision = { action: "card_effect_continue", payload: { decision: "acknowledge" } };
      } else if (pending.type === "card_effect_reaction") {
        const choices = Array.isArray(pending.choices) ? pending.choices : [];
        const choice = choices.includes("pass") ? "pass" : choices[0];
        if (choice) decision = { action: "card_effect_continue", payload: { choice } };
      }
    }
    if (!decision) decision = chooseTurnAction(state, battle.ai_user_id, battle.last_next_hint_turn_number);
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
        return { is_ai: true, actions: ["end_turn"], message: "AI 탐정: 넥스트 힌트의 후속 전개를 안전하게 진행할 수 없어 파일을 더 소모하지 않고 턴을 종료했습니다." };
      }
      actionError = fallback.error;
    } else if (actionError && decision.action === "next_hint") {
      const fallback = await service.rpc("perform_private_ai_turn_action_v1", {
        p_room_id: roomId, p_action: "cancel_next_hint", p_payload: {},
      });
      if (!fallback.error) {
        return { is_ai: true, actions: ["cancel_next_hint"], message: "AI 탐정: 넥스트 힌트로 가져온 카드의 등장이 처리되지 않아 응급 취소로 진행을 복구했습니다." };
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
      const { error: humanEventColorError } = await userClient.rpc("set_private_room_event_has_non_blue_color_v1", {
        p_room_id: room.out_room_id,
        p_has_non_blue_color: Boolean(body.event_has_non_blue_color),
      });
      if (humanEventColorError) throw humanEventColorError;

      const botId = await ensureBotAccount(service);
      const { error: battleError } = await service.rpc("create_private_ai_battle_v1", {
        p_room_id: room.out_room_id,
        p_human_user_id: user.id,
        p_ai_user_id: botId,
        p_ai_main_deck: aiDeck.main_deck,
        p_ai_partner_key: String(aiDeck.partner_key),
        p_ai_event_key: String(aiDeck.event_key),
        p_ai_event_has_non_blue_color: Boolean(aiDeck.event_has_non_blue_color),
        p_ai_event_rule_code: String(aiDeck.event_rule_code || ""),
      });
      if (battleError) throw battleError;

      const initial = await driveAiTurns(service, room.out_room_id, user.id);
      return json({ room_id: room.out_room_id, invite_code: room.out_invite_code, initial_ai: initial });
    }

    if (body.action === "step" || body.action === "cancel") {
      const roomId = String(body.room_id || "");
      if (!roomId) return json({ error: "대전 방 ID가 없습니다." }, 400);
      const { data: isAi, error: isAiError } = await userClient.rpc("is_private_ai_battle_v1", { p_room_id: roomId });
      if (isAiError) throw isAiError;
      if (isAi !== true) return json({ is_ai: false });
      if (body.action === "cancel") {
        // The client records its cancellation request first; an AI response is then immediate,
        // without waiting for the AI worker's next normal turn tick.
        const { error: cancelError } = await service.rpc("respond_private_ai_cancel_v1", { p_room_id: roomId });
        if (cancelError) throw cancelError;
        return json({ is_ai: true, cancelled: true, message: "AI 대전을 즉시 종료했습니다." });
      }
      return json(await driveAiTurns(service, roomId, user.id));
    }

    return json({ error: "지원하지 않는 AI 대전 요청입니다." }, 400);
  } catch (error) {
    console.error("ai-battle error", error);
    return json({ error: error instanceof Error ? error.message : "AI 대전을 처리하지 못했습니다." }, 500);
  }
});
