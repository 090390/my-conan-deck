import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";

function normalized(value) {
  return String(value ?? "").trim().toLocaleUpperCase();
}

function resolveCard(cards, entry) {
  if (entry == null || entry === "") return null;
  const raw = typeof entry === "object" ? entry : { key: entry };
  const directKey = String(raw.key ?? raw.id ?? "");
  if (directKey) {
    const match = cards.find((card) => String(card.key) === directKey);
    if (match) return match;
  }
  const fields = ["cardNum", "card_num", "databaseId", "database_id", "cardId", "card_id", "key", "id"];
  for (const field of fields) {
    const wanted = normalized(raw[field]);
    if (!wanted) continue;
    const found = cards.find((card) => [card[field], card.cardNum, card.databaseId, card.cardId, card.key, card.id].some((value) => normalized(value) === wanted));
    if (found) return found;
  }
  if (raw.name) return cards.find((card) => String(card.name ?? "") === String(raw.name)) || null;
  return null;
}

function describeCard(cards, key) {
  const card = resolveCard(cards, key);
  if (!card) return null;
  return { key: String(card.key), databaseId: card.databaseId || card.key, cardId: card.cardId || "", cardNum: card.cardNum || "", name: card.name || "이름 없음" };
}

function cardType(card) {
  return `${card?.type || ""} ${card?.originalType || ""} ${card?.roleText || ""}`.toLowerCase();
}

function isEvent(card) {
  return /event|이벤트|イベント|事件/.test(cardType(card));
}

function exportableDeck(cards, deck, partnerId, eventId) {
  return {
    format: "conan-tcg-deck",
    version: 1,
    exportedAt: new Date().toISOString(),
    partner: describeCard(cards, partnerId),
    event: describeCard(cards, eventId),
    mainDeckCount: Object.values(deck || {}).reduce((sum, count) => sum + Math.max(0, Math.floor(Number(count) || 0)), 0),
    mainDeck: Object.entries(deck || {}).map(([key, count]) => {
      const card = resolveCard(cards, { key });
      return card ? {
        key: String(card.key), databaseId: card.databaseId || card.key,
        cardId: card.cardId || "", cardNum: card.cardNum || "",
        name: card.name || "이름 없음", count: Math.max(0, Math.floor(Number(count) || 0)),
      } : null;
    }).filter((entry) => entry && entry.count > 0),
  };
}

function resolveImportedDeck(cards, deckJson) {
  const entries = Array.isArray(deckJson?.mainDeck) ? deckJson.mainDeck
    : Array.isArray(deckJson?.main_deck) ? deckJson.main_deck : null;
  if (!entries) throw new Error("저장된 덱에서 메인 카드 목록을 찾지 못했습니다.");
  const nextDeck = {};
  let total = 0;
  const copyCount = new Map();
  for (const entry of entries) {
    const card = resolveCard(cards, entry);
    if (!card) throw new Error(`현재 카드 목록에서 '${entry?.name || entry?.key || "알 수 없는 카드"}'를 찾지 못했습니다.`);
    const count = Math.max(0, Math.floor(Number(entry.count) || 0));
    if (!count) continue;
    const id = normalized(card.cardId || card.databaseId || card.key);
    const unlimited = ["0627", "1039"].includes(normalized(card.cardId)) || ["0627", "1039"].includes(normalized(card.cardNum)) || ["0627", "1039"].includes(normalized(card.databaseId)) || ["0627", "1039"].includes(normalized(card.key));
    const next = (copyCount.get(id) || 0) + count;
    if (!unlimited && next > 3) throw new Error(`${card.name}: 같은 카드 ID는 최대 3장까지 넣을 수 있습니다.`);
    copyCount.set(id, next);
    nextDeck[String(card.key)] = (nextDeck[String(card.key)] || 0) + count;
    total += count;
  }
  if (total !== 40) throw new Error(`메인 덱은 40장이어야 합니다. 현재 ${total}장입니다.`);
  const partner = resolveCard(cards, deckJson.partner ?? deckJson.partnerId ?? deckJson.partner_id);
  const event = resolveCard(cards, deckJson.event ?? deckJson.eventId ?? deckJson.event_id);
  if (!partner) throw new Error("파트너 카드를 현재 카드 목록에서 찾지 못했습니다.");
  if (!event) throw new Error("사건 카드를 현재 카드 목록에서 찾지 못했습니다.");
  return { deck: nextDeck, partnerId: String(partner.key), eventId: String(event.key) };
}

