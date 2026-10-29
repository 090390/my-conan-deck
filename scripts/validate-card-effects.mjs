import { readFile } from "node:fs/promises";

const path = new URL("../supabase/seed/card_effect_definitions.json", import.meta.url);
const data = JSON.parse(await readFile(path, "utf8"));

const allowedEvents = new Set([
  "character.entered_field",
  "character.removed_from_field",
  "character.activated_ability",
  "character.acted",
  "player.turn_ended",
  "continuous.recalculate",
  "event.played",
  "opponent.deduction.declared",
  "character.disguised", "character.contact_removed_opponent", "character.contact_started",
  "case.solution_entered", "case.activated_ability", "evidence.card_removed",
]);
const allowedOperators = new Set([
  "equals", "not_equals", "in", "less_than", "less_than_or_equal", "greater_than",
  "greater_than_or_equal", "has_keyword", "has_trait", "name_matches",
]);
const allowedOps = new Set([
  "refill_deck_from_remove_area", "peek_top_cards", "select_cards", "reveal_cards",
  "move_cards", "move_unselected_to_deck_bottom", "move_unselected_to_zone", "filter_cards",
  "reveal_until_match", "attach_cards", "grant_keyword", "modify_stat",
  "offer_reaction", "pay_cost", "set_mislead_value", "draw_cards", "gain_evidence",
  "ready_cards_that_used_keyword", "mark_keyword_activated", "shuffle_deck",
  "set_continuous_stat", "set_continuous_keyword",
  "rest_cards", "ready_source_character", "schedule_move_to_deck_bottom",
  "attach_top_card", "flip_evidence", "win_game", "start_contact",
  "modify_contact_ap", "grant_bond_alias",
]);
const zoneNames = new Set([
  "deck", "hand", "field", "opponent_field", "remove_area", "evidence_area", "partner_area",
  "source_character", "deck_bottom", "both_fields", "opponent_hand", "attached_cards",
]);
const errors = [];
const need = (ok, message) => { if (!ok) errors.push(message); };
const isObject = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const has = (obj, fields) => fields.every((field) => Object.hasOwn(obj, field));
const variableRoot = (ref) => typeof ref === "string" ? ref.split(".")[0] : "";

function checkCondition(condition, location) {
  need(isObject(condition), `${location}: condition은 객체여야 합니다.`);
  if (!isObject(condition)) return;
  need(typeof condition.fact === "string" && condition.fact.length > 0, `${location}: fact가 필요합니다.`);
  need(allowedOperators.has(condition.operator), `${location}: 지원하지 않는 operator ${String(condition.operator)}`);
  need(Object.hasOwn(condition, "value"), `${location}: value가 필요합니다.`);
  if (condition.operator === "in") need(Array.isArray(condition.value), `${location}: in의 value는 배열이어야 합니다.`);
  if (condition.operator === "has_keyword" || condition.operator === "has_trait" || condition.operator === "name_matches") {
    need(typeof condition.value === "string" && condition.value.length > 0, `${location}: ${condition.operator}의 value는 문자열이어야 합니다.`);
  }
}

function checkFilter(filter, location) {
  need(isObject(filter), `${location}: filter는 객체여야 합니다.`);
  if (!isObject(filter)) return;
  if (filter.allOf !== undefined) {
    need(Array.isArray(filter.allOf) && filter.allOf.length > 0, `${location}.allOf는 비어 있지 않은 배열이어야 합니다.`);
    for (const [i, part] of (filter.allOf ?? []).entries()) checkFilter(part, `${location}.allOf[${i}]`);
    return;
  }
  if (filter.anyOf !== undefined) {
    need(Array.isArray(filter.anyOf) && filter.anyOf.length > 0, `${location}.anyOf는 비어 있지 않은 배열이어야 합니다.`);
    for (const [i, part] of (filter.anyOf ?? []).entries()) checkFilter(part, `${location}.anyOf[${i}]`);
    return;
  }
  need(typeof filter.field === "string", `${location}: field가 필요합니다.`);
  need(allowedOperators.has(filter.operator), `${location}: 지원하지 않는 filter operator ${String(filter.operator)}`);
  need(Object.hasOwn(filter, "value"), `${location}: value가 필요합니다.`);
}

