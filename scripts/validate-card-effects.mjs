import { readFile } from "node:fs/promises";

const path = new URL("../supabase/seed/card_effect_definitions.json", import.meta.url);
const data = JSON.parse(await readFile(path, "utf8"));

// Keep this list aligned with the server-side private_card_effect_run_v1 allowlist.
const allowedEvents = new Set([
  "character.entered_field",
  "character.removed_from_field",
  "character.activated_ability",
  "character.acted",
  "character.contact_removed_opponent",
  "character.contact_started",
  "character.disguised",
  "player.turn_ended",
  "continuous.recalculate",
  "event.played",
  "event.resolved",
  "hand.card_revealed_for_cost",
  "opponent.deduction.declared",
  "case.solution_entered",
  "case.activated_ability",
  "evidence.card_removed",
]);

const allowedOperators = new Set([
  "equals", "not_equals", "in", "less_than", "less_than_or_equal", "greater_than",
  "greater_than_or_equal", "has_keyword", "has_trait", "name_matches",
]);

const allowedOps = new Set([
  "attach_cards", "attach_top_card", "calculate_hand_difference", "calculate_switch_count",
  "disable_original_abilities", "draw_cards", "filter_cards", "flip_evidence", "gain_evidence",
  "grant_bond_alias", "grant_contact_remove", "grant_keyword", "investigate_opponent_deck",
  "mark_keyword_activated", "modify_contact_ap", "modify_contact_target_level", "modify_lp",
  "modify_stat", "move_cards", "move_selected_to_deck_bottom", "move_source_to_faceup_evidence",
  "move_source_to_remove_area", "move_top_file_cards", "move_unselected_to_deck_bottom",
  "move_unselected_to_zone", "offer_reaction", "pay_cost", "peek_top_cards", "ready_cards",
  "ready_cards_that_used_keyword", "ready_source_character", "refill_deck_from_remove_area",
  "remove_all_contacting_characters", "remove_all_deck_and_refresh", "remove_all_field_characters",
  "remove_contact_target", "remove_top_deck_cards_and_refresh_excluding_source_if_empty",
  "remove_top_deck_cards_and_refresh_if_empty", "remove_top_evidence_silently", "rest_cards",
  "return_unselected_to_deck_top", "reveal_all_evidence", "reveal_cards", "reveal_opponent_hand",
  "reveal_until_match", "schedule_move_to_deck_bottom", "select_cards", "select_trait",
  "set_continuous_keyword", "set_continuous_stat", "set_mislead_value", "set_next_hint_disabled",
  "set_turn_flag", "shuffle_deck", "start_contact", "stun_action_character", "stun_cards", "win_game",
]);

const zoneNames = new Set([
  "deck", "hand", "field", "opponent_field", "remove_area", "evidence_area", "opponent_evidence",
  "partner_area", "source_character", "deck_bottom", "both_fields", "opponent_hand",
  "attached_cards", "hand_or_attachment", "opponent_remove_area", "heiji_green_police_attachments",
]);

const errors = [];
const need = (ok, message) => { if (!ok) errors.push(message); };
const isObject = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const has = (obj, fields) => fields.every((field) => Object.hasOwn(obj, field));
const variableRoot = (ref) => {
  if (typeof ref !== "string") return "";
  return ref.startsWith("vars.") ? ref.slice(5).split(".")[0] : ref.split(".")[0];
};

function checkCondition(condition, location) {
  need(isObject(condition), location + ": condition은 객체여야 합니다.");
  if (!isObject(condition)) return;
  if (condition.allOf !== undefined || condition.anyOf !== undefined) {
    for (const branch of ["allOf", "anyOf"]) if (condition[branch] !== undefined) {
      need(Array.isArray(condition[branch]) && condition[branch].length > 0, location + "." + branch + "는 비어 있지 않은 배열이어야 합니다.");
      for (const [i, part] of (condition[branch] ?? []).entries()) checkCondition(part, location + "." + branch + "[" + i + "]");
    }
    return;
  }
  if (condition.not !== undefined) {
    checkCondition(condition.not, location + ".not");
    return;
  }
  need(typeof condition.fact === "string" && condition.fact.length > 0, location + ": fact가 필요합니다.");
  need(allowedOperators.has(condition.operator), location + ": 지원하지 않는 operator " + String(condition.operator));
  need(Object.hasOwn(condition, "value"), location + ": value가 필요합니다.");
  if (condition.operator === "in") need(Array.isArray(condition.value), location + ": in의 value는 배열이어야 합니다.");
  if (["has_keyword", "has_trait", "name_matches"].includes(condition.operator)) {
    need(typeof condition.value === "string" && condition.value.length > 0, location + ": " + condition.operator + "의 value는 문자열이어야 합니다.");
  }
}

