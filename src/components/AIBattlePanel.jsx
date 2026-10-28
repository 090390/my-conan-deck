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
function cardPayload(card, key, count, eventColorKey = "") {
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
    color: String(cardColorRaw(card) || ""),
    color_key: colorKey(card),
    event_color_key: String(eventColorKey || ""),
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
function buildHumanDeck(deck, cards, eventColorKey = "") {
  const byKey = new Map(cards.map((card) => [String(card.key), card]));
  return Object.entries(deck || {}).map(([key, rawCount]) => {
    const count = Math.floor(Number(rawCount) || 0);
    const card = byKey.get(String(key));
    if (!card || count <= 0) return null;
    return cardPayload(card, key, count, eventColorKey);
  }).filter(Boolean);
}
const COLOR_ORDER = ["청", "적", "황", "녹", "흑", "백"];
const COLOR_DEFINITIONS = [
  { tag: "청", aliases: ["청", "파랑", "파란색", "파랑색", "푸른색", "青色", "青", "ブルー", "blue"] },
  { tag: "적", aliases: ["적", "빨강", "빨간색", "빨강색", "赤色", "赤", "レッド", "red"] },
  { tag: "황", aliases: ["황", "노랑", "노란색", "노랑색", "黄色", "黄", "イエロー", "yellow"] },
  { tag: "녹", aliases: ["녹", "녹색", "초록", "초록색", "緑色", "緑", "グリーン", "green"] },
  { tag: "흑", aliases: ["흑", "검정", "검정색", "검은색", "黒色", "黒", "黑", "ブラック", "black"] },
  { tag: "백", aliases: ["백", "흰색", "하양", "하얀색", "白色", "白", "ホワイト", "white"] },
];
const COLOR_ALIASES = COLOR_DEFINITIONS
  .flatMap(({ tag, aliases }) => aliases.map((alias) => ({ tag, alias: alias.toLocaleLowerCase() })))
  .sort((a, b) => b.alias.length - a.alias.length);
function cardColorRaw(card) {
  return card?.color ?? card?.sourceData?.color ?? card?.sourceData?.colour ?? card?.raw?.color ?? "";
}
function colorKey(valueOrCard) {
  const raw = typeof valueOrCard === "object" && valueOrCard !== null
    ? cardColorRaw(valueOrCard) : valueOrCard;
  let remaining = String(raw ?? "").trim().toLocaleLowerCase()
    .replace(/[【】［］\[\]()（）]/gu, "")
    .replace(/[\s,，、/&＋+・·|｜]/gu, "");
  if (!remaining) return "";
  const tags = [];
  while (remaining) {
    const match = COLOR_ALIASES.find((entry) => remaining.startsWith(entry.alias));
    if (!match) return "";
    tags.push(match.tag);
    remaining = remaining.slice(match.alias.length);
  }
  const unique = new Set(tags);
  return COLOR_ORDER.filter((tag) => unique.has(tag)).join("");
}
function cardAllowedByEvent(card, eventColorKey) {
  const cardKey = colorKey(card);
  const allowed = new Set(String(eventColorKey || "").split(""));
  return Boolean(cardKey && allowed.size && [...cardKey].every((tag) => allowed.has(tag)));
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
  if (!entries) return null;
  const total = entries.reduce((sum, entry) => sum + Math.max(0, Math.floor(Number(entry?.count) || 0)), 0);
  if (total !== 40) return null;
  const event = resolvePublicDeckCard(cards, source.event ?? source.eventId ?? source.event_id);
  const partner = resolvePublicDeckCard(cards, source.partner ?? source.partnerId ?? source.partner_id);
  if (!event || !isEvent(event) || !partner || !isPartner(partner)) return null;
  const eventColorKey = colorKey(event);
  if (!eventColorKey) return null;
  const mainDeck = [];
  const copyCounts = new Map();
  for (const entry of entries) {
    const count = Math.max(0, Math.floor(Number(entry?.count) || 0));
    if (!count) continue;
    const card = resolvePublicDeckCard(cards, entry);
    if (!card || !cardAllowedByEvent(card, eventColorKey)) return null;
    const sameCardId = identity(card) || String(card.key);
    if (!exemptionId(card, card.key)) {
      const nextCount = (copyCounts.get(sameCardId) || 0) + count;
      if (nextCount > 3) return null;
      copyCounts.set(sameCardId, nextCount);
    }
    mainDeck.push(cardPayload(card, card.key, count, eventColorKey));
  }
  if (mainDeck.reduce((sum, card) => sum + card.count, 0) !== 40) return null;
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
  const candidates = (Array.isArray(data) ? data : [])
    .map((item) => ({ item, deck: preparePublicDeck(cards, item) }))
    .filter((entry) => entry.deck);
  if (!candidates.length) {
    throw new Error("공개 덱 저장소에서 사건 카드 색상과 맞는 40장 덱을 찾지 못했습니다. 합법적인 색상 구성의 덱을 먼저 업로드해 주세요.");
  }
  const picked = candidates[Math.floor(Math.random() * candidates.length)];
  return picked.deck;
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
      const eventColorKey = colorKey(event);
      if (!eventColorKey) throw new Error("선택한 사건 카드의 색상을 판독할 수 없습니다. 카드 데이터의 색상 표기를 확인해 주세요.");
      const humanDeck = buildHumanDeck(deck, cards, eventColorKey);
      const offColorCard = Object.entries(deck || {}).map(([key, rawCount]) => {
        const count = Math.max(0, Math.floor(Number(rawCount) || 0));
        return count > 0 ? cards.find((card) => String(card.key) === String(key)) : null;
      }).find((card) => card && !cardAllowedByEvent(card, eventColorKey));
      if (offColorCard) {
        throw new Error(`내 덱의 ‘${offColorCard.name || offColorCard.cardId || "카드"}’는 선택한 사건 카드의 색상(${eventColorKey})과 맞지 않습니다. 사건 카드 색상에 해당하는 카드만 포함해 주세요.`);
      }
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
            내 덱으로 AI 탐정과 별도 대전을 시작합니다. AI는 공개 덱 저장소에 등록된 덱 중 사건 카드 색상과 구성이 맞는 덱 하나를 무작위로 사용합니다.
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
        <span style={{ color: "#74839a", fontSize: 11 }}>AI는 공개 덱 저장소의 합법적인 덱을 무작위로 선택합니다.</span>
      </div>
      {notice && <p role="status" style={{ color: "#86efac", marginTop: 13, fontSize: 12 }}>{notice}</p>}
      {error && <p role="alert" style={{ color: "#fda4af", marginTop: 13, fontSize: 12, overflowWrap: "anywhere" }}>{error}</p>}
    </section>
  );
}
