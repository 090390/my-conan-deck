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
  const value = Number(card?.cost ?? card?.level ?? card?.level_number ?? card?.sourceData?.cost);
  if (!Number.isFinite(value)) return 999;
  const bonus = Number(card?.level_bonus ?? card?.levelBonus ?? 0);
  return Math.max(0, value + (Number.isFinite(bonus) ? bonus : 0));
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
  removeArea: any[] = [],
  eventKey = "",
  ownHand: any[] = [],
): number {
  let bonus = cardCutInBonus(card);
  if (matchesInternalCardId(card, "1117")) {
    if (partnerColor !== "red") return 0;
    return Math.max(0, ownHand.length - 1) <= 2 ? 3000 : 1000;
  }

  // Card-specific legality modifiers. These are conditions for whether the cut-in
  // can be used at all, not just changes to its AP bonus.
  if (matchesInternalCardId(card, "1001") && !isOwnerTurn) return 0;
  if ((matchesInternalCardId(card, "0974") || matchesInternalCardId(card, "0729")) && !isOwnerTurn) return 0;
  // ID0540 is legal only with the green partner and a mono-green incident.
  // The current supported green case in this deck is 恋と推理の剣道大会 (0666).
  if (matchesInternalCardId(card, "0540")
    && (partnerColor !== "green" || !["B06043P", "B06043", "0666"].includes(String(eventKey || "").toUpperCase()))) return 0;
  if (matchesInternalCardId(card, "0570") && partnerColor !== "red") return 0;
  if (matchesInternalCardId(card, "1073")) {
    const allowedTarget = Boolean(subject && (
      matchesCardName(subject, "쿠도 신이치") || matchesCardName(subject, "모리 란")
    ));
    return allowedTarget ? bonus : 0;
  }
  if (matchesInternalCardId(card, "1183")) {
    if (!isOwnerTurn) return 0;
    return subject && matchesCardName(subject, "쿠도 신이치") ? Math.max(3000, bonus) : bonus;
  }

  // ID0627: count 犯人 cards already in the remove area plus this cut-in card,
  // which is moved from hand to the remove area as part of using the cut-in.
  if (matchesInternalCardId(card, "0627")) {
    if (!isOwnerTurn) return 0;
    const removedCulprits = removeArea.filter((entry: any) =>
      matchesCardName(entry, "犯人") || matchesCardName(entry, "범인")).length;
    return (removedCulprits + 1) * 2000;
  }

  // PR278 / internal 0940: partner-yellow adds 1000 AP; the server separately
  // draws when the supported character has Police.
  if (matchesInternalCardId(card, "0940") && partnerColor === "yellow") {
    bonus += 1000;
  }

  // B05095 / internal 0593: its entire bonus is 1000 AP per Police
  // character on the owner's field. Do not retain the generic parser's first
  // "+1000" token as a flat base bonus, and do not allow it outside the owner's turn.
  if (matchesInternalCardId(card, "0593")) {
    if (!isOwnerTurn) return 0;
    const policeCount = ownField.filter((entry: any) =>
      isCharacter(entry) && hasTrait(entry, "경찰")).length;
    return policeCount * 1000;
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
function hasBullet(card: any): boolean {
  return dslKeywordValues(card).some((value) =>
    ["bullet", "브렛", "ブレット"].includes(value));
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
function estimateEventEffectScore(definition: any, ownField: any[] = [], enemyField: any[] = []): number {
  return estimateEffectUtility(
    definition,
    ownField.map((card: any) => ({ ...card, controller: "self" })),
    enemyField.map((card: any) => ({ ...card, controller: "opponent" })),
  );
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
  "모리 란": ["모리 란", "毛利蘭", "毛利 蘭", "mouri ran", "ran mouri"],
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
      if (op === "has_keyword") {
        const keyword = String(expected ?? "").toLocaleLowerCase();
        if (values.includes(keyword)) return true;
        if (["カットイン", "컷인", "cut_in", "cut-in"].includes(keyword)) {
          const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData
            : card?.raw && typeof card.raw === "object" ? card.raw : {};
          const printed = [
            card?.cut_in, card?.cutIn, card?.cut_in_text, card?.cutInText,
            card?.cut_in_effect, card?.cutInEffect, source?.cut_in, source?.cutIn,
            card?.abilityJp, card?.abilityKo, card?.ability_jp, card?.ability_ko,
          ].filter((value) => typeof value === "string").join(" ");
          return /カットイン|컷인|cut[\\s_-]*in/iu.test(printed);
        }
        return false;
      }
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

function estimateEffectUtility(
  definition: any,
  ownField: any[] = [],
  enemyField: any[] = [],
  precomputedSelections: Array<{ step: any; targets: any[] }> = [],
  source: any = null,
  opponentEvidenceCount = 0,
  ownEvidenceCount = 0,
): number {
  const steps = Array.isArray(definition?.steps) ? definition.steps : [];
  if (!steps.length) return 0;

  const own = ownField.map((card: any) => ({ ...card, controller: card?.controller || "self" }));
  const enemy = enemyField.map((card: any) => ({ ...card, controller: card?.controller || "opponent" }));
  const selections = precomputedSelections.length ? precomputedSelections : steps
    .filter((step: any) => step?.op === "select_cards")
    .map((step: any) => {
      const from = String(step?.from || "");
      let candidates: any[] = [];
      if (from === "opponent_field") candidates = enemy;
      else if (["field", "own_field", "self_field"].includes(from)) candidates = own;
      else if (from === "both_fields") candidates = [...own, ...enemy];
      else if (from === "opponent_evidence") {
        candidates = Array.from({ length: Math.max(0, opponentEvidenceCount) }, (_, index) => ({
          instance_id: `opponent-evidence:${index}`, card_type: "evidence", controller: "opponent",
        }));
      } else if (from === "evidence_area") {
        candidates = Array.from({ length: Math.max(0, ownEvidenceCount) }, (_, index) => ({
          instance_id: `own-evidence:${index}`, card_type: "evidence", controller: "self",
        }));
      }
      const valid = candidates.filter((card: any) => matchesDslFilter(card, step.filter));
      const max = step?.max === "all"
        ? valid.length
        : Math.max(0, Number(step?.max ?? Math.max(1, Number(step?.min ?? 1))));
      return { step, targets: valid.slice(0, max) };
    });

  const selectionByVariable = new Map<string, { step: any; targets: any[] }>();
  for (const selection of selections) {
    const variable = String(selection?.step?.saveAs || "");
    if (variable) selectionByVariable.set(variable, selection);
  }

  const variablesIn = (step: any): string[] => {
    const serialized = JSON.stringify(step || {});
    return [...serialized.matchAll(/vars\.([A-Za-z0-9_]+)/gu)]
      .map((match: any) => String(match[1]))
      .filter((value: string, index: number, all: string[]) => all.indexOf(value) === index);
  };
  const targetsFor = (step: any): any[] => {
    const variables = variablesIn(step);
    const linked = variables.flatMap((variable) => {
      const selection = selectionByVariable.get(variable);
      if (!selection) return [];
      const max = selection.step?.max === "all"
        ? selection.targets.length
        : Math.max(0, Number(selection.step?.max ?? Math.max(1, Number(selection.step?.min ?? 1))));
      return selection.targets.slice(0, max);
    });
    if (linked.length) {
      return linked.filter((card: any, index: number, all: any[]) =>
        all.findIndex((entry: any) => String(entry?.instance_id || entry) === String(card?.instance_id || card)) === index);
    }
    const from = String(step?.from || step?.target || "").replace(/^vars\./u, "");
    if (from === "opponent_field") return enemy.filter((card: any) => matchesDslFilter(card, step?.filter));
    if (["field", "own_field", "self_field"].includes(from)) return own.filter((card: any) => matchesDslFilter(card, step?.filter));
    if (from === "both_fields") return [...own, ...enemy].filter((card: any) => matchesDslFilter(card, step?.filter));
    if (from === "opponent_evidence") {
      return Array.from({ length: Math.max(0, opponentEvidenceCount) }, (_, index) => ({
        instance_id: `opponent-evidence:${index}`, card_type: "evidence", controller: "opponent",
      }));
    }
    return [];
  };
  const isOpponentTarget = (card: any) => {
    const controller = String(card?.controller || "").toLowerCase();
    if (controller === "opponent") return true;
    if (controller === "self") return false;
    return Boolean(source?.owner_user_id && card?.owner_user_id != null
      && String(card.owner_user_id) !== String(source.owner_user_id));
  };
  const targetValue = (card: any): number => {
    if (!isCharacter(card)) return 24;
    return 22 + Math.max(0, cardAp(card)) / 700
      + Math.max(0, cardCost(card)) * 2
      + cardLifePoints(card) * 10
      + (isActive(card) ? 10 : 0);
  };

  let score = 0;
  for (const step of steps) {
    const op = String(step?.op || "");
    if (op === "remove_all_field_characters") {
      const enemyCharacters = enemy.filter((card: any) => isCharacter(card) && cardLifePoints(card) > 0);
      const ownCharacters = own.filter((card: any) => isCharacter(card) && cardLifePoints(card) > 0);
      score += enemyCharacters.reduce((sum: number, card: any) => sum + 48 + targetValue(card) * 0.55, 0)
        - ownCharacters.length * 42;
      continue;
    }
    if (op === "move_cards") {
      const targets = targetsFor(step);
      const destination = String(step?.to || "");
      const enemyTargets = targets.filter(isOpponentTarget);
      const ownTargets = targets.filter((card: any) => !isOpponentTarget(card));
      if (["remove_area", "deck_bottom", "hand"].includes(destination)) {
        const base = destination === "remove_area" ? 88 : destination === "deck_bottom" ? 76 : 56;
        for (const target of enemyTargets) score += base + targetValue(target) * 0.72;
        for (const target of ownTargets) score -= 28 + targetValue(target) * 0.42;
        if (!targets.length && String(step?.from || "").startsWith("vars.")) score += 3;
      } else if (destination === "field") {
        score += Math.max(1, targets.length) * 34;
      } else if (destination === "evidence_area") {
        score += Math.max(1, targets.length) * 20;
      } else if (destination === "hand") {
        score += Math.max(1, targets.length) * 5;
      }
      continue;
    }
    if (op === "rest_cards" || op === "stun_cards") {
      const targets = targetsFor(step).filter((card: any) => isOpponentTarget(card));
      const base = op === "stun_cards" ? 68 : 48;
      score += targets.reduce((sum: number, card: any) => sum + base + targetValue(card) * 0.48, 0);
      continue;
    }
    if (op === "draw_cards") {
      score += 12 * Math.max(1, Number(step?.count || 1));
      continue;
    }
    if (op === "peek_top_cards") {
      score += 6 + Math.min(4, Math.max(0, Number(step?.count || 0))) * 2;
      continue;
    }
    if (op === "move_top_file_cards") {
      score += step?.to === "hand" ? 12 : 6;
      continue;
    }
    if (op === "flip_evidence") {
      score += 8 * Math.max(1, Number(step?.count || 1));
      continue;
    }
    if (op === "modify_stat" || op === "modify_contact_ap") {
      const amount = Number(step?.amount ?? step?.value ?? step?.by ?? 0);
      const targets = targetsFor(step);
      if (amount !== 0) score += targets.length ? targets.length * 16 : 8;
      continue;
    }
    if (op === "grant_keyword" || op === "set_continuous_keyword") {
      const targets = targetsFor(step);
      const keyword = String(step?.keyword || "").toLowerCase();
      const bonus = /charge|돌격|突撃|swift|신속|질풍|疾風/u.test(keyword) ? 30 : 14;
      score += Math.max(1, targets.length) * bonus;
      continue;
    }
    if (op === "start_contact") {
      score += Math.max(1, targetsFor(step).filter(isOpponentTarget).length) * 34;
      continue;
    }
    if (op === "ready_source_character") {
      if (source && !isActive(source)) score += 28;
      continue;
    }
    if (op === "attach_top_card") {
      score += 15;
      continue;
    }
    if (op === "calculate_switch_count") {
      score += 3;
      continue;
    }
    if (op === "set_next_hint_disabled") {
      score += 2;
      continue;
    }
    if (op === "schedule_move_to_deck_bottom") {
      score += 8;
    }
  }

  // Strategic objective: finish the AI turn with at most three opposing field
  // cards, and prefer zero or one whenever an available effect can achieve it.
  // Count only cards that will actually leave the opponent's field; resting or
  // stunning a character is useful control, but does not reduce the field count.
  const plannedOpponentRemovals = new Map<string, any>();
  for (const step of steps) {
    const op = String(step?.op || "");
    if (op === "remove_all_field_characters") {
      for (const target of enemy.filter((card: any) => isCharacter(card) && cardLifePoints(card) > 0)) {
        const id = String(target?.instance_id || "");
        if (id) plannedOpponentRemovals.set(id, target);
      }
      continue;
    }
    if (op !== "move_cards" || !["remove_area", "deck_bottom", "hand"].includes(String(step?.to || ""))) {
      continue;
    }
    for (const target of targetsFor(step)) {
      if (!isOpponentTarget(target)) continue;
      const id = String(target?.instance_id || "");
      if (!id || !enemy.some((card: any) => String(card?.instance_id || "") === id)) continue;
      plannedOpponentRemovals.set(id, target);
    }
  }
  const opponentFieldCount = enemy.length;
  const plannedRemovalCount = Math.min(opponentFieldCount, plannedOpponentRemovals.size);
  if (plannedRemovalCount > 0) {
    const remainingOpponentField = Math.max(0, opponentFieldCount - plannedRemovalCount);
    const perCardRemovalBonus = 125 + Math.min(6, opponentFieldCount) * 10;
    const targetCountBonus = remainingOpponentField <= 1 ? 150
      : remainingOpponentField <= 3 ? 90 : 0;
    score += plannedRemovalCount * perCardRemovalBonus + targetCountBonus;
  }

  for (const step of steps.filter((entry: any) => entry?.op === "pay_cost")) {
    const cost = String(step?.cost || "").toLowerCase();
    if (cost === "sleep_source_character" && source) {
      score -= 26 + Math.max(0, cardAp(source)) / 800;
    } else if (cost.includes("discard")) {
      score -= 9;
    } else if (cost.includes("rest_partner")) {
      score -= 22;
    }
  }

  return Math.max(0, score);
}

function cardLifePoints(card: any): number {
  const value = Number(card?.lp ?? card?.life_points ?? card?.lifePoints ?? 0);
  return Number.isFinite(value) ? Math.max(0, Math.min(3, value)) : 0;
}

function isStunnedCard(card: any): boolean {
  const status = String(card?.status || "").toLocaleLowerCase();
  return Boolean(card?.stunned || card?.stun || card?.is_stunned)
    || ["stunned", "stun", "스턴"].includes(status);
}

function getOpponentNextTurnThreat(state: any, aiId: string) {
  const boards = Array.isArray(state?.boards) ? state.boards : [];
  const opponent = boards.find((board: any) => String(board?.user_id || "") !== String(aiId));
  if (!opponent) {
    return { urgent: false, canEnterSolution: false, evidenceCount: 0, threshold: 0,
      fieldCapacity: 0, partnerCapacity: 0, remainingEvidence: 0, opponentEvidenceCount: 0 };
  }

  const eventKey = String(opponent.event_key || opponent.eventKey || opponent.event_rule_code
    || opponent.eventRuleCode || "").toLocaleUpperCase().replace(/[^A-Z0-9]/gu, "");
  const eventRule = String(opponent.event_rule_code || opponent.eventRuleCode || "");
  const isConanVsKidCase = eventKey.includes("B11098") || eventKey.includes("1261")
    || eventRule === "conan_vs_kid_1261";
  const isCulpritsCrimeCase = eventKey.includes("B09107") || eventKey.includes("1046")
    || eventRule === "culprits_1046";
  const isFirstPlayer = String(state?.first_player_user_id || "") === String(opponent.user_id || "");
  const threshold = isConanVsKidCase ? (isFirstPlayer ? 8 : 7) : (isFirstPlayer ? 7 : 6);
  const evidenceCount = Math.max(0, Number(opponent.evidence_count || 0));
  const remainingEvidence = Math.max(0, threshold - evidenceCount);
  const phase = String(opponent.case_phase || "incident").toLocaleLowerCase();
  const alreadyInSolution = phase === "solution";
  const fileThreshold = isFirstPlayer ? 7 : 6;
  // A player places one file at the beginning of their next turn. Count that
  // file when checking whether they can enter the solution phase immediately.
  const canEnterSolution = alreadyInSolution
    || Number(opponent.file_count || 0) + 1 >= fileThreshold;
  const enemyCharacters = (Array.isArray(opponent.field_cards) ? opponent.field_cards : [])
    .filter((card: any) => isCharacter(card));
  // Rested characters stand up at their owner's next turn; stun is the status
  // that persists. Therefore, exclude stunned characters but count rested ones.
  const fieldCapacity = enemyCharacters
    .filter((card: any) => !isStunnedCard(card))
    .reduce((sum: number, card: any) => sum + cardLifePoints(card), 0);
  const hasPartner = Boolean(opponent.partner_key || opponent.partner_card
    || opponent.partner_mr_card || opponent.partnerMRCard
    || (Array.isArray(opponent.partner_non_mr_cards) && opponent.partner_non_mr_cards.length > 0)
    || (Array.isArray(opponent.partnerNonMrCards) && opponent.partnerNonMrCards.length > 0));
  // Partner deduction is available again at the opponent's next turn.
  const partnerCapacity = hasPartner ? 1 : 0;
  const opponentEvidenceCount = evidenceCount;
  const nextTurnEvidencePotential = evidenceCount + fieldCapacity + partnerCapacity;
  const publicEvidence = Array.isArray(opponent.evidence_public_cards) ? opponent.evidence_public_cards : [];
  const visibleCulpritEvidenceCount = publicEvidence.filter((card: any) =>
    hasTrait(card, "범인") || hasTrait(card, "犯人") || hasTrait(card, "culprit")).length;
  // The opponent's facedown evidence is hidden. Count it as a possible culprit
  // card rather than assuming it is harmless; also include evidence they could
  // add with surviving characters and partner deduction on their next turn.
  const hiddenEvidenceUpperBound = Math.max(0, evidenceCount - publicEvidence.length);
  const culpritEvidencePotential = visibleCulpritEvidenceCount
    + hiddenEvidenceUpperBound + fieldCapacity + partnerCapacity;
  const opponentDeckCount = Math.max(0, Number(opponent.deck_count ?? 0));
  const opponentRemoveCount = Math.max(0, Number(opponent.remove_count ?? 0));
  // A zero-deck player with cards in the remove area may manually refresh
  // before using the special case effect, so keep that line in the threat model.
  const canRefreshCulpritDeck = opponentDeckCount > 0 || opponentRemoveCount > 0;
  const canWinNextTurn = canEnterSolution && (isCulpritsCrimeCase
    ? canRefreshCulpritDeck && culpritEvidencePotential >= 8
    : nextTurnEvidencePotential >= threshold);
  // Treat a one-evidence-short position as urgent too. This catches boards
  // where a small additional effect or partner action can turn a near-win into
  // a win, instead of letting the AI pass because its estimate is exactly one short.
  const isNearWinNextTurn = canEnterSolution && (isCulpritsCrimeCase
    ? canRefreshCulpritDeck && culpritEvidencePotential >= 7
    : nextTurnEvidencePotential >= Math.max(0, threshold - 1));

  return {
    urgent: isNearWinNextTurn,
    canWinNextTurn,
    isNearWinNextTurn,
    nextTurnEvidencePotential,
    culpritEvidencePotential,
    visibleCulpritEvidenceCount,
    hiddenEvidenceUpperBound,
    opponentDeckCount,
    opponentRemoveCount,
    canRefreshCulpritDeck,
    canEnterSolution,
    evidenceCount,
    threshold: isCulpritsCrimeCase ? 8 : threshold,
    fieldCapacity,
    partnerCapacity,
    remainingEvidence,
    opponentEvidenceCount,
    enemyCharacterCount: enemyCharacters.filter((card: any) => !isStunnedCard(card)
      && cardLifePoints(card) > 0).length,
    opponentUserId: String(opponent.user_id || ""),
  };
}

function effectStepReferencesVariable(step: any, variable: string): boolean {
  const name = String(variable || "").replace(/^vars\./u, "");
  if (!name) return false;
  const from = String(step?.from || "").replace(/^vars\./u, "");
  const target = String(step?.target || "").replace(/^vars\./u, "");
  if (from === name || target === name || String(step?.selectedVariable || "").replace(/^vars\./u, "") === name) {
    return true;
  }
  return JSON.stringify(step || {}).includes("vars." + name);
}

function getThreatMitigationKind(definition: any, selectionStep: any): string | null {
  const steps = Array.isArray(definition?.steps) ? definition.steps : [];
  const source = String(selectionStep?.from || "");
  const variable = String(selectionStep?.saveAs || "");
  if (!variable || !["opponent_field", "both_fields", "opponent_evidence"].includes(source)) return null;
  const linked = steps.filter((step: any) => step !== selectionStep
    && effectStepReferencesVariable(step, variable));
  if (source === "opponent_evidence" && linked.some((step: any) =>
    step?.op === "move_cards" && ["deck_bottom", "remove_area"].includes(String(step?.to || "")))) {
    return "evidence_remove";
  }
  if (linked.some((step: any) => step?.op === "stun_cards")) return "stun";
  if (linked.some((step: any) => step?.op === "move_cards"
    && ["remove_area", "deck_bottom", "hand"].includes(String(step?.to || "")))) return "remove";
  if (linked.some((step: any) => step?.op === "rest_cards")) return "rest";
  return null;
}

function scoreThreatMitigation(definition: any, ownField: any[], enemyField: any[], threat: any): number {
  if (!threat?.urgent || !Array.isArray(definition?.steps)) return 0;
  const steps = definition.steps;
  let bestScore = 0;

  for (const selectionStep of steps.filter((step: any) => step?.op === "select_cards")) {
    const kind = getThreatMitigationKind(definition, selectionStep);
    if (!kind) continue;
    const source = String(selectionStep.from || "");
    if (source === "opponent_evidence") {
      bestScore = Math.max(bestScore, 130 + Math.min(3, Number(threat.opponentEvidenceCount || 0)) * 8);
      continue;
    }

    const candidates = enemyField.filter((card: any) =>
      isCharacter(card) && matchesDslFilter({ ...card, controller: "opponent" }, selectionStep.filter));
    if (!candidates.length) continue;
    const highestLp = Math.max(...candidates.map(cardLifePoints));
    const countBonus = Math.min(3, candidates.length) * 3;

    if (kind === "remove") {
      const variable = String(selectionStep.saveAs || "");
      const move = steps.find((step: any) => step?.op === "move_cards"
        && effectStepReferencesVariable(step, variable)
        && ["remove_area", "deck_bottom", "hand"].includes(String(step?.to || "")));
      const destination = String(move?.to || "");
      const base = destination === "remove_area" ? 105 : destination === "deck_bottom" ? 98 : 72;
      bestScore = Math.max(bestScore, base + highestLp * 7 + countBonus);
    } else if (kind === "stun") {
      bestScore = Math.max(bestScore, 92 + highestLp * 6 + countBonus);
    }
  }

  if (steps.some((step: any) => step?.op === "remove_all_field_characters")) {
    const enemyCount = enemyField.filter((card: any) => isCharacter(card)
      && !isStunnedCard(card) && cardLifePoints(card) > 0).length;
    const ownCount = ownField.filter((card: any) => isCharacter(card)).length;
    if (enemyCount > 0) {
      // A field wipe is a costly last resort, but stopping a lethal next turn
      // is worth sacrificing some of the AI's own board.
      bestScore = Math.max(bestScore, 76 + enemyCount * 10 - ownCount * 3);
    }
  }
  return bestScore;
}

function findPendingThreatSelectionStep(definition: any, pending: any): any | null {
  const steps = Array.isArray(definition?.steps) ? definition.steps : [];
  const selections = steps.filter((step: any) => step?.op === "select_cards");
  const variableHint = String(pending?.save_as || pending?.saveAs || pending?.selection_variable
    || pending?.selectionVariable || pending?.variable || pending?.target_key || "");
  if (variableHint) {
    const byVariable = selections.find((step: any) => String(step?.saveAs || "") === variableHint);
    if (byVariable) return byVariable;
  }
  const prompt = String(pending?.prompt || "").trim().replace(/\s+/gu, "");
  if (prompt) {
    const byPrompt = selections.find((step: any) =>
      String(step?.prompt || "").trim().replace(/\s+/gu, "") === prompt);
    if (byPrompt) return byPrompt;
  }
  const mitigation = selections.filter((step: any) => getThreatMitigationKind(definition, step));
  return mitigation.length === 1 ? mitigation[0] : null;
}

function chooseActivatedAbility(state: any, aiId: string, threatOnly = false) {
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
  // get_private_turn_state_v2 returns the AI's own evidence cards in full while
  // masking the opponent's facedown evidence. Use these real cards so a face-up
  // evidence card is never mistaken for a legal facedown selection candidate.
  const ownEvidenceCards = Array.isArray(me.evidence_private_cards) ? me.evidence_private_cards : [];
  const ownEvidenceCount = Math.max(0, Number(me.evidence_count ?? ownEvidenceCards.length));
  const opponentEvidenceCount = Math.max(0, Number(opponent.evidence_count || 0));
  const opponentHandCount = Math.max(0, Number(opponent.hand_count || opponent.hand_size || state?.opponent_hand_count || 0));
  const opponentThreat = getOpponentNextTurnThreat(state, aiId);
  if (threatOnly && !opponentThreat.urgent) return null;
  let bestDecision: any = null;
  let bestActionScore = Number.NEGATIVE_INFINITY;

  for (const ability of activations) {
    const sourceId = String(ability?.source_instance_id || "");
    const definition = ability?.definition;
    if (!definition || !Array.isArray(definition.steps)) continue;
    // Case abilities use synthetic sources, so preflight every mandatory,
    // statically-resolvable selection before asking the server to start the effect.
    // In particular, a total evidence count is not enough: ID:0806 and ID:1139
    // require actual facedown evidence cards.
    if (sourceId.startsWith("case:")) {
      const missingRequiredSelection = definition.steps.some((step: any) => {
        if (step?.op !== "select_cards") return false;
        const min = Math.max(0, Number(step.min ?? (step.optional ? 0 : 1)));
        if (min <= 0) return false;

        const whenText = JSON.stringify(step.when || {});
        // A selector gated by an earlier selection is evaluated by the effect
        // runner after that selection, not by this preflight.
        if (whenText.includes("vars.")) return false;
        // The only case-effect hand-count guard currently used by the catalog.
        if (whenText.includes("opponent.hand.count")
          && opponentHandCount === 0
          && /greater_than|greater_than_or_equal/u.test(whenText)) return false;

        const from = String(step.from || "");
        let candidates: any[] | null = null;
        if (from === "evidence_area") candidates = ownEvidenceCards;
        else if (from === "field" || from === "own_field" || from === "self_field") candidates = ownField;
        else if (from === "opponent_field") candidates = enemyField;
        else if (from === "both_fields") candidates = [...ownField, ...enemyField];
        else if (from === "hand") candidates = hand;
        else if (from === "remove_area") candidates = removeArea;
        else if (from === "opponent_hand") {
          candidates = Array.from({ length: opponentHandCount }, () => ({ card_type: "unknown" }));
        } else if (from === "opponent_evidence") {
          candidates = Array.from({ length: opponentEvidenceCount }, () => ({
            card_type: "evidence", type: "evidence", face_up: false,
          }));
        }
        // Dynamic or deck-backed selectors are resolved by the effect runner.
        if (candidates === null) return false;
        const valid = candidates.filter((card: any) => matchesDslFilter(card, step.filter));
        return valid.length < min;
      });
      if (missingRequiredSelection) continue;
      const candidate = { action: "activate_case_effect", payload: { effect_id: String(ability?.effect_id || "") } };
      const threatScore = scoreThreatMitigation(definition, ownField, enemyField, opponentThreat);
      if (threatOnly && threatScore <= 0) continue;
      const utilityScore = estimateEffectUtility(
        definition, ownField, enemyField, [], null, opponentEvidenceCount, ownEvidenceCount,
      );
      const actionScore = utilityScore + threatScore * 2;
      if (actionScore > bestActionScore) {
        bestDecision = candidate;
        bestActionScore = actionScore;
      }
      continue;
    }
    const source = ownField.find((card: any) => String(card?.instance_id || "") === sourceId)
      || (String(me.partner_mr_card?.instance_id || "") === sourceId ? me.partner_mr_card : null)
      || (Array.isArray(me.partner_non_mr_cards) ? me.partner_non_mr_cards : [])
        .find((card: any) => String(card?.instance_id || "") === sourceId)
      || null;
    if (!source) continue;

    // ID:1004 grants Charge until the end of the current turn. Its printed
    // text does not impose a once-per-turn limit, but activating it again
    // while the same source already has this temporary Charge only wastes
    // another hand card. Suppress that redundant AI choice without changing
    // the card's general activation legality for human players.
    const abilityEffectId = String(ability?.effect_id || "");
    if (abilityEffectId === "card-1004-activated-discard-hand-grant-charge") {
      const alreadyHasChargeFromThisAbility = (Array.isArray(source.dsl_keywords) ? source.dsl_keywords : [])
        .some((entry: any) => String(entry?.keyword || "").toLowerCase() === "charge"
          && String(entry?.effect_id || "") === abilityEffectId
          && Number(entry?.expires_turn_number || 0) >= Number(state?.turn_number || 0));
      if (alreadyHasChargeFromThisAbility) continue;
    }

    const sourceStatus = String(source.status || "active").toLowerCase();
    const sourceIsRested = Boolean(source.rested)
      || ["rested", "sleep", "slumber", "sleeping", "슬립"].includes(sourceStatus);
    const sourceIsStunned = Boolean(source.stunned || source.stun || source.is_stunned)
      || ["stunned", "stun", "스턴"].includes(sourceStatus);
    const abilityHasSleepCost = definition.steps.some((step: any) =>
      step?.op === "pay_cost" && step?.cost === "sleep_source_character");
    const canUseWhileRested = sourceIsRested && !sourceIsStunned
      && !abilityHasSleepCost && definition.allowRestedSource === true
      && definition.requiresActiveSource !== true;
    const canUseWhileStunned = sourceIsStunned && definition.allowStunnedSource === true
      && definition.requiresActiveSource !== true;
    const canReadyRestedSource = sourceIsRested && !sourceIsStunned
      && definition.requiresActiveSource !== true
      && definition.steps.some((step: any) => step?.op === "ready_source_character");
    if (!isActive(source) && !canUseWhileRested && !canUseWhileStunned && !canReadyRestedSource) continue;

    // Preflight follow-up contacts before opening an effect chooser. The SQL
    // effect runner rejects a newly summoned source when start_contact does
    // not explicitly allow it, which otherwise leaves a stale selection modal.
    const hasBlockedNewlyPlayedContact = Boolean(source.summoned_this_turn)
      && definition.steps.some((step: any) =>
        step?.op === "start_contact" && step?.allowNewlyPlayed !== true);
    if (hasBlockedNewlyPlayedContact) continue;

    const restTargetVariables = new Set(
      definition.steps
        .filter((step: any) => step?.op === "rest_cards")
        .map((step: any) => String(step?.target || "").replace(/^vars\./u, ""))
        .filter(Boolean),
    );
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
      const effectId = String(ability?.effect_id || "");
      if (effectId === "card-1039-declare-remove-character-ap-8000") {
        // ID:1039 is strategically used only when it can remove an opponent's
        // character. Do not sleep the AI source merely to remove its own card.
        candidates = enemyField;
      } else if (effectId === "card-1040-declare-remove-character-level-7") {
        // ID:1040 is used only when it can remove a legal character from the
        // opponent's field; never sleep the source to target the AI's own field.
        candidates = enemyField;
      } else if (from === "opponent_field") candidates = enemyField;
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
        candidates = ownEvidenceCards;
      } else if (from === "opponent_evidence") {
        candidates = Array.from({ length: opponentEvidenceCount }, (_, index) => ({
          instance_id: `opponent-evidence:${index}`, card_type: "evidence", type: "evidence",
          face_up: false, owner_user_id: opponent.user_id,
        }));
      } else if (from === "opponent_hand") {
        const count = opponentHandCount;
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

      let validTargets = candidates.filter((card: any) => matchesDslFilter(card, step.filter));
      // A card that is already rested cannot be meaningfully rested again.
      // Apply this guard based on the actual rest_cards target variable so all
      // current and future catalog effects get the same legality check.
      if (step.saveAs && restTargetVariables.has(String(step.saveAs))) {
        validTargets = validTargets.filter((card: any) => isActive(card));
      }
      if ((String(ability?.effect_id || "") === "card-1039-declare-remove-character-ap-8000"
        || String(ability?.effect_id || "") === "card-1040-declare-remove-character-level-7")
        && validTargets.length === 0) {
        invalid = true;
        break;
      }
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

    // Skip a rest-only ability entirely when every legal target is already
    // rested/stunned. This prevents the AI from reopening a zero-value effect
    // after it has already exhausted the active characters it could rest.
    const hasAvailableRestTarget = selections.some(({ step, targets }) =>
      Boolean(step.saveAs)
      && restTargetVariables.has(String(step.saveAs))
      && targets.length > 0
    );
    const hasIndependentNonRestEffect = definition.steps.some((step: any) =>
      !["pay_cost", "select_cards", "offer_reaction", "rest_cards"].includes(String(step?.op || ""))
    );
    if (restTargetVariables.size > 0 && !hasAvailableRestTarget && !hasIndependentNonRestEffect) {
      continue;
    }

    // Do not pay an activation cost merely because a cost-selection target exists.
    // Check whether at least one selected variable actually feeds a useful effect
    // (remove/deploy/buff/contact/etc.), or whether the definition has a separate
    // independent effect such as a draw or reveal.
    const hasExplicitCost = definition.steps.some((step: any) => step?.op === "pay_cost");
    if (hasExplicitCost) {
      const selectionSteps = definition.steps.filter((step: any) =>
        step?.op === "select_cards" && step?.saveAs);
      const effectSteps = definition.steps.filter((step: any) =>
        !["pay_cost", "select_cards", "offer_reaction"].includes(String(step?.op || "")));

      const stepUsesVariable = (step: any, variable: string) => {
        const serialized = JSON.stringify(step || {});
        return serialized.includes(`vars.${variable}`)
          || [step?.from, step?.target, step?.selectedVariable, step?.deploymentVariable,
            step?.targetVariable, step?.source]
            .some((value) => String(value || "").replace(/^vars\./u, "") === variable);
      };

      const selectionHasUsefulOutcome = (selectionStep: any) => {
        const variable = String(selectionStep.saveAs);
        const selection = selections.find(({ step: selectedStep }) =>
          String(selectedStep?.saveAs || "") === variable);
        const canSelectSomething = selection
          ? selection.targets.length > 0
          : unresolvedVars.has(variable);
        if (!canSelectSomething) return false;

        return effectSteps.some((effectStep: any) => {
          if (!stepUsesVariable(effectStep, variable)) return false;
          if (effectStep?.op === "move_cards") {
            const source = String(selectionStep.from || "");
            const filterText = JSON.stringify(selectionStep.filter || {});
            const selectsOwnField = /"field":"controller","value":"self"/u.test(filterText);
            // A character the AI sends from its own field to deck bottom or remove
            // is a cost-like trade, not the opponent-facing payoff being sought.
            if (effectStep.to === "deck_bottom"
              && (["field", "own_field", "self_field"].includes(source) || selectsOwnField)) return false;
            if (effectStep.to === "remove_area"
              && (source === "hand" || selectsOwnField)) return false;
          }
          return true;
        });
      };

      const hasTargetedPayoff = selectionSteps.some(selectionHasUsefulOutcome);
      const hasIndependentPayoff = effectSteps.some((effectStep: any) =>
        !selectionSteps.some((selectionStep: any) =>
          stepUsesVariable(effectStep, String(selectionStep.saveAs))));
      if (!hasTargetedPayoff && !hasIndependentPayoff) continue;
    }

    const candidate = { action: "activate_card_effect", payload: { source_instance_id: sourceId, effect_id: ability.effect_id } };
    const threatScore = scoreThreatMitigation(definition, ownField, enemyField, opponentThreat);
    if (threatOnly && threatScore <= 0) continue;
    const utilityScore = estimateEffectUtility(
      definition, ownField, enemyField, selections, source, opponentEvidenceCount, ownEvidenceCount,
    );
    const actionScore = utilityScore + threatScore * 2;
    if (actionScore > bestActionScore) {
      bestDecision = candidate;
      bestActionScore = actionScore;
    }
  }
  return bestDecision;
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
    case "begin_turn": return "AI 탐정: 현장 카드를 액티브로 전환하고 손패 1장 드로우와 파일 배치를 한 번에 완료했습니다.";
    case "place_files": return "AI 탐정: 턴 시작에 필요한 파일을 배치했습니다.";
    case "play_character":
      return `AI 탐정: 현재 레벨 상한에 맞는 ${cardName(card)}(코스트 ${cost})를 골라 등장시켰습니다.`;
    case "play_event":
      return `AI 탐정: 카드 효과를 사용할 수 있는 ${cardName(card)} 이벤트를 발동했습니다.`;
    case "declare_solution":
      return "AI 탐정: 파일 수와 파트너 조건이 충족되어 해결편으로 전환했습니다.";
    case "solve_case":
      return "AI 탐정: 승리 조건을 충족해 사건 해결을 선언하고 승리했습니다.";
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
      return `AI 탐정: ${cardName(attacker)}으로 ${opponent?.display_name || "상대"}의 증거 에이리어를 공격했습니다.`;
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
        Array.isArray(state?.my_remove_cards) ? state.my_remove_cards : [], String(me?.event_key || ""),
        Array.isArray(state?.my_hand) ? state.my_hand : [],
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
  const removeArea = Array.isArray(state?.my_remove_cards) ? state.my_remove_cards : [];
  if (!pending) return null;

  // Shared reveal windows always need an AI acknowledgement, even when it is not the AI's turn.
  // Once acknowledged, do not acknowledge the same window again while waiting for the human.
  const acknowledgementAction = SHARED_REVEAL_ACKNOWLEDGEMENTS[String(pending.type || "")];
  if (acknowledgementAction) {
    const acknowledged = Array.isArray(pending.acknowledged_user_ids) ? pending.acknowledged_user_ids : [];
    return acknowledged.includes(aiId) ? null : { action: acknowledgementAction };
  }
  if (pending.type === "character_contact_guard" && pending.target_user_id === aiId) {
    const attackerBoard = boards.find((board: any) => String(board?.user_id || "") === String(pending.attacker_user_id || ""));
    const attacker = (Array.isArray(attackerBoard?.field_cards) ? attackerBoard.field_cards : [])
      .find((card: any) => String(card?.instance_id || "") === String(pending.attacker_instance_id || ""));
    // A Bullet action cannot be guarded. This also safely handles a guard window
    // created before the current runtime was deployed.
    if (hasBullet(attacker)) return { action: "decline_contact_guard" };
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
    const isAiAttacker = pending.attacker_user_id === aiId;
    // The attacker wins AP ties; a defender must exceed the attacker's AP.
    const needed = Math.max(0, opponentAp - myAp + (isAiAttacker ? 0 : 1));
    const contactSubjectId = pending.attacker_user_id === aiId
      ? String(pending.attacker_instance_id || "")
      : String(pending.target_instance_id || "");
    const contactSubject = field.find((card: any) => String(card.instance_id || "") === contactSubjectId);
    const isAiOwnerTurn = state.current_turn_user_id === aiId;
    const partnerColor = normalizedColor(state.ai_partner_color || me?.partner_color || "");
    const cutinBonus = (card: any) => cardCutInBonusForSubject(
      card, contactSubject, isAiOwnerTurn, partnerColor, field, removeArea, String(me?.event_key || ""),
      Array.isArray(state?.my_hand) ? state.my_hand : [],
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
function chooseTurnAction(state: any, aiId: string, lastNextHintTurnNumber: number | null = null, skipNextHint = false) {
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
  const removeArea = Array.isArray(state?.my_remove_cards) ? state.my_remove_cards : [];
  const partnerColor = normalizedColor(state.ai_partner_color || me.partner_color || "");
  const opponentThreat = getOpponentNextTurnThreat(state, aiId);
  const activeAttackers = field.filter((card: any) => isCharacter(card) && isActive(card)
    && (!card.summoned_this_turn || hasCharge(card)))
    .sort((a: any, b: any) => cardAp(b) - cardAp(a));
  const characterAttackers = activeAttackers.filter((card: any) => !hasCaseOnlyCharge(card));
  const evidenceAttackers = activeAttackers.filter((card: any) => !hasCharacterOnlyCharge(card));
  const characterCount = field.filter((card: any) => isCharacter(card)).length;
  const level = Math.max(0, Number(me.file_count || 0)) + (me.partner_assist_used ? 1 : 0);
  // Partner assist/deduction and other non-card actions may set base_action_done;
  // Next Hint is unlocked only after the actual basic character/event card play.
  const basePlayed = Boolean(me.base_card_played_this_turn || me.base_character_played_this_turn || me.character_played_this_turn);
  const turnNumber = Number(state?.turn_number || 0);
  const nextHintAlreadyUsedThisTurn = turnNumber > 0 && Number(lastNextHintTurnNumber) === turnNumber;
  const isSolution = String(me.case_phase || "incident").toLocaleLowerCase() === "solution";
  const canPlanNextHint = Boolean(
    basePlayed && !me.next_hint_used && !nextHintAlreadyUsedThisTurn
      && isSolution && Number(me.file_count || 0) >= 4 && characterCount < 5
  );
  // Event cards can also be played while Next Hint is pending; unlike characters,
  // they do not need an available character slot on the field.
  const canConsiderEmergencyNextHint = Boolean(
    basePlayed && !me.next_hint_used && !nextHintAlreadyUsedThisTurn
      && isSolution && Number(me.file_count || 0) >= 4
  );

  if (state.turn_step === "begin") return { action: "begin_turn" };
  if (state.turn_step === "file") {
    // DECLARE/SLEEP abilities are main-step actions; finish the required file
    // placement before considering them.
    return { action: "place_files" };
  }
  if (state.turn_step !== "main") return null;

  // An event is only left on the field while its effect is resolving. Once no
  // pending response remains, finish it before selecting any other main action.
  const resolvingEvent = field.find((card: any) => isEvent(card) && card.resolving);
  if (resolvingEvent) return { action: "finish_event", payload: { instance_id: resolvingEvent.instance_id } };

  // Resolve the case as soon as the evidence threshold is met. The Conan vs Kid
  // event uses its own 8/7 threshold; other cases use 7/6 (first/second player).
  const currentCaseKey = String(me.event_key || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const isConanVsKidCase = ["B11098", "B11098P", "1261"].includes(currentCaseKey)
    || String(me.event_rule_code || "") === "conan_vs_kid_1261";
  const isCulpritsCrimeCase = ["B09107", "B09107P", "1046"].includes(currentCaseKey)
    || String(me.event_rule_code || "") === "culprits_1046";
  const solveEvidenceThreshold = isConanVsKidCase
    ? (state.first_player_user_id === aiId ? 8 : 7)
    : (state.first_player_user_id === aiId ? 7 : 6);
  // B09107P cannot be solved normally; its dedicated activated ability is the
  // only win route and is evaluated later in the main-step decision sequence.
  if (isSolution && !isCulpritsCrimeCase
    && !me.partner_rested
    && Number(me.evidence_count || 0) >= solveEvidenceThreshold) {
    return { action: "solve_case" };
  }

  // [신속] alone grants an immediate investigation after entering the field.
  // [돌격] is handled by the character/evidence attack branches below, not by investigate.
  const newlyPlayedSwift = field.find((card: any) =>
    isCharacter(card) && isActive(card) && Boolean(card.summoned_this_turn)
      && hasSwift(card) && cardLifePoints(card) > 0);
  if (newlyPlayedSwift) {
    return {
      action: "investigate",
      payload: {
        instance_id: newlyPlayedSwift.instance_id,
        evidence_count: cardLifePoints(newlyPlayedSwift),
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

    // Event cards are legal after Next Hint too. The server exposes only event
    // effects whose live partner/case/file conditions currently pass; choose a
    // playable event when its payoff compares favourably with the best character.
    const eventCandidates = Array.isArray(state?.ai_event_effect_candidates)
      ? state.ai_event_effect_candidates : [];
    const eventScoreByInstance = new Map<string, number>();
    for (const candidate of eventCandidates) {
      const instanceId = String(candidate?.source_instance_id || "");
      if (!instanceId) continue;
      let score = estimateEventEffectScore(candidate?.definition, field, enemyField);
      const effectId = String(candidate?.effect_id || candidate?.definition?.effectId || "");
      if (effectId === "card-1044-event-deploy-different-level-culprits") {
        const distinctCulpritLevels = new Set(removeArea
          .filter((card: any) => isCharacter(card) && cardCost(card) <= 8
            && (hasTrait(card, "犯人") || hasTrait(card, "범인")))
          .map((card: any) => cardCost(card)));
        score = distinctCulpritLevels.size > 0
          ? score + Math.min(5, distinctCulpritLevels.size) * 12
          : -1;
      } else if (effectId === "card-0721-solution-remove-all-and-deploy-black") {
        const totalFieldCharacters = [...field, ...enemyField].filter((card: any) => isCharacter(card)).length;
        score += totalFieldCharacters * 16;
      }
      if (opponentThreat.urgent) {
        score += scoreThreatMitigation(candidate?.definition, field, enemyField, opponentThreat);
      }
      eventScoreByInstance.set(instanceId, Math.max(eventScoreByInstance.get(instanceId) || 0, score));
    }
    const nextHintEvent = hand.filter((card: any) => isEvent(card)
      && cardCost(card) <= level + 1
      && eventScoreByInstance.has(String(card?.instance_id || "")))
      .map((card: any) => ({
        card,
        score: eventScoreByInstance.get(String(card.instance_id)) || 0,
      }))
      .sort((a: any, b: any) => b.score - a.score || cardCost(a.card) - cardCost(b.card))[0];
    const eventThreshold = nextCard ? Math.max(5, cardStrength(nextCard) / 250) : 1.5;
    if (nextHintEvent && nextHintEvent.score >= eventThreshold) {
      return { action: "play_event", payload: { instance_id: nextHintEvent.card.instance_id } };
    }
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
      let score = estimateEventEffectScore(candidate?.definition, field, enemyField);
      const effectId = String(candidate?.effect_id || candidate?.definition?.effectId || "");
      if (effectId === "card-1044-event-deploy-different-level-culprits") {
        const distinctCulpritLevels = new Set(removeArea
          .filter((card: any) => isCharacter(card) && cardCost(card) <= 8
            && (hasTrait(card, "犯人") || hasTrait(card, "범인")))
          .map((card: any) => cardCost(card)));
        score = distinctCulpritLevels.size > 0
          ? score + Math.min(5, distinctCulpritLevels.size) * 12
          : -1;
      } else if (effectId === "card-0721-solution-remove-all-and-deploy-black") {
        const totalFieldCharacters = [...field, ...enemyField].filter((card: any) => isCharacter(card)).length;
        score += totalFieldCharacters * 16;
      }
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

  // When the opponent can win on their next turn, use a real defensive ability first.
  // If no removal/stun/evidence-denial effect is available, spend the legal Next Hint
  // before ordinary utility actions so the AI does not concede while a rescue remains.
  if (opponentThreat.urgent) {
    // Use immediate, already-available defensive effects before considering
    // the more speculative Next Hint line.
    const defensiveAbility = chooseActivatedAbility(state, aiId, true);
    if (defensiveAbility) return defensiveAbility;
  }

  // A newly deployed Charge character should use its same-turn action before
  // optional activated abilities, partner deduction, or a planned Next Hint.
  const newlyPlayedChargeAttackers = activeAttackers.filter((card: any) =>
    Boolean(card.summoned_this_turn) && hasCharge(card));
  const newlyPlayedChargeCharacterAttackers = newlyPlayedChargeAttackers
    .filter((card: any) => !hasCaseOnlyCharge(card));
  // Preserve D11007's special contact against an active level-7+ character,
  // but only use it here when the Matsuda card itself is a newly played Charge attacker.
  const newlyPlayedChargeMatsuda = newlyPlayedChargeCharacterAttackers
    .find((card: any) => matchesInternalCardId(card, "0938"));
  const newlyPlayedChargeActiveTarget = enemyField
    .filter((card: any) => isCharacter(card) && isActive(card) && cardCost(card) >= 7)
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (newlyPlayedChargeMatsuda && newlyPlayedChargeActiveTarget) {
    const attackerAp = cardAp(newlyPlayedChargeMatsuda);
    const targetAp = cardAp(newlyPlayedChargeActiveTarget);
    const canWinWithoutCost = attackerAp >= targetAp;
    const canWinByD11007 = hand.length > 0 && attackerAp < targetAp && attackerAp + 3000 >= targetAp;
    const canWinByCutin = hand.some((card: any) => {
      const bonus = cardCutInBonusForSubject(
        card, newlyPlayedChargeMatsuda, true, partnerColor, field, removeArea,
        String(me?.event_key || ""), Array.isArray(state?.my_hand) ? state.my_hand : [],
      );
      return bonus > 0 && attackerAp + bonus >= targetAp;
    });
    if (canWinWithoutCost || canWinByD11007 || canWinByCutin) {
      return {
        action: "declare_contact",
        payload: {
          attacker_instance_id: newlyPlayedChargeMatsuda.instance_id,
          target_user_id: opponent.user_id,
          target_instance_id: newlyPlayedChargeActiveTarget.instance_id,
          allow_active_target: true,
          allow_newly_played: true,
        },
      };
    }
  }

  const newlyPlayedChargeRestedTarget = enemyField
    .filter((card: any) => isCharacter(card) && !isActive(card))
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (newlyPlayedChargeCharacterAttackers.length && newlyPlayedChargeRestedTarget) {
    // Do not waste a same-turn Charge attack on a contact it cannot win,
    // unless a legal cut-in or D11007's discard bonus can bridge the AP gap.
    const attacker = newlyPlayedChargeCharacterAttackers.find((candidate: any) => {
      const attackerAp = cardAp(candidate);
      const targetAp = cardAp(newlyPlayedChargeRestedTarget);
      const canUseMatsudaContactEffect = matchesInternalCardId(candidate, "0938")
        && hand.length > 0 && attackerAp < targetAp && attackerAp + 3000 >= targetAp;
      return attackerAp >= targetAp || canUseMatsudaContactEffect || hand.some((card: any) => {
        const bonus = cardCutInBonusForSubject(
          card, candidate, true, partnerColor, field, removeArea,
          String(me?.event_key || ""), Array.isArray(state?.my_hand) ? state.my_hand : [],
        );
        return bonus > 0 && attackerAp + bonus >= targetAp;
      });
    });
    if (attacker) {
      return {
        action: "declare_contact",
        payload: {
          attacker_instance_id: attacker.instance_id,
          target_user_id: opponent.user_id,
          target_instance_id: newlyPlayedChargeRestedTarget.instance_id,
          allow_active_target: false,
          allow_newly_played: true,
        },
      };
    }
  }

  // Existing attackers remain available below when no new Charge attacker has
  // a legal same-turn target.

  // D11007 can select an active opposing character of level 7 or higher.
  // Its discard ability can bridge an AP deficit of less than 3000 during that contact.
  const specialTargetAttacker = activeAttackers.find((card: any) => matchesInternalCardId(card, "0938"));
  const activeHighLevelTarget = enemyField
    .filter((card: any) => isCharacter(card) && isActive(card) && cardCost(card) >= 7)
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (specialTargetAttacker && activeHighLevelTarget) {
    const attackerAp = cardAp(specialTargetAttacker);
    const targetAp = cardAp(activeHighLevelTarget);
    const canWinWithoutCost = attackerAp >= targetAp;
    const canWinByD11007 = hand.length > 0 && attackerAp < targetAp && attackerAp + 3000 >= targetAp;
    const canWinByCutin = hand.some((card: any) => {
      const bonus = cardCutInBonusForSubject(card, specialTargetAttacker, true, partnerColor, field, removeArea, String(me?.event_key || ""), Array.isArray(state?.my_hand) ? state.my_hand : []);
      return bonus > 0 && attackerAp + bonus >= targetAp;
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

  // Bond with Hiromitsu lets Furuya Rei contact an active opposing character.
  // Only take the line when the contact can be won without consuming another resource.
  const bondFuruyaAttacker = activeAttackers.find((card: any) => matchesInternalCardId(card, "1123"));
  const hasBondHiromitsu = field.some((card: any) => matchesCardName(card, "모로후시 히로미츠"));
  const bondActiveTarget = enemyField
    .filter((card: any) => isCharacter(card) && isActive(card))
    .sort((a: any, b: any) => cardAp(a) - cardAp(b))[0];
  if (bondFuruyaAttacker && hasBondHiromitsu && bondActiveTarget
    && cardAp(bondFuruyaAttacker) >= cardAp(bondActiveTarget)) {
    return {
      action: "declare_contact",
      payload: {
        attacker_instance_id: bondFuruyaAttacker.instance_id,
        target_user_id: opponent.user_id,
        target_instance_id: bondActiveTarget.instance_id,
        allow_active_target: true,
        allow_newly_played: hasCharge(bondFuruyaAttacker),
      },
    };
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
        && hand.length > 0 && attackerAp < targetAp && attackerAp + 3000 >= targetAp;
      return attackerAp >= targetAp || canUseMatsudaContactEffect || hand.some((card: any) => {
        const bonus = cardCutInBonusForSubject(card, candidate, true, partnerColor, field, removeArea, String(me?.event_key || ""), Array.isArray(state?.my_hand) ? state.my_hand : []);
        return bonus > 0 && attackerAp + bonus >= targetAp;
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
  // Clear or suppress the opponent's remaining field before spending attacks
  // on evidence. Event, character, and case effects share the same field-control
  // scoring, so the strongest available removal effect is chosen here.
  const activatedAbility = chooseActivatedAbility(state, aiId);
  if (activatedAbility) return activatedAbility;

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

  // After all useful attacks, use every older active character that can still
  // investigate. A character played this turn may investigate only through
  // the separate [신속] branch above.
  const investigator = field.find((card: any) =>
    isCharacter(card) && isActive(card) && !Boolean(card.summoned_this_turn)
      && cardLifePoints(card) > 0);
  if (investigator) {
    return {
      action: "investigate",
      payload: {
        instance_id: investigator.instance_id,
        evidence_count: cardLifePoints(investigator),
      },
    };
  }

  // Partner deduction is an independent evidence action. Do not stop at an
  // arbitrary evidence-count cutoff: the solve threshold was checked above.
  if (!me.partner_rested && !me.partner_deduction_used && me.partner_key) {
    return { action: "partner_deduce", payload: { evidence_count: 1 } };
  }

  // Next Hint is a follow-on deployment, not a substitute for attacks,
  // removals, investigations, or partner deduction already available this turn.
  if (!opponentThreat.urgent && !skipNextHint && canPlanNextHint) {
    const canContinue = hand.some((card: any) => isCharacter(card)
      && cardCost(card) <= level && characterCount < 5);
    if (canContinue) return { action: "next_hint_take_file" };
  }

  // Only after immediate removal contacts and other available actions have
  // been exhausted, gamble on Next Hint as the final rescue attempt.
  if (opponentThreat.urgent && !skipNextHint && canConsiderEmergencyNextHint) {
    const hasNextHintCharacter = hand.some((card: any) => isCharacter(card)
      && cardCost(card) <= level && characterCount < 5);
    // Event cards can be played with play_event while next_hint_pending is true
    // and do not need a free character slot.
    const hasNextHintEvent = hand.some((card: any) => isEvent(card)
      && cardCost(card) <= level);
    if (hasNextHintCharacter || hasNextHintEvent) return { action: "next_hint_take_file" };
  }

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
    if (
      pending
      && String(pending.type || "").startsWith("card_effect_")
      && pending.chooser_user_id
      && pending.chooser_user_id !== battle.ai_user_id
    ) {
      return {
        is_ai: true,
        actions: [],
        message: "AI 탐정: 카드 효과의 선택·공개 확인을 플레이어가 완료하기를 기다립니다.",
      };
    }
    if (pending && ["opponent_hand_request","opponent_hand_select","opponent_hand_discard_confirmation"].includes(String(pending.type || ""))) {
      const { data: handStep, error: handStepError } = await service.rpc("perform_private_ai_opponent_hand_step_v1", {
        p_room_id: roomId,
        p_ai_user_id: battle.ai_user_id,
      });
      if (handStepError) throw handStepError;
      if (handStep?.handled) {
        return {
          is_ai: true,
          actions: [String(handStep.action || "opponent_hand_operation")],
          message: String(handStep.message || "AI 탐정: 상대 손패 요청을 처리했습니다."),
        };
      }
      if (pending.type === "opponent_hand_select" && pending.chooser_user_id !== battle.ai_user_id) {
        return {
          is_ai: true,
          actions: [],
          message: "AI 탐정: 플레이어가 손패에서 카드를 선택하기를 기다립니다.",
        };
      }
    }
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

    const aiHand = Array.isArray(state.my_hand) ? state.my_hand : [];
    const aiBoard = (Array.isArray(state.boards) ? state.boards : [])
      .find((board: any) => String(board?.user_id || "") === String(battle.ai_user_id));
    const ownField = Array.isArray(aiBoard?.field_cards) ? aiBoard.field_cards : [];
    const removeArea = Array.isArray(state.my_remove_cards) ? state.my_remove_cards : [];

    let decision: any = null;
    if (pending?.chooser_user_id === battle.ai_user_id && String(pending?.type || "").startsWith("card_effect_")) {
      if (pending.type === "card_effect_trait_selection") {
        const enemyBoard = (Array.isArray(state?.boards) ? state.boards : [])
          .find((board: any) => String(board?.user_id || "") !== String(battle.ai_user_id));
        const enemyField = Array.isArray(enemyBoard?.field_cards) ? enemyBoard.field_cards : [];
        // Prefer a trait already represented on the visible opponent field. When no
        // visible clue exists, Police is a stable fallback for the Police Academy deck.
        const traitCandidates = ["警察", "警視庁", "公安", "探偵", "怪盗", "黒ずくめの組織", "FBI", "犯人", "高校生", "少年探偵団"];
        const rankedTraits = traitCandidates.map((trait: string, index: number) => ({
          trait,
          score: enemyField.filter((card: any) => hasTrait(card, trait)).length,
          tieBreak: index,
        })).sort((left: any, right: any) => right.score - left.score || left.tieBreak - right.tieBreak);
        const selectedTrait = rankedTraits[0]?.trait || "警察";
        decision = { action: "card_effect_continue", payload: { trait: selectedTrait } };
      } else if (pending.type === "card_effect_selection" || pending.type === "card_effect_order") {
        const { data: effectOptions, error: optionsError } = await service.rpc("get_private_card_effect_options_for_ai_v1", {
          p_room_id: roomId, p_ai_user_id: battle.ai_user_id,
        });
        if (optionsError) throw optionsError;
        const options = Array.isArray(effectOptions?.options) ? effectOptions.options : [];
        const opponentThreat = getOpponentNextTurnThreat(state, battle.ai_user_id);
        const activeEffect = [
          ...(Array.isArray(state?.ai_card_effect_activations) ? state.ai_card_effect_activations : []),
          ...(Array.isArray(state?.ai_event_effect_candidates) ? state.ai_event_effect_candidates : []),
        ].find((entry: any) => String(entry?.effect_id || entry?.definition?.effectId || "") === String(pending.effect_id || ""));
        const threatSelectionStep = findPendingThreatSelectionStep(activeEffect?.definition, pending);
        const threatSelectionKind = threatSelectionStep
          ? getThreatMitigationKind(activeEffect?.definition, threatSelectionStep) : null;
        const preferOpponentFieldTargetEffects = new Set([
          "card-0211-hirameki-rest-character",
          "card-0691-hirameki-rest-character",
          "card-0704-hirameki-rest-character",
          "card-1121-field-watch-remove-level9-on-police-academy-enter",
          "card-1197-activated-ready-ap-minus2000-and-rest-character",
          "card-0531-when-heiji-or-self-enters-rest-character",
          "card-0971-activated-face-down-set-or-hand-cost-stun-rested-character",
          "card-1083-partner-green-sleep-remove-level8-character",
          "card-1083-activated-remove-two-facedown-heiji-green-police-set-cards",
        ]);
        const strictOpponentRemoval = new Set([
          "card-1039-declare-remove-character-ap-8000",
          "card-1040-declare-remove-character-level-7",
        ]).has(String(pending.effect_id || ""));
        const preferOpponentRestTarget = preferOpponentFieldTargetEffects.has(String(pending.effect_id || ""))
          || strictOpponentRemoval;
        // Some effects use the same effect ID for multiple selection steps.
        // For ID:1197 the first step is an AI-owned hand discard cost, while
        // the later step targets an opposing field character. Apply the
        // opponent-only preference only to field-card choices, never to hand costs.
        const isFieldTargetSelection = options.some((option: any) => String(option?.zone || "") === "field");
        const isRestTargetSelection = isFieldTargetSelection
          && /슬립(?:시킬| 상태로 만들)/u.test(String(pending.prompt || ""));
        const preferOwnFieldTarget = String(pending.effect_id || "") === "card-0531-activated-once-ready-or-charge-green-level8"
          && isFieldTargetSelection;
        let targetOptions = isRestTargetSelection
          ? (() => {
              const activeTargets = options.filter((option: any) => isActive(option?.card || option));
              const activeOpponents = activeTargets.filter((option: any) =>
                String(option?.owner_user_id || option?.card?.owner_user_id || "") !== String(battle.ai_user_id));
              return activeOpponents.length > 0 ? activeOpponents : activeTargets;
            })()
          : preferOpponentRestTarget && isFieldTargetSelection
          ? (() => {
              const opponents = options.filter((option: any) =>
                String(option?.owner_user_id || "") !== String(battle.ai_user_id));
              return strictOpponentRemoval ? opponents : opponents.length > 0 ? opponents : options;
            })()
          : preferOwnFieldTarget
            ? options.filter((option: any) => String(option?.owner_user_id || "") === String(battle.ai_user_id))
            : options;

        // For field removal, prefer a card that is still active and represents
        // the largest remaining threat. A rested low-AP character is normally
        // a much less valuable removal than an active high-AP character.
        const isReviveSelection = String(pending.effect_id || "") === "card-0797-on-enter-revive-red-level5"
          && options.some((option: any) => String(option?.zone || "") === "remove_area");
        if (isReviveSelection) {
          targetOptions = [...targetOptions].sort((left: any, right: any) =>
            cardStrength(right?.card || right) - cardStrength(left?.card || left));
        }
        const currentSelectionVariable = String(threatSelectionStep?.saveAs || "");
        const removesSelectedFieldCards = Boolean(currentSelectionVariable)
          && (Array.isArray(activeEffect?.definition?.steps) ? activeEffect.definition.steps : []).some((step: any) =>
            step?.op === "move_cards"
            && effectStepReferencesVariable(step, currentSelectionVariable)
            && ["remove_area", "deck_bottom", "hand"].includes(String(step?.to || "")));
        const isRemovalSelection = isFieldTargetSelection
          && (/(?:리무브|제거)/u.test(String(pending.prompt || "")) || removesSelectedFieldCards);
        if (isRemovalSelection) {
          const opponentOptions = targetOptions.filter((option: any) => {
            const card = option?.card || option;
            const owner = String(option?.owner_user_id || card?.owner_user_id || "");
            return owner && owner !== String(battle.ai_user_id);
          });
          if (opponentOptions.length > 0) targetOptions = opponentOptions;
          targetOptions = [...targetOptions].sort((left: any, right: any) => {
            const leftCard = left?.card || left;
            const rightCard = right?.card || right;
            const activePriority = Number(isActive(rightCard)) - Number(isActive(leftCard));
            if (activePriority !== 0) return activePriority;
            const lpDifference = cardLifePoints(rightCard) - cardLifePoints(leftCard);
            if (lpDifference !== 0) return lpDifference;
            return cardAp(rightCard) - cardAp(leftCard);
          });
        }
        const isReviveSlotSacrifice = String(pending.effect_id || "") === "card-0797-on-enter-revive-red-level5"
          && /현장.*캐릭터.*리무브/u.test(String(pending.prompt || ""));
        if (isReviveSlotSacrifice) {
          targetOptions = options.filter((option: any) =>
            String(option?.owner_user_id || option?.card?.owner_user_id || "") === String(battle.ai_user_id)
            && String(option?.zone || "field") === "field"
            && String(option?.instance_id || option?.card?.instance_id || "") !== String(pending.source_instance_id || "")
          ).sort((left: any, right: any) =>
            cardStrength(left?.card || left) - cardStrength(right?.card || right)
          );
        }
        if (opponentThreat.urgent && threatSelectionKind) {
          if (threatSelectionKind === "evidence_remove") {
            const opposingEvidence = options.filter((option: any) =>
              String(option?.owner_user_id || option?.card?.owner_user_id || "") !== String(battle.ai_user_id)
              && ["evidence", "evidence_area", "opponent_evidence"].includes(String(option?.zone || "evidence_area")));
            if (opposingEvidence.length > 0) targetOptions = opposingEvidence;
          } else if (["remove", "stun", "rest"].includes(threatSelectionKind) && isFieldTargetSelection) {
            const opposingCharacters = options.filter((option: any) => {
              const owner = String(option?.owner_user_id || option?.card?.owner_user_id || "");
              const zone = String(option?.zone || "field");
              return zone === "field" && (owner ? owner !== String(battle.ai_user_id)
                : String(threatSelectionStep?.from || "") === "opponent_field");
            });
            if (opposingCharacters.length > 0) {
              targetOptions = [...opposingCharacters].sort((left: any, right: any) => {
                const lpDifference = cardLifePoints(right?.card || right) - cardLifePoints(left?.card || left);
                if (lpDifference !== 0) return lpDifference;
                const activeDifference = Number(isActive(right?.card || right)) - Number(isActive(left?.card || left));
                if (activeDifference !== 0) return activeDifference;
                return cardAp(right?.card || right) - cardAp(left?.card || left);
              });
            }
          }
        }
        const ids = targetOptions.map((option: any) => String(option?.instance_id || option?.card?.instance_id || "")).filter(Boolean);
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
          if (aiHand.length > 0 && choices.includes("hand")) choice = "hand";
          else if (choices.includes("attachment")) choice = "attachment";
        }
        // ID:0147 (PR151) spends a hand card only when the AI can actually
        // pay the cost and there is a legal AP<=8000 character to remove.
        // Avoid accepting the optional cost merely because "yes" is listed first.
        if (reactionId === "card-0147-discard-hand-remove-ap8000") {
          const hasHandCost = aiHand.length > 0;
          const hasLegalRemovalTarget = [...ownField, ...(
            (Array.isArray(state?.boards) ? state.boards : [])
              .find((board: any) => String(board?.user_id || "") !== String(battle.ai_user_id))
              ?.field_cards || []
          )].some((card: any) => isCharacter(card) && cardAp(card) <= 8000);
          choice = hasHandCost && hasLegalRemovalTarget && choices.includes("yes")
            ? "yes"
            : choices.includes("no") ? "no" : choice;
        }
        if (reactionId === "card-0797-revive-red-level5") {
          const hasEligibleRevive = removeArea.some((card: any) =>
            isCharacter(card)
            && normalizedColor(card?.color || card?.color_key || card?.colorKo || card?.color_ja) === "red"
            && cardCost(card) <= 5
          );
          choice = hasEligibleRevive && choices.includes("yes") ? "yes" : "no";
        }
        if (reactionId === "card-0224-offer-opponent-evidence-and-charge-case") {
          const hasFreshRedCharacter = ownField.some((card: any) =>
            isCharacter(card)
            && normalizedColor(card?.color || card?.color_key || card?.colorKo || card?.color_ja) === "red"
            && Boolean(card?.summoned_this_turn)
            && isActive(card)
          );
          choice = hasFreshRedCharacter && choices.includes("yes") ? "yes" : "no";
        }
        if (reactionId === "card-0802-discard-search-red") {
          choice = aiHand.length > 0 && choices.includes("yes") ? "yes" : "no";
        }
        if (reactionId === "card-0220-keyword-choice") {
          const enemyBoard = (Array.isArray(state?.boards) ? state.boards : [])
            .find((board: any) => String(board?.user_id || "") !== String(battle.ai_user_id));
          const hasRestedEnemy = (Array.isArray(enemyBoard?.field_cards) ? enemyBoard.field_cards : [])
            .some((card: any) => isCharacter(card) && !isActive(card));
          const hasFreshOwnCharacter = ownField.some((card: any) =>
            isCharacter(card) && Boolean(card?.summoned_this_turn) && isActive(card));
          choice = hasRestedEnemy && choices.includes("bullet")
            ? "bullet"
            : hasFreshOwnCharacter && choices.includes("charge_case") ? "charge_case" : choices[0];
        }
        if (reactionId === "card-1120-antique-tray-mode") {
          choice = choices.includes("draw") ? "draw" : "ap";
        }
        if (reactionId === "card-0531-choose-ready-or-charge") {
          const boards = Array.isArray(state?.boards) ? state.boards : [];
          const ownBoard = boards.find((board: any) => String(board?.user_id || "") === String(battle.ai_user_id));
          const greenLevel8 = (Array.isArray(ownBoard?.field_cards) ? ownBoard.field_cards : []).filter((card: any) =>
            isCharacter(card)
            && normalizedColor(card?.color || card?.color_key || card?.colorKo || card?.color_ja) === "green"
            && cardCost(card) <= 8
          );
          const hasUsefulReadyTarget = greenLevel8.some((card: any) => {
            const status = String(card?.status || (card?.rested ? "rested" : "active")).toLowerCase();
            const stunned = Boolean(card?.stunned || card?.stun || card?.is_stunned)
              || ["stunned", "stun", "스턴"].includes(status);
            return !stunned && (Boolean(card?.rested) || ["rested", "sleep", "slumber", "슬립"].includes(status));
          });
          const hasUsefulChargeTarget = greenLevel8.some((card: any) =>
            isActive(card) && Boolean(card?.summoned_this_turn) && !hasCharge(card)
          );
          if (hasUsefulReadyTarget && choices.includes("액티브화")) choice = "액티브화";
          else if (hasUsefulChargeTarget && choices.includes("돌격 부여")) choice = "돌격 부여";
          else if (choices.includes("액티브화")) choice = "액티브화";
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
      const urgentThreat = getOpponentNextTurnThreat(state, battle.ai_user_id).urgent;
      if (urgentThreat) {
        // If an emergency Next Hint is rejected by the rules engine, do not
        // immediately concede. Re-run the normal action planner with Next Hint
        // suppressed so it can still use partner actions, contacts, attacks,
        // or any other legal line before deciding that the turn is over.
        const fallbackDecision = chooseTurnAction(
          state, battle.ai_user_id, battle.last_next_hint_turn_number, true,
        );
        if (fallbackDecision && fallbackDecision.action !== "next_hint_take_file") {
          const fallbackAttempt = await service.rpc("perform_private_ai_turn_action_v1", {
            p_room_id: roomId,
            p_action: fallbackDecision.action,
            p_payload: fallbackDecision.payload || {},
          });
          if (!fallbackAttempt.error) {
            return {
              is_ai: true,
              actions: [fallbackDecision.action],
              action: fallbackDecision.action,
              message: fallbackDecision.action === "end_turn"
                ? "AI 탐정: 긴급 넥스트 힌트가 규칙 검사에서 막혀 다른 방어 수단과 행동을 확인했지만 더 진행할 수 없어 턴을 종료했습니다."
                : "AI 탐정: 긴급 넥스트 힌트가 규칙 검사에서 막혀, 아직 가능한 다른 행동을 이어서 시도했습니다.",
            };
          }
          actionError = fallbackAttempt.error;
        }
      } else {
        const fallback = await service.rpc("perform_private_ai_turn_action_v1", {
          p_room_id: roomId, p_action: "end_turn", p_payload: {},
        });
        if (!fallback.error) {
          return { is_ai: true, actions: ["end_turn"], message: "AI 탐정: 넥스트 힌트의 후속 전개를 안전하게 진행할 수 없어 파일을 더 소모하지 않고 턴을 종료했습니다." };
        }
        actionError = fallback.error;
      }
    } else if (actionError && decision.action === "next_hint") {
      const fallback = await service.rpc("perform_private_ai_turn_action_v1", {
        p_room_id: roomId, p_action: "cancel_next_hint", p_payload: {},
      });
      if (!fallback.error) {
        return { is_ai: true, actions: ["cancel_next_hint"], message: "AI 탐정: 넥스트 힌트로 가져온 카드의 등장이 처리되지 않아 응급 취소로 진행을 복구했습니다." };
      }
      actionError = fallback.error;
    }
    if (actionError && decision.action === "contact_use_cutin") {
      // A card may have a conditional target/turn requirement that is not fully
      // represented in the AI's normalized metadata. If the server rejects that
      // cut-in, the failed RPC has rolled back; safely pass instead of freezing
      // the contact window.
      const fallback = await service.rpc("perform_private_ai_turn_action_v1", {
        p_room_id: roomId, p_action: "contact_pass_cutin", p_payload: {},
      });
      if (!fallback.error) {
        return {
          is_ai: true,
          actions: ["contact_pass_cutin"],
          message: "AI 탐정: 컷인 사용 조건을 충족하지 않아 컷인 없이 컨택을 진행했습니다.",
        };
      }
      actionError = fallback.error;
    }
    if (actionError) {
      const { data: diagnosticReport, error: diagnosticError } = await service.rpc("report_private_match_diagnostic_error_internal_v1", {
        p_room_id: roomId,
        p_actor_user_id: humanId,
        p_action: `AI:${decision.action}`,
        p_error_message: actionError.message || "AI 행동이 규칙 검사에서 거부되었습니다.",
        p_error_code: actionError.code || null,
        p_error_context: {
          component: "ai-battle",
          ai_action: decision.action,
          blocked_action: decision.action,
          turn_number: state?.turn_number == null ? "" : String(state.turn_number),
          phase: state?.phase || "",
          turn_step: state?.turn_step || "",
          state_version: state?.state_version == null ? "" : String(state.state_version),
          pending_action_type: state?.pending_action?.type || "",
          last_action_label: state?.last_action_label || "",
        },
      });
      if (diagnosticError) console.error("failed to persist AI diagnostic report", diagnosticError);
      const failureMessage = `AI 탐정: ${decision.action} 행동이 규칙 검사에서 거부되어 진행을 멈췄습니다. ${actionError.message || "상태를 다시 확인해 주세요."}`;
      return {
        is_ai: true,
        actions: [],
        blocked_action: decision.action,
        message: failureMessage,
        diagnostic_report: diagnosticReport || null,
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

  let requestBody: any = {};
  let diagnosticUserId: string | null = null;
  let diagnosticRoomId: string | null = null;
  try {
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    const user = userData?.user;
    if (userError || !user) return json({ error: "로그인 세션을 확인할 수 없습니다." }, 401);
    diagnosticUserId = user.id;
    requestBody = await req.json();
    const body = requestBody;

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
      diagnosticRoomId = room.out_room_id;

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

      const { error: humanEventRedColorError } = await userClient.rpc("set_private_room_event_has_non_red_color_v1", {
        p_room_id: room.out_room_id,
        p_has_non_red_color: Boolean(body.event_has_non_red_color),
      });
      if (humanEventRedColorError) throw humanEventRedColorError;

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
        p_ai_event_has_non_red_color: Boolean(aiDeck.event_has_non_red_color),
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
      diagnosticRoomId = roomId;
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
    let diagnosticReport: any = null;
    if (diagnosticRoomId && diagnosticUserId) {
      try {
        const { data, error: reportError } = await service.rpc("report_private_match_diagnostic_error_internal_v1", {
          p_room_id: diagnosticRoomId,
          p_actor_user_id: diagnosticUserId,
          p_action: String(requestBody?.action || "ai-battle"),
          p_error_message: getReadableErrorMessage(error),
          p_error_code: (error as any)?.code || null,
          p_error_context: {
            component: "ai-battle-edge",
            edge_action: String(requestBody?.action || "unknown"),
          },
        });
        if (reportError) console.error("failed to save ai-battle request diagnostic", reportError);
        else diagnosticReport = data;
      } catch (reportFailure) {
        console.error("failed to persist ai-battle diagnostic", reportFailure);
      }
    }
    const readable = getReadableErrorMessage(error);
    return json({
      error: readable,
      message: readable,
      blocked_action: diagnosticReport?.report_code ? "edge_error" : null,
      diagnostic_report: diagnosticReport,
      diagnostic_notice: diagnosticReport?.report_code
        ? "오류 보고 코드: " + diagnosticReport.report_code
        : null,
    }, diagnosticReport?.report_code ? 200 : 500);
  }
});
