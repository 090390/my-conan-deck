import { readFile } from "node:fs/promises";

export const ALLOWED_EVENTS = new Set([
  "character.entered_field", "character.removed_from_field", "character.activated_ability",
  "character.acted", "player.turn_ended", "continuous.recalculate", "event.played", "opponent.deduction.declared",
  "character.disguised", "character.contact_removed_opponent", "character.contact_started",
  "case.solution_entered", "case.activated_ability", "evidence.card_removed"
]);
export const ALLOWED_OPERATORS = new Set([
  "equals", "not_equals", "in", "less_than", "less_than_or_equal", "greater_than", "greater_than_or_equal",
  "has_keyword", "has_trait", "name_matches"
]);
export const ALLOWED_OPS = new Set([
  "refill_deck_from_remove_area", "peek_top_cards", "select_cards", "reveal_cards",
  "move_cards", "move_unselected_to_deck_bottom", "move_unselected_to_zone", "filter_cards",
  "reveal_until_match", "attach_cards", "grant_keyword", "modify_stat", "offer_reaction",
  "pay_cost", "set_mislead_value", "draw_cards", "gain_evidence", "ready_cards_that_used_keyword",
  "mark_keyword_activated", "shuffle_deck", "set_continuous_stat", "set_continuous_keyword",
  "rest_cards", "ready_source_character", "schedule_move_to_deck_bottom", "attach_top_card",
  "flip_evidence", "win_game", "start_contact", "modify_contact_ap", "grant_bond_alias"
]);
export const REQUIRED_FIELDS = {
  refill_deck_from_remove_area: ["includeRemainingDeck", "includeRemoveArea", "shuffle"],
  peek_top_cards: ["count", "allowFewer", "saveAs"],
  select_cards: ["from", "min", "max", "optional", "saveAs"],
  reveal_cards: ["from", "to", "awaitAcknowledgement"],
  move_cards: ["from", "to"],
  filter_cards: ["from", "filter", "saveAs"],
  move_unselected_to_deck_bottom: ["from", "selectedVariable", "order"],
  move_unselected_to_zone: ["from", "selectedVariable", "to", "order"],
  reveal_until_match: ["from", "saveAs", "match", "includeMatchingCard", "publicReveal", "oneByOne"],
  attach_cards: ["from", "to"],
  grant_keyword: ["target", "keyword", "duration"],
  modify_stat: ["target", "stat", "amount", "duration", "stacking"],
  offer_reaction: ["reactionId", "actor", "choices", "saveAs"],
  pay_cost: ["cost"],
  set_mislead_value: ["target", "value", "duration"],
  draw_cards: ["destination", "count"],
  gain_evidence: ["count"],
  ready_cards_that_used_keyword: ["keyword", "turn", "includePartnerArea"],
  mark_keyword_activated: ["keyword"],
  shuffle_deck: [],
  set_continuous_stat: ["target", "stat", "amount", "modifierId", "duration"],
  set_continuous_keyword: ["target", "keyword", "modifierId", "duration"],
  rest_cards: ["target"], ready_source_character: [],
  schedule_move_to_deck_bottom: ["target"], attach_top_card: ["target"], flip_evidence: ["count"],
  win_game: [], start_contact: ["target", "allowActiveTarget", "allowNewlyPlayed"],
  modify_contact_ap: ["amount"], grant_bond_alias: ["target", "name", "duration"]
};
const ZONES = new Set(["deck", "hand", "field", "opponent_field", "remove_area", "evidence_area", "partner_area", "source_character", "deck_bottom", "both_fields", "opponent_hand", "attached_cards"]);
const VALUE_FIELDS = new Set(["card_type", "level", "color", "keyword", "trait", "card_name", "card_id", "rarity", "face_up", "ap_current", "controller", "is_active", "status"]);
const object = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const variableRoot = (v) => typeof v === "string" ? v.split(".")[0] : "";