function checkFilter(filter, location) {
  need(isObject(filter), location + ": filter는 객체여야 합니다.");
  if (!isObject(filter)) return;
  for (const branch of ["allOf", "anyOf"]) if (filter[branch] !== undefined) {
    need(Array.isArray(filter[branch]) && filter[branch].length > 0, location + "." + branch + "는 비어 있지 않은 배열이어야 합니다.");
    for (const [i, part] of (filter[branch] ?? []).entries()) checkFilter(part, location + "." + branch + "[" + i + "]");
  }
  if (filter.not !== undefined) checkFilter(filter.not, location + ".not");
  if (filter.allOf !== undefined || filter.anyOf !== undefined || filter.not !== undefined) return;
  need(typeof filter.field === "string", location + ": field가 필요합니다.");
  need(allowedOperators.has(filter.operator), location + ": 지원하지 않는 filter operator " + String(filter.operator));
  need(Object.hasOwn(filter, "value"), location + ": value가 필요합니다.");
}

function checkVariableReference(ref, vars, location, label) {
  if (typeof ref !== "string" || zoneNames.has(ref)) return;
  const root = variableRoot(ref);
  need(vars.has(root), location + ": " + label + " 변수 '" + ref + "'가 앞 단계에 정의되지 않았습니다.");
}

