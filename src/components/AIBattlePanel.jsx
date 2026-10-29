import { useEffect, useState } from "react";
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
function eventHasNonBlueColor(card) {
  const source = card?.sourceData && typeof card.sourceData === "object"
    ? card.sourceData
    : card?.raw && typeof card.raw === "object" ? card.raw : {};
  const values = [
    card?.color, card?.colorKo, card?.color_ko, card?.colorKey, card?.color_key,
    card?.colorText, card?.color_text, card?.colors, card?.originalColor,
    source?.color, source?.colorKo, source?.color_ko, source?.colorKey, source?.color_key,
    source?.colors, source?.raw?.color,
  ];
  const text = values.flatMap((value) => Array.isArray(value) ? value : [value])
    .filter((value) => value !== null && value !== undefined)
    .map((value) => String(value).trim().toLocaleLowerCase())
    .join(" ");
  if (!text) return false;
  return /(?:red|yellow|green|white|black|purple|orange|pink|brown|gold|silver|적|황|녹|백|흑|자|주|빨강|노랑|초록|흰색|검정|보라|桃|赤|黄|緑|白|黒|紫|橙|金|銀)/iu.test(text);
}

function getTraits(card) {
  const values = [card?.traits, card?.category1, card?.category2, card?.category3];
  return [...new Set(values.flatMap((value) => {
    if (Array.isArray(value)) return value.map((item) => String(item ?? "").trim()).filter(Boolean);
    if (value == null || String(value).trim() === "") return [];
    return String(value).split(/[、,，;；|｜]/u).map((item) => item.trim()).filter(Boolean);
  }))];
}
function cardTypeText(card) {
  return [
    card?.type, card?.typeKo, card?.originalType, card?.roleText,
    card?.sourceData?.type, card?.sourceData?.typeKo,
  ].map((value) => String(value ?? "")).join(" ");
}
function isPartner(card) {
  return /パートナー|파트너/iu.test(cardTypeText(card))
    || /^P\d+/iu.test(String(card?.cardId || ""));
}
function isEvent(card) {
  return /事件|사건|이벤트|イベント|event/iu.test(cardTypeText(card));
}
function isCharacter(card) {
  return /キャラ|character|캐릭터/iu.test(cardTypeText(card))
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
    event_has_non_blue_color: eventHasNonBlueColor(event),
    deck_name: String(item.deck_name || "이름 없는 공개 덱"),
    composer_name: String(item.composer_name || ""),
  };
}
async function fetchPublicDecks() {
  const { data, error } = await supabase.from("public_deck_library")
    .select("id, deck_name, description, composer_name, deck_json, created_at")
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw new Error(`공개 덱 저장소를 불러오지 못했습니다: ${error.message}`);
  return Array.isArray(data) ? data : [];
}

