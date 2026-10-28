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
    name: String(card?.name || card?.originalName || card?.cardId || key),
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
function resolvePublicDeckCard(cards, entry) {
  if (entry == null || entry === "") return null;
  const raw = typeof entry === "object" ? entry : { key: entry };
  const directKey = String(raw.key ?? raw.id ?? "");
  if (directKey) {
    const direct = cards.find((card) => String(card.key) === directKey);
    if (direct) return direct;
  }
  const fields = ["cardNum", "card_num", "databaseId", "database_id", "cardId", "card_id", "key", "id"];
  for (const field of fields) {
    const wanted = String(raw[field] ?? "").trim().toLocaleUpperCase();
    if (!wanted) continue;
    const found = cards.find((card) => [card[field], card.cardNum, card.databaseId, card.cardId, card.key, card.id]
      .some((value) => String(value ?? "").trim().toLocaleUpperCase() === wanted));
    if (found) return found;
  }
  if (raw.name) return cards.find((card) => String(card.name ?? "") === String(raw.name)) || null;
  return null;
}
function preparePublicDeck(cards, item) {
  const source = item?.deck_json;
  const entries = Array.isArray(source?.mainDeck) ? source.mainDeck
    : Array.isArray(source?.main_deck) ? source.main_deck : null;
  if (!entries) throw new Error(`공개 덱 ‘${item?.deck_name || "이름 없는 덱"}’에서 메인 덱 목록을 읽지 못했습니다.`);

  const event = resolvePublicDeckCard(cards, source.event ?? source.eventId ?? source.event_id);
  const partner = resolvePublicDeckCard(cards, source.partner ?? source.partnerId ?? source.partner_id);
  if (!event || !partner) {
    throw new Error(`공개 덱 ‘${item?.deck_name || "이름 없는 덱"}’의 파트너 또는 사건 카드를 현재 카드 데이터에서 찾지 못했습니다.`);
  }

  // 공개 저장소에 등록된 덱의 특이한 구성과 예외는 그대로 존중합니다.
  // 색상/동일 카드 장수/덱 구성 규칙에 대한 별도 사전 심사는 하지 않습니다.
  const mainDeck = entries.map((entry) => {
    const count = Math.floor(Number(entry?.count) || 0);
    if (count <= 0) return null;
    const card = resolvePublicDeckCard(cards, entry);
    if (!card) {
      throw new Error(`공개 덱 ‘${item?.deck_name || "이름 없는 덱"}’의 카드 ‘${entry?.name || entry?.key || "알 수 없는 카드"}’를 현재 카드 데이터에서 찾지 못했습니다.`);
    }
    return cardPayload(card, card.key, count);
  }).filter(Boolean);

  return {
    main_deck: mainDeck,
    partner_key: String(partner.key),
    event_key: String(event.key),
    event_rule_code: getEventRuleCode(event, event.key),
    deck_name: String(item.deck_name || "이름 없는 공개 덱"),
    composer_name: String(item.composer_name || ""),
  };
}
async function pickRandomPublicDeck(cards) {
  const { data, error } = await supabase.from("public_deck_library")
    .select("id, deck_name, composer_name, deck_json, created_at")
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw new Error(`공개 덱 저장소를 불러오지 못했습니다: ${error.message}`);
  if (!Array.isArray(data) || data.length === 0) {
    throw new Error("공개 덱 저장소에 등록된 덱이 없습니다. 먼저 덱을 공개 업로드해 주세요.");
  }
  // Choose first; do not pre-filter by competitive legality or special-case deck construction.
  const picked = data[Math.floor(Math.random() * data.length)];
  return preparePublicDeck(cards, picked);
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
      const event = cards.find((card) => String(card.key) === String(eventId));
      if (!event || !isEvent(event)) throw new Error("선택한 사건 카드를 확인할 수 없습니다.");
      const humanDeck = buildHumanDeck(deck, cards);
      const aiDeck = await pickRandomPublicDeck(cards);
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
      setNotice(`공개 덱 저장소에서 ‘${aiDeck.deck_name}’ 덱을 무작위로 선택했습니다.`);
      await onStarted?.({ roomId: data.room_id, inviteCode: data.invite_code, userId: session?.user?.id, aiDeckName: aiDeck.deck_name, aiDeckComposer: aiDeck.composer_name, initialAiMessage: data.initial_ai?.message || "" });
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
            내 덱으로 AI 탐정과 별도 대전을 시작합니다. AI는 공개 덱 저장소에 등록된 덱 하나를 무작위로 사용합니다.
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
        <span style={{ color: "#74839a", fontSize: 11 }}>AI는 공개 덱 저장소의 덱을 무작위로 선택합니다.</span>
      </div>
      {notice && <p role="status" style={{ color: "#86efac", marginTop: 13, fontSize: 12 }}>{notice}</p>}
      {error && <p role="alert" style={{ color: "#fda4af", marginTop: 13, fontSize: 12, overflowWrap: "anywhere" }}>{error}</p>}
    </section>
  );
}