export async function loadActiveCatalog() {
  const data = JSON.parse(await readFile(new URL("../supabase/seed/card_effect_definitions.json", import.meta.url), "utf8"));
  const facts = new Set();
  const visit = (v) => {
    if (!v || typeof v !== "object") return;
    if (typeof v.fact === "string") facts.add(v.fact);
    for (const child of Object.values(v)) if (child && typeof child === "object") visit(child);
  };
  visit(data);
  [
    "turn.is_source_controller_turn", "turn.is_opponent_turn", "source.is_active", "source.status",
    "player.field.has_card_name", "player.partner.color", "player.deck.count", "player.hand.count",
    "player.file.count", "player.case_phase", "player.event.has_non_blue_color",
    "opponent.hand.count", "entry.method", "entry.source.card_type", "entry.source.level",
    "entry.is_first_character_this_turn", "entry.source.card_name", "entry.source.card_id",
    "source.under_cards.count", "player.evidence.count", "player.evidence.facedown_count",
    "game.total_evidence_count", "turn.number", "contact.source.ap", "contact.target.ap",
    "player.event.has_detective_vs_kid_trait"
  ].forEach((f) => facts.add(f));
  return { data, facts };
}

export function validateDslDefinition(def, expectedCardId, knownFacts = new Set()) {
  const errors = [];
  const need = (ok, message) => { if (!ok) errors.push(message); };
  need(object(def), "정의는 객체여야 합니다.");
  if (!object(def)) return errors;
  need(typeof def.effectId === "string" && def.effectId.length > 0, "effectId가 필요합니다.");
  need(Array.isArray(def.cardIds) && def.cardIds.length > 0 && def.cardIds.every((id) => typeof id === "string" && /^\d{4}$/.test(id)), "cardIds는 네 자리 문자열 배열이어야 합니다.");
  if (expectedCardId && /^\d{4}$/.test(expectedCardId)) need(def.cardIds?.includes(expectedCardId), `cardIds에 내부 ID ${expectedCardId}가 포함되어야 합니다.`);
  need(object(def.trigger) && ALLOWED_EVENTS.has(def.trigger.event), `지원하지 않는 trigger.event: ${String(def.trigger?.event)}`);
  need(object(def.trigger) && ["immediate", "after", "continuous"].includes(def.trigger.timing), `지원하지 않는 trigger.timing: ${String(def.trigger?.timing)}`);
  need(Array.isArray(def.conditions ?? []), "conditions는 배열이어야 합니다.");
  const checkCondition = (c, at) => {
    need(object(c), `${at}: 조건은 객체여야 합니다.`); if (!object(c)) return;
    need(typeof c.fact === "string" && c.fact, `${at}: fact가 필요합니다.`);
    if (typeof c.fact === "string" && !knownFacts.has(c.fact) && !c.fact.startsWith("vars.")) need(false, `${at}: 확인되지 않은 fact 경로 '${c.fact}'`);
    need(ALLOWED_OPERATORS.has(c.operator), `${at}: 지원하지 않는 operator '${String(c.operator)}'`);
    need(Object.hasOwn(c, "value"), `${at}: value가 필요합니다.`);
    if (c.operator === "in") need(Array.isArray(c.value), `${at}: in 연산의 value는 배열이어야 합니다.`);
  };
  for (const [i, c] of (def.conditions ?? []).entries()) checkCondition(c, `conditions[${i}]`);
  need(Array.isArray(def.steps) && def.steps.length > 0, "steps는 비어 있지 않은 배열이어야 합니다.");
  const vars = new Set();
  const checkFilter = (f, at) => {
    need(object(f), `${at}: filter는 객체여야 합니다.`); if (!object(f)) return;
    if (f.allOf !== undefined || f.anyOf !== undefined) {
      for (const branch of ["allOf", "anyOf"]) if (f[branch] !== undefined) {
        need(Array.isArray(f[branch]) && f[branch].length > 0, `${at}.${branch}는 비어 있지 않은 배열이어야 합니다.`);
        (f[branch] || []).forEach((x, i) => checkFilter(x, `${at}.${branch}[${i}]`));
      }
      return;
    }
    need(typeof f.field === "string" && VALUE_FIELDS.has(f.field), `${at}: 지원 여부를 확인하지 못한 field '${String(f.field)}'`);
    need(ALLOWED_OPERATORS.has(f.operator), `${at}: 지원하지 않는 filter operator '${String(f.operator)}'`);
    need(Object.hasOwn(f, "value"), `${at}: filter value가 필요합니다.`);
  };
  for (const [i, s] of (def.steps ?? []).entries()) {
    const at = `steps[${i}]`;
    need(object(s), `${at}: step은 객체여야 합니다.`); if (!object(s)) continue;
    need(ALLOWED_OPS.has(s.op), `${at}: 지원하지 않는 op '${String(s.op)}'`);
    if (REQUIRED_FIELDS[s.op]) for (const k of REQUIRED_FIELDS[s.op]) need(Object.hasOwn(s, k), `${at}: ${s.op}에 ${k}가 필요합니다.`);
    if (s.when) checkCondition(s.when, `${at}.when`);
    if (s.filter) checkFilter(s.filter, `${at}.filter`);
    if (s.op === "reveal_until_match" && s.match) checkFilter(s.match, `${at}.match`);
    if (s.op === "select_cards") {
      need(Number.isInteger(s.min) && s.min >= 0, `${at}: min은 0 이상의 정수여야 합니다.`);
      need(Number.isInteger(s.max) && s.max >= s.min && s.max <= 30, `${at}: max가 유효하지 않습니다.`);
    }
    if (["move_cards", "reveal_cards", "move_unselected_to_deck_bottom", "move_unselected_to_zone", "attach_cards", "modify_stat", "filter_cards"].includes(s.op)) {
      if (typeof s.from === "string" && !ZONES.has(s.from)) need(vars.has(variableRoot(s.from)), `${at}: from 변수 '${s.from}'가 앞 단계에서 정의되지 않았습니다.`);
    }
    if (["move_unselected_to_deck_bottom", "move_unselected_to_zone"].includes(s.op)) need(vars.has(variableRoot(s.selectedVariable)), `${at}: selectedVariable가 앞 단계에서 정의되지 않았습니다.`);
    if (s.op === "pay_cost" && !["sleep_source_character", "sleep_selected_character"].includes(s.cost)) need(false, `${at}: 지원하지 않는 cost '${String(s.cost)}'`);
    if (s.op === "modify_stat" && s.duration !== "turn_end") need(false, `${at}: modify_stat은 현재 turn_end만 지원합니다.`);
    if (s.op === "grant_keyword" && s.duration !== "turn_end") need(false, `${at}: grant_keyword는 현재 turn_end만 지원합니다.`);
    if (s.op === "set_continuous_stat" && s.duration !== "while_condition_true") need(false, `${at}: set_continuous_stat 지속 시간이 유효하지 않습니다.`);
    if (s.op === "set_continuous_keyword" && s.duration !== "while_condition_true") need(false, `${at}: set_continuous_keyword 지속 시간이 유효하지 않습니다.`);
    if (typeof s.saveAs === "string" && s.saveAs) vars.add(s.saveAs);
  }
  return errors;
}

