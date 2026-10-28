import { useState } from "react";
import { supabase } from "../lib/supabase";

function identity(card) {
  return String(card?.cardId ?? card?.sourceData?.card_id ?? card?.databaseId ?? card?.key ?? "")
    .trim().toLocaleUpperCase();
}
function normalizedId(card, fallback = "") {
  const values = [card?.key, card?.databaseId, card?.cardId, card?.cardNum, fallback,
    card?.sourceData?.id, card?.sourceData?.databaseId, card?.sourceData?.database_id,
    card?.sourceData?.cardId, card?.sourceData?.card_id, card?.sourceData?.cardNum, card?.sourceData?.card_num];
  return values.map((value) => String(value ?? "").trim().toLocaleUpperCase());
}
function exemptionId(card, fallback = "") {
  const ids = normalizedId(card, fallback).map((value) => /^\d+$/.test(value) ? String(Number(value)) : value);
  if (ids.includes("627")) return "0627";
  if (ids.includes("1039")) return "1039";
  return null;
}
function getEventRuleCode(card, fallback = "") {
  const ids = normalizedId(card, fallback);
  const normalized = ids.map((value) => /^\d+$/.test(value) ? String(Number(value)) : value);
  if (normalized.includes("1046")) return "culprits_1046";
  if (normalized.includes("1261") || normalized.includes("B11098") || normalized.includes("B11098P")) return "conan_vs_kid_1261";
  return "";
}
function getTraits(card) {
  const values = [card?.traits, card?.category1, card?.category2, card?.category3];
  return [...new Set(values.flatMap((value) => {
    if (Array.isArray(value)) return value.map((item) => String(item ?? "").trim()).filter(Boolean);
    if (value == null || String(value).trim() === "") return [];
    return String(value).split(/[、,，;；|｜]/u).map((item) => item.trim()).filter(Boolean);
  }))];
}
function isPartner(card) {
  return /パートナー|파트너/iu.test([card?.type, card?.originalType, card?.roleText].join(" "))
    || /^P\d+/iu.test(String(card?.cardId || ""));
}
function isEvent(card) {
  return /事件|사건|event/iu.test([card?.type, card?.originalType, card?.roleText].join(" "));
}
function isCharacter(card) {
  return /キャラ|character|캐릭터/iu.test([card?.type, card?.originalType, card?.roleText].join(" "))
    && !isPartner(card) && !isEvent(card);
}
function cardPayload(card, key, count) {
  const identityValue = identity(card) || String(key);
  const cutInText = String(card?.cutInEffect || "").trim();
  const cutInMatch = cutInText.normalize("NFKC").match(/AP\s*\+\s*(\d{1,5})/iu);
  const misleadSource = [...(card?.keywordTags || []), card?.ability || "", card?.originalAbility || ""].join(" ");
  const misleadMatch = misleadSource.match(/[【〚［\[]\s*(?:미스리드|ミスリード)\s*([0-9０-９]+)\s*[】〛］\]]/iu)
    || misleadSource.match(/[【〚［\[]\s*(?:미스리드|ミスリード)\s*[】〛］\]]\s*([0-9０-９]+)/iu)
    || misleadSource.match(/(?:미스리드|ミスリード)\s*([0-9０-９]+)/iu);
  const misleadValue = misleadMatch
    ? Math.max(0, Number(String(misleadMatch[1]).replace(/[０-９]/gu, (digit) => String.fromCharCode(digit.charCodeAt(0) - 0xFEE0))) || 0)
    : 0;
  return {
    key: String(key), count, limit_key: identityValue,
    card_type: isEvent(card) ? "event" : isCharacter(card) ? "character" : "other",
    copy_limit_exemption_id: exemptionId(card, key),
    card_id: String(card?.cardId || card?.sourceData?.card_id || ""),
    card_num: String(card?.cardNum || card?.sourceData?.card_num || ""),
    database_id: String(card?.databaseId || card?.sourceData?.database_id || key),
    traits: getTraits(card),
    category1: String(card?.category1 || ""),
    category2: String(card?.category2 || ""),
    category3: String(card?.category3 || ""),
    rarity: String(card?.rarity || card?.sourceData?.rarity || ""),
    cost: Math.max(0, Number(card?.cost) || 0),
    ap: Math.max(0, Number(card?.ap ?? card?.sourceData?.ap ?? card?.sourceData?.AP) || 0),
    lp: Math.max(0, Number(card?.lp ?? card?.sourceData?.lp ?? card?.sourceData?.LP) || 0),
    cut_in_bonus: cutInMatch ? Math.max(0, Number(cutInMatch[1]) || 0) : 0,
    cut_in_effect: cutInText,
    mislead_value: misleadValue,
    disguise_effect: String(card?.disguiseEffect || card?.hensoEffect || ""),
  };
}
function buildHumanDeck(deck, cards) {
  const byKey = new Map(cards.map((card) => [String(card.key), card]));
  return Object.entries(deck || {}).map(([key, rawCount]) => {
    const count = Math.floor(Number(rawCount) || 0);
    const card = byKey.get(String(key));
    if (!card || count <= 0) return null;
    return cardPayload(card, key, count);
  }).filter(Boolean);
}
function buildAiDeck(cards) {
  const characters = cards.filter((card) => isCharacter(card) && Number.isFinite(Number(card.cost)));
  const uncomplicated = characters.filter((card) => !String(card.ability || "").trim()
    && !String(card.hiramekiEffect || "").trim()
    && !String(card.cutInEffect || "").trim()
    && !String(card.disguiseEffect || card.hensoEffect || "").trim()
    && !(card.keywordTags || []).length);
  const source = uncomplicated.length >= 14 ? uncomplicated : characters.filter((card) =>
    !String(card.hiramekiEffect || "").trim()
    && !String(card.cutInEffect || "").trim()
    && !String(card.disguiseEffect || card.hensoEffect || "").trim());
  const unique = new Map();
  for (const card of source) {
    const cardIdentity = identity(card);
    if (!cardIdentity || unique.has(cardIdentity)) continue;
    unique.set(cardIdentity, card);
  }
  const candidateCards = [...unique.values()].sort((a, b) =>
    (Number(a.cost) || 99) - (Number(b.cost) || 99)
    || (Number(b.ap) || 0) - (Number(a.ap) || 0));
  if (candidateCards.length < 14) throw new Error("AI용으로 사용할 수 있는 단순 캐릭터 카드 14종을 찾지 못했습니다.");

  const chosen = candidateCards.slice(0, 14);
  const counts = new Map(chosen.map((card, index) => [String(card.key), index < 12 ? 3 : 2]));
  const mainDeck = chosen.map((card) => cardPayload(card, card.key, counts.get(String(card.key))));

  const partner = cards.filter((card) => isPartner(card)
    && !["MR", "MRP"].includes(String(card.rarity || "").toUpperCase()))
    .sort((a, b) => (Number(a.cost) || 0) - (Number(b.cost) || 0))[0];
  const events = cards.filter(isEvent).filter((card) => !getEventRuleCode(card))
    .sort((a, b) => String(a.name || "").localeCompare(String(b.name || ""), "ko"));
  const event = events[0] || cards.filter(isEvent)[0];
  if (!partner || !event) throw new Error("AI용 파트너 또는 사건 카드를 선택할 수 없습니다.");
  return {
    main_deck: mainDeck,
    partner_key: String(partner.key),
    event_key: String(event.key),
    event_rule_code: getEventRuleCode(event, event.key),
  };
}