function checkStep(step, location, vars, def) {
  need(isObject(step), `${location}: step은 객체여야 합니다.`);
  if (!isObject(step)) return;
  need(allowedOps.has(step.op), `${location}: 지원하지 않는 op ${String(step.op)}`);
  if (step.when !== undefined) checkCondition(step.when, `${location}.when`);

  const required = {
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
    set_continuous_stat: ["target", "stat", "amount", "modifierId", "duration"],
    set_continuous_keyword: ["target", "keyword", "modifierId", "duration"],
    rest_cards: ["target"],
    ready_source_character: [],
    schedule_move_to_deck_bottom: ["target"],
    attach_top_card: ["target"],
    flip_evidence: ["count"],
    win_game: [],
    start_contact: ["target", "allowActiveTarget", "allowNewlyPlayed"],
    modify_contact_ap: ["amount"],
    grant_bond_alias: ["target", "name", "duration"],
  };
  if (required[step.op]) need(has(step, required[step.op]), `${location}: ${step.op}의 필수 필드(${required[step.op].join(", ")})가 빠졌습니다.`);

  if (step.op === "filter_cards") {
    if (typeof step.from === "string" && !zoneNames.has(step.from)) {
      need(vars.has(variableRoot(step.from)), `${location}: 필터 출처 변수 '${step.from}'가 앞 단계에 정의되지 않았습니다.`);
    }
    checkFilter(step.filter, `${location}.filter`);
  }

  if (step.op === "select_cards") {
    need(Number.isInteger(step.min) && step.min >= 0, `${location}: min은 0 이상의 정수여야 합니다.`);
    need(Number.isInteger(step.max) && step.max >= step.min, `${location}: max는 min 이상의 정수여야 합니다.`);
    need(step.max <= 30, `${location}: max는 30을 넘을 수 없습니다.`);
    if (typeof step.from === "string" && !zoneNames.has(step.from)) {
      need(vars.has(variableRoot(step.from)), `${location}: 선택 출처 변수 '${step.from}'가 앞 단계에 정의되지 않았습니다.`);
    }
    if (step.filter) checkFilter(step.filter, `${location}.filter`);
    if (step.uniqueBy !== undefined) need(step.uniqueBy === "card_name", `${location}: 현재 uniqueBy는 card_name만 지원합니다.`);
  }

  if (["reveal_cards", "move_cards", "move_unselected_to_deck_bottom", "move_unselected_to_zone", "attach_cards", "modify_stat"].includes(step.op)) {
    if (typeof step.from === "string" && !zoneNames.has(step.from)) {
      need(vars.has(variableRoot(step.from)), `${location}: 출처 변수 '${step.from}'가 앞 단계에 정의되지 않았습니다.`);
    }
    if (step.op === "move_unselected_to_deck_bottom" || step.op === "move_unselected_to_zone") {
      need(vars.has(variableRoot(step.selectedVariable)), `${location}: 선택 변수 '${step.selectedVariable}'가 앞 단계에 정의되지 않았습니다.`);
    }
  }

  if (step.op === "reveal_until_match") checkFilter(step.match, `${location}.match`);
  if (step.op === "refill_deck_from_remove_area") need(step.shuffle === true, `${location}: refill은 반드시 섞어야 합니다.`);
  if (step.op === "offer_reaction") need(Array.isArray(step.choices) && step.choices.length >= 2, `${location}: 반응 choices가 필요합니다.`);
  if (step.op === "grant_keyword") need(step.duration === "turn_end", `${location}: 현재 grant_keyword는 turn_end 지속만 지원합니다.`);
  if (step.op === "grant_bond_alias") need(step.duration === "turn_end", `${location}: grant_bond_alias는 turn_end 지속이어야 합니다.`);
  if (step.op === "modify_stat") {
    need(step.duration === "turn_end", `${location}: 현재 modify_stat은 turn_end만 지원합니다.`);
    need(Number.isInteger(step.amount) && step.amount !== 0, `${location}: amount는 0이 아닌 정수여야 합니다.`);
  }
  if (step.op === "set_mislead_value") need(Number.isInteger(step.value) && step.value >= 0 && step.value <= 3 && step.duration === "while_in_field", `${location}: 미스리드는 0~3의 정수이며 while_in_field 지속이어야 합니다.`);
  if (step.op === "draw_cards" || step.op === "gain_evidence") {
    need(Number.isInteger(step.count) && step.count > 0 && step.count <= 10, `${location}: count는 1~10 정수여야 합니다.`);
  }
  if (step.op === "set_continuous_stat") need(step.duration === "while_condition_true" && Number.isInteger(step.amount), `${location}: continuous stat 정의가 올바르지 않습니다.`);
  if (step.op === "set_continuous_keyword") need(step.duration === "while_condition_true", `${location}: continuous keyword 정의가 올바르지 않습니다.`);
  if (step.op === "ready_cards_that_used_keyword") need(step.turn === "ending_turn", `${location}: turn은 ending_turn이어야 합니다.`);
  if (step.op === "move_unselected_to_deck_bottom") need(step.order === "player_choice", `${location}: order는 player_choice여야 합니다.`);
  if (step.op === "move_unselected_to_zone") need(["preserve", "player_choice"].includes(step.order), `${location}: 지원하지 않는 order입니다.`);
  if (step.op === "pay_cost") need([
    "sleep_source_character", "sleep_selected_character",
  ].includes(step.cost), `${location}: 지원하지 않는 cost ${String(step.cost)}`);

  if (typeof step.saveAs === "string" && step.saveAs.trim()) vars.add(step.saveAs);
  if (step.op === "reveal_until_match" && typeof step.saveAs === "string") vars.add(step.saveAs);
}