function checkStep(step, location, vars) {
  need(isObject(step), location + ": step은 객체여야 합니다.");
  if (!isObject(step)) return;
  need(allowedOps.has(step.op), location + ": 지원하지 않는 op " + String(step.op));
  if (step.when !== undefined) checkCondition(step.when, location + ".when");

  // Fields with defaults in the server runner are intentionally optional here.
  const required = {
    refill_deck_from_remove_area: ["includeRemainingDeck", "includeRemoveArea", "shuffle"],
    peek_top_cards: ["count", "saveAs"],
    select_cards: ["from", "saveAs"],
    reveal_cards: ["from", "to"],
    move_cards: ["from", "to"],
    filter_cards: ["from", "filter", "saveAs"],
    move_unselected_to_deck_bottom: ["from", "order"],
    move_unselected_to_zone: ["from", "to", "order"],
    reveal_until_match: ["from", "saveAs", "match"],
    attach_cards: ["from"],
    grant_keyword: ["target", "keyword", "duration"],
    modify_stat: ["target", "stat", "amount", "duration", "stacking"],
    offer_reaction: ["choices", "saveAs"],
    pay_cost: ["cost"],
    set_mislead_value: ["target", "value", "duration"],
    gain_evidence: ["count"],
    ready_cards_that_used_keyword: ["keyword", "turn", "includePartnerArea"],
    mark_keyword_activated: ["keyword"],
    set_continuous_stat: ["stat", "amount"],
    set_continuous_keyword: ["keyword"],
    rest_cards: ["target"],
    ready_cards: ["target"],
    schedule_move_to_deck_bottom: ["target"],
    attach_top_card: ["target"],
    flip_evidence: ["count"],
    start_contact: ["target", "allowActiveTarget", "allowNewlyPlayed"],
    modify_contact_ap: ["amount"],
    modify_contact_target_level: ["amount"],
    grant_bond_alias: ["target", "name", "duration"],
    grant_contact_remove: ["target"],
    stun_cards: ["target"],
    disable_original_abilities: ["target"],
    set_turn_flag: ["key"],
    remove_top_deck_cards_and_refresh_excluding_source_if_empty: ["count"],
    remove_top_deck_cards_and_refresh_if_empty: ["count"],
  };
  if (required[step.op]) {
    need(has(step, required[step.op]), location + ": " + step.op + "의 필수 필드(" + required[step.op].join(", ") + ")가 빠졌습니다.");
  }

  if (step.op === "select_cards") {
    const hasMin = Number.isInteger(step.min) && step.min >= 0;
    const hasMax = Number.isInteger(step.max) && step.max >= 0;
    const hasMinFrom = typeof step.minFrom === "string" && step.minFrom.startsWith("vars.");
    const hasMaxFrom = typeof step.maxFrom === "string" && step.maxFrom.startsWith("vars.");
    need(hasMin || hasMinFrom, location + ": min 또는 minFrom이 필요합니다.");
    need(hasMax || hasMaxFrom, location + ": max 또는 maxFrom이 필요합니다.");
    if (hasMin && hasMax) need(step.max >= step.min, location + ": max는 min 이상의 정수여야 합니다.");
    if (hasMax) need(step.max <= 100, location + ": max는 100을 넘을 수 없습니다.");
    if (step.minFrom) checkVariableReference(step.minFrom, vars, location, "minFrom");
    if (step.maxFrom) checkVariableReference(step.maxFrom, vars, location, "maxFrom");
    checkVariableReference(step.from, vars, location, "선택 출처");
    if (step.filter) checkFilter(step.filter, location + ".filter");
    if (step.uniqueBy !== undefined) need(["card_name", "level"].includes(step.uniqueBy), location + ": 지원하지 않는 uniqueBy " + String(step.uniqueBy));
  }

  if (step.op === "filter_cards") {
    checkVariableReference(step.from, vars, location, "필터 출처");
    checkFilter(step.filter, location + ".filter");
  }

  if (["reveal_cards", "move_cards", "move_unselected_to_deck_bottom", "move_unselected_to_zone", "return_unselected_to_deck_top", "attach_cards", "modify_stat"].includes(step.op)) {
    if (step.from !== undefined) checkVariableReference(step.from, vars, location, "출처");
    if (["move_unselected_to_deck_bottom", "move_unselected_to_zone", "return_unselected_to_deck_top"].includes(step.op)) {
      const selected = Array.isArray(step.selectedVariables)
        ? step.selectedVariables
        : (typeof step.selectedVariable === "string" ? [step.selectedVariable] : []);
      need(selected.length > 0, location + ": selectedVariable 또는 selectedVariables가 필요합니다.");
      for (const name of selected) checkVariableReference(name, vars, location, "선택");
    }
  }

  if (step.op === "reveal_until_match") checkFilter(step.match, location + ".match");
  if (step.op === "refill_deck_from_remove_area") need(step.shuffle === true, location + ": refill은 반드시 섞어야 합니다.");
  if (step.op === "offer_reaction") need(Array.isArray(step.choices) && step.choices.length >= 2, location + ": 반응 choices가 필요합니다.");
  if (step.op === "grant_keyword") need(step.duration === "turn_end", location + ": 현재 grant_keyword는 turn_end 지속만 지원합니다.");
  if (step.op === "grant_bond_alias") need(step.duration === "turn_end", location + ": grant_bond_alias는 turn_end 지속이어야 합니다.");
  if (step.op === "modify_stat") {
    need(step.duration === "turn_end", location + ": 현재 modify_stat은 turn_end만 지원합니다.");
    need(Number.isInteger(step.amount) && step.amount !== 0, location + ": amount는 0이 아닌 정수여야 합니다.");
  }
  if (step.op === "set_mislead_value") need(Number.isInteger(step.value) && step.value >= 0 && step.value <= 3 && step.duration === "while_in_field", location + ": 미스리드는 0~3의 정수이며 while_in_field 지속이어야 합니다.");
  if (step.op === "draw_cards") {
    const hasStaticCount = Number.isInteger(step.count) && step.count >= 0 && step.count <= 100;
    const hasDynamicCount = typeof step.countFrom === "string" && step.countFrom.startsWith("vars.");
    need(hasStaticCount || hasDynamicCount, location + ": count는 0~100 정수이거나 countFrom이어야 합니다.");
    if (step.countFrom) checkVariableReference(step.countFrom, vars, location, "countFrom");
    need(typeof step.destination === "string" && step.destination.length > 0, location + ": destination이 필요합니다.");
  }
  if (step.op === "calculate_hand_difference") {
    need(["deficit", "excess"].includes(step.mode) && Number.isInteger(step.targetCount) && step.targetCount >= 0 && typeof step.saveAs === "string", location + ": calculate_hand_difference 구성이 올바르지 않습니다.");
  }
  if (step.op === "calculate_switch_count") {
    need(typeof step.saveAs === "string" && typeof step.deploymentVariable === "string", location + ": calculate_switch_count 구성이 올바르지 않습니다.");
    checkVariableReference(step.deploymentVariable, vars, location, "deploymentVariable");
  }
  if (step.op === "set_continuous_stat") {
    need(step.duration === undefined || step.duration === "while_condition_true", location + ": continuous stat duration이 올바르지 않습니다.");
    need(Number.isInteger(step.amount), location + ": continuous stat amount는 정수여야 합니다.");
  }
  if (step.op === "set_continuous_keyword") {
    need(step.duration === undefined || step.duration === "while_condition_true", location + ": continuous keyword duration이 올바르지 않습니다.");
  }
  if (step.op === "ready_cards_that_used_keyword") need(step.turn === "ending_turn", location + ": turn은 ending_turn이어야 합니다.");
  if (step.op === "move_unselected_to_deck_bottom") need(step.order === "player_choice", location + ": order는 player_choice여야 합니다.");
  if (step.op === "move_unselected_to_zone") need(["preserve", "player_choice"].includes(step.order), location + ": 지원하지 않는 order입니다.");
  if (step.op === "pay_cost") need([
    "sleep_source_character", "sleep_selected_character", "sleep_partner",
  ].includes(step.cost), location + ": 지원하지 않는 cost " + String(step.cost));
  if (step.op === "investigate_opponent_deck") {
    need(Number.isInteger(step.count) && step.count > 0 && step.count <= 30, location + ": investigate_opponent_deck count는 1~30이어야 합니다.");
    need(typeof step.saveAs === "string", location + ": investigate_opponent_deck saveAs가 필요합니다.");
    if (step.traitVariable) checkVariableReference(step.traitVariable, vars, location, "traitVariable");
  }
  if (step.op === "select_trait") need(typeof step.saveAs === "string", location + ": select_trait saveAs가 필요합니다.");
  if (step.op === "move_top_file_cards") {
    if (step.count !== undefined) need(Number.isInteger(step.count) && step.count >= 0 && step.count <= 100, location + ": move_top_file_cards count는 0~100이어야 합니다.");
  }

  if (typeof step.saveAs === "string" && step.saveAs.trim()) vars.add(step.saveAs);
  if (step.op === "reveal_until_match" && typeof step.saveAs === "string") vars.add(step.saveAs);
}