export function validateDraftBatch(batch, knownFacts = new Set()) {
  const errors = [];
  if (!object(batch)) return ["초안 파일의 최상위 값은 객체여야 합니다."];
  if (batch.artifactType !== "conan-card-effect-draft-batch") errors.push("artifactType이 올바르지 않습니다.");
  if (!Array.isArray(batch.cards)) errors.push("cards 배열이 필요합니다.");

  // A model must never be asked to infer basic card identity or reconstruct missing source text.
  // Blank ability/hirameki/cut-in fields are allowed when that card simply has no such section,
  // but each field must exist and sourceText must faithfully combine the non-empty sections.
  const requiredCardFields = [
    "sourceKey", "databaseId", "cardKey", "internalCardId", "nameKo",
    "typeKo", "colorKo", "rarityKo", "abilityKo", "hirameki", "cutIn", "sourceText",
  ];
  const requiredNonEmptyCardFields = [
    "sourceKey", "databaseId", "cardKey", "internalCardId",
    "nameKo", "typeKo", "colorKo", "rarityKo",
  ];
  const sourceKeys = new Set();
  const candidateIds = new Set();
  for (const [i, card] of (batch.cards || []).entries()) {
    const at = `cards[${i}]`;
    if (!object(card)) { errors.push(`${at}: 카드 객체가 아닙니다.`); continue; }

    for (const field of requiredCardFields) {
      if (!Object.prototype.hasOwnProperty.call(card, field) || card[field] === null || card[field] === undefined) {
        errors.push(`${at}: 기본 카드 필드 ${field}가 누락되었습니다.`);
      }
    }
    for (const field of requiredNonEmptyCardFields) {
      if (typeof card[field] !== "string" || !card[field].trim()) {
        errors.push(`${at}: 기본 카드 필드 ${field} 값이 비어 있습니다.`);
      }
    }
    const expectedSourceText = [card.abilityKo, card.hirameki, card.cutIn]
      .filter((section) => typeof section === "string" && section.trim())
      .join("\n");
    if (typeof card.sourceText === "string" && card.sourceText !== expectedSourceText) {
      errors.push(`${at}: sourceText가 abilityKo/hirameki/cutIn 원문을 정확히 반영하지 않습니다.`);
    }

    if (!card.sourceKey) errors.push(`${at}: sourceKey가 필요합니다.`);
    if (sourceKeys.has(card.sourceKey)) errors.push(`${at}: sourceKey 중복 ${card.sourceKey}`);
    sourceKeys.add(card.sourceKey);
    if (!Array.isArray(card.effectCandidates)) { errors.push(`${at}: effectCandidates 배열이 필요합니다.`); continue; }
    for (const [j, c] of card.effectCandidates.entries()) {
      const loc = `${at}.effectCandidates[${j}]`;
      if (!c?.candidateId) errors.push(`${loc}: candidateId가 필요합니다.`);
      if (candidateIds.has(c?.candidateId)) errors.push(`${loc}: candidateId 중복 ${c.candidateId}`);
      candidateIds.add(c?.candidateId);
      if (!c?.draftStatus) errors.push(`${loc}: draftStatus가 필요합니다.`);
      if (!c?.approvalStatus) errors.push(`${loc}: approvalStatus가 필요합니다.`);
      if (c?.manualInterpretationLocked === true && !c?.proposedDefinition) {
        errors.push(`${loc}: 수동 검토 잠금 후보에 proposedDefinition이 없습니다.`);
      }
      if (!c?.proposedDefinition) continue;
      const de = validateDslDefinition(c.proposedDefinition, card.internalCardId, knownFacts);
      c.structuralValidation = { status: de.length ? "failed" : "passed", errors: de };
      c.approvalStatus = c.approvalStatus || "pending";
      if (de.length) c.draftStatus = "review_required";
      else if (c.draftStatus === "draft_candidate") c.draftStatus = "dsl_valid_pending_human_review";
    }
  }

  if (batch.dataReadinessAudit && Array.isArray(batch.cards)) {
    const sourceCandidateCount = batch.cards.reduce((sum, card) => sum + (card.effectCandidates?.length || 0), 0);
    if (batch.dataReadinessAudit.cardCount !== batch.cards.length) errors.push("dataReadinessAudit.cardCount가 실제 카드 수와 다릅니다.");
    if (batch.dataReadinessAudit.effectCandidateCount !== sourceCandidateCount) errors.push("dataReadinessAudit.effectCandidateCount가 실제 후보 수와 다릅니다.");
  }
  return errors;
}