function getCardColorLabel(card) {
  const source = card?.sourceData && typeof card.sourceData === "object" ? card.sourceData : {};
  const values = [
    card?.colorKo, card?.color_ko, card?.colorText, card?.color_text, card?.color,
    card?.colors, card?.originalColor, card?.colorKey, card?.color_key,
    source?.colorKo, source?.color_ko, source?.color, source?.colors,
  ];
  for (const value of values) {
    if (Array.isArray(value) && value.length) return value.map((item) => String(item ?? "").trim()).filter(Boolean).join("/");
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return "";
}

function publicDeckLabels(cards, item) {
  const source = item?.deck_json && typeof item.deck_json === "object" ? item.deck_json : {};
  const partnerEntry = source.partner ?? source.partnerId ?? source.partner_id;
  const eventEntry = source.event ?? source.eventId ?? source.event_id;
  const partner = resolvePublicDeckCard(cards, partnerEntry);
  const event = resolvePublicDeckCard(cards, eventEntry);
  const fallbackName = (entry) => {
    if (entry == null || entry === "") return "정보 없음";
    if (typeof entry === "object") return String(entry.name ?? entry.cardName ?? entry.card_name ?? entry.cardId ?? entry.card_id ?? entry.key ?? entry.id ?? "정보 없음");
    return String(entry);
  };
  return {
    partnerName: String(partner?.name || partner?.originalName || fallbackName(partnerEntry)),
    partnerColor: getCardColorLabel(partner),
    eventName: String(event?.name || event?.originalName || fallbackName(eventEntry)),
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
  const [publicDecks, setPublicDecks] = useState([]);
  const [selectedDeckIds, setSelectedDeckIds] = useState([]);
  const [deckListLoading, setDeckListLoading] = useState(true);
  const [deckListError, setDeckListError] = useState("");

  useEffect(() => {
    let active = true;
    async function loadDecks() {
      setDeckListLoading(true);
      setDeckListError("");
      try {
        const data = await fetchPublicDecks();
        if (!active) return;
        setPublicDecks(data);
        setSelectedDeckIds(data.map((item) => String(item.id)));
      } catch (err) {
        if (!active) return;
        setPublicDecks([]);
        setSelectedDeckIds([]);
        setDeckListError(err?.message || "공개 덱 목록을 불러오지 못했습니다.");
      } finally {
        if (active) setDeckListLoading(false);
      }
    }
    void loadDecks();
    return () => { active = false; };
  }, []);

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
      if (deckListLoading) throw new Error("AI 덱 후보 목록을 불러오는 중입니다. 잠시 후 다시 시도해 주세요.");
      if (deckListError) throw new Error(deckListError);
      const candidates = publicDecks.filter((item) => selectedDeckIds.includes(String(item.id)));
      if (!candidates.length) throw new Error("AI가 사용할 덱을 하나 이상 선택해 주세요.");
      const pickedDeck = candidates[Math.floor(Math.random() * candidates.length)];
      const humanDeck = buildHumanDeck(deck, cards);
      const aiDeck = preparePublicDeck(cards, pickedDeck);
      const { data, error: invokeError } = await supabase.functions.invoke("ai-battle", {
        body: {
          action: "create",
          main_deck: humanDeck,
          partner_key: String(partnerId),
          event_key: String(eventId),
          event_rule_code: getEventRuleCode(event, eventId),
          event_has_non_blue_color: eventHasNonBlueColor(event),
          ai_deck: aiDeck,
        },
      });
      if (invokeError) throw invokeError;
      if (!data?.room_id || !data?.invite_code) throw new Error(data?.error || "AI 대전 생성 결과를 확인할 수 없습니다.");
      await onStarted?.({ roomId: data.room_id, inviteCode: data.invite_code, userId: session?.user?.id, initialAiMessage: data.initial_ai?.message || "" });
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
            아래에서 AI가 사용할 공개 덱 후보를 선택하세요. 체크한 덱 가운데 하나를 무작위로 골라 대전합니다.
          </p>
        </div>
      </div>
      <div style={{ marginTop: 14, padding: 12, borderRadius: 9, border: "1px solid rgba(252,211,77,.24)", background: "rgba(161,98,7,.09)", color: "#fcd34d", fontSize: 11, lineHeight: 1.7 }}>
        실험 중인 기능입니다. 덱 효과별 지원 범위에 따라 일부 행동이 정상적으로 처리되지 않을 수 있습니다.
      </div>
      <div style={{ marginTop: 16, border: "1px solid rgba(148,163,184,.2)", borderRadius: 12, overflow: "hidden" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: 10, padding: "12px 14px", background: "rgba(15,23,42,.7)" }}>
          <div>
            <strong style={{ fontSize: 13 }}>AI 덱 후보</strong>
            <div style={{ color: "#94a3b8", fontSize: 11, marginTop: 3 }}>
              {deckListLoading ? "공개 덱 목록을 불러오는 중…" : `${selectedDeckIds.length} / ${publicDecks.length}개 선택됨`}
            </div>
          </div>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            <button type="button" style={{ ...buttonStyle, padding: "7px 10px", fontSize: 11 }} disabled={deckListLoading || publicDecks.length === 0} onClick={() => setSelectedDeckIds(publicDecks.map((item) => String(item.id)))}>전체 선택</button>
            <button type="button" style={{ ...buttonStyle, padding: "7px 10px", fontSize: 11, background: "#1e293b", borderColor: "rgba(148,163,184,.28)" }} disabled={deckListLoading || selectedDeckIds.length === 0} onClick={() => setSelectedDeckIds([])}>전체 해제</button>
          </div>
        </div>
        {deckListError && <p role="alert" style={{ margin: 0, padding: 12, color: "#fda4af", fontSize: 12 }}>{deckListError}</p>}
        {!deckListLoading && !deckListError && publicDecks.length === 0 && <p style={{ margin: 0, padding: 12, color: "#fda4af", fontSize: 12 }}>공개 덱 저장소에 등록된 덱이 없습니다.</p>}
        <div style={{ maxHeight: 340, overflowY: "auto" }}>
          {publicDecks.map((item) => {
            const id = String(item.id);
            const checked = selectedDeckIds.includes(id);
            const details = publicDeckLabels(cards, item);
            return (
              <label key={id} style={{ display: "flex", alignItems: "flex-start", gap: 10, padding: "11px 13px", borderTop: "1px solid rgba(148,163,184,.12)", background: checked ? "rgba(8,47,73,.18)" : "transparent", cursor: "pointer" }}>
                <input
                  type="checkbox"
                  checked={checked}
                  disabled={deckListLoading}
                  onChange={(event) => setSelectedDeckIds((current) => event.target.checked
                    ? [...new Set([...current, id])]
                    : current.filter((selectedId) => selectedId !== id))}
                  style={{ marginTop: 3, accentColor: "#38bdf8" }}
                />
                <span style={{ minWidth: 0, flex: 1 }}>
                  <span style={{ display: "block", color: "#e2e8f0", fontSize: 12, fontWeight: 800, overflowWrap: "anywhere" }}>{item.deck_name || "이름 없는 덱"}</span>
                  <span style={{ display: "block", marginTop: 3, color: "#94a3b8", fontSize: 10, lineHeight: 1.6 }}>
                    제작자: {item.composer_name || "미상"}
                    {" · "}파트너: {details.partnerColor ? `[${details.partnerColor}] ` : ""}{details.partnerName}
                    {" · "}사건: {details.eventName}
                  </span>
                  {item.description && <span style={{ display: "block", marginTop: 3, color: "#718096", fontSize: 10, lineHeight: 1.5, overflowWrap: "anywhere" }}>{item.description}</span>}
                </span>
              </label>
            );
          })}
        </div>
      </div>
      <div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 8, marginTop: 16 }}>
        <button type="button" style={{ ...buttonStyle, opacity: loading ? .6 : 1, cursor: loading ? "wait" : "pointer" }} disabled={loading || deckListLoading || !!deckListError || publicDecks.length === 0} onClick={() => void startAIBattle()}>
          {loading ? "AI 대전 준비 중…" : "AI 대전 시작"}
        </button>
        <span style={{ color: "#74839a", fontSize: 11 }}>체크한 덱 {selectedDeckIds.length}개 중 무작위 선택</span>
      </div>
      {notice && <p role="status" style={{ color: "#86efac", marginTop: 13, fontSize: 12 }}>{notice}</p>}
      {error && <p role="alert" style={{ color: "#fda4af", marginTop: 13, fontSize: 12, overflowWrap: "anywhere" }}>{error}</p>}
    </section>
  );
}
