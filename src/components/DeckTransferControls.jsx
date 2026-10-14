import { useRef, useState } from "react";

function normalizedIdentity(card) {
  return String(card?.cardId ?? card?.sourceData?.card_id ?? card?.databaseId ?? card?.key ?? "").trim().toLocaleUpperCase();
}

function resolveCard(cardsByKey, cards, savedCard) {
  if (savedCard === null || savedCard === undefined || savedCard === "") return "";
  const raw = typeof savedCard === "object" ? savedCard : { key: savedCard };
  const directKey = String(raw.key ?? raw.id ?? "");
  if (directKey && cardsByKey.has(directKey)) return directKey;
  // Prefer the print-specific card number before the shared internal card ID, so a foil
  // printing does not accidentally resolve to a different printing of the same card.
  const selectors = [
    [raw.cardNum, (card) => card.cardNum],
    [raw.databaseId, (card) => card.databaseId],
    [raw.id, (card) => card.databaseId],
    [raw.cardId, (card) => card.cardId],
  ];
  for (const [needle, getValue] of selectors) {
    const normalized = String(needle ?? "").trim().toLocaleUpperCase();
    if (!normalized) continue;
    const match = cards.find((card) => String(getValue(card) ?? "").trim().toLocaleUpperCase() === normalized);
    if (match?.key) return String(match.key);
  }
  const byName = raw.name ? cards.find((card) => String(card.name ?? "") === String(raw.name)) : null;
  return byName?.key ? String(byName.key) : "";
}

function resolveMainDeck(payload, cards, cardsByKey) {
  let pairs = [];
  if (Array.isArray(payload.mainDeck)) {
    pairs = payload.mainDeck.map((entry) => [resolveCard(cardsByKey, cards, entry), Number(entry.count)]);
  } else if (Array.isArray(payload.main_deck)) {
    pairs = payload.main_deck.map((entry) => [resolveCard(cardsByKey, cards, entry), Number(entry.count)]);
  } else if (payload.deck && typeof payload.deck === "object") {
    pairs = Object.entries(payload.deck).map(([key, count]) => [resolveCard(cardsByKey, cards, key), Number(count)]);
  } else if (payload.main && typeof payload.main === "object") {
    pairs = Object.entries(payload.main).map(([key, count]) => [resolveCard(cardsByKey, cards, key), Number(count)]);
  } else {
    throw new Error("메인 덱 카드 목록을 찾지 못했습니다.");
  }

  const deck = {};
  let total = 0;
  const sameIdCounts = new Map();
  for (const [key, rawCount] of pairs) {
    if (!key) throw new Error("파일에 현재 카드 데이터와 일치하지 않는 카드가 있습니다. 사이트의 카드 데이터 버전이 같은지 확인해 주세요.");
    const count = Math.floor(rawCount);
    if (!Number.isFinite(count) || count < 0 || count > 40) throw new Error("카드 장수 정보가 올바르지 않습니다.");
    if (!count) continue;
    const card = cardsByKey.get(key);
    const identity = normalizedIdentity(card) || key;
    const nextIdentityCount = (sameIdCounts.get(identity) || 0) + count;
    if (nextIdentityCount > 3) throw new Error(`${card?.name || key}: 같은 카드 ID는 최대 3장까지 넣을 수 있습니다.`);
    sameIdCounts.set(identity, nextIdentityCount);
    deck[key] = (deck[key] || 0) + count;
    total += count;
    if (total > 40) throw new Error("메인 덱은 최대 40장입니다.");
  }
  return deck;
}

