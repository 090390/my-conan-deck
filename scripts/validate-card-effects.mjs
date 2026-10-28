import { readFile } from "node:fs/promises";

const path = new URL("../supabase/seed/card_effect_definitions.json", import.meta.url);
const data = JSON.parse(await readFile(path, "utf8"));

const allowedEvents = new Set([
  "character.entered_field",
  "opponent.deduction.declared",
]);
const allowedOperators = new Set([
  "equals",
  "in",
  "less_than",
  "greater_than",
  "greater_than_or_equal",
]);
const allowedOps = new Set([
  "refill_deck_from_remove_area",
  "peek_top_cards",
  "select_cards",
  "reveal_cards",
  "move_cards",
  "move_unselected_to_deck_bottom",
  "grant_keyword",
  "modify_stat",
  "offer_reaction",
  "pay_cost",
  "modify_lp",
]);

const errors = [];
const need = (ok, message) => { if (!ok) errors.push(message); };
const isObject = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const has = (obj, fields) => fields.every((field) => Object.hasOwn(obj, field));

function checkCondition(condition, location) {
  need(isObject(condition), `${location}: condition은 객체여야 합니다.`);
  if (!isObject(condition)) return;
  need(typeof condition.fact === "string" && condition.fact.length > 0, `${location}: fact가 필요합니다.`);
  need(allowedOperators.has(condition.operator), `${location}: 지원하지 않는 operator ${String(condition.operator)}`);
  need(Object.hasOwn(condition, "value"), `${location}: value가 필요합니다.`);
  if (condition.operator === "in") need(Array.isArray(condition.value), `${location}: in의 value는 배열이어야 합니다.`);
}

function checkStep(step, location, vars) {
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
    move_unselected_to_deck_bottom: ["from", "selectedVariable", "order"],
    grant_keyword: ["target", "keyword", "duration"],
    modify_stat: ["target", "stat", "amount", "duration", "stacking"],
    offer_reaction: ["reactionId", "actor", "choices", "saveAs"],
    pay_cost: ["cost"],
    modify_lp: ["target", "amount", "duration"],
  };
  if (required[step.op]) need(has(step, required[step.op]), `${location}: ${step.op}의 필수 필드(${required[step.op].join(", ")})가 빠졌습니다.`);

  if (step.op === "peek_top_cards" || step.op === "select_cards") {
    need(Number.isInteger(step.count ?? step.max), `${location}: count/max는 정수여야 합니다.`);
    if (step.op === "peek_top_cards") need(step.count > 0, `${location}: count는 1 이상이어야 합니다.`);
    if (step.op === "select_cards") {
      need(Number.isInteger(step.min) && step.min >= 0, `${location}: min은 0 이상의 정수여야 합니다.`);
      need(Number.isInteger(step.max) && step.max >= step.min, `${location}: max는 min 이상의 정수여야 합니다.`);
      const zones = new Set(["deck", "hand", "field", "remove_area", "evidence_area", "partner_area"]);
      if (typeof step.from === "string" && !zones.has(step.from)) {
        need(vars.has(step.from), `${location}: 선택 출처 변수 '${step.from}'가 앞 단계에 정의되지 않았습니다.`);
      }
      if (step.filter) need(isObject(step.filter) && typeof step.filter.field === "string" && allowedOperators.has(step.filter.operator) && Object.hasOwn(step.filter, "value"), `${location}: filter 형식이 올바르지 않습니다.`);
    }
  }

  if (step.op === "reveal_cards" || step.op === "move_cards" || step.op === "move_unselected_to_deck_bottom" || step.op === "modify_stat") {
    if (typeof step.from === "string" && !["deck", "hand", "field", "remove_area", "evidence_area", "partner_area"].includes(step.from)) {
      need(vars.has(step.from), `${location}: 출처 변수 '${step.from}'가 앞 단계에 정의되지 않았습니다.`);
    }
    if (step.op === "move_unselected_to_deck_bottom") {
      need(step.order === "player_choice", `${location}: order는 player_choice여야 합니다.`);
      need(vars.has(step.selectedVariable), `${location}: 선택 변수 '${step.selectedVariable}'가 앞 단계에 정의되지 않았습니다.`);
    }
  }

  if (step.op === "refill_deck_from_remove_area") {
    need(step.shuffle === true, `${location}: 리무브 에이리어에서 보충할 때 shuffle은 true여야 합니다.`);
  }
  if (step.op === "offer_reaction") need(Array.isArray(step.choices) && step.choices.length >= 2, `${location}: 반응 choices가 필요합니다.`);
  if (step.op === "grant_keyword") need(step.duration === "turn_end", `${location}: 현재는 turn_end 지속 키워드만 지원합니다.`);
  if (step.op === "modify_stat") {
    need(step.duration === "turn_end", `${location}: 현재는 turn_end 보정만 지원합니다.`);
    need(Number.isInteger(step.amount) && step.amount !== 0, `${location}: amount는 0이 아닌 정수여야 합니다.`);
  }
  if (step.op === "modify_lp") need(Number.isInteger(step.amount) && step.amount !== 0, `${location}: LP amount는 0이 아닌 정수여야 합니다.`);

  if (typeof step.saveAs === "string" && step.saveAs.trim()) vars.add(step.saveAs);
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
  need(Array.isArray(def.conditions), `${loc}: conditions는 배열이어야 합니다.`);
  for (const [ci, condition] of (def.conditions ?? []).entries()) checkCondition(condition, `${loc}.conditions[${ci}]`);
  need(Array.isArray(def.steps) && def.steps.length > 0, `${loc}: steps 배열이 필요합니다.`);
  const vars = new Set();
  for (const [si, step] of (def.steps ?? []).entries()) checkStep(step, `${loc}.steps[${si}]`, vars);
}

if (errors.length) {
  console.error(`카드 효과 정의 검증 실패 (${errors.length}건):\n- ${errors.join("\n- ")}`);
  process.exitCode = 1;
} else {
  console.log(`카드 효과 정의 검증 완료: ${data.definitions.length}개 정의, ${[...effectIds].length}개 고유 effectId.`);
}