const panelStyle = {
  boxSizing: "border-box", width: "100%", maxWidth: 820, margin: "0 auto 24px",
  padding: 22, border: "1px solid rgba(56,189,248,.24)", borderRadius: 16,
  background: "linear-gradient(145deg,#101827,#09111d)", color: "#e8edf7",
  boxShadow: "0 12px 36px rgba(0,0,0,.16)",
};
const buttonStyle = {
  border: "1px solid rgba(56,189,248,.35)", borderRadius: 9, padding: "10px 14px",
  background: "#164e63", color: "#f0f9ff", cursor: "pointer", fontSize: 13, fontWeight: 800,
};

export default function AIBattlePanel({ deck, partnerId, eventId, cards = [], ensureSignedIn, onStarted }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  async function startAIBattle() {
    if (loading) return;
    const deckTotal = Object.values(deck || {}).reduce((sum, value) => sum + Math.max(0, Math.floor(Number(value) || 0)), 0);
    if (deckTotal !== 40 || !partnerId || !eventId) {
      setError("AI 대전을 시작하려면 메인 덱 40장, 파트너 카드 1장, 사건 카드 1장을 먼저 선택해 주세요.");
      return;
    }
    setLoading(true);
    setError("");
    setNotice("");
    try {
      const session = await ensureSignedIn();
      const humanDeck = buildHumanDeck(deck, cards);
      const aiDeck = buildAiDeck(cards);
      const event = cards.find((card) => String(card.key) === String(eventId));
      const { data, error: invokeError } = await supabase.functions.invoke("ai-battle", {
        body: {
          action: "create",
          main_deck: humanDeck,
          partner_key: String(partnerId),
          event_key: String(eventId),
          event_rule_code: getEventRuleCode(event, eventId),
          ai_deck: aiDeck,
        },
      });
      if (invokeError) throw invokeError;
      if (!data?.room_id || !data?.invite_code) throw new Error(data?.error || "AI 대전 생성 결과를 확인할 수 없습니다.");
      setNotice("AI 대전용 방을 만들었습니다. AI가 첫 행동을 준비하고 있습니다.");
      await onStarted?.({ roomId: data.room_id, inviteCode: data.invite_code, userId: session?.user?.id });
    } catch (err) {
      setError(err?.message || "AI 대전을 시작하지 못했습니다.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <section style={panelStyle}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
        <div>
          <p style={{ margin: "0 0 5px", color: "#7dd3fc", fontSize: 10, fontWeight: 900, letterSpacing: ".18em" }}>AI BATTLE · EXPERIMENTAL</p>
          <h2 style={{ margin: 0, fontSize: 22, fontWeight: 850 }}>AI 대전</h2>
          <p style={{ color: "#9aa8bd", marginTop: 7, fontSize: 13, lineHeight: 1.7 }}>
            현재 내 덱과 파트너·사건 카드를 사용해 AI 탐정과 별도 대전을 시작합니다. 기본 행동 판단부터 시험하는 초기 버전입니다.
          </p>
        </div>
      </div>
      <div style={{ marginTop: 14, padding: 12, borderRadius: 9, border: "1px solid rgba(252,211,77,.24)", background: "rgba(161,98,7,.09)", color: "#fcd34d", fontSize: 11, lineHeight: 1.7 }}>
        ※ 현재 개발 중으로, 정상 동작하지 않습니다. 관리자의 검토를 위해 사이트에 통합되어 있을 뿐으로 일반 모의전을 원하는 분들께선 신경 쓰지 말아 주세요.
      </div>
      <div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 8, marginTop: 16 }}>
        <button type="button" style={{ ...buttonStyle, opacity: loading ? .6 : 1, cursor: loading ? "wait" : "pointer" }} disabled={loading} onClick={() => void startAIBattle()}>
          {loading ? "AI 대전 준비 중…" : "AI 대전 시작"}
        </button>
        <span style={{ color: "#74839a", fontSize: 11 }}>AI가 사용하는 덱은 단순한 캐릭터 카드 위주로 자동 구성됩니다.</span>
      </div>
      {notice && <p role="status" style={{ color: "#86efac", marginTop: 13, fontSize: 12 }}>{notice}</p>}
      {error && <p role="alert" style={{ color: "#fda4af", marginTop: 13, fontSize: 12, overflowWrap: "anywhere" }}>{error}</p>}
    </section>
  );
}