export default function DeckTransferControls({ cards = [], deck = {}, partnerId = "", eventId = "", onImport }) {
  const inputRef = useRef(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");

  async function importFile(event) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setBusy(true); setStatus("");
    try {
      const raw = JSON.parse(await file.text());
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("JSON 객체 형식의 덱 파일이 아닙니다.");
      if (raw.format && raw.format !== "conan-tcg-deck") throw new Error("코난 TCG 덱 파일 형식이 아닙니다.");
      const cardsByKey = new Map(cards.map((card) => [String(card.key), card]));
      const nextDeck = resolveMainDeck(raw, cards, cardsByKey);
      const savedPartner = raw.partner ?? raw.partnerId ?? raw.partner_id ?? "";
      const savedEvent = raw.event ?? raw.eventId ?? raw.event_id ?? "";
      const nextPartnerId = resolveCard(cardsByKey, cards, savedPartner);
      const nextEventId = resolveCard(cardsByKey, cards, savedEvent);
      if (savedPartner && !nextPartnerId) throw new Error("파트너 카드가 현재 카드 데이터에서 확인되지 않습니다.");
      if (savedEvent && !nextEventId) throw new Error("사건 카드가 현재 카드 데이터에서 확인되지 않습니다.");
      if (typeof onImport !== "function") throw new Error("덱을 적용할 수 있는 연결이 없습니다.");
      onImport({ deck: nextDeck, partnerId: nextPartnerId, eventId: nextEventId });
      const total = Object.values(nextDeck).reduce((sum, count) => sum + count, 0);
      setStatus(`${total}/40장 덱을 불러왔습니다.`);
    } catch (err) {
      setStatus(`불러오기 실패: ${err?.message || "파일을 읽지 못했습니다."}`);
    } finally { setBusy(false); }
  }

  function exportFile() {
    try {
      const cardsByKey = new Map(cards.map((card) => [String(card.key), card]));
      const mainDeck = Object.entries(deck || {}).map(([key, count]) => {
        const card = cardsByKey.get(String(key));
        return {
          key: String(key),
          cardId: card?.cardId || "",
          cardNum: card?.cardNum || "",
          name: card?.name || "",
          count: Math.max(0, Math.floor(Number(count) || 0)),
        };
      }).filter((entry) => entry.count > 0);
      const describeSpecial = (key) => {
        const card = cardsByKey.get(String(key || ""));
        return card ? { key: String(card.key), cardId: card.cardId || "", cardNum: card.cardNum || "", name: card.name || "" } : null;
      };
      const payload = {
        format: "conan-tcg-deck",
        version: 1,
        exportedAt: new Date().toISOString(),
        mainDeck,
        partner: describeSpecial(partnerId),
        event: describeSpecial(eventId),
        count: mainDeck.reduce((sum, entry) => sum + entry.count, 0),
      };
      const blob = new Blob([`${JSON.stringify(payload, null, 2)}\n`], { type: "application/json;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${(describeSpecial(partnerId)?.name || "conan-deck").replace(/[\\/:*?"<>|]/g, "_")}.json`;
      document.body.appendChild(link); link.click(); link.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1200);
      setStatus("덱 JSON을 저장했습니다.");
    } catch (err) {
      setStatus(`내보내기 실패: ${err?.message || "파일을 만들지 못했습니다."}`);
    }
  }

  const button = { display: "inline-flex", alignItems: "center", justifyContent: "center", minHeight: 36, border: "1px solid rgba(148,163,184,.24)", borderRadius: 8, padding: "7px 10px", color: "#e8edf7", background: "#172033", fontSize: 11, fontWeight: 800, cursor: busy ? "wait" : "pointer", opacity: busy ? .65 : 1, whiteSpace: "nowrap" };
  return <div style={{ display: "inline-flex", alignItems: "center", justifyContent: "flex-end", flexWrap: "wrap", gap: 6 }}>
    <button type="button" style={button} onClick={exportFile} disabled={busy}>덱 JSON 저장</button>
    <button type="button" style={{ ...button, background: "#263d63" }} onClick={() => inputRef.current?.click()} disabled={busy}>{busy ? "읽는 중…" : "덱 JSON 불러오기"}</button>
    <input ref={inputRef} type="file" accept="application/json,.json,.txt" onChange={importFile} style={{ display: "none" }} aria-label="덱 JSON 파일 선택" />
    {status && <span role="status" style={{ width: "100%", textAlign: "right", color: status.startsWith("불러오기 실패") || status.startsWith("내보내기 실패") ? "#fda4af" : "#86efac", fontSize: 10 }}>{status}</span>}
  </div>;
}