need(data.schemaVersion === 1, "schemaVersion은 1이어야 합니다.");
need(data.language === "conan-card-effect-dsl", "language 값이 올바르지 않습니다.");
need(Array.isArray(data.definitions) && data.definitions.length > 0, "definitions 배열이 필요합니다.");

const effectIds = new Set();
for (const [index, def] of (data.definitions ?? []).entries()) {
  const loc = `definitions[${index}]`;
  need(isObject(def), `${loc}: 정의가 객체가 아닙니다.`);
  if (!isObject(def)) continue;
  need(typeof def.effectId === "string" && def.effectId.length > 0, `${loc}: effectId가 필요합니다.`);
  if (def.effectId) {
    need(!effectIds.has(def.effectId), `${loc}: 중복 effectId ${def.effectId}`);
    effectIds.add(def.effectId);
  }
  need(Array.isArray(def.cardIds) && def.cardIds.length > 0 && def.cardIds.every((id) => typeof id === "string" && /^\d{4}$/.test(id)), `${loc}: cardIds는 네 자리 문자열 배열이어야 합니다.`);
  need(isObject(def.trigger) && allowedEvents.has(def.trigger.event), `${loc}: 지원하지 않는 trigger.event ${String(def.trigger?.event)}`);
  need(isObject(def.trigger) && typeof def.trigger.timing === "string", `${loc}: trigger.timing이 필요합니다.`);
  need(Array.isArray(def.conditions ?? []), `${loc}: conditions는 배열이어야 합니다.`);
  for (const [ci, condition] of (def.conditions ?? []).entries()) checkCondition(condition, `${loc}.conditions[${ci}]`);
  need(Array.isArray(def.steps) && def.steps.length > 0, `${loc}: steps 배열이 필요합니다.`);
  if (def.continuous) need(def.trigger.event === "continuous.recalculate", `${loc}: continuous 정의는 continuous.recalculate여야 합니다.`);
  const vars = new Set();
  for (const [si, step] of (def.steps ?? []).entries()) checkStep(step, `${loc}.steps[${si}]`, vars, def);
  if (def.oncePerTurn !== undefined) need(typeof def.oncePerTurn === "boolean", `${loc}: oncePerTurn은 boolean이어야 합니다.`);
}

if (errors.length) {
  console.error(`카드 효과 정의 검증 실패 (${errors.length}건):\n- ${errors.join("\n- ")}`);
  process.exitCode = 1;
} else {
  console.log(`카드 효과 정의 검증 완료: ${data.definitions.length}개 정의, ${[...effectIds].length}개 고유 effectId.`);
}
