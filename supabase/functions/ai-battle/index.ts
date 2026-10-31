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
function cardCutInBonus(card: any): number {
  const explicit = Number(card?.cut_in_bonus ?? card?.cutInBonus ?? card?.cut_in_ap_bonus ?? card?.cutInApBonus);
  if (Number.isFinite(explicit) && explicit > 0) return explicit;

  // Some imported cards store their cut-in as printed text instead of a normalized
  // numeric field (e.g. B10041: 「【カットイン】AP＋2000」). Read only cut-in
  // fields so a normal ability mentioning AP does not get mistaken for a cut-in.
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData
    : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const printed = [
    card?.cut_in, card?.cutIn, card?.cut_in_text, card?.cutInText,
    card?.cut_in_effect, card?.cutInEffect, card?.cut_in_description, card?.cutInDescription,
    source?.cut_in, source?.cutIn, source?.cut_in_text, source?.cutInText,
  ].filter((value) => typeof value === "string").join(" ");
  if (!printed || !/(?:カットイン|컷인|cut[\s_-]*in)/iu.test(printed)) return 0;

  const match = printed.match(/(?:ＡＰ|AP)\s*[＋+]\s*([0-9０-９,，]+)/iu);
  if (!match) return 0;
  const digits = match[1].replace(/[０-９]/gu, (digit: string) =>
    String(digit.charCodeAt(0) - "０".charCodeAt(0))).replace(/[，,]/gu, "");
  const bonus = Number(digits);
  return Number.isFinite(bonus) && bonus > 0 ? bonus : 0;
}
function cardCutInBonusForSubject(
  card: any,
  subject: any,
  isOwnerTurn: boolean,
  partnerColor = "",
  ownField: any[] = [],
): number {
  let bonus = cardCutInBonus(card);

  // PR278 / internal 0940: partner-yellow adds 1000 AP; the server separately
  // draws when the supported character has Police.
  if (matchesInternalCardId(card, "0940") && partnerColor === "yellow") {
    bonus += 1000;
  }

  // B05095 / internal 0593: during its owner's turn, each Police character
  // currently on that owner's field adds 1000 AP.
  if (matchesInternalCardId(card, "0593") && isOwnerTurn) {
    const policeCount = ownField.filter((entry: any) =>
      isCharacter(entry) && hasTrait(entry, "경찰")).length;
    bonus += policeCount * 1000;
  }

  // B10078 / internal 1134: AP+2000 only when its owner cuts in during their
  // own turn on a character with the Police trait.
  if (matchesInternalCardId(card, "1134")) {
    return isOwnerTurn && subject && hasTrait(subject, "경찰")
      ? Math.max(2000, bonus)
      : 0;
  }
  return bonus;
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
function cardIdentifierValues(card: any): string[] {
  const sourceData = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : {};
  const raw = card?.raw && typeof card.raw === "object" ? card.raw : {};
  const candidates = [
    card?.internal_card_id, card?.internalCardId, card?.id_code, card?.idCode,
    card?.card_id, card?.cardId, card?.card_num, card?.cardNum,
    sourceData?.internal_card_id, sourceData?.internalCardId, sourceData?.id_code,
    sourceData?.idCode, sourceData?.card_id, sourceData?.cardId,
    raw?.internal_card_id, raw?.internalCardId, raw?.id_code, raw?.idCode,
    raw?.card_id, raw?.cardId, raw?.card_num, raw?.cardNum,
    raw?.sourceData?.internal_card_id, raw?.sourceData?.internalCardId,
    raw?.sourceData?.card_id, raw?.sourceData?.cardId,
  ];
  // Only explicit canonical ID fields are accepted. Printing codes, database row
  // IDs, card numbers, and UUID/key fields are never parsed as card identities.
  return candidates.map((value) => String(value ?? "").trim().toLocaleUpperCase())
    .map((value) => value.replace(/^ID\s*:\s*/u, ""))
    .filter((value) => /^\d{4}$/u.test(value));
}
function matchesInternalCardId(card: any, internalId: string): boolean {
  const wanted = String(internalId ?? "").trim().replace(/^ID\s*:\s*/iu, "");
  return /^\d{4}$/u.test(wanted) && cardIdentifierValues(card).includes(wanted);
}
function dslKeywordValues(card: any): string[] {
  const fields = [card?.dsl_keywords, card?.dsl_continuous_keywords, card?.keywords, card?.keyword_tags, card?.keyword];
  return fields.flatMap((field) => {
    if (Array.isArray(field)) return field.map((item: any) =>
      String(item?.keyword ?? item?.value ?? item?.name ?? item ?? "").trim().toLocaleLowerCase());
    return field == null ? [] : [String(field).trim().toLocaleLowerCase()];
  }).filter(Boolean);
}
function hasCaseOnlyCharge(card: any): boolean {
  return dslKeywordValues(card).some((value) =>
    ["charge_case", "돌격[사건]", "돌격［사건］", "突撃[事件]", "突撃［事件］"].includes(value));
}
function hasCharacterOnlyCharge(card: any): boolean {
  return dslKeywordValues(card).some((value) =>
    ["charge_character", "돌격[캐릭터]", "돌격［캐릭터］", "突撃[キャラ]", "突撃［キャラ］"].includes(value));
}
function hasCharge(card: any): boolean {
  return hasCaseOnlyCharge(card) || hasCharacterOnlyCharge(card)
    || dslKeywordValues(card).some((value) => ["charge", "돌격", "突撃"].includes(value));
}
function hasSwift(card: any): boolean {
  return dslKeywordValues(card).some((value) =>
    ["haya", "swift", "신속", "疾風", "질풍"].includes(value));
}
function isDetectiveVsKidCycleEvent(card: any): boolean {
  return matchesInternalCardId(card, "1215");
}
function normalizedColor(value: unknown): string {
  const token = String(value ?? "").trim().toLocaleLowerCase();
  if (["white", "백", "백색", "白", "白色"].includes(token)) return "white";
  if (["blue", "청", "청색", "青", "青色"].includes(token)) return "blue";
  if (["yellow", "황", "황색", "黄", "黄色"].includes(token)) return "yellow";
  if (["red", "적", "적색", "赤", "赤色"].includes(token)) return "red";
  if (["green", "녹", "녹색", "緑", "緑色"].includes(token)) return "green";
  if (["black", "흑", "흑색", "黒", "黒色"].includes(token)) return "black";
  return token;
}
function isBasicSearchEvent(card: any) {
  // Search events share one rules implementation per four-digit internal ID.
  return ["0144", "0158", "0102", "0116", "0130", "0381"]
    .some((id) => matchesInternalCardId(card, id));
}
function cardStrength(card: any) {
  return cardAp(card) * 2 + Math.max(0, 4 - cardCost(card)) * 250 + Number(card?.lp || 0) * 20;
}
function estimateEventEffectScore(definition: any): number {
  const steps = Array.isArray(definition?.steps) ? definition.steps : [];
  return steps.reduce((score: number, step: any) => {
    switch (String(step?.op || "")) {
      case "peek_top_cards": return score + 4 + Math.min(4, Math.max(0, Number(step.count || 0))) * 0.5;
      case "draw_cards": return score + 4 * Math.max(1, Number(step.count || 1));
      case "move_cards":
        if (step.to === "field") return score + 5;
        if (step.to === "hand") return score + 2.5;
        if (step.to === "evidence_area") return score + 3;
        return score;
      case "flip_evidence": return score + 2.5;
      case "rest_cards": return score + 2;
      case "modify_stat":
      case "modify_contact_ap": return score + 1.5;
      case "grant_keyword":
      case "set_continuous_keyword": return score + 2.5;
      case "attach_top_card": return score + 1.5;
      case "select_cards": return score + 0.5;
      case "schedule_move_to_deck_bottom": return score + 1;
      default: return score;
    }
  }, 0);
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
  if (filter.not) return !matchesDslFilter(card, filter.not);
  const field = String(filter.field || "");
  const op = String(filter.operator || "");
  const expected = filter.value;
  let actual: any;
  switch (field) {
    case "controller": actual = String(card?.controller || "").toLowerCase(); break;
    case "card_type": actual = isCharacter(card) ? "character" : String(card?.card_type || card?.type || "").toLowerCase(); break;
    case "level": actual = cardCost(card); break;
    case "ap_current": actual = cardAp(card); break;
    case "is_active": actual = isActive(card); break;
    case "status": actual = String(card?.status || (card?.rested ? "rested" : "active")).toLowerCase(); break;
    case "face_up": actual = Boolean(card?.face_up ?? card?.faceUp ?? card?.is_face_up ?? card?.isFaceUp ?? false); break;
    case "rarity": actual = String(card?.rarity || card?.rare || card?.rarity_key || "").toUpperCase(); break;
    case "color": actual = normalizedColor(card?.color || card?.color_key || card?.colorKo || card?.color_ja); break;
    case "card_id":
      if (op === "equals") return matchesInternalCardId(card, String(expected ?? ""));
      if (op === "not_equals") return !matchesInternalCardId(card, String(expected ?? ""));
      actual = cardIdentifierValues(card).map((value) => value.toLocaleUpperCase());
      break;
    case "trait": return op === "has_trait" ? hasTrait(card, expected) : false;
    case "card_name": {
      if (op === "name_matches") return matchesCardName(card, expected);
      if (op === "in") return Array.isArray(expected) && expected.some((name) => matchesCardName(card, name));
      actual = String(card?.name || card?.card_name || "");
      break;
    }
    case "keyword": {
      const values = dslKeywordValues(card);
      if (op === "has_keyword") return values.includes(String(expected ?? "").toLocaleLowerCase());
      actual = values;
      break;
    }
    default: actual = card?.[field];
  }
  if (op === "equals") return Array.isArray(actual) ? actual.includes(String(expected).toLocaleUpperCase()) : actual === expected;
  if (op === "not_equals") return Array.isArray(actual) ? !actual.includes(String(expected).toLocaleUpperCase()) : actual !== expected;
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
  const ownField = (Array.isArray(me.field_cards) ? me.field_cards : [])
    .map((card: any) => ({ ...card, controller: "self" }));
  const enemyField = (Array.isArray(opponent.field_cards) ? opponent.field_cards : [])
    .map((card: any) => ({ ...card, controller: "opponent" }));
  const hand = Array.isArray(state?.my_hand) ? state.my_hand : [];
  const removeArea = Array.isArray(state?.my_remove_cards) ? state.my_remove_cards : [];
  const ownEvidenceCount = Math.max(0, Number(me.evidence_count || 0));
  const opponentEvidenceCount = Math.max(0, Number(opponent.evidence_count || 0));

  for (const ability of activations) {
    const sourceId = String(ability?.source_instance_id || "");
    const definition = ability?.definition;
    if (!definition || !Array.isArray(definition.steps)) continue;
    // Case abilities use a synthetic source. The server RPC has already checked the
    // solution phase, partner colour, evidence count and per-turn use limit.
    if (sourceId.startsWith("case:")) {
      return { action: "activate_case_effect", payload: { effect_id: String(ability?.effect_id || "") } };
    }
    const source = ownField.find((card: any) => String(card?.instance_id || "") === sourceId)
      || (String(me.partner_mr_card?.instance_id || "") === sourceId ? me.partner_mr_card : null)
      || (Array.isArray(me.partner_non_mr_cards) ? me.partner_non_mr_cards : [])
        .find((card: any) => String(card?.instance_id || "") === sourceId)
      || null;
    if (!source || !isActive(source)) continue;

    // Preflight follow-up contacts before opening an effect chooser. The SQL
    // effect runner rejects a newly summoned source when start_contact does
    // not explicitly allow it, which otherwise leaves a stale selection modal.
    const hasBlockedNewlyPlayedContact = Boolean(source.summoned_this_turn)
      && definition.steps.some((step: any) =>
        step?.op === "start_contact" && step?.allowNewlyPlayed !== true);
    if (hasBlockedNewlyPlayedContact) continue;

    const selections: Array<{ step: any; targets: any[] }> = [];
    const unresolvedVars = new Set<string>();
    let invalid = false;
    for (const step of definition.steps) {
      if (step?.op === "offer_reaction" && step.saveAs) {
        unresolvedVars.add(String(step.saveAs));
        continue;
      }
      if (step?.op !== "select_cards") continue;
      const whenText = JSON.stringify(step.when || {});
      if ([...unresolvedVars].some((name) => whenText.includes(`vars.${name}`))) {
        if (step.saveAs) unresolvedVars.add(String(step.saveAs));
        continue;
      }

      let candidates: any[] = [];
      const from = String(step.from || "");
      if (from === "opponent_field") candidates = enemyField;
      else if (from === "field" || from === "own_field" || from === "self_field") candidates = ownField;
      else if (from === "both_fields") candidates = [...ownField, ...enemyField];
      else if (from === "remove_area") candidates = removeArea;
      else if (from === "hand") candidates = hand;
      else if (from === "attached_cards") {
        candidates = ownField.flatMap((parent: any) => {
          const attached = parent?.stacked_cards || parent?.under_cards || parent?.attached_cards || [];
          return Array.isArray(attached) ? attached.map((entry: any) => entry?.card || entry) : [];
        });
      } else if (from === "evidence_area") {
        candidates = Array.from({ length: ownEvidenceCount }, (_, index) => ({
          instance_id: `evidence:${index}`, card_type: "evidence", type: "evidence", face_up: false,
        }));
      } else if (from === "opponent_evidence") {
        candidates = Array.from({ length: opponentEvidenceCount }, (_, index) => ({
          instance_id: `opponent-evidence:${index}`, card_type: "evidence", type: "evidence",
          face_up: false, owner_user_id: opponent.user_id,
        }));
      } else if (from === "opponent_hand") {
        const count = Math.max(0, Number(opponent.hand_count || opponent.hand_size || state?.opponent_hand_count || 0));
        candidates = Array.from({ length: count }, (_, index) => ({
          instance_id: `opponent-hand:${index}`, card_type: "unknown",
        }));
      } else if (from === "deck") {
        const deckCount = Math.max(0, Number(state?.my_deck_count ?? me?.deck_count ?? 0));
        if (deckCount > 0) {
          if (step.saveAs) unresolvedVars.add(String(step.saveAs));
          continue;
        }
        candidates = [];
      }
      else if (/^vars\./u.test(from)) {
        if (step.saveAs) unresolvedVars.add(String(step.saveAs));
        continue;
      } else {
        if (step.saveAs) unresolvedVars.add(String(step.saveAs));
        continue;
      }

      let validTargets = from === "evidence_area"
        ? candidates
        : candidates.filter((card: any) => matchesDslFilter(card, step.filter));
      const statStep = definition.steps.find((candidate: any) =>
        candidate?.op === "modify_stat"
        && String(candidate.target || "").replace(/^vars\./u, "") === String(step.saveAs || ""));
      if (statStep && (from === "field" || from === "both_fields")) {
        const preferred = validTargets.filter((card: any) => isActive(card)
          && String(card.instance_id || "") !== sourceId);
        validTargets = preferred;
      }
      selections.push({ step, targets: validTargets });
      const min = Math.max(0, Number(step.min || 0));
      if (validTargets.length < min) {
        invalid = true;
        break;
      }
      if (validTargets.length === 0 && min === 0) {
        const feedsDeployment = definition.steps.some((candidate: any) =>
          candidate?.op === "move_cards"
          && String(candidate?.from || "") === `vars.${String(step.saveAs || "")}`
          && String(candidate?.to || "") === "field");
        // Optional steps in a multi-part effect may have no legal target while
        // another step still has one (e.g. B06085's evidence and field choices).
        // The final cost guard below rejects only when every selection is empty.
        if (feedsDeployment) {
          invalid = true;
          break;
        }
      }
      if (step.saveAs) unresolvedVars.add(String(step.saveAs));
    }
    if (invalid) continue;

    // Avoid paying costs when no actual target exists; non-field zones (e.g. remove/evidence)
    // are valid meaningful targets too, including PR181's remove-area deployment.
    if (definition.steps.some((step: any) => step?.op === "pay_cost")
      && selections.length > 0 && !selections.some(({ targets }) => targets.length > 0)) continue;

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
    case "play_event":
      return `AI 탐정: 카드 효과를 사용할 수 있는 ${cardName(card)} 이벤트를 발동했습니다.`;
    case "declare_solution":
      return "AI 탐정: 파일 수와 파트너 조건이 충족되어 해결편으로 전환했습니다.";
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
    case "activate_case_effect":
      return "AI 탐정: 사건 카드의 선언 효과를 발동했습니다.";
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
    case "contact_use_cutin": {
      const cutin = hand.find((entry: any) => entry.instance_id === decision?.payload?.instance_id);
      const subjectId = state?.pending_action?.attacker_user_id === aiId
        ? state?.pending_action?.attacker_instance_id
        : state?.pending_action?.target_instance_id;
      const subject = field.find((entry: any) => String(entry.instance_id || "") === String(subjectId || ""));
      const bonus = cardCutInBonusForSubject(
        cutin, subject, state?.current_turn_user_id === aiId,
        normalizedColor(state?.ai_partner_color || me?.partner_color || ""), field,
      );
      return `AI 탐정: 컷인을 사용해 AP를 ${bonus} 올렸습니다.`;
    }
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
    const contactSubjectId = pending.attacker_user_id === aiId
      ? String(pending.attacker_instance_id || "")
      : String(pending.target_instance_id || "");
    const contactSubject = field.find((card: any) => String(card.instance_id || "") === contactSubjectId);
    const isAiOwnerTurn = state.current_turn_user_id === aiId;
    const partnerColor = normalizedColor(state.ai_partner_color || me?.partner_color || "");
    const cutinBonus = (card: any) => cardCutInBonusForSubject(
      card, contactSubject, isAiOwnerTurn, partnerColor, field,
    );
    const cutin = hand.filter((card: any) => {
      const bonus = cutinBonus(card);
      return bonus >= needed && bonus > 0;
    }).sort((a: any, b: any) => cutinBonus(a) - cutinBonus(b))[0];
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
  const partnerColor = normalizedColor(state.ai_partner_color || me.partner_color || "");
  const activeAttackers = field.filter((card: any) => isCharacter(card) && isActive(card)
    && (!card.summoned_this_turn || hasCharge(card)))
    .sort((a: any, b: any) => cardAp(b) - cardAp(a));
  const characterAttackers = activeAttackers.filter((card: any) => !hasCaseOnlyCharge(card));
  const evidenceAttackers = activeAttackers.filter((card: any) => !hasCharacterOnlyCharge(card));
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

  // [신속] alone grants an immediate investigation after entering the field.
  // [돌격] variants are handled only by the character/evidence attack branches below.
  const newlyPlayedSwift = field.find((card: any) =>
    isCharacter(card) && isActive(card) && card.summoned_this_turn && hasSwift(card));
  if (newlyPlayedSwift) {
    return {
      action: "investigate",
      payload: {
        instance_id: newlyPlayedSwift.instance_id,
        evidence_count: Math.max(0, Math.min(3, Number(newlyPlayedSwift.lp || 1))),
        allow_newly_played: true,
      },
    };
  }

  const solutionFileThreshold = state.first_player_user_id === aiId ? 7 : 6;
  const canTransitionSolution = !isSolution
    && Number(me.file_count || 0) >= solutionFileThreshold
    && !me.partner_rested && !me.partner_assist_used
    && !me.next_hint_used && !me.next_hint_pending;
  if (canTransitionSolution) return { action: "declare_solution" };

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
    const eventCandidates = Array.isArray(state?.ai_event_effect_candidates)
      ? state.ai_event_effect_candidates : [];
    const eventScoreByInstance = new Map<string, number>();
    for (const candidate of eventCandidates) {
      const instanceId = String(candidate?.source_instance_id || "");
      if (!instanceId) continue;
      const score = estimateEventEffectScore(candidate?.definition);
      eventScoreByInstance.set(instanceId, Math.max(eventScoreByInstance.get(instanceId) || 0, score));
    }
    const effectEvent = hand.filter((card: any) => isEvent(card)
      && cardCost(card) <= level
      && eventScoreByInstance.has(String(card?.instance_id || "")))
      .map((card: any) => ({
        card,
        score: eventScoreByInstance.get(String(card.instance_id)) || 0,
      }))
      .sort((a: any, b: any) => b.score - a.score || cardCost(a.card) - cardCost(b.card))[0];
    const bestCharacter = playableCharacters[0];
    const characterPriority = bestCharacter ? cardStrength(bestCharacter) / 250 : -1;
    const requiredEventPriority = bestCharacter ? Math.max(5, characterPriority) : 1.5;
    if (effectEvent && effectEvent.score >= requiredEventPriority) {
      return { action: "play_event", payload: { instance_id: effectEvent.card.instance_id } };
    }
    if (bestCharacter) {
      return { action: "play_character", payload: { instance_id: bestCharacter.instance_id } };
    }
    // Use color-search events when no character in hand is currently playable.
    const searchEvent = hand.filter((card: any) => isEvent(card) && isBasicSearchEvent(card)
      && cardCost(card) <= level)
      .sort((a: any, b: any) => cardCost(a) - cardCost(b))[0];
    if (searchEvent && characterCount < 5) {
      return { action: "play_event", payload: { instance_id: searchEvent.instance_id } };
    }

    // In the Detective-vs-Kid case with a white partner, B11049P2 is a useful
    // hand-cycling fallback even when no character can currently be deployed.
    const eventKey = String(me.event_key || me.eventKey || me.event_rule_code || me.eventRuleCode || "").toLocaleUpperCase();
    const partnerColor = normalizedColor(me.partner_color || me.partnerColor
      || me.partner?.color || me.partner_card?.color || me.partnerCard?.color
      || me.partner_mr_card?.color || me.partnerMRCard?.color
      || me.partner_non_mr_cards?.[0]?.color || me.partnerNonMrCards?.[0]?.color
      || me.partner_non_mr_cards?.[0]?.card?.color || me.partnerNonMrCards?.[0]?.card?.color);
    const isDetectiveVsKidCase = ["B11098", "B11098P", "1261", "CONAN_VS_KID_1261"].includes(eventKey);
    const cycleEvent = hand.filter((card: any) => isEvent(card) && isDetectiveVsKidCycleEvent(card)
      && cardCost(card) <= level).sort((a: any, b: any) => cardCost(a) - cardCost(b))[0];
    if (cycleEvent && characterCount < 5 && partnerColor === "white" && isDetectiveVsKidCase) {
      return { action: "play_event", payload: { instance_id: cycleEvent.instance_id } };
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

  // D11007 can select an active opposing character of level 7 or higher.
  // Its discard ability can bridge an AP deficit of less than 3000 during that contact.
  const specialTargetAttacker = activeAttackers.find((card: any) => matchesInternalCardId(card, "0938"));
  const activeHighLevelTarget = enemyField
    .filter((card: any) => isCharacter(card) && isActive(card) && cardCost(card) >= 7)
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (specialTargetAttacker && activeHighLevelTarget) {
    const attackerAp = cardAp(specialTargetAttacker);
    const targetAp = cardAp(activeHighLevelTarget);
    const canWinWithoutCost = attackerAp > targetAp;
    const canWinByD11007 = hand.length > 0 && attackerAp < targetAp && attackerAp + 3000 > targetAp;
    const canWinByCutin = hand.some((card: any) => {
      const bonus = cardCutInBonusForSubject(card, specialTargetAttacker, true, partnerColor, field);
      return bonus > 0 && attackerAp + bonus > targetAp;
    });
    if (canWinWithoutCost || canWinByD11007 || canWinByCutin) {
      return {
        action: "declare_contact",
        payload: {
          attacker_instance_id: specialTargetAttacker.instance_id,
          target_user_id: opponent.user_id,
          target_instance_id: activeHighLevelTarget.instance_id,
          allow_active_target: true,
          allow_newly_played: hasCharge(specialTargetAttacker),
        },
      };
    }
  }

  const restedTarget = enemyField.filter((card: any) => isCharacter(card) && !isActive(card))
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (characterAttackers.length && restedTarget) {
    // Do not throw a lower-AP attacker into a losing contact unless a hand cut-in can
    // raise it above the target's AP during that contact.
    const attacker = characterAttackers.find((candidate: any) => {
      const attackerAp = cardAp(candidate);
      const targetAp = cardAp(restedTarget);
      const canUseMatsudaContactEffect = matchesInternalCardId(candidate, "0938")
        && hand.length > 0 && attackerAp < targetAp && attackerAp + 3000 > targetAp;
      return attackerAp > targetAp || canUseMatsudaContactEffect || hand.some((card: any) => {
        const bonus = cardCutInBonusForSubject(card, candidate, true, partnerColor, field);
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
          allow_newly_played: hasCharge(attacker),
        },
      };
    }
  }
  if (evidenceAttackers.length && Number(opponent.evidence_count || 0) > 0) {
    return {
      action: "attack_evidence",
      payload: {
        attacker_instance_id: evidenceAttackers[0].instance_id,
        target_user_id: opponent.user_id,
        allow_newly_played: hasCharge(evidenceAttackers[0]),
      },
    };
  }

  const resolvingEvent = field.find((card: any) => isEvent(card) && card.resolving);
  if (resolvingEvent) return { action: "finish_event", payload: { instance_id: resolvingEvent.instance_id } };
  return { action: "end_turn" };
}


function getReadableErrorMessage(error: any): string {
  if (error instanceof Error && error.message) return error.message;
  if (error && typeof error === "object") {
    const message = typeof error.message === "string" ? error.message.trim() : "";
    const details = typeof error.details === "string" ? error.details.trim() : "";
    const hint = typeof error.hint === "string" ? error.hint.trim() : "";
    const combined = [message, details, hint].filter(Boolean).join("\\n");
    if (combined) return combined;
  }
  return "AI 대전을 처리하지 못했습니다. 서버 로그를 확인해 주세요.";
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
    {
      // Also read partner colour while a contact is pending so the AI can price
      // conditional cut-ins (PR278, B05095, B10078) before deciding to spend one.
      const { data: activationData, error: activationError } = await service.rpc("get_private_ai_card_effect_activations_v1", {
        p_room_id: roomId,
        p_ai_user_id: battle.ai_user_id,
      });
      if (activationError) throw activationError;
      state.ai_card_effect_activations = Array.isArray(activationData?.activations) ? activationData.activations : [];
      state.ai_event_effect_candidates = Array.isArray(activationData?.event_candidates) ? activationData.event_candidates : [];
      state.ai_partner_color = activationData?.partner_color || null;
    }
    const hasAnyTimingAbility = !pending && state.ai_card_effect_activations.some((ability: any) =>
      String(ability?.definition?.activationTiming || "") === "any");
    if (state.current_turn_user_id !== battle.ai_user_id
      && !aiMustRespond && !hasAnyTimingAbility) {
      return { is_ai: true, actions: [] };
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
          // Choose up to max rather than silently discarding only one card from
          // multi-card effects such as B11049P2's draw-two, remove-two sequence.
          const take = Math.min(max, ids.length);
          decision = { action: "card_effect_continue", payload: { selected_instance_ids: ids.slice(0, take) } };
        }
      } else if (pending.type === "card_effect_reveal_ack" || pending.type === "card_effect_reveal_sequence") {
        decision = { action: "card_effect_continue", payload: { decision: "acknowledge" } };
      } else if (pending.type === "card_effect_reaction") {
        const choices = Array.isArray(pending.choices) ? pending.choices : [];
        const reactionId = String(pending.reaction_id || pending.reactionId || "");
        let choice = choices.includes("pass") ? "pass" : choices[0];
        // This bond ability offers hand or attachment as the cost. Prefer hand only
        // when one is available; otherwise use an attached card if the effect offered it.
        if (reactionId === "b05052-cost-zone") {
          if (hand.length > 0 && choices.includes("hand")) choice = "hand";
          else if (choices.includes("attachment")) choice = "attachment";
        }
        if (choice) decision = { action: "card_effect_continue", payload: { choice } };
      }
    }
    if (!decision) {
      decision = state.current_turn_user_id === battle.ai_user_id || pending
        ? chooseTurnAction(state, battle.ai_user_id, battle.last_next_hint_turn_number)
        : chooseActivatedAbility(state, battle.ai_user_id);
    }
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

      const { error: deckError } = await userClient.rpc("submit_private_room_deck_with_metadata_v1", {
        p_room_id: room.out_room_id,
        p_main_deck: humanDeck,
        p_partner_key: String(body.partner_key),
        p_event_key: String(body.event_key),
        p_event_rule_code: String(body.event_rule_code || ""),
        p_partner_color: String(body.partner_color || ""),
        p_event_has_non_blue_color: Boolean(body.event_has_non_blue_color),
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
        p_ai_event_has_non_blue_color: Boolean(aiDeck.event_has_non_blue_color),
        p_ai_event_rule_code: String(aiDeck.event_rule_code || ""),
        p_ai_partner_color: String(aiDeck.partner_color || ""),
      });
      if (battleError) throw battleError;

      let initial;
      try {
        initial = await driveAiTurns(service, room.out_room_id, user.id);
      } catch (initialError) {
        // The room and both submitted decks are already committed at this point.
        // Do not return HTTP 500 and strand the user in the lobby: the realtime
        // MatchTurnBoard worker will retry an AI step after the match view mounts.
        console.error("ai-battle initial AI step error", initialError);
        initial = {
          is_ai: true,
          actions: [],
          message: "대전은 생성됐지만 AI의 첫 행동을 처리하지 못했습니다. 게임 화면에서 자동으로 다시 시도합니다.",
          initial_step_error: getReadableErrorMessage(initialError),
        };
      }
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
    return json({ error: getReadableErrorMessage(error) }, 500);
  }
});