function downloadJson(fileName, data) {
  const blob = new Blob([JSON.stringify(data, null, 2) + "\n"], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

export default function PublicDeckLibrary({ cards = [], deck = {}, partnerId = "", eventId = "", onImport }) {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState([]);
  const [selected, setSelected] = useState(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [deckName, setDeckName] = useState("");
  const [description, setDescription] = useState("");
  const [composerName, setComposerName] = useState("");
  const [currentUserId, setCurrentUserId] = useState("");

  const cardsByKey = useMemo(() => new Map(cards.map((card) => [String(card.key), card])), [cards]);

  const loadItems = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const { data, error: queryError } = await supabase
        .from("public_deck_library")
        .select("id, deck_name, description, composer_name, deck_json, created_by, created_at")
        .order("created_at", { ascending: false })
        .limit(200);
      if (queryError) throw queryError;
      setItems(Array.isArray(data) ? data : []);
    } catch (err) {
      setError(err?.message || "공개 덱 저장소를 불러오지 못했습니다.");
    } finally { setLoading(false); }
  }, []);

  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(({ data }) => { if (active) setCurrentUserId(data?.user?.id || ""); }).catch(() => {});
    return () => { active = false; };
  }, []);
  useEffect(() => { if (open) void loadItems(); }, [open, loadItems]);

  const selectedDeck = selected ? resolveImportedDeckSafe(cards, selected.deck_json) : null;
  const selectedJson = selected?.deck_json || null;
  const mainCards = selectedDeck ? Object.entries(selectedDeck.deck).map(([key, count]) => ({ card: cardsByKey.get(key), count }))
    .filter((row) => row.card && row.count > 0)
    .sort((a, b) => Number(isEvent(a.card)) - Number(isEvent(b.card)) || Number(b.card.cost || 0) - Number(a.card.cost || 0) || String(a.card.name).localeCompare(String(b.card.name), "ko")) : [];
  const partnerCard = selectedDeck?.partnerId ? cardsByKey.get(String(selectedDeck.partnerId)) : null;
  const caseCard = selectedDeck?.eventId ? cardsByKey.get(String(selectedDeck.eventId)) : null;
  const totalCards = Object.values(deck || {}).reduce((sum, count) => sum + Math.max(0, Math.floor(Number(count) || 0)), 0);

  async function ensureUploadUser() {
    const { data: userResult } = await supabase.auth.getUser().catch(() => ({ data: { user: null } }));
    if (userResult?.user) { setCurrentUserId(userResult.user.id); return userResult.user; }
    const { data, error: authError } = await supabase.auth.signInAnonymously();
    if (authError) throw new Error(`서버에 덱을 업로드하려면 로그인이 필요합니다. 익명 로그인을 사용할 수 없습니다: ${authError.message}`);
    if (!data?.user) throw new Error("업로드 계정을 생성하지 못했습니다.");
    setCurrentUserId(data.user.id);
    return data.user;
  }

  async function uploadCurrentDeck(event) {
    event?.preventDefault?.();
    if (saving) return;
    setError(""); setNotice("");
    if (!deckName.trim() || !composerName.trim()) { setError("덱 이름과 덱 편성자 닉네임을 입력해 주세요."); return; }
    if (totalCards !== 40 || !partnerId || !eventId) { setError("완성된 덱(메인 40장, 파트너, 사건 카드)을 먼저 준비해 주세요."); return; }
    setSaving(true);
    try {
      const user = await ensureUploadUser();
      const deckJson = exportableDeck(cards, deck, partnerId, eventId);
      const { data, error: insertError } = await supabase.from("public_deck_library").insert({
        deck_name: deckName.trim(), description: description.trim(), composer_name: composerName.trim(),
        deck_json: deckJson, created_by: user.id,
      }).select("id, deck_name, description, composer_name, deck_json, created_by, created_at").single();
      if (insertError) throw insertError;
      setItems((current) => [data, ...current.filter((item) => item.id !== data.id)]);
      setSelected(data);
      setNotice("덱을 공개 저장소에 업로드했습니다.");
      setDeckName(""); setDescription("");
    } catch (err) {
      setError(err?.message || "덱을 업로드하지 못했습니다.");
    } finally { setSaving(false); }
  }

  function applySelectedDeck() {
    if (!selected) return;
    try {
      const resolved = resolveImportedDeck(cards, selected.deck_json);
      if (typeof onImport !== "function") throw new Error("덱 구성 화면과 연결되어 있지 않습니다.");
      onImport(resolved);
      setNotice(`'${selected.deck_name}' 덱을 내 덱 구성에 적용했습니다.`);
      setSelected(null);
    } catch (err) {
      setError(err?.message || "덱을 적용하지 못했습니다.");
    }
  }

  async function deleteOwnDeck(item) {
    if (!item?.id || !window.confirm(`공개 저장소에서 '${item.deck_name}' 덱을 삭제할까요?`)) return;
    setError(""); setNotice("");
    try {
      const { error: deleteError } = await supabase.from("public_deck_library").delete().eq("id", item.id);
      if (deleteError) throw deleteError;
      setItems((current) => current.filter((row) => row.id !== item.id));
      if (selected?.id === item.id) setSelected(null);
      setNotice("업로드한 덱을 공개 저장소에서 삭제했습니다.");
    } catch (err) { setError(err?.message || "덱을 삭제하지 못했습니다."); }
  }

  return <>
    <button
      type="button"
      onClick={() => setOpen(true)}
      style={{ ...buttonStyle, minHeight: 36, padding: "7px 10px", whiteSpace: "nowrap", flex: "0 0 auto" }}
      aria-haspopup="dialog"
      aria-expanded={open}
    >덱 저장소</button>
    {open && <div
      role="presentation"
      onMouseDown={(event) => { if (event.target === event.currentTarget) { setSelected(null); setOpen(false); } }}
      style={{ position: "fixed", inset: 0, zIndex: 100400, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.86)", backdropFilter: "blur(4px)" }}
    >
      <section role="dialog" aria-modal="true" aria-label="공개 덱 저장소" style={{ width: "min(100%, 1080px)", maxHeight: "92dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(147,197,253,.35)", borderRadius: 12, background: "#101827", color: "#e8edf7", boxShadow: "0 24px 80px rgba(0,0,0,.6)" }}>
        <header style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 10, padding: 13, borderBottom: "1px solid rgba(255,255,255,.1)" }}>
          <div><h2 style={{ margin: 0, fontSize: 17, fontWeight: 900 }}>공개 덱 저장소</h2><p style={{ margin: "5px 0 0", color: "#94a3b8", fontSize: 11, lineHeight: 1.5 }}>공개 덱을 검색하고 상세 구성을 확인한 뒤, JSON으로 다운로드하거나 내 덱 구성에 적용할 수 있습니다.</p></div>
          <button type="button" onClick={() => { setSelected(null); setOpen(false); }} style={smallButtonStyle}>닫기 ✕</button>
        </header>
        <div style={{ padding: 12, overflowY: "auto", display: "grid", gridTemplateColumns: "minmax(0,1fr)", gap: 12 }}>
          {notice && <p role="status" style={{ color: "#86efac", fontSize: 11, margin: 0 }}>{notice}</p>}
          {error && <p role="alert" style={{ color: "#fda4af", fontSize: 11, margin: 0, overflowWrap: "anywhere" }}>{error}</p>}
          <form onSubmit={uploadCurrentDeck} style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(180px,1fr))", gap: 8, padding: 10, border: "1px solid rgba(147,197,253,.2)", borderRadius: 8, background: "#080d16" }}>
            <strong style={{ gridColumn: "1 / -1", fontSize: 12 }}>현재 덱을 서버에 공개 업로드</strong>
            <label style={labelStyle}>덱 이름<input value={deckName} onChange={(event) => setDeckName(event.target.value)} maxLength={80} placeholder="예: 질풍덱" style={inputStyle} /></label>
            <label style={labelStyle}>덱 편성자 닉네임<input value={composerName} onChange={(event) => setComposerName(event.target.value)} maxLength={80} placeholder="공개할 편성자 이름" style={inputStyle} /></label>
            <label style={{ ...labelStyle, gridColumn: "1 / -1" }}>덱 설명<textarea value={description} onChange={(event) => setDescription(event.target.value)} maxLength={2000} rows={3} placeholder="덱의 전략, 운용법, 특징 등을 작성해 주세요." style={{ ...inputStyle, resize: "vertical" }} /></label>
            <div style={{ gridColumn: "1 / -1", display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", alignItems: "center" }}><span style={{ color: totalCards === 40 && partnerId && eventId ? "#86efac" : "#fcd34d", fontSize: 10 }}>현재 덱: {totalCards}/40장 · 파트너 {partnerId ? "선택됨" : "미선택"} · 사건 {eventId ? "선택됨" : "미선택"}</span><button type="submit" disabled={saving} style={buttonStyle}>{saving ? "업로드 중…" : "서버에 공개 업로드"}</button></div>
          </form>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, flexWrap: "wrap" }}><strong style={{ fontSize: 12 }}>공개된 덱 · {items.length}개</strong><button type="button" onClick={() => void loadItems()} disabled={loading} style={smallButtonStyle}>{loading ? "불러오는 중…" : "새로고침"}</button></div>
          {loading && !items.length && <p style={mutedStyle}>공개 덱을 불러오고 있습니다…</p>}
          {!loading && !items.length && <p style={mutedStyle}>아직 공개된 덱이 없습니다. 첫 덱을 업로드해 보세요.</p>}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(220px,1fr))", gap: 7 }}>
            {items.map((item) => <article key={item.id} style={{ minWidth: 0, padding: 10, border: `1px solid ${selected?.id === item.id ? "rgba(252,211,77,.6)" : "rgba(255,255,255,.1)"}`, borderRadius: 8, background: "#0b1220" }}>
              <button type="button" onClick={() => { setSelected(item); setError(""); }} style={{ display: "block", width: "100%", padding: 0, border: 0, textAlign: "left", background: "transparent", color: "#f8fafc", cursor: "pointer" }}><strong style={{ display: "block", fontSize: 12, overflowWrap: "anywhere" }}>{item.deck_name}</strong><span style={{ display: "block", color: "#94a3b8", fontSize: 10, marginTop: 4 }}>편성자: {item.composer_name}</span><span style={{ display: "block", color: "#64748b", fontSize: 9, marginTop: 3 }}>{new Date(item.created_at).toLocaleDateString("ko-KR")}</span><span style={{ display: "block", color: "#93c5fd", fontSize: 10, marginTop: 7 }}>상세 보기 →</span></button>
              <div style={{ display: "flex", gap: 5, flexWrap: "wrap", marginTop: 8 }}><button type="button" style={smallButtonStyle} onClick={() => downloadJson(`${safeFileName(item.deck_name)}.json`, item.deck_json)}>JSON 다운로드</button>{item.created_by && item.created_by === currentUserId && <button type="button" style={smallButtonStyle} onClick={() => void deleteOwnDeck(item)}>삭제</button>}</div>
            </article>)}
          </div>
        </div>
      </section>
      {selected && <div role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }} style={{ position: "fixed", inset: 0, zIndex: 100500, padding: 12, display: "flex", alignItems: "center", justifyContent: "center", background: "rgba(0,0,0,.88)" }}>
        <section role="dialog" aria-modal="true" aria-label={`${selected.deck_name} 상세 정보`} style={{ width: "min(100%,980px)", maxHeight: "92dvh", overflow: "hidden", display: "flex", flexDirection: "column", border: "1px solid rgba(147,197,253,.35)", borderRadius: 12, background: "#101827", color: "#e8edf7" }}>
          <header style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "flex-start", padding: 13, borderBottom: "1px solid rgba(255,255,255,.1)" }}><div><h3 style={{ margin: 0, fontSize: 17 }}>{selected.deck_name}</h3><p style={{ margin: "5px 0 0", color: "#94a3b8", fontSize: 10 }}>편성자: {selected.composer_name} · {new Date(selected.created_at).toLocaleString("ko-KR")}</p></div><button type="button" onClick={() => setSelected(null)} style={smallButtonStyle}>상세 닫기 ✕</button></header>
          <div style={{ padding: 12, overflowY: "auto" }}>
            <p style={{ whiteSpace: "pre-wrap", overflowWrap: "anywhere", fontSize: 11, lineHeight: 1.6, color: "#cbd5e1", marginTop: 0 }}>{selected.description || "등록된 설명이 없습니다."}</p>
            {selectedDeck ? <><section style={{ display: "grid", gridTemplateColumns: "repeat(2,minmax(0,1fr))", gap: 8, marginBottom: 13 }}>
              {[{ label: "파트너 카드", card: partnerCard }, { label: "사건 카드", card: caseCard }].map((slot) => <div key={slot.label} style={{ minWidth: 0, padding: 8, border: "1px solid rgba(252,211,77,.18)", borderRadius: 8, background: "#080d16" }}><strong style={{ fontSize: 10, color: "#fcd34d" }}>{slot.label}</strong>{slot.card?.imageUrl && <img src={slot.card.imageUrl} alt={slot.card.name} style={{ width: "100%", maxHeight: 150, aspectRatio: "3/4", objectFit: "contain", marginTop: 5 }} />}<div style={{ fontSize: 10, fontWeight: 800, marginTop: 4, overflowWrap: "anywhere" }}>{slot.card?.name || "카드를 찾을 수 없습니다."}</div></div>)}
            </section>
            <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 7, alignItems: "baseline", marginBottom: 7 }}><strong style={{ fontSize: 12 }}>메인 덱 전체 · {totalOf(selected.deck_json)}/40장</strong><span style={{ color: "#94a3b8", fontSize: 9 }}>캐릭터 카드 → 이벤트 카드 · 각 그룹 레벨 높은 순</span></div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill,minmax(100px,1fr))", gap: 7 }}>{mainCards.map(({ card, count }) => <article key={card.key} style={{ minWidth: 0, padding: 6, border: "1px solid rgba(255,255,255,.1)", borderRadius: 7, background: "#080d16" }}>{card.imageUrl && <img src={card.imageUrl} alt={card.name} style={{ width: "100%", aspectRatio: "3/4", objectFit: "contain" }} />}<strong style={{ display: "block", marginTop: 4, fontSize: 9, lineHeight: 1.35, overflowWrap: "anywhere" }}>{card.name}</strong><span style={{ display: "block", marginTop: 3, fontSize: 8, color: "#94a3b8" }}>레벨 {card.cost ?? "-"} · {count}장</span></article>)}</div>
            </> : <p style={{ color: "#fda4af", fontSize: 11 }}>저장된 덱을 현재 카드 데이터와 연결할 수 없습니다. 카드 목록 버전이 다른지 확인해 주세요.</p>}
          </div>
          <footer style={{ display: "flex", justifyContent: "space-between", gap: 8, flexWrap: "wrap", padding: 12, borderTop: "1px solid rgba(255,255,255,.1)" }}><button type="button" style={smallButtonStyle} onClick={() => downloadJson(`${safeFileName(selected.deck_name)}.json`, selectedJson)}>덱 JSON 다운로드</button><button type="button" disabled={!selectedDeck} onClick={applySelectedDeck} style={buttonStyle}>내 덱 구성으로 적용</button></footer>
        </section>
      </div>}
    </div>}
  </>;

}