need(data.schemaVersion === 1, "schemaVersion은 1이어야 합니다.");
need(data.language === "conan-card-effect-dsl", "language 값이 올바르지 않습니다.");
need(Array.isArray(data.definitions) && data.definitions.length > 0, "definitions 배열이 필요합니다.");

const effectIds = new Set();
for (const [index, def] of (data.definitions ?? []).entries()) {
  const loc = "definitions[" + index + "]";
  need(isObject(def), loc + ": 정의가 객체가 아닙니다.");
  if (!isObject(def)) continue;
  need(typeof def.effectId === "string" && def.effectId.length > 0, loc + ": effectId가 필요합니다.");
  if (def.effectId) {
    need(!effectIds.has(def.effectId), loc + ": 중복 effectId " + def.effectId);
    effectIds.add(def.effectId);
  }
  need(Array.isArray(def.cardIds) && def.cardIds.length > 0 && def.cardIds.every((id) => typeof id === "string" && /^\d{4}$/.test(id)), loc + ": cardIds는 네 자리 문자열 배열이어야 합니다.");
  need(isObject(def.trigger) && allowedEvents.has(def.trigger.event), loc + ": 지원하지 않는 trigger.event " + String(def.trigger?.event));
  need(isObject(def.trigger) && typeof def.trigger.timing === "string", loc + ": trigger.timing이 필요합니다.");
  need(Array.isArray(def.conditions ?? []), loc + ": conditions는 배열이어야 합니다.");
  for (const [ci, condition] of (def.conditions ?? []).entries()) checkCondition(condition, loc + ".conditions[" + ci + "]");
  need(Array.isArray(def.steps) && def.steps.length > 0, loc + ": steps 배열이 필요합니다.");
  if (def.continuous) need(def.trigger?.event === "continuous.recalculate", loc + ": continuous 정의는 continuous.recalculate여야 합니다.");
  const vars = new Set();
  for (const [si, step] of (def.steps ?? []).entries()) checkStep(step, loc + ".steps[" + si + "]", vars);
  if (def.oncePerTurn !== undefined) need(typeof def.oncePerTurn === "boolean", loc + ": oncePerTurn은 boolean이어야 합니다.");
}

if (errors.length) {
  console.error("카드 효과 정의 검증 실패 (" + errors.length + "건):\n- " + errors.join("\n- "));
  process.exitCode = 1;
} else {
  console.log("카드 효과 정의 검증 완료: " + data.definitions.length + "개 정의, " + effectIds.size + "개 고유 effectId.");
}