function resolveImportedDeckSafe(cards, raw) {
  try { return resolveImportedDeck(cards, raw); } catch { return null; }
}
function totalOf(deckJson) {
  const arr = Array.isArray(deckJson?.mainDeck) ? deckJson.mainDeck : Array.isArray(deckJson?.main_deck) ? deckJson.main_deck : [];
  return arr.reduce((sum, entry) => sum + Math.max(0, Math.floor(Number(entry?.count) || 0)), 0);
}
function safeFileName(value) {
  return String(value || "conan-deck").replace(/[\\/:*?"<>|\u0000-\u001f]/g, "-").slice(0, 80) || "conan-deck";
}
const buttonStyle = { border: "1px solid rgba(147,197,253,.45)", borderRadius: 7, padding: "8px 10px", background: "#213454", color: "#eff6ff", cursor: "pointer", fontSize: 11, fontWeight: 850 };
const smallButtonStyle = { border: "1px solid rgba(255,255,255,.13)", borderRadius: 6, padding: "5px 7px", background: "#17243a", color: "#dbe4f1", cursor: "pointer", fontSize: 9, fontWeight: 750 };
const labelStyle = { display: "grid", gap: 5, color: "#94a3b8", fontSize: 10, fontWeight: 750 };
const inputStyle = { width: "100%", boxSizing: "border-box", border: "1px solid rgba(148,163,184,.25)", borderRadius: 6, padding: "8px", color: "#e8edf7", background: "#101827", font: "inherit", fontWeight: 500 };
const mutedStyle = { margin: 0, color: "#94a3b8", fontSize: 10, lineHeight: 1.5 };
